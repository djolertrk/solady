"""Guard against counting incorrect executions as optimization wins."""

import copy
import tempfile
import unittest
from pathlib import Path

import benchmark


class CoreSourcesTests(unittest.TestCase):
    def test_nested_modules_keep_their_import_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "codecs").mkdir()
            (root / "Bytes.sol").write_text("library Bytes {}")
            (root / "codecs" / "Base64.sol").write_text("library Base64 {}")
            self.assertEqual(
                benchmark.core_sources(root),
                {
                    "solar:core/v1/Bytes.sol": {"content": "library Bytes {}"},
                    "solar:core/v1/codecs/Base64.sol": {"content": "library Base64 {}"},
                },
            )


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        self.case = {
            "variants": {
                "solc-upstream-legacy": {"matches_oracle": True, "opcode_gas": 100},
                "solc-upstream-ir": {"matches_oracle": True, "opcode_gas": 120},
                "solc-safe-legacy": {"matches_oracle": True, "opcode_gas": 200},
                "solc-safe-ir": {"matches_oracle": True, "opcode_gas": 150},
                "solar-upstream": {"matches_oracle": True, "opcode_gas": 90},
                "solar-safe": {"matches_oracle": True, "opcode_gas": 80},
            }
        }

    def test_reference_uses_cheaper_upstream_solc_pipeline(self):
        self.assertEqual(benchmark.comparison_delta(self.case), -20)
        self.case["variants"]["solc-upstream-ir"]["opcode_gas"] = 70
        self.assertEqual(benchmark.comparison_delta(self.case), 10)

    def test_any_incorrect_leg_excludes_case(self):
        for label in self.case["variants"]:
            with self.subTest(variant=label):
                case = copy.deepcopy(self.case)
                case["variants"][label] = {"matches_oracle": False, "opcode_gas": 0}
                self.assertIsNone(benchmark.comparison_delta(case))

    def test_missing_correctness_evidence_is_not_accepted(self):
        del self.case["variants"]["solar-safe"]["matches_oracle"]
        with self.assertRaises(KeyError):
            benchmark.comparison_delta(self.case)


class SafetyAuditTests(unittest.TestCase):
    def test_nested_unsafe_blocks_in_dependencies_are_rejected(self):
        output = {
            "sources": {
                "Harness.sol": {"ast": {"nodeType": "SourceUnit"}},
                "src/Dependency.sol": {
                    "ast": {
                        "nodes": [
                            {
                                "body": {
                                    "statements": [
                                        {"nodeType": "UncheckedBlock"},
                                        {"nodeType": "InlineAssembly"},
                                    ]
                                }
                            }
                        ]
                    }
                },
            }
        }
        self.assertEqual(
            benchmark.safety_violations(output),
            [
                ("src/Dependency.sol", "UncheckedBlock"),
                ("src/Dependency.sol", "InlineAssembly"),
            ],
        )

    def test_comments_do_not_create_false_violations(self):
        output = {
            "sources": {
                "src/Safe.sol": {
                    "ast": {
                        "nodeType": "SourceUnit",
                        "documentation": "No assembly or unchecked blocks.",
                    }
                }
            }
        }
        self.assertEqual(benchmark.safety_violations(output), [])

    def test_missing_ast_is_an_error(self):
        with self.assertRaises(KeyError):
            benchmark.safety_violations({"sources": {"src/Missing.sol": {}}})


class HarnessSelectionTests(unittest.TestCase):
    def setUp(self):
        self.apis = [
            {"library": "Lib", "signature": "a(uint256)"},
            {"library": "Lib", "signature": "b(bytes)"},
        ]

    def test_combined_harness_keeps_every_api(self):
        self.assertIs(
            benchmark.select_harness_apis(
                self.apis, ["Lib.a(uint256)"], isolate=False
            ),
            self.apis,
        )

    def test_isolated_harness_keeps_only_requested_api(self):
        self.assertEqual(
            benchmark.select_harness_apis(
                self.apis, ["Lib.b(bytes)"], isolate=True
            ),
            [self.apis[1]],
        )

    def test_isolation_requires_a_known_api(self):
        with self.assertRaisesRegex(ValueError, "requires at least one"):
            benchmark.select_harness_apis(self.apis, [], isolate=True)
        with self.assertRaisesRegex(ValueError, "unknown API"):
            benchmark.select_harness_apis(self.apis, ["Lib.missing()"], isolate=True)


class DispatchGasTests(unittest.TestCase):
    SELECTOR = bytes.fromhex("12345678")

    def trace(self, steps):
        # steps: (pc, op, gas); code holds the selector after PUSH4s at pc 10.
        return [{"pc": pc, "op": op, "gasCost": gas} for pc, op, gas in steps]

    def code(self):
        code = bytearray(64)
        code[11:15] = self.SELECTOR
        code[31:35] = bytes.fromhex("87654321")
        return bytes(code)

    def test_taken_equality_jump_ends_the_dispatch(self):
        logs = self.trace([
            (30, "PUSH4", 3), (35, "EQ", 3), (36, "PUSH2", 3), (39, "JUMPI", 10),
            (40, "PUSH4", 3), (10, "PUSH4", 3), (15, "EQ", 3), (16, "PUSH2", 3),
            (19, "JUMPI", 10), (50, "JUMPDEST", 1), (51, "STOP", 0),
        ])
        # The first comparison is a different selector and falls through.
        self.assertEqual(benchmark.dispatch_gas(logs, self.code(), self.SELECTOR), 41)

    def test_mismatch_branch_falls_through_on_the_selector(self):
        logs = self.trace([
            (10, "PUSH4", 3), (15, "XOR", 3), (16, "PUSH2", 3), (19, "JUMPI", 10),
            (20, "JUMPDEST", 1),
        ])
        self.assertEqual(benchmark.dispatch_gas(logs, self.code(), self.SELECTOR), 19)

    def test_split_on_the_selector_is_not_the_match(self):
        logs = self.trace([
            (10, "PUSH4", 3), (15, "GT", 3), (16, "PUSH2", 3), (19, "JUMPI", 10),
            (50, "JUMPDEST", 1),
        ])
        self.assertIsNone(benchmark.dispatch_gas(logs, self.code(), self.SELECTOR))


class WrapperNameTests(unittest.TestCase):
    def test_name_depends_only_on_the_api(self):
        name = benchmark.wrapper_name("LibSort", "sort(uint256[])")
        self.assertEqual(name, benchmark.wrapper_name("LibSort", "sort(uint256[])"))
        self.assertRegex(name, "^f[0-9a-f]{8}$")
        self.assertNotEqual(name, benchmark.wrapper_name("LibSort", "sort(int256[])"))
        self.assertNotEqual(name, benchmark.wrapper_name("LibBit", "sort(uint256[])"))


class StorageLayoutTests(unittest.TestCase):
    def test_short_value_packs_its_length_below_its_bytes(self):
        words = benchmark.packed_words(b"abc")
        self.assertEqual(words[0], b"abc" + bytes(28) + bytes([3]))
        self.assertEqual(words[1:], [bytes(32)] * benchmark.STORAGE_WORDS)

    def test_short_value_continues_from_byte_31_in_derived_words(self):
        value = bytes(range(40))
        words = benchmark.packed_words(value)
        self.assertEqual(words[0], value[:31] + bytes([40]))
        self.assertEqual(words[1], value[31:].ljust(32, b"\0"))
        self.assertEqual(words[2], bytes(32))

    def test_long_value_keeps_its_length_in_the_root(self):
        value = bytes(i % 251 for i in range(300))
        words = benchmark.packed_words(value)
        self.assertEqual(words[0], ((300 << 8) | 0xFF).to_bytes(32, "big"))
        self.assertEqual(b"".join(words[1:11])[:300], value)
        self.assertEqual(words[10][300 - 288 :], bytes(20))

    def test_shorter_value_leaves_later_words_of_a_longer_one(self):
        longer = benchmark.packed_words(b"y" * 300)
        words = benchmark.packed_words(b"x" * 40, longer)
        self.assertEqual(words[1], b"x" * 9 + bytes(23))
        self.assertEqual(words[2:], longer[2:])

    def test_reads_start_from_the_stored_words(self):
        cases = list(benchmark.storage_vectors("length", [b"", b"ab"], bytes))
        self.assertEqual([case[1] for case in cases], [[0], [2]])
        self.assertEqual(cases[1][2][0][-1], 2)

    def test_stores_expect_the_words_they_leave(self):
        base, value = benchmark.packed_words(b""), b"z" * 40
        cases = list(benchmark.storage_vectors("set", [value], bytes))
        self.assertEqual(cases[0], ([value], [], base, benchmark.packed_words(value)))

    def test_derived_slots_follow_the_root_hash(self):
        slots = benchmark.storage_slots(3)
        base = int.from_bytes(benchmark.keccak((3).to_bytes(32, "big")), "big")
        self.assertEqual(slots[:3], [3, base, base + 1])
        self.assertEqual(len(slots), benchmark.STORAGE_WORDS + 1)


class CaseIdentityTests(unittest.TestCase):
    def test_identity_covers_input_source_and_compiler(self):
        artifact = {"input_sha256": "safe", "compiler_sha256": "solar"}
        identity = benchmark.case_identity("Lib", "f(bytes)", b"abc", "cancun", 200, artifact)
        self.assertEqual(
            identity,
            benchmark.case_identity("Lib", "f(bytes)", b"abc", "cancun", 200, artifact),
        )
        changed = dict(artifact, compiler_sha256="other")
        self.assertNotEqual(
            identity,
            benchmark.case_identity("Lib", "f(bytes)", b"abc", "cancun", 200, changed),
        )


if __name__ == "__main__":
    unittest.main()

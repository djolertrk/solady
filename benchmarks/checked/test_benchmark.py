"""Guard against counting incorrect executions as optimization wins."""

import copy
import unittest

import benchmark


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

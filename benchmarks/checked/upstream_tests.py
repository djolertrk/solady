#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["eth-abi==5.2.0", "eth-hash[pycryptodome]==0.7.1"]
# ///
"""Run the pinned upstream tests for the ported libraries whose suites compile.

Original test helpers remain test oracles, including their assembly. Only the
selected production sources are replaced in the safe legs, which also receive
the compiler's core modules; `--ported` also replaces every other ported source
the suites import. A library is named by its path below `src/`, or by
its bare name for `src/utils/`; its suite is `test/<name>.t.sol` unless
`SUITES` names another. This is an additional correctness check, not the gas
benchmark or safety audit.
"""

import argparse
import gzip
import json
import os
import subprocess
from pathlib import Path

from benchmark import (
    ARCHIVE,
    DEFAULT_CORE_MODULES,
    REPO,
    ROOT,
    closure,
    core_sources,
    digest,
)

LIBRARIES = [
    "SafeCastLib",
    "LibBit",
    "Base64",
    "ECDSA",
    "SignatureCheckerLib",
    "MerkleProofLib",
    "EfficientHashLib",
    "LibBytes",
    "LibString",
    "LibSort",
    "LibBitmap",
    "LibMap",
    "DateTimeLib",
    "LibPRNG",
    "FixedPointMathLib",
    "EnumerableSetLib",
    "DynamicBufferLib",
    "DynamicArrayLib",
    "MinHeapLib",
    "JSONParserLib",
    "LibCall",
    "SSTORE2",
    "SafeTransferLib",
    "LibClone",
    "tokens/ERC20",
    "tokens/WETH",
    "tokens/ERC4626",
    "tokens/ERC721",
    "tokens/ERC1155",
    "tokens/ERC6909",
    "auth/Ownable",
    "auth/OwnableRoles",
    "accounts/Receiver",
    "ReentrancyGuard",
    "Initializable",
    "CREATE3",
    "UpgradeableBeacon",
    "ERC1967FactoryConstants",
    "ERC1967Factory",
    "EnumerableMapLib",
    "LibStorage",
    "RedBlackTreeLib",
    "auth/EnumerableRoles",
    "auth/TimedRoles",
    "tokens/ERC2981",
    "tokens/ERC20Votes",
    "Multicallable",
    "MetadataReaderLib",
    "Lifebuoy",
    "DeploylessPredeployQueryer",
    "utils/ext/delegatexyz/DelegateCheckerLib",
    "utils/legacy/LibCWIA",
    "utils/legacy/CWIA",
    "accounts/LibERC7579",
    "accounts/LibERC6551",
    "accounts/ERC7821",
    "accounts/Timelock",
    "CallContextChecker",
    "UUPSUpgradeable",
    "EIP712",
    "accounts/ERC1271",
    "accounts/ERC4337Factory",
]


# Tests that fail on upstream's own build too, for reasons outside the
# sources under test. A leg succeeds when no other test fails.
KNOWN_FAILURES = {
    # Upstream's `toNibbles` allocates too little memory for the long input the
    # fuzzer draws, which the test's memory check catches; the ports pass it.
    "test/LibBit.t.sol:LibBitTest::testToNibblesDifferential(uint256,bytes)",
    # The fuzzer draws Foundry's console address as the deployer, whose calls
    # Foundry intercepts, on every leg.
    "test/Lifebuoy.t.sol:LifebuoyTest::testLifebuoyCreateDeployment(address,address,uint256)",
}

# Suites not named after the library they test.
SUITES = {
    "RedBlackTreeLib": "test/RedBlackTree.t.sol",
    "ERC1967FactoryConstants": "test/ERC1967Factory.t.sol",
    "accounts/ERC6551Proxy": "test/ERC6551.t.sol",
    "utils/legacy/CWIA": "test/LibCWIA.t.sol",
    "utils/ext/delegatexyz/DelegateCheckerLib": "test/ext/delegatexyz/DelegateCheckerLib.t.sol",
}


def source_path(library):
    return f"src/{library}.sol" if "/" in library else f"src/utils/{library}.sol"


def test_path(library):
    return SUITES.get(library, f"test/{library.rsplit('/', 1)[-1]}.t.sol")


def run(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    libraries = args.library or LIBRARIES
    archive = json.loads(gzip.decompress(ARCHIVE.read_bytes()))
    sources = closure(archive["sources"], sorted({test_path(name) for name in libraries}))
    replaced = {source_path(name) for name in libraries}
    if args.ported:
        replaced |= {
            name
            for name in sources
            if name.startswith("src/")
            and (ROOT / name).exists()
            and "@custom:solar-safe" in (ROOT / name).read_text()
        }
    results = {}
    for label, compiler, safe in [
        ("solc-upstream", args.solc, False),
        ("solc-safe", args.solc, True),
        ("solar-safe", args.solar, True),
    ]:
        folder = output / label
        folder.mkdir()
        hashes = {}
        for name, source in sources.items():
            text = source["content"]
            if safe and name in replaced:
                text = (ROOT / name).read_text()
            path = folder / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
            hashes[name] = digest(text.encode())
        if safe:
            for name, source in core_sources(args.core_modules).items():
                path = folder / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(source["content"])
                hashes[name] = digest(source["content"].encode())
        (folder / "foundry.toml").write_text(
            '[profile.default]\nsrc = "src"\ntest = "test"\nlibs = []\n'
            'evm_version = "cancun"\noptimizer = true\noptimizer_runs = 200\n'
            f'via_ir = {"false" if args.legacy else "true"}\nbytecode_hash = "none"\n'
            'cbor_metadata = false\n'
            'gas_limit = 100000000\nremappings = ["forge-std/=test/utils/forge-std/"]\n'
            f'[profile.default.fuzz]\nruns = {args.fuzz_runs}\nseed = "0x20260910"\n'
        )
        env = os.environ.copy()
        env["FOUNDRY_SOLC"] = str(compiler.resolve())
        if label == "solar-safe":
            env["SOLC_WRAPPER"] = "1"
            env["SOLC_WRAPPER_VERSION"] = args.solc_version
        else:
            env.pop("SOLC_WRAPPER", None)
        command = [args.forge, "test", "--root", str(folder), "--force", "--json"]
        print(f"Running {label}", flush=True)
        result = subprocess.run(
            command,
            cwd=folder,
            env=env,
            capture_output=True,
            text=True,
            timeout=600,
            check=False,
        )
        (folder / "stdout.json").write_text(result.stdout)
        (folder / "stderr.txt").write_text(result.stderr)
        tests = {}
        if result.stdout.lstrip().startswith("{"):
            for contract, data in json.loads(result.stdout).items():
                for name, test in data.get("test_results", {}).items():
                    tests[f"{contract}::{name}"] = {
                        "status": test["status"],
                        "reason": test.get("reason"),
                    }
        complete = all(
            any(name.startswith(f"{test_path(lib)}:") for name in tests)
            for lib in libraries
        )
        failures = {
            name for name, test in tests.items() if test["status"] != "Success"
        }
        succeeded = complete and (
            result.returncode == 0 if not failures else failures <= KNOWN_FAILURES
        )
        results[label] = {
            "exit_code": result.returncode,
            "succeeded": succeeded,
            "tests": tests,
            "source_sha256": hashes,
            "command": command,
            "compiler_sha256": digest(compiler.read_bytes()),
        }
        print(f"{label}: exit {result.returncode}", flush=True)
        (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return int(any(not r["succeeded"] for r in results.values()))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--solc", type=Path, required=True)
    parser.add_argument("--solc-version", default="0.8.37")
    parser.add_argument(
        "--solar", type=Path, default=REPO.parent / "solar/target/debug/solar"
    )
    parser.add_argument("--forge", default="forge")
    parser.add_argument(
        "--library",
        action="append",
        help="library to test, repeatable (default: every library whose suite passes)",
    )
    parser.add_argument("--core-modules", type=Path, default=DEFAULT_CORE_MODULES)
    parser.add_argument("--fuzz-runs", type=int, default=256)
    parser.add_argument(
        "--legacy", action="store_true", help="build solc's legs without via-IR"
    )
    parser.add_argument(
        "--ported",
        action="store_true",
        help="also swap in every other ported source the suites import",
    )
    parser.add_argument("--output", type=Path, required=True)
    raise SystemExit(run(parser.parse_args()))

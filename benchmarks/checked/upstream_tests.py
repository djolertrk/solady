#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["eth-abi==5.2.0", "eth-hash[pycryptodome]==0.7.1"]
# ///
"""Run the pinned upstream tests for the ported libraries whose suites compile.

Original test helpers remain test oracles, including their assembly. Only the
selected production sources are replaced in the safe legs, which also receive
the compiler's core modules. A library is named by its path below `src/`, or by
its bare name for `src/utils/`; its suite is `test/<name>.t.sol`. This is an
additional correctness check, not the gas benchmark or safety audit.
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

# MerkleProofLib's suite calls the `empty*` functions the port leaves out, and
# EfficientHashLib's checks that `free` moves the free-memory pointer back.
LIBRARIES = [
    "SafeCastLib",
    "LibBit",
    "Base64",
    "ECDSA",
    "SignatureCheckerLib",
    "tokens/ERC20",
]


def source_path(library):
    return f"src/{library}.sol" if "/" in library else f"src/utils/{library}.sol"


def test_path(library):
    return f"test/{library.rsplit('/', 1)[-1]}.t.sol"


def run(args):
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    libraries = args.library or LIBRARIES
    archive = json.loads(gzip.decompress(ARCHIVE.read_bytes()))
    sources = closure(archive["sources"], [test_path(name) for name in libraries])
    replaced = {source_path(name) for name in libraries}
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
            'via_ir = true\nbytecode_hash = "none"\ncbor_metadata = false\n'
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
        succeeded = (
            result.returncode == 0
            and complete
            and all(test["status"] == "Success" for test in tests.values())
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
    parser.add_argument("--output", type=Path, required=True)
    raise SystemExit(run(parser.parse_args()))

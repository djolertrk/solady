#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["eth-abi==5.2.0", "eth-hash[pycryptodome]==0.7.1"]
# ///
"""Composed-workload comparison for the checked Solady port.

The per-API matrix in `benchmark.py` measures one library call per transaction.
This script measures workloads that chain several libraries in one call, the way
an application uses them: an ERC-721 style metadata URI, a set pipeline over two
lists, and a decode-then-scan path.

The workload source is byte-identical across every leg and uses only APIs whose
declarations the port shares with the pinned archive, so the same contract
compiles against the checked sources and against the original assembly sources.
There is no separate Python oracle here: the check is that all six legs return
the same bytes, which is agreement between two independent implementations under
three compiler pipelines. Gas is the sum of executed opcode gas from
`debug_traceCall`, excluding transaction intrinsic gas, and includes the
workload's own dispatch, ABI handling and allocation.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

from eth_abi import encode
from eth_hash.auto import keccak

sys.path.insert(0, str(Path(__file__).resolve().parent))
import benchmark  # noqa: E402

WORKLOAD_PATH = "Composed.sol"

WORKLOAD_SOURCE = '''// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/utils/Base64.sol";
import "src/utils/LibBit.sol";
import "src/utils/LibSort.sol";
import "src/utils/LibString.sol";

contract Composed {
    /// @dev ERC-721 style metadata: escape the name, render the identifier and
    /// the owner, then Base64 the JSON document.
    function tokenURI(uint256 id, address owner, string memory name)
        external
        pure
        returns (string memory)
    {
        string memory json = string.concat(
            '{"name":"',
            LibString.escapeJSON(name),
            " #",
            LibString.toString(id),
            '","owner":"',
            LibString.toHexStringChecksummed(owner),
            '","id":"',
            LibString.toHexString(id),
            '"}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    /// @dev Sort two lists, then take their union, intersection and difference.
    function mergeLists(uint256[] memory a, uint256[] memory b)
        external
        pure
        returns (uint256[] memory u, uint256[] memory i, uint256[] memory d, bool dup)
    {
        LibSort.sort(a);
        LibSort.sort(b);
        dup = LibSort.hasDuplicate(a);
        u = LibSort.union(a, b);
        i = LibSort.intersection(a, b);
        d = LibSort.difference(a, b);
    }

    /// @dev Decode a Base64 payload, then measure and search the result.
    function decodeAndScan(string memory encoded, string memory needle)
        external
        pure
        returns (uint256 zeroBytes, uint256 runes, uint256 at, string memory hexed)
    {
        bytes memory raw = Base64.decode(encoded);
        zeroBytes = LibBit.countZeroBytes(raw);
        string memory text = string(raw);
        runes = LibString.runeCount(text);
        at = LibString.indexOf(text, needle);
        hexed = LibString.toHexString(raw);
    }
}
'''

ROOTS = [
    "src/utils/Base64.sol",
    "src/utils/LibBit.sol",
    "src/utils/LibSort.sol",
    "src/utils/LibString.sol",
]


def workload_cases():
    """Returns (name, signature, arg types, argument tuples) for every workload."""
    names = [
        "Solady",
        'Escape "me" \\ now',
        "unicode éèê name",
        "a" * 64,
        "",
        "Token #17 <tag> & co",
    ]
    ids = [0, 1, 4919, 2**64 - 1, 10**18, 2**255]
    owners = [
        "0x0000000000000000000000000000000000000000",
        "0x000000000000000000000000000000000000dead",
        "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
        "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
        "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB",
        "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb",
    ]
    token = [
        ("tokenURI(uint256,address,string)", ["uint256", "address", "string"], (i, o, n))
        for i, o, n in zip(ids, owners, names)
    ]

    lists = []
    for k in range(6):
        size = [0, 1, 2, 8, 24, 64][k]
        a = [(i * 2654435761 + k) % 100003 for i in range(size)]
        b = [(i * 40503 + 7 * k) % 100003 for i in range(size)]
        # The set operations document sorted, uniquified inputs; keep the
        # workload inside that domain.
        a = sorted(dict.fromkeys(a))
        b = sorted(dict.fromkeys(b))
        lists.append(
            ("mergeLists(uint256[],uint256[])", ["uint256[]", "uint256[]"], (a, b))
        )

    payloads = [
        b"",
        b"Solady",
        b"the quick brown fox jumps over the lazy dog",
        bytes(range(64)),
        b"needle in a haystack " * 8,
        bytes(200),
    ]
    import base64 as b64

    scan = [
        (
            "decodeAndScan(string,string)",
            ["string", "string"],
            (b64.b64encode(p).decode(), "needle"),
        )
        for p in payloads
    ]
    return {"tokenURI": token, "mergeLists": lists, "decodeAndScan": scan}


def run(args):
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    archive = json.loads(
        __import__("gzip").decompress(benchmark.ARCHIVE.read_bytes())
    )
    safe = benchmark.closure(
        {
            p.relative_to(benchmark.ROOT).as_posix(): {"content": p.read_text()}
            for p in sorted((benchmark.ROOT / "src").rglob("*.sol"))
        }
        | benchmark.core_sources(args.core_modules),
        ROOTS,
    )
    ast_settings = {"outputSelection": {"*": {"": ["ast"]}}}
    safe_ast = benchmark.compile_json(
        args.solc, {"language": "Solidity", "sources": safe, "settings": ast_settings}
    )
    violations = benchmark.safety_violations(safe_ast)
    if violations:
        raise ValueError(f"safe source audit failed: {violations}")
    upstream = benchmark.closure(archive["sources"], ROOTS)
    safe[WORKLOAD_PATH] = {"content": WORKLOAD_SOURCE}
    upstream[WORKLOAD_PATH] = {"content": WORKLOAD_SOURCE}
    (out / WORKLOAD_PATH).write_text(WORKLOAD_SOURCE)

    variants = [
        (
            f"{compiler}-{source}"
            + ("" if compiler == "solar" else "-ir" if ir else "-legacy"),
            binary,
            sources,
            ir,
        )
        for compiler, binary in [("solc", args.solc), ("solar", args.solar)]
        for source, sources in [("upstream", upstream), ("safe", safe)]
        for ir in ([False, True] if compiler == "solc" else [True])
    ]
    binaries = {}
    artifacts = {}
    for label, binary, sources, ir in variants:
        print(f"Compiling {label}", flush=True)
        settings = {
            "optimizer": {"enabled": True, "runs": args.runs},
            "evmVersion": args.evm_version,
            "viaIR": ir,
            "metadata": {"bytecodeHash": "none", "appendCBOR": False},
            "outputSelection": {
                WORKLOAD_PATH: {
                    "*": ["abi", "evm.bytecode.object", "evm.deployedBytecode.object"]
                },
                "*": {"": ["ast"]},
            },
        }
        payload = {"language": "Solidity", "sources": sources, "settings": settings}
        result = benchmark.compile_json(binary, payload)
        if label.startswith("solc-safe") and benchmark.safety_violations(result):
            raise ValueError(f"{label} safety audit failed")
        folder = out / label
        folder.mkdir()
        (folder / "output.json").write_text(json.dumps(result, indent=2) + "\n")
        binaries[label] = result["contracts"][WORKLOAD_PATH]["Composed"]
        artifacts[label] = {
            "compiler": subprocess.check_output(
                [str(binary), "--version"], text=True
            ).strip(),
            "compiler_sha256": benchmark.digest(Path(binary).read_bytes()),
        }

    proc, url, sender = benchmark.launch_anvil(args.evm_version)
    cases = []
    try:
        addresses = {}
        for label, artifact in binaries.items():
            bytecode = artifact["evm"]["bytecode"]["object"]
            tx = benchmark.rpc(
                url,
                "eth_sendTransaction",
                [{"from": sender, "data": "0x" + bytecode, "gas": hex(80000000)}],
            )
            receipt = None
            for _ in range(200):
                receipt = benchmark.rpc(url, "eth_getTransactionReceipt", [tx])
                if receipt is not None:
                    break
                time.sleep(0.05)
            if receipt is None or int(receipt["status"], 16) != 1:
                raise RuntimeError(f"deployment failed: {label}")
            addresses[label] = receipt["contractAddress"]
            runtime = benchmark.rpc(
                url, "eth_getCode", [receipt["contractAddress"], "latest"]
            )
            artifacts[label]["creation_bytes"] = len(bytecode) // 2
            artifacts[label]["runtime_bytes"] = (len(runtime) - 2) // 2
            artifacts[label]["deployment_gas"] = int(receipt["gasUsed"], 16)

        for workload, entries in workload_cases().items():
            print(f"{workload}: {len(entries)} cases", flush=True)
            for index, (signature, types, values) in enumerate(entries):
                calldata = keccak(signature.encode())[:4] + encode(types, list(values))
                measurements = {}
                for label in binaries:
                    trace = benchmark.rpc(
                        url,
                        "debug_traceCall",
                        [
                            {
                                "from": sender,
                                "to": addresses[label],
                                "data": "0x" + calldata.hex(),
                                "gas": hex(80000000),
                            },
                            "latest",
                            {
                                "disableStorage": True,
                                "disableStack": True,
                                "enableMemory": False,
                            },
                        ],
                    )
                    measurements[label] = {
                        "opcode_gas": sum(
                            int(x["gasCost"]) for x in trace["structLogs"]
                        ),
                        "failed": trace.get("failed", False),
                        "return_data": "0x"
                        + trace.get("returnValue", "").removeprefix("0x").lower(),
                    }
                answers = {
                    (m["failed"], m["return_data"]) for m in measurements.values()
                }
                cases.append(
                    {
                        "workload": workload,
                        "case": index,
                        "calldata": "0x" + calldata.hex(),
                        "agree": len(answers) == 1,
                        "variants": measurements,
                    }
                )
    finally:
        proc.terminate()
        proc.wait(timeout=10)

    report = {
        "schema": "solady-checked-composed-1",
        "evm_version": args.evm_version,
        "optimizer_runs": args.runs,
        "artifacts": artifacts,
        "cases": cases,
    }
    (out / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    write_report(report, out / "report.md")
    disagreeing = [c for c in cases if not c["agree"]]
    print(f"{len(cases)} cases, {len(disagreeing)} disagreements; {out / 'report.md'}")
    return 1 if disagreeing else 0


def write_report(report, path):
    labels = list(report["artifacts"])
    lines = [
        "# Composed workload comparison",
        "",
        f"EVM: {report['evm_version']}; optimizer runs: {report['optimizer_runs']}.",
        "",
        "Each workload chains several libraries in one call. The workload source is "
        "byte-identical across every leg, so the only difference is which library "
        "implementation and which compiler produced the code. Agreement between the "
        "six legs is the correctness check; there is no separate oracle.",
        "",
        "Gas is the sum of executed opcode gas from `debug_traceCall`, excluding "
        "transaction intrinsic gas, and includes the workload's own dispatch, ABI "
        "handling and allocation. The reference is the cheaper of the two upstream "
        "solc pipelines for each call.",
        "",
        "| Workload | Cases | Envelope | Safe Solar | Ratio | Wins | Losses |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    totals = {}
    for case in report["cases"]:
        if not case["agree"]:
            continue
        v = case["variants"]
        env = min(
            v["solc-upstream-legacy"]["opcode_gas"], v["solc-upstream-ir"]["opcode_gas"]
        )
        ours = v["solar-safe"]["opcode_gas"]
        row = totals.setdefault(case["workload"], [0, 0, 0, 0, 0])
        row[0] += 1
        row[1] += env
        row[2] += ours
        row[3] += 1 if ours < env else 0
        row[4] += 1 if ours > env else 0
    grand = [0, 0, 0, 0, 0]
    for workload, row in totals.items():
        for i in range(5):
            grand[i] += row[i]
        ratio = row[2] / row[1] if row[1] else 0
        lines.append(
            f"| `{workload}` | {row[0]} | {row[1]:,} | {row[2]:,} | {ratio:.2f}x |"
            f" {row[3]} | {row[4]} |"
        )
    ratio = grand[2] / grand[1] if grand[1] else 0
    lines.append(
        f"| Total | {grand[0]} | {grand[1]:,} | {grand[2]:,} | {ratio:.2f}x |"
        f" {grand[3]} | {grand[4]} |"
    )
    lines += [
        "",
        "Every leg, so the compiler and the source can be separated:",
        "",
        "| Workload | " + " | ".join(labels) + " |",
        "|---" * (len(labels) + 1) + "|",
    ]
    per_leg = {}
    for case in report["cases"]:
        row = per_leg.setdefault(case["workload"], dict.fromkeys(labels, 0))
        for label in labels:
            row[label] += case["variants"][label]["opcode_gas"]
    leg_totals = dict.fromkeys(labels, 0)
    for workload, row in per_leg.items():
        lines.append(
            f"| `{workload}` | " + " | ".join(f"{row[l]:,}" for l in labels) + " |"
        )
        for label in labels:
            leg_totals[label] += row[label]
    lines.append(
        "| Total | " + " | ".join(f"{leg_totals[l]:,}" for l in labels) + " |"
    )
    same_source = []
    for source in ("upstream", "safe"):
        ours = leg_totals.get(f"solar-{source}")
        theirs = min(
            leg_totals.get(f"solc-{source}-legacy", 0),
            leg_totals.get(f"solc-{source}-ir", 0),
        )
        if ours and theirs:
            same_source.append(
                f"On the {source} sources our compiler costs {ours:,} against solc's "
                f"cheaper pipeline at {theirs:,}, a ratio of {ours / theirs:.2f}."
            )
    if same_source:
        lines += ["", " ".join(same_source)]
    lines += [
        "",
        "Deployed size and cost of the identical workload contract:",
        "",
        "| Leg | Runtime bytes | Creation bytes | Deployment gas |",
        "|---|---:|---:|---:|",
    ]
    for label in labels:
        a = report["artifacts"][label]
        lines.append(
            f"| {label} | {a['runtime_bytes']:,} | {a['creation_bytes']:,} |"
            f" {a['deployment_gas']:,} |"
        )
    disagreeing = [c for c in report["cases"] if not c["agree"]]
    if disagreeing:
        lines += ["", "Disagreeing cases (the runner exits nonzero):", ""]
        for case in disagreeing:
            lines.append(f"- `{case['workload']}` case {case['case']}")
    lines += [
        "",
        "This measures the published workloads only. It is not a claim about "
        "unmeasured inputs, memory aliasing, or APIs outside the three workloads.",
        "",
    ]
    path.write_text("\n".join(lines))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--solc", type=Path, required=True)
    parser.add_argument("--solar", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=200)
    parser.add_argument("--evm-version", default="cancun")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--core-modules",
        type=Path,
        default=benchmark.DEFAULT_CORE_MODULES,
        help="directory holding the compiler-owned solar:core/v1 module sources",
    )
    raise SystemExit(run(parser.parse_args()))


if __name__ == "__main__":
    main()

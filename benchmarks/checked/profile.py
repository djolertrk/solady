#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["eth-abi==5.2.0", "eth-hash[pycryptodome]==0.7.1"]
# ///
"""Attribute the executed gas of recorded comparison cases to cost classes.

Replays exact calldata against the recorded bytecode of one configuration and
classifies every executed instruction with the static bytecode structure:
frame spill traffic (small constant addresses below the heap), payload memory
accesses, checks (comparisons feeding a jump into a reverting block), control
flow, stack movement, ABI and environment work, arithmetic, and an explicit
unattributed remainder. The classes are structural approximations, not a
claim that every load is a spill.
"""

from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import benchmark  # noqa: E402

FRAME_LIMIT = 0x1000
STACK_OPS = {"POP"} | {f"DUP{i}" for i in range(1, 17)} | {f"SWAP{i}" for i in range(1, 17)}
COMPARE_OPS = {"LT", "GT", "SLT", "SGT", "EQ", "ISZERO"}
ABI_OPS = {
    "CALLDATALOAD",
    "CALLDATASIZE",
    "CALLDATACOPY",
    "CALLVALUE",
    "RETURN",
    "RETURNDATASIZE",
    "RETURNDATACOPY",
    "MCOPY",
}
TERMINATORS = {"JUMP", "JUMPI", "STOP", "RETURN", "REVERT", "INVALID", "SELFDESTRUCT"}


def disassemble(code):
    """Returns pc -> (op, immediate or None, next_pc) for a runtime bytecode."""
    ops = {}
    pc = 0
    while pc < len(code):
        byte = code[pc]
        if 0x60 <= byte <= 0x7F:
            width = byte - 0x5F
            immediate = int.from_bytes(code[pc + 1 : pc + 1 + width], "big")
            ops[pc] = (f"PUSH{width}", immediate, pc + 1 + width)
            pc += 1 + width
        else:
            ops[pc] = (OPCODES.get(byte, f"UNKNOWN_{byte:02x}"), None, pc + 1)
            pc += 1
    return ops


def reverting_blocks(ops):
    """Returns the pcs from which straight-line execution reaches REVERT or INVALID.

    A block that ends in an unconditional jump into such a block counts as
    well, so a check that jumps to the continuation and falls through into a
    shared panic block is recognized from either side of its `JUMPI`.
    """
    direct = set()
    for start in ops:
        pc = start
        while pc in ops:
            name, _, next_pc = ops[pc]
            if name in TERMINATORS:
                if name in {"REVERT", "INVALID"}:
                    direct.add(start)
                break
            pc = next_pc
    result = set(direct)
    for start in ops:
        pc = start
        previous = None
        while pc in ops:
            name, immediate, next_pc = ops[pc]
            if name in TERMINATORS:
                if name == "JUMP" and previous is not None and previous in direct:
                    result.add(start)
                break
            previous = immediate if name.startswith("PUSH") else None
            pc = next_pc
    return result


def classify(ops, logs):
    """Assigns every executed step a cost class using static neighbours."""
    reverting = reverting_blocks(ops)
    classes = []
    pending_check = []
    for index, log in enumerate(logs):
        pc = log["pc"]
        op = log["op"]
        immediate = ops.get(pc, (op, None, None))[1]
        following = ops.get(ops[pc][2], (None, None, None))[0] if pc in ops else None
        if op.startswith("PUSH") and following in {"MLOAD", "MSTORE"} and immediate is not None:
            if immediate < FRAME_LIMIT and immediate != 0x40 and immediate >= 0x80:
                cls = "spill"
            elif immediate == 0x40:
                cls = "alloc"
            else:
                cls = "abi"
        elif op in {"MLOAD", "MSTORE"} and index and logs[index - 1]["op"].startswith("PUSH"):
            previous = ops[logs[index - 1]["pc"]][1]
            if previous is not None and 0x80 <= previous < FRAME_LIMIT:
                cls = "spill"
            elif previous == 0x40:
                cls = "alloc"
            else:
                cls = "abi"
        elif op in {"MLOAD", "MSTORE", "MSTORE8"}:
            cls = "payload"
        elif op.startswith("PUSH") and following in {"JUMP", "JUMPI"}:
            jumpi_pc = ops[pc][2]
            fallthrough = ops.get(jumpi_pc, (None, None, None))[2]
            if following == "JUMPI" and (immediate in reverting or fallthrough in reverting):
                cls = "check"
                pending_check.append(len(classes))
            else:
                cls = "control"
        elif op == "JUMPI" and classes and classes[-1] == "check":
            cls = "check"
        elif op in {"JUMP", "JUMPI", "JUMPDEST"}:
            cls = "control"
        elif op in STACK_OPS:
            cls = "stack"
        elif op in ABI_OPS:
            cls = "abi"
        elif op in COMPARE_OPS:
            cls = "compare"
        elif op.startswith("PUSH") or op in {
            "ADD",
            "SUB",
            "MUL",
            "DIV",
            "MOD",
            "EXP",
            "AND",
            "OR",
            "XOR",
            "NOT",
            "SHL",
            "SHR",
            "SAR",
            "BYTE",
            "SIGNEXTEND",
            "ADDMOD",
            "MULMOD",
        }:
            cls = "compute"
        else:
            cls = "other"
        classes.append(cls)
    # A comparison chain immediately preceding a check jump belongs to the check.
    for position in pending_check:
        cursor = position - 1
        while cursor >= 0 and classes[cursor] in {"compare", "compute"} and logs[cursor]["op"] in (
            COMPARE_OPS | {"PUSH1", "PUSH2", "PUSH32", "NOT", "SUB", "ADD", "OR", "AND"}
        ):
            if logs[cursor]["op"] in COMPARE_OPS or classes[cursor] == "compare":
                classes[cursor] = "check"
                cursor -= 1
                continue
            break
    return classes


def profile(results, variant, selected, evm):
    cases = [
        case
        for case in results["cases"]
        if (case["library"], case["api"], case["case"]) in selected
    ]
    missing = selected - {(c["library"], c["api"], c["case"]) for c in cases}
    if missing:
        raise SystemExit(f"cases not found in results: {sorted(missing)}")
    root = Path(results["_root"])
    output = json.loads((root / variant / "output.json").read_text())
    proc, url, sender = benchmark.launch_anvil(evm)
    profiles = []
    try:
        addresses = {}
        codes = {}
        for library in sorted({case["library"] for case in cases}):
            artifact = output["contracts"]["Harness.sol"][library + "Harness"]
            creation = artifact["evm"]["bytecode"]["object"]
            tx = benchmark.rpc(
                url,
                "eth_sendTransaction",
                [{"from": sender, "data": "0x" + creation, "gas": hex(80_000_000)}],
            )
            receipt = None
            for _ in range(200):
                receipt = benchmark.rpc(url, "eth_getTransactionReceipt", [tx])
                if receipt is not None:
                    break
                benchmark.time.sleep(0.05)
            assert receipt and int(receipt["status"], 16) == 1, library
            addresses[library] = receipt["contractAddress"]
            runtime = benchmark.rpc(url, "eth_getCode", [receipt["contractAddress"], "latest"])
            codes[library] = disassemble(bytes.fromhex(runtime[2:]))
        for case in cases:
            trace = benchmark.rpc(
                url,
                "debug_traceCall",
                [
                    {
                        "from": sender,
                        "to": addresses[case["library"]],
                        "data": case["calldata"],
                        "gas": hex(80_000_000),
                    },
                    "latest",
                    {"disableStorage": True, "disableStack": True, "enableMemory": False},
                ],
            )
            logs = trace["structLogs"]
            recorded = case["variants"][variant]
            total = sum(int(log["gasCost"]) for log in logs)
            if total != recorded["opcode_gas"]:
                raise SystemExit(
                    f"replayed gas {total} differs from recorded {recorded['opcode_gas']}"
                )
            if trace.get("failed", False) != case["expected_revert"]:
                raise SystemExit("replayed outcome differs from the recorded expectation")
            classes = classify(codes[case["library"]], logs)
            by_class = collections.Counter()
            steps = collections.Counter()
            by_op = collections.Counter()
            for log, cls in zip(logs, classes):
                by_class[cls] += int(log["gasCost"])
                steps[cls] += 1
                by_op[log["op"]] += 1
            profiles.append(
                {
                    "case_id": case.get("case_id"),
                    "library": case["library"],
                    "api": case["api"],
                    "case": case["case"],
                    "variant": variant,
                    "calldata_bytes": len(case["calldata"]) // 2 - 1,
                    "opcode_gas": total,
                    "gas_by_class": dict(sorted(by_class.items())),
                    "steps_by_class": dict(sorted(steps.items())),
                    "op_counts": dict(sorted(by_op.items())),
                }
            )
    finally:
        proc.terminate()
        proc.wait(timeout=10)
    return profiles


def parse_case(text):
    library_api, _, index = text.rpartition("#")
    library, _, api = library_api.partition(".")
    if not (library and api and index.isdigit()):
        raise argparse.ArgumentTypeError("expected Library.signature#case")
    return library, api, int(index)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", type=Path, required=True, help="comparison output directory")
    parser.add_argument("--variant", default="solar-safe")
    parser.add_argument(
        "--case",
        type=parse_case,
        action="append",
        required=True,
        help="Library.signature#index, repeatable",
    )
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    results = json.loads((args.results / "results.json").read_text())
    results["_root"] = str(args.results.resolve())
    profiles = profile(results, args.variant, set(args.case), results["evm_version"])
    for entry in profiles:
        print(f"{entry['library']}.{entry['api']} case {entry['case']} ({entry['variant']}): "
              f"{entry['opcode_gas']} gas")
        for cls, gas in sorted(entry["gas_by_class"].items(), key=lambda kv: -kv[1]):
            share = 100 * gas / entry["opcode_gas"]
            print(f"  {cls:>9}: {gas:>8} gas ({share:5.1f}%), {entry['steps_by_class'][cls]} steps")
    if args.output:
        args.output.write_text(json.dumps(profiles, indent=2) + "\n")


OPCODES = {
    0x00: "STOP", 0x01: "ADD", 0x02: "MUL", 0x03: "SUB", 0x04: "DIV", 0x05: "SDIV", 0x06: "MOD",
    0x07: "SMOD", 0x08: "ADDMOD", 0x09: "MULMOD", 0x0A: "EXP", 0x0B: "SIGNEXTEND", 0x10: "LT",
    0x11: "GT", 0x12: "SLT", 0x13: "SGT", 0x14: "EQ", 0x15: "ISZERO", 0x16: "AND", 0x17: "OR",
    0x18: "XOR", 0x19: "NOT", 0x1A: "BYTE", 0x1B: "SHL", 0x1C: "SHR", 0x1D: "SAR", 0x1E: "CLZ",
    0x20: "KECCAK256", 0x30: "ADDRESS", 0x31: "BALANCE", 0x32: "ORIGIN", 0x33: "CALLER",
    0x34: "CALLVALUE", 0x35: "CALLDATALOAD", 0x36: "CALLDATASIZE", 0x37: "CALLDATACOPY",
    0x38: "CODESIZE", 0x39: "CODECOPY", 0x3A: "GASPRICE", 0x3B: "EXTCODESIZE",
    0x3C: "EXTCODECOPY", 0x3D: "RETURNDATASIZE", 0x3E: "RETURNDATACOPY", 0x3F: "EXTCODEHASH",
    0x40: "BLOCKHASH", 0x41: "COINBASE", 0x42: "TIMESTAMP", 0x43: "NUMBER", 0x44: "PREVRANDAO",
    0x45: "GASLIMIT", 0x46: "CHAINID", 0x47: "SELFBALANCE", 0x48: "BASEFEE", 0x49: "BLOBHASH",
    0x4A: "BLOBBASEFEE", 0x50: "POP", 0x51: "MLOAD", 0x52: "MSTORE", 0x53: "MSTORE8",
    0x54: "SLOAD", 0x55: "SSTORE", 0x56: "JUMP", 0x57: "JUMPI", 0x58: "PC", 0x59: "MSIZE",
    0x5A: "GAS", 0x5B: "JUMPDEST", 0x5C: "TLOAD", 0x5D: "TSTORE", 0x5E: "MCOPY", 0x5F: "PUSH0",
    0xF0: "CREATE", 0xF1: "CALL", 0xF2: "CALLCODE", 0xF3: "RETURN", 0xF4: "DELEGATECALL",
    0xF5: "CREATE2", 0xFA: "STATICCALL", 0xFD: "REVERT", 0xFE: "INVALID", 0xFF: "SELFDESTRUCT",
}
OPCODES.update({0x80 + i: f"DUP{i + 1}" for i in range(16)})
OPCODES.update({0x90 + i: f"SWAP{i + 1}" for i in range(16)})
OPCODES.update({0xA0 + i: f"LOG{i}" for i in range(5)})


if __name__ == "__main__":
    main()

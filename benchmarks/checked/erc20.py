#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["eth-abi==5.2.0", "eth-hash[pycryptodome]==0.7.1"]
# ///
"""ERC20 comparison for the checked Solady port.

The per-API matrix measures pure library calls; a token is stateful, so this
script replays one sequence of transactions on a fresh deployment of the same
benchmark token per leg: mints, transfers to fresh and existing recipients,
finite, infinite and Permit2 `transferFrom`, approvals, burns, and valid,
replayed, expired and forged permits, with the reverting cases among them. A
Python model of the pinned upstream semantics is the oracle: every
transaction's success, return data and events, and the balances, allowances,
nonces and supply after it, must match it on every leg. The port must also keep
every non-private declaration of the original, and the token's ABI, with its
events and errors, must be the same on every leg.

Gas is the executed opcode gas of each transaction from
`debug_traceTransaction`, excluding transaction intrinsic gas and before
refunds, with cold storage as each transaction starts. Views are measured the
same way with `debug_traceCall`. The six legs are the upstream assembly and the
checked port, each under solc's legacy and IR pipelines and under Solar.
"""

from __future__ import annotations

import argparse
import gzip
import json
import subprocess
import sys
import time
from pathlib import Path

from eth_abi import encode
from eth_hash.auto import keccak

sys.path.insert(0, str(Path(__file__).resolve().parent))
import benchmark  # noqa: E402

TOKEN_PATH = "BenchToken.sol"

TOKEN_SOURCE = """// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "src/tokens/ERC20.sol";

/// @dev A token with a constant name, as a production token has, and
/// unrestricted mint and burn for the benchmark to drive.
contract BenchToken is ERC20 {
    function name() public pure override returns (string memory) {
        return "Bench Token";
    }

    function symbol() public pure override returns (string memory) {
        return "BENCH";
    }

    function _constantNameHash() internal pure override returns (bytes32) {
        return keccak256("Bench Token");
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
"""

MAX = (1 << 256) - 1
PERMIT2 = "0x000000000022d473030f116ddee9f6b43ac78ba3"
ALICE = "0x" + "a1" * 20
BOB = "0x" + "b2" * 20
CAROL = "0x" + "c3" * 20
SPENDER = "0x" + "d4" * 20
OWNER_KEY = 0xB0B
OWNER = benchmark.ec_address(benchmark.ec_mul(OWNER_KEY, benchmark.SECP_G))

TRANSFER_TOPIC = keccak(b"Transfer(address,address,uint256)")
APPROVAL_TOPIC = keccak(b"Approval(address,address,uint256)")
DOMAIN_TYPEHASH = keccak(
    b"EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
)
PERMIT_TYPEHASH = keccak(
    b"Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
)


def error(signature):
    return keccak(signature.encode())[:4]


def word(value):
    return value.to_bytes(32, "big")


def topic(address):
    return "0x" + (bytes(12) + bytes.fromhex(address[2:])).hex()


class Token:
    """The pinned upstream ERC20's observable behavior."""

    def __init__(self):
        self.supply = 0
        self.balances = {}
        self.allowances = {}
        self.nonces = {}

    def balance(self, account):
        return self.balances.get(account, 0)

    def allowance(self, owner, spender):
        if spender == PERMIT2:
            return MAX
        return self.allowances.get((owner, spender), 0)

    def _move(self, sender, to, amount):
        if amount > self.balance(sender):
            return error("InsufficientBalance()")
        self.balances[sender] = self.balance(sender) - amount
        self.balances[to] = self.balance(to) + amount
        return None

    def apply(self, caller, op, args, block):
        """Returns (success, return data, logs) and updates the state."""
        if op == "mint":
            to, amount = args
            if self.supply + amount > MAX:
                return False, error("TotalSupplyOverflow()"), []
            self.supply += amount
            self.balances[to] = self.balance(to) + amount
            return True, b"", [(TRANSFER_TOPIC, "0x" + "00" * 20, to, amount)]
        if op == "burn":
            sender, amount = args
            if amount > self.balance(sender):
                return False, error("InsufficientBalance()"), []
            self.balances[sender] -= amount
            self.supply -= amount
            return True, b"", [(TRANSFER_TOPIC, sender, "0x" + "00" * 20, amount)]
        if op == "transfer":
            to, amount = args
            failure = self._move(caller, to, amount)
            if failure:
                return False, failure, []
            return True, word(1), [(TRANSFER_TOPIC, caller, to, amount)]
        if op == "transferFrom":
            sender, to, amount = args
            if caller != PERMIT2:
                allowed = self.allowances.get((sender, caller), 0)
                if allowed != MAX:
                    if amount > allowed:
                        return False, error("InsufficientAllowance()"), []
                    remaining = allowed - amount
                else:
                    remaining = None
            failure = self._move(sender, to, amount)
            if failure:
                return False, failure, []
            if caller != PERMIT2 and remaining is not None:
                self.allowances[(sender, caller)] = remaining
            return True, word(1), [(TRANSFER_TOPIC, sender, to, amount)]
        if op == "approve":
            spender, amount = args
            if spender == PERMIT2 and amount != MAX:
                return False, error("Permit2AllowanceIsFixedAtInfinity()"), []
            self.allowances[(caller, spender)] = amount
            return True, word(1), [(APPROVAL_TOPIC, caller, spender, amount)]
        if op == "permit":
            owner, spender, value, deadline, v, r, s, _ = args
            if spender == PERMIT2 and value != MAX:
                return False, error("Permit2AllowanceIsFixedAtInfinity()"), []
            if block["timestamp"] > deadline:
                return False, error("PermitExpired()"), []
            expected = permit_digest(
                block, owner, spender, value, self.nonces.get(owner, 0), deadline
            )
            recovered = benchmark.ec_recover(int.from_bytes(expected, "big"), v, r, s)
            if recovered != owner:
                return False, error("InvalidPermit()"), []
            self.nonces[owner] = self.nonces.get(owner, 0) + 1
            self.allowances[(owner, spender)] = value
            return True, b"", [(APPROVAL_TOPIC, owner, spender, value)]
        raise ValueError(op)


def domain_separator(block):
    return keccak(
        DOMAIN_TYPEHASH
        + keccak(b"Bench Token")
        + keccak(b"1")
        + word(block["chain_id"])
        + bytes(12)
        + bytes.fromhex(block["token"][2:])
    )


def permit_digest(block, owner, spender, value, nonce, deadline):
    struct = keccak(
        PERMIT_TYPEHASH
        + bytes(12)
        + bytes.fromhex(owner[2:])
        + bytes(12)
        + bytes.fromhex(spender[2:])
        + word(value)
        + word(nonce)
        + word(deadline)
    )
    return keccak(b"\x19\x01" + domain_separator(block) + struct)


def sign_permit(block, spender, value, nonce, deadline, key=OWNER_KEY, k=0x5EED):
    digest = permit_digest(block, OWNER, spender, value, nonce, deadline)
    v, r, s = benchmark.ec_sign(int.from_bytes(digest, "big"), key, k)
    return (OWNER, spender, value, deadline, v, r, s, digest)


# Each operation: (label, caller, name, argument builder). A builder takes the
# oracle state and the block context, so amounts and signatures follow them.
OPERATIONS = [
    ("mint to fresh holder", ALICE, "mint", lambda t, b: (ALICE, 10**24)),
    ("mint to existing holder", ALICE, "mint", lambda t, b: (ALICE, 10**18)),
    ("transfer to fresh recipient", ALICE, "transfer", lambda t, b: (BOB, 10**20)),
    ("transfer to existing recipient", ALICE, "transfer", lambda t, b: (BOB, 10**20)),
    ("transfer to self", ALICE, "transfer", lambda t, b: (ALICE, 10**18)),
    ("transfer of zero", ALICE, "transfer", lambda t, b: (CAROL, 0)),
    ("transfer beyond balance", BOB, "transfer", lambda t, b: (ALICE, 10**30)),
    ("first approval", ALICE, "approve", lambda t, b: (SPENDER, 10**21)),
    ("approval overwrite", ALICE, "approve", lambda t, b: (SPENDER, 5 * 10**20)),
    (
        "transferFrom, finite allowance",
        SPENDER,
        "transferFrom",
        lambda t, b: (ALICE, BOB, 10**20),
    ),
    (
        "transferFrom beyond allowance",
        SPENDER,
        "transferFrom",
        lambda t, b: (ALICE, BOB, 10**22),
    ),
    ("infinite approval", ALICE, "approve", lambda t, b: (SPENDER, MAX)),
    (
        "transferFrom, infinite allowance",
        SPENDER,
        "transferFrom",
        lambda t, b: (ALICE, CAROL, 10**19),
    ),
    (
        "transferFrom beyond balance",
        SPENDER,
        "transferFrom",
        lambda t, b: (ALICE, BOB, 10**30),
    ),
    ("finite Permit2 approval", ALICE, "approve", lambda t, b: (PERMIT2, 5)),
    ("infinite Permit2 approval", ALICE, "approve", lambda t, b: (PERMIT2, MAX)),
    ("transferFrom by Permit2", PERMIT2, "transferFrom", lambda t, b: (ALICE, BOB, 7)),
    (
        "transferFrom without allowance",
        CAROL,
        "transferFrom",
        lambda t, b: (ALICE, BOB, 1),
    ),
    ("partial burn", ALICE, "burn", lambda t, b: (ALICE, 10**18)),
    ("burn of whole balance", ALICE, "burn", lambda t, b: (CAROL, t.balance(CAROL))),
    ("burn beyond balance", ALICE, "burn", lambda t, b: (CAROL, 1)),
    (
        "permit",
        ALICE,
        "permit",
        lambda t, b: sign_permit(b, SPENDER, 10**20, t.nonces.get(OWNER, 0), 2**40),
    ),
    (
        "replayed permit",
        ALICE,
        "permit",
        lambda t, b: sign_permit(b, SPENDER, 10**20, t.nonces.get(OWNER, 0) - 1, 2**40),
    ),
    (
        "expired permit",
        ALICE,
        "permit",
        lambda t, b: sign_permit(
            b, SPENDER, 1, t.nonces.get(OWNER, 0), b["timestamp"] - 1
        ),
    ),
    (
        "permit by another signer",
        ALICE,
        "permit",
        lambda t, b: sign_permit(
            b, SPENDER, 1, t.nonces.get(OWNER, 0), 2**40, key=0xBAD
        ),
    ),
    (
        "finite Permit2 permit",
        ALICE,
        "permit",
        lambda t, b: sign_permit(b, PERMIT2, 1, t.nonces.get(OWNER, 0), 2**40),
    ),
]

SIGNATURES = {
    "mint": ("mint(address,uint256)", ["address", "uint256"]),
    "burn": ("burn(address,uint256)", ["address", "uint256"]),
    "transfer": ("transfer(address,uint256)", ["address", "uint256"]),
    "transferFrom": (
        "transferFrom(address,address,uint256)",
        ["address", "address", "uint256"],
    ),
    "approve": ("approve(address,uint256)", ["address", "uint256"]),
    "permit": (
        "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
        ["address", "address", "uint256", "uint256", "uint8", "bytes32", "bytes32"],
    ),
}

VIEWS = [
    ("balanceOf", "balanceOf(address)", ["address"], [ALICE], ["uint256"]),
    (
        "allowance",
        "allowance(address,address)",
        ["address", "address"],
        [ALICE, SPENDER],
        ["uint256"],
    ),
    (
        "allowance of Permit2",
        "allowance(address,address)",
        ["address", "address"],
        [ALICE, PERMIT2],
        ["uint256"],
    ),
    ("totalSupply", "totalSupply()", [], [], ["uint256"]),
    ("nonces", "nonces(address)", ["address"], [OWNER], ["uint256"]),
    ("DOMAIN_SEPARATOR", "DOMAIN_SEPARATOR()", [], [], ["bytes32"]),
    ("name", "name()", [], [], ["string"]),
    ("symbol", "symbol()", [], [], ["string"]),
    ("decimals", "decimals()", [], [], ["uint8"]),
]


def calldata(name, args):
    signature, types = SIGNATURES[name]
    values = list(args)
    if name == "permit":
        owner, spender, value, deadline, v, r, s, _ = args
        values = [owner, spender, value, deadline, v, word(r), word(s)]
    return keccak(signature.encode())[:4] + encode(types, values)


def view_value(token, block, label):
    if label == "balanceOf":
        return [token.balance(ALICE)]
    if label == "allowance":
        return [token.allowance(ALICE, SPENDER)]
    if label == "allowance of Permit2":
        return [token.allowance(ALICE, PERMIT2)]
    if label == "totalSupply":
        return [token.supply]
    if label == "nonces":
        return [token.nonces.get(OWNER, 0)]
    if label == "DOMAIN_SEPARATOR":
        return [domain_separator(block)]
    if label == "name":
        return ["Bench Token"]
    if label == "symbol":
        return ["BENCH"]
    return [18]


def state_checks(token):
    """(calldata, expected return data) pairs covering the model's state."""
    checks = [(keccak(b"totalSupply()")[:4], word(token.supply))]
    for account in [ALICE, BOB, CAROL, SPENDER, OWNER]:
        checks.append(
            (
                keccak(b"balanceOf(address)")[:4] + encode(["address"], [account]),
                word(token.balance(account)),
            )
        )
    for owner, spender in [
        (ALICE, SPENDER),
        (OWNER, SPENDER),
        (ALICE, PERMIT2),
        (CAROL, BOB),
    ]:
        checks.append(
            (
                keccak(b"allowance(address,address)")[:4]
                + encode(["address", "address"], [owner, spender]),
                word(token.allowance(owner, spender)),
            )
        )
    checks.append(
        (
            keccak(b"nonces(address)")[:4] + encode(["address"], [OWNER]),
            word(token.nonces.get(OWNER, 0)),
        )
    )
    return checks


def run(args):
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    archive = json.loads(gzip.decompress(benchmark.ARCHIVE.read_bytes()))
    upstream = benchmark.closure(archive["sources"], ["src/tokens/ERC20.sol"])
    safe = {
        "src/tokens/ERC20.sol": {
            "content": (benchmark.ROOT / "src/tokens/ERC20.sol").read_text()
        }
    }
    for sources in (upstream, safe):
        sources[TOKEN_PATH] = {"content": TOKEN_SOURCE}
    (out / TOKEN_PATH).write_text(TOKEN_SOURCE)
    ast_settings = {"outputSelection": {"*": {"": ["ast"]}}}
    asts = {
        source: benchmark.compile_json(
            args.solc,
            {"language": "Solidity", "sources": sources, "settings": ast_settings},
        )
        for source, sources in [("upstream", upstream), ("safe", safe)]
    }
    violations = benchmark.safety_violations(asts["safe"])
    if violations:
        raise ValueError(f"safe source audit failed: {violations}")
    # Every non-private declaration keeps its name, parameters, returns,
    # visibility and mutability, and the port adds none.
    declarations = {
        source: sorted(
            json.dumps(row, sort_keys=True)
            for row in benchmark.api_rows(ast["sources"]["src/tokens/ERC20.sol"]["ast"])
        )
        for source, ast in asts.items()
    }
    if declarations["safe"] != declarations["upstream"]:
        raise ValueError("ERC20 declarations differ from upstream")

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
    bytecodes = {}
    abis = {}
    artifacts = {}
    for label, binary, sources, ir in variants:
        print(f"Compiling {label}", flush=True)
        settings = {
            "optimizer": {"enabled": True, "runs": args.runs},
            "evmVersion": args.evm_version,
            "viaIR": ir,
            "metadata": {"bytecodeHash": "none", "appendCBOR": False},
            "outputSelection": {
                TOKEN_PATH: {"BenchToken": ["abi", "evm.bytecode.object"]}
            },
        }
        start = time.monotonic()
        result = benchmark.compile_json(
            binary, {"language": "Solidity", "sources": sources, "settings": settings}
        )
        elapsed = time.monotonic() - start
        (out / f"{label}.json").write_text(json.dumps(result, indent=2) + "\n")
        contract = result["contracts"][TOKEN_PATH]["BenchToken"]
        bytecodes[label] = contract["evm"]["bytecode"]["object"]
        # Functions, events and errors: the token's whole interface.
        abis[label] = sorted(
            json.dumps(entry, sort_keys=True) for entry in contract["abi"]
        )
        if abis[label] != next(iter(abis.values())):
            raise ValueError(f"ABI mismatch: {label}")
        artifacts[label] = {
            "compiler": subprocess.check_output(
                [str(binary), "--version"], text=True
            ).strip(),
            "compiler_sha256": benchmark.digest(Path(binary).read_bytes()),
            "compile_seconds": elapsed,
        }

    proc, url, sender = benchmark.launch_anvil(args.evm_version)
    operations = []
    views = []
    failures = []
    try:
        chain_id = int(benchmark.rpc(url, "eth_chainId", []), 16)
        for account in [ALICE, BOB, CAROL, SPENDER, PERMIT2, OWNER]:
            benchmark.rpc(url, "anvil_impersonateAccount", [account])
            benchmark.rpc(url, "anvil_setBalance", [account, hex(10**24)])
        tokens = {}
        for label, code in bytecodes.items():
            receipt = transact(url, sender, None, bytes.fromhex(code))
            if int(receipt["status"], 16) != 1:
                raise RuntimeError(f"deployment failed: {label}")
            tokens[label] = receipt["contractAddress"]
            runtime = benchmark.rpc(
                url, "eth_getCode", [receipt["contractAddress"], "latest"]
            )
            artifacts[label]["creation_bytes"] = len(code) // 2
            artifacts[label]["runtime_bytes"] = (len(runtime) - 2) // 2
            artifacts[label]["deployment_gas"] = int(receipt["gasUsed"], 16)

        models = {label: Token() for label in bytecodes}
        for label_op, caller, name, build in OPERATIONS:
            measurements = {}
            for label, token_address in tokens.items():
                model = models[label]
                latest = benchmark.rpc(url, "eth_getBlockByNumber", ["latest", False])
                # The transaction lands in the next block, one second later at least.
                block = {
                    "chain_id": chain_id,
                    "token": token_address.lower(),
                    "timestamp": int(latest["timestamp"], 16),
                }
                op_args = build(model, block)
                data = calldata(name, op_args)
                receipt = transact(url, caller, token_address, data)
                mined = benchmark.rpc(
                    url, "eth_getBlockByNumber", [receipt["blockNumber"], False]
                )
                block["timestamp"] = int(mined["timestamp"], 16)
                success, returned, logs = model.apply(caller, name, op_args, block)
                trace = benchmark.rpc(
                    url,
                    "debug_traceTransaction",
                    [
                        receipt["transactionHash"],
                        {
                            "disableStorage": True,
                            "disableStack": True,
                            "enableMemory": False,
                        },
                    ],
                )
                actual_logs = [
                    (
                        bytes.fromhex(log["topics"][0][2:]),
                        log["topics"][1],
                        log["topics"][2],
                        int(log["data"], 16),
                    )
                    for log in receipt["logs"]
                ]
                expected_logs = [
                    (t0, topic(a), topic(b), amount) for t0, a, b, amount in logs
                ]
                agrees = (
                    (int(receipt["status"], 16) == 1) == success
                    and trace.get("returnValue", "").removeprefix("0x").lower()
                    == returned.hex()
                    and actual_logs == expected_logs
                )
                for query, expected in state_checks(model):
                    got = benchmark.rpc(
                        url,
                        "eth_call",
                        [{"to": token_address, "data": "0x" + query.hex()}, "latest"],
                    )
                    agrees &= got.removeprefix("0x").lower() == expected.hex()
                if not agrees:
                    failures.append(
                        {
                            "operation": label_op,
                            "variant": label,
                            "calldata": "0x" + data.hex(),
                        }
                    )
                measurements[label] = {
                    "opcode_gas": benchmark.opcode_gas(trace["structLogs"]),
                    "success": int(receipt["status"], 16) == 1,
                    "agrees": agrees,
                }
            operations.append({"operation": label_op, "variants": measurements})
            print(
                f"{label_op}: {'ok' if all(m['agrees'] for m in measurements.values()) else 'MISMATCH'}",
                flush=True,
            )

        for label_view, signature, types, values, outputs in VIEWS:
            data = keccak(signature.encode())[:4] + encode(types, values)
            measurements = {}
            for label, token_address in tokens.items():
                block = {"chain_id": chain_id, "token": token_address.lower()}
                trace = benchmark.rpc(
                    url,
                    "debug_traceCall",
                    [
                        {
                            "from": sender,
                            "to": token_address,
                            "data": "0x" + data.hex(),
                            "gas": hex(10**7),
                        },
                        "latest",
                        {
                            "disableStorage": True,
                            "disableStack": True,
                            "enableMemory": False,
                        },
                    ],
                )
                expected = encode(outputs, view_value(models[label], block, label_view))
                agrees = (
                    not trace.get("failed")
                    and trace.get("returnValue", "").removeprefix("0x").lower()
                    == expected.hex()
                )
                if not agrees:
                    failures.append({"operation": label_view, "variant": label})
                measurements[label] = {
                    "opcode_gas": benchmark.opcode_gas(trace["structLogs"]),
                    "agrees": agrees,
                }
            views.append({"operation": label_view, "variants": measurements})
    finally:
        proc.terminate()
        proc.wait(timeout=10)

    report = {
        "schema": "solady-checked-erc20-1",
        "evm_version": args.evm_version,
        "optimizer_runs": args.runs,
        "artifacts": artifacts,
        "operations": operations,
        "views": views,
        "failures": failures,
    }
    (out / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    write_report(report, out / "report.md")
    print(
        f"{len(operations)} transactions, {len(views)} views, {len(failures)} mismatches; {out / 'report.md'}"
    )
    return 1 if failures else 0


def transact(url, sender, to, data):
    tx = {"from": sender, "data": "0x" + data.hex(), "gas": hex(10**7)}
    if to:
        tx["to"] = to
    hash_ = benchmark.rpc(url, "eth_sendTransaction", [tx])
    for _ in range(200):
        receipt = benchmark.rpc(url, "eth_getTransactionReceipt", [hash_])
        if receipt is not None:
            return receipt
        time.sleep(0.02)
    raise RuntimeError("receipt timed out")


def write_report(report, path):
    labels = list(report["artifacts"])
    lines = [
        "# ERC20 comparison",
        "",
        f"EVM: {report['evm_version']}; optimizer runs: {report['optimizer_runs']}.",
        "",
        (
            "One sequence of transactions on a fresh token per leg, checked against a model of "
            "the pinned upstream semantics after every step. Gas is executed opcode gas, excluding "
            "transaction intrinsic gas and before refunds. The envelope is the cheaper upstream "
            "solc pipeline for each row."
        ),
        "",
        "| Operation | Envelope | Safe Solar | Change | " + " | ".join(labels) + " |",
        "|---|---:|---:|---:|" + "---:|" * len(labels),
    ]
    totals = {label: 0 for label in labels}
    envelope_total = 0
    for row in report["operations"] + report["views"]:
        gas = {label: row["variants"][label]["opcode_gas"] for label in labels}
        envelope = min(gas["solc-upstream-legacy"], gas["solc-upstream-ir"])
        envelope_total += envelope
        for label in labels:
            totals[label] += gas[label]
        change = (gas["solar-safe"] - envelope) / envelope * 100 if envelope else 0.0
        lines.append(
            f"| {row['operation']} | {envelope:,} | {gas['solar-safe']:,} | {change:+.2f}% | "
            + " | ".join(f"{gas[label]:,}" for label in labels)
            + " |"
        )
    change = (totals["solar-safe"] - envelope_total) / envelope_total * 100
    lines.append(
        f"| Total | {envelope_total:,} | {totals['solar-safe']:,} | {change:+.2f}% | "
        + " | ".join(f"{totals[label]:,}" for label in labels)
        + " |"
    )
    lines += [
        "",
        "| Leg | Runtime bytes | Creation bytes | Deployment gas |",
        "|---|---:|---:|---:|",
    ]
    for label in labels:
        a = report["artifacts"][label]
        lines.append(
            f"| {label} | {a['runtime_bytes']:,} | {a['creation_bytes']:,} | {a['deployment_gas']:,} |"
        )
    lines += ["", f"Mismatches: {len(report['failures'])}.", ""]
    path.write_text("\n".join(lines))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--solc", type=Path, required=True)
    parser.add_argument("--solar", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=200)
    parser.add_argument("--evm-version", default="cancun")
    parser.add_argument("--output", type=Path, required=True)
    raise SystemExit(run(parser.parse_args()))


if __name__ == "__main__":
    main()

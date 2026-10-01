#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = ["eth-abi==5.2.0", "eth-hash[pycryptodome]==0.7.1"]
# ///
"""Composed-workload comparison for the checked Solady port.

The per-API matrix in `benchmark.py` measures one library call per transaction.
This script measures workloads that chain several libraries in one call, the way
an application uses them: an ERC-721 style metadata URI, a set pipeline over two
lists, a decode-then-scan path, data contracts, clones of every proxy family, token
and ETH transfers, permits, and bounded calls.

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

# The contract each workload calls, when it is not `Composed`.
WORKLOAD_CONTRACT = {"cloneFamilies": "Clones", "cloneArgsLimit": "Clones"}

WORKLOAD_SOURCE = '''// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/utils/Base64.sol";
import "src/utils/LibBit.sol";
import "src/utils/LibCall.sol";
import "src/utils/LibClone.sol";
import "src/utils/LibSort.sol";
import "src/utils/LibString.sol";
import "src/utils/SafeTransferLib.sol";
import "src/utils/SSTORE2.sol";

/// @dev A token whose `transfer`, `transferFrom` and `approve` answer `true`.
contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @dev A token whose `transfer` answers nothing, as older tokens do.
contract QuietToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }
}

/// @dev A token with an EIP-2612 permit that records its arguments.
contract PermitToken {
    bytes32 public constant DOMAIN_SEPARATOR = keccak256("PermitToken");
    bytes32 public recorded;

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        recorded = keccak256(abi.encode(owner, spender, value, deadline, v, r, s));
    }
}

/// @dev A token with DAI's domain separator and permit, recording its arguments.
contract DaiToken {
    bytes32 public constant DOMAIN_SEPARATOR =
        0xdbb8cf42e1ecb028be3f3dbc922e1d878b963f411dc388ced501601c60f7c6f7;
    bytes32 public recorded;

    function nonces(address) external pure returns (uint256) {
        return 7;
    }

    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        recorded = keccak256(abi.encode(holder, spender, nonce, expiry, allowed, v, r, s));
    }
}

/// @dev A beacon that points proxies at one implementation.
contract Beacon {
    address public implementation;

    constructor(address target) {
        implementation = target;
    }
}

/// @dev A contract that refuses every ETH transfer.
contract Rejector {
    receive() external payable {
        revert();
    }
}

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

    /// @dev Store bytes in data contracts three ways, then read ranges back.
    function storeAndRead(bytes memory data, bytes32 salt)
        external
        returns (
            bytes memory whole,
            bytes memory tail,
            bytes memory middle,
            bool counterfactual,
            bool deterministic
        )
    {
        address pointer = SSTORE2.write(data);
        whole = SSTORE2.read(pointer);
        tail = SSTORE2.read(pointer, 1);
        middle = SSTORE2.read(pointer, 1, 5);
        counterfactual = SSTORE2.writeCounterfactual(data, salt)
            == SSTORE2.predictCounterfactualAddress(data, salt);
        deterministic =
            SSTORE2.writeDeterministic(data, salt) == SSTORE2.predictDeterministicAddress(salt);
    }

    /// @dev Clone this contract twice and call through both clones.
    function cloneAndCall(uint256 x, bytes32 salt)
        external
        returns (uint256 viaClone, uint256 viaDeterministic, bool predicted)
    {
        address instance = LibClone.clone(address(this));
        viaClone = Composed(instance).twice(x);
        address deterministic = LibClone.cloneDeterministic(address(this), salt);
        predicted =
            deterministic == LibClone.predictDeterministicAddress(address(this), salt, address(this));
        viaDeterministic = Composed(deterministic).twice(x + 1);
    }

    function twice(uint256 x) external pure returns (uint256) {
        return 2 * x;
    }

    /// @dev Move a token that answers `true` and one that answers nothing.
    function tokenFlow(uint256 amount)
        external
        returns (uint256[4] memory balances, uint256 supply, bool unapproved)
    {
        MockToken token = new MockToken();
        QuietToken quiet = new QuietToken();
        token.mint(address(this), amount * 2);
        quiet.mint(address(this), amount * 2);
        address to = address(0xBEEF);
        SafeTransferLib.safeTransfer(address(token), to, amount);
        SafeTransferLib.safeTransfer(address(quiet), to, amount);
        SafeTransferLib.safeApprove(address(token), to, amount);
        unapproved = SafeTransferLib.trySafeTransferFrom(address(token), to, address(this), 1);
        uint256 rest = SafeTransferLib.safeTransferAll(address(quiet), to);
        balances = [
            SafeTransferLib.balanceOf(address(token), to),
            SafeTransferLib.balanceOf(address(token), address(this)),
            SafeTransferLib.balanceOf(address(quiet), to),
            rest
        ];
        supply = SafeTransferLib.totalSupply(address(token));
    }

    /// @dev Call this contract through LibCall, whole and bounded.
    function callFlow(bytes memory payload, uint16 maxCopy)
        external
        returns (
            bytes memory echoed,
            bool success,
            bool exceeded,
            bytes memory bounded,
            bytes memory reselected
        )
    {
        bytes memory call = abi.encodeCall(this.echo, (payload));
        echoed = abi.decode(LibCall.callContract(address(this), call), (bytes));
        (success, exceeded, bounded) = LibCall.tryCall(address(this), 0, gasleft() / 2, maxCopy, call);
        reselected = abi.encodeCall(this.echo, (payload));
        LibCall.setSelector(this.twice.selector, reselected);
    }

    function echo(bytes memory payload) external pure returns (bytes memory) {
        return payload;
    }

    /// @dev Permit through tokens' own permits, EIP-2612's and DAI's, and
    /// through Permit2, which this chain lacks, so those fail with their errors.
    function permitFlow(uint256 amount, uint8 v, bytes32 r, bytes32 s)
        external
        returns (bytes32 plain, bytes32 dai, bytes memory missing, bytes memory viaPermit2)
    {
        PermitToken token = new PermitToken();
        DaiToken daiToken = new DaiToken();
        SafeTransferLib.permit2(address(token), address(0xA11CE), address(0xB0B), amount, 1000, v, r, s);
        plain = token.recorded();
        SafeTransferLib.permit2(
            address(daiToken), address(0xA11CE), address(0xB0B), amount, 1000, v, r, s
        );
        dai = daiToken.recorded();
        try this.permitWithoutPermit(amount, v, r, s) {}
        catch (bytes memory reason) {
            missing = reason;
        }
        try this.transferFromWithoutPermit2(amount) {}
        catch (bytes memory reason) {
            viaPermit2 = reason;
        }
        SafeTransferLib.permit2Approve(address(token), address(0xB0B), uint160(amount), 5);
        SafeTransferLib.permit2Lockdown(address(token), address(0xB0B));
    }

    function permitWithoutPermit(uint256 amount, uint8 v, bytes32 r, bytes32 s) external {
        SafeTransferLib.permit2(address(0xdead), address(0xA11CE), address(0xB0B), amount, 1000, v, r, s);
    }

    function transferFromWithoutPermit2(uint256 amount) external {
        SafeTransferLib.safeTransferFrom2(address(0xdead), address(0xA11CE), address(0xB0B), amount);
    }

    /// @dev Force ETH into contracts that refuse it, and move ETH through a
    /// vault, as this chain has no mover.
    function ethFlow(uint256 amount)
        external
        returns (
            uint256 forced,
            uint256 forcedAll,
            bool vaultPredicted,
            uint256 vaultBalance,
            bytes memory toMover
        )
    {
        Rejector first = new Rejector();
        SafeTransferLib.forceSafeTransferETH(address(first), amount);
        forced = address(first).balance;
        address vault = SafeTransferLib.safeMoveETH(address(0xB0B), amount);
        bytes32 codeHash = keccak256(
            abi.encodePacked(
                hex"6035600b3d3960353df3fe73",
                address(0xB0B),
                hex"33146025575b600160005260206000f35b3d3d3d3d47335af1601a5760003dfd"
            )
        );
        vaultPredicted = vault
            == address(
                uint160(uint256(keccak256(abi.encodePacked(hex"ff", address(this), bytes32(0), codeHash))))
            );
        vaultBalance = vault.balance;
        try this.moveToMover(amount) {}
        catch (bytes memory reason) {
            toMover = reason;
        }
        Rejector second = new Rejector();
        SafeTransferLib.forceSafeTransferAllETH(address(second));
        forcedAll = address(second).balance;
    }

    function moveToMover(uint256 amount) external {
        SafeTransferLib.safeMoveETH(SafeTransferLib.ETH_MOVER, amount);
    }
}

/// @dev Every LibClone proxy family, in a contract of its own so that its code
/// does not change how the other workloads compile.
contract Clones {
    /// @dev Deploy every proxy family around this contract, with and without
    /// arguments, and read each back: calls through it, its arguments, its
    /// implementation, and its address against the prediction.
    function cloneFamilies(uint256 x, bytes memory args, bytes32 salt)
        external
        returns (uint256[] memory calls, bool[] memory checks, bytes memory readBack, bytes32 codes)
    {
        address beacon = address(new Beacon(address(this)));
        address[12] memory p = _deployFamilies(beacon, args, salt);
        calls = new uint256[](12);
        for (uint256 i; i < 12; ++i) {
            calls[i] = Clones(p[i]).twice(x + i);
        }
        checks = _checkFamilies(p, beacon, x, args, salt);
        readBack = _readFamilies(p, args);
        codes = _familyCodes(args);
    }

    function _deployFamilies(address beacon, bytes memory args, bytes32 salt)
        internal
        returns (address[12] memory p)
    {
        address target = address(this);
        p[0] = LibClone.clone_PUSH0(target);
        p[1] = LibClone.clone(target, args);
        p[2] = LibClone.deployERC1967(target);
        p[3] = LibClone.deployERC1967(target, args);
        p[4] = LibClone.deployERC1967I(target);
        p[5] = LibClone.deployERC1967I(target, args);
        p[6] = LibClone.deployERC1967BeaconProxy(beacon);
        p[7] = LibClone.deployERC1967BeaconProxy(beacon, args);
        p[8] = LibClone.deployERC1967IBeaconProxy(beacon);
        p[9] = LibClone.deployERC1967IBeaconProxy(beacon, args);
        p[10] = LibClone.cloneDeterministic_PUSH0(target, salt);
        p[11] = LibClone.cloneDeterministic(target, args, salt);
    }

    function _checkFamilies(
        address[12] memory p,
        address beacon,
        uint256 x,
        bytes memory args,
        bytes32 salt
    ) internal returns (bool[] memory checks) {
        address target = address(this);
        checks = new bool[](16);
        checks[0] = LibClone.implementationOf(p[0]) == target;
        checks[1] = LibClone.implementationOf(p[1]) == target;
        checks[2] = LibClone.implementationOf(p[2]) == address(0);
        checks[3] = LibClone.implementationOf(p[5]) == target;
        checks[4] = LibClone.implementationOf(p[8]) == target;
        checks[5] = p[10] == LibClone.predictDeterministicAddress_PUSH0(target, salt, target);
        checks[6] = p[11] == LibClone.predictDeterministicAddress(target, args, salt, target);
        checks[7] = LibClone.deployDeterministicERC1967(target, args, salt)
            == LibClone.predictDeterministicAddressERC1967(target, args, salt, target);
        checks[8] = LibClone.deployDeterministicERC1967I(target, salt)
            == LibClone.predictDeterministicAddressERC1967I(target, salt, target);
        checks[9] = LibClone.deployDeterministicERC1967BeaconProxy(beacon, args, salt)
            == LibClone.predictDeterministicAddressERC1967BeaconProxy(beacon, args, salt, target);
        checks[10] = _createTwice(beacon, args, salt);
        checks[11] = _bootstrapFlow(x);
        checks[12] = _bootstrapAndCallFlow(x);
        checks[13] = LibClone.implementationOf(p[9]) == target;
        // `argLoad` past the end of a buffer reads what follows it, which the
        // assembly leaves to memory; `argsOn` buffers are followed by zeros.
        checks[14] = LibClone.argLoad(LibClone.argsOnClone(p[1]), 0) == bytes32(args);
        checks[15] = LibClone.implementationOf(address(0xdead)) == address(0);
    }

    function _createTwice(address beacon, bytes memory args, bytes32 salt) internal returns (bool) {
        (bool first, address made) =
            LibClone.createDeterministicERC1967IBeaconProxy(beacon, args, salt);
        (bool again, address found) =
            LibClone.createDeterministicERC1967IBeaconProxy(beacon, args, salt);
        return !first && again && made == found;
    }

    function _bootstrapFlow(uint256 x) internal returns (bool) {
        address bootstrap = LibClone.erc1967Bootstrap();
        if (bootstrap != LibClone.predictDeterministicAddressERC1967Bootstrap()) return false;
        address upgradable = LibClone.deployERC1967(bootstrap);
        LibClone.bootstrapERC1967(upgradable, address(this));
        return Clones(upgradable).twice(x) == 2 * x;
    }

    function _bootstrapAndCallFlow(uint256 x) internal returns (bool) {
        address called = LibClone.deployERC1967(LibClone.erc1967Bootstrap());
        LibClone.bootstrapERC1967AndCall(called, address(this), abi.encodeCall(this.twice, (x)));
        return Clones(called).twice(x + 1) == 2 * x + 2;
    }

    function _readFamilies(address[12] memory p, bytes memory args)
        internal
        view
        returns (bytes memory read)
    {
        read = bytes.concat(
            LibClone.argsOnClone(p[1]), LibClone.argsOnClone(p[1], 1), LibClone.argsOnClone(p[1], 2, 7)
        );
        read = bytes.concat(read, LibClone.argsOnERC1967(p[3], 1), LibClone.argsOnERC1967I(p[5], 3, 40));
        read = bytes.concat(
            read,
            LibClone.argsOnERC1967BeaconProxy(p[7]),
            LibClone.argsOnERC1967IBeaconProxy(p[9], 0, 2 ** 255)
        );
        bytes memory stored = LibClone.argsOnClone(p[1]);
        read = bytes.concat(read, LibClone.argLoad(stored, 1), LibClone.argLoad(stored, 31));
    }

    function _familyCodes(bytes memory args) internal pure returns (bytes32 h) {
        address a = address(0xA11CE);
        h = keccak256(
            abi.encode(
                LibClone.initCodeHash(a), LibClone.initCodeHash_PUSH0(a), LibClone.initCodeHashERC1967(a)
            )
        );
        h = keccak256(
            abi.encode(h, LibClone.initCodeHashERC1967I(a), LibClone.initCodeHashERC1967BeaconProxy(a))
        );
        h = keccak256(
            abi.encode(
                h, LibClone.initCodeHashERC1967IBeaconProxy(a), LibClone.initCodeHashERC1967Bootstrap(a)
            )
        );
        h = keccak256(
            abi.encode(h, LibClone.initCodeHash(a, args), LibClone.initCodeHashERC1967(a, args))
        );
        h = keccak256(
            abi.encode(
                h, LibClone.initCodeHashERC1967I(a, args), LibClone.initCodeHashERC1967BeaconProxy(a, args)
            )
        );
        h = keccak256(
            abi.encode(
                h,
                LibClone.initCodeHashERC1967IBeaconProxy(a, args),
                keccak256(LibClone.initCodeERC1967IBeaconProxy(a, args))
            )
        );
    }

    /// @dev Arguments too long for a proxy fail its deployment. The assembly
    /// deploys creation code it made invalid, which burns the gas the
    /// creation gets, so this is a workload of its own.
    function cloneArgsLimit() external returns (bool failed) {
        try this.tooManyArgs() {}
        catch (bytes memory reason) {
            failed = keccak256(reason) == keccak256(abi.encodeWithSignature("DeploymentFailed()"));
        }
    }

    function tooManyArgs() external {
        LibClone.deployERC1967I(address(this), new bytes(0xffae));
    }

    function twice(uint256 x) external pure returns (uint256) {
        return 2 * x;
    }
}
'''

ROOTS = [
    "src/utils/Base64.sol",
    "src/utils/LibBit.sol",
    "src/utils/LibCall.sol",
    "src/utils/LibClone.sol",
    "src/utils/LibSort.sol",
    "src/utils/LibString.sol",
    "src/utils/SafeTransferLib.sol",
    "src/utils/SSTORE2.sol",
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
    blobs = [b"", b"a", b"sstore2 data", bytes(range(31)), bytes(range(33)), bytes(range(200))]
    store = [
        ("storeAndRead(bytes,bytes32)", ["bytes", "bytes32"], (b, bytes([k + 1]) * 32))
        for k, b in enumerate(blobs)
    ]
    clones = [
        ("cloneAndCall(uint256,bytes32)", ["uint256", "bytes32"], (x, bytes([k + 7]) * 32))
        for k, x in enumerate([0, 1, 7, 2**128, 2**200, 12345])
    ]
    tokens = [
        ("tokenFlow(uint256)", ["uint256"], (amount,))
        for amount in [1, 2, 1000, 10**18, 2**100, 7]
    ]
    calls = [
        ("callFlow(bytes,uint16)", ["bytes", "uint16"], (b, cap))
        for b, cap in zip(blobs, [0, 32, 64, 96, 0xFFFF, 128])
    ]
    permits = [
        (
            "permitFlow(uint256,uint8,bytes32,bytes32)",
            ["uint256", "uint8", "bytes32", "bytes32"],
            (amount, v, bytes([k + 1]) * 32, bytes([k + 9]) * 32),
        )
        for k, (amount, v) in enumerate(
            [(0, 27), (1, 28), (10**18, 27), (2**160 - 1, 28), (2**160, 27), (2**255, 0)]
        )
    ]
    ether = [
        ("ethFlow(uint256)", ["uint256"], (amount,))
        for amount in [0, 1, 2, 10**15, 10**18, 3 * 10**18]
    ]
    families = [
        (
            "cloneFamilies(uint256,bytes,bytes32)",
            ["uint256", "bytes", "bytes32"],
            (x, bytes((0x41 + i) % 256 for i in range(n)), bytes([k + 3]) * 32),
        )
        for k, (x, n) in enumerate([(0, 0), (1, 1), (7, 20), (2**64, 32), (12345, 33), (3, 100)])
    ]
    return {
        "tokenURI": token,
        "mergeLists": lists,
        "decodeAndScan": scan,
        "storeAndRead": store,
        "cloneAndCall": clones,
        "tokenFlow": tokens,
        "callFlow": calls,
        "permitFlow": permits,
        "ethFlow": ether,
        "cloneFamilies": families,
        "cloneArgsLimit": [("cloneArgsLimit()", [], ())],
    }


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
        binaries[label] = result["contracts"][WORKLOAD_PATH]
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
        for label, contracts in binaries.items():
            addresses[label] = {}
            for name in ["Composed", *sorted(set(WORKLOAD_CONTRACT.values()))]:
                bytecode = contracts[name]["evm"]["bytecode"]["object"]
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
                    raise RuntimeError(f"deployment failed: {label} {name}")
                address = receipt["contractAddress"]
                addresses[label][name] = address
                # `ethFlow` sends ETH out of the contract, the same amount on every leg.
                benchmark.rpc(url, "anvil_setBalance", [address, hex(10**22)])
                if name != "Composed":
                    continue
                runtime = benchmark.rpc(url, "eth_getCode", [address, "latest"])
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
                                "to": addresses[label][
                                    WORKLOAD_CONTRACT.get(workload, "Composed")
                                ],
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
                        # Calls and creations count at what they used, not
                        # at the allowance their steps report.
                        "opcode_gas": benchmark.opcode_gas(trace["structLogs"]),
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
        "unmeasured inputs, memory aliasing, or APIs outside the published workloads.",
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
        help="directory holding the compiler-owned solar:core module sources",
    )
    raise SystemExit(run(parser.parse_args()))


if __name__ == "__main__":
    main()

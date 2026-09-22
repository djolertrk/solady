# Base64 core builtin measurement — 22 September 2026

The checked Solady wrapper now calls the compiler-owned
`solar:core/v1/codecs/Base64.sol` API. Solar lowers these calls to a codec;
solc and Solar's `-Zno-core-intrinsics` execute the checked reference body.
No assembly or `unchecked` block was added to the port or codec body.
The compiler implementation is part of the trusted core layer.

The encoder processes 24 bytes into 32 ASCII byte lanes at once. The decoder
validates and maps 32 ASCII lanes into 24 bytes. Smaller groups use an owned
lookup table; tails access only the logical input. Tables do not borrow the
input, scratch slots, or the zero slot. Output bytes and padding are initialized.
The standard/URL alphabets and padded/unpadded forms are supported. The port
selects the explicit IMAP option when decoding; the core default still rejects
commas. Malformed input reverts with `InvalidBase64()`; upstream Solady leaves
malformed-input results unspecified.

## Measurements

Solc 0.8.37, Cancun, optimizer runs 200. The reference is the cheaper upstream
Solady legacy/via-IR result for each call. These are opcode-gas totals, including
the identical harness's ABI and dispatch work, excluding transaction intrinsic
gas. Totals weight the listed test inputs equally, not production usage.
The baseline is compiler `0063332ae` with checked port `c12f9ef`.
The builtin implementation is compiler commit `eb85a84a4`.

| API | Calls | Previous safe Solar | Builtin safe Solar | Upstream solc envelope | Builtin wins / losses |
|---|---:|---:|---:|---:|---:|
| `encode(bytes)` | 16 | 112,780 | 46,063 | 68,788 | 10 / 6 |
| `encode(bytes,bool)` | 32 | 228,189 | 98,766 | 141,116 | 20 / 12 |
| `encode(bytes,bool,bool)` | 64 | 453,382 | 203,790 | 283,220 | 40 / 24 |
| `decode(string)` | 65 | 616,143 | 356,917 | 312,712 | 10 / 55 |

All 177 cases match the independent oracle in all six compiler/source legs.
Encoding totals beat the solc envelope by 28–33%; decoding is still 14.1%
above it. The worst decoder deficit falls from 16,223 to 1,185 gas. The best
individual encoder improvement against solc is 8,500 gas.

**This is not an optimality claim or an equal-or-better size result.** The
four-API harness grows from 3,783 to 6,247 runtime bytes; upstream solc uses
1,300 bytes in legacy mode and 1,673 via IR. Short inputs remain behind.
Compact lowering, sharing specialized variants, and reducing short-input setup
costs are still needed before calling the Base64 gap closed.

The composed `tokenURI` workload uses 75,587 opcode gas across six calls versus
114,061 for the solc envelope (all six win). `decodeAndScan` uses 114,258 versus
153,635 (four wins, two losses). All 18 composed calls agree in all six legs;
`mergeLists` remains behind and was not changed. The composed safe harness is
12,375 bytes versus upstream solc's 4,406 legacy / 4,139 via IR.

The full five-library run contains 20,605 cases. It retains 132 upstream
oracle disagreements over 44 cases in `toNibbles`, empty-delimiter `split`,
and fixed-width hexadecimal conversion. No checked implementation disagrees.
Those 44 cases are excluded from performance totals; they are not successes.

## Validation

The compiler UI suite passes 4,021 tests (124 filtered); the codegen/sema
unit suite passes 359 tests. New codec tests cover RFC vectors, all 256 input
byte values in both decoder paths, dirty tails, repeated allocations, all
encoding modes, malformed padding, and the portable fallback. The 11 benchmark
unit tests pass, including nested core-module resolution.

The ordinary 33-entry runtime/project corpus has identical baseline/candidate
output fingerprints, gas and sizes. The known Uniswap V2 `chainid` syntax
compilation failure remains. Strict Clippy encounters two pre-existing
`too_many_arguments` findings in `indvar_simplify.rs`; rerunning with that lint
allowed reports no other warnings. Rust formatting and diff whitespace checks
pass. This is test evidence, not an all-input correctness proof.

## Reproduce

From this fork, with the matching Solar checkout built:

```sh
uv run benchmarks/checked/benchmark.py \
  --solc "$BENCH_SOLC" --solar ../solar/target/debug/solar \
  --api 'Base64.encode(bytes)' --api 'Base64.encode(bytes,bool)' \
  --api 'Base64.encode(bytes,bool,bool)' --api 'Base64.decode(string)' \
  --isolate-api --runs 200 --evm-version cancun \
  --output target/base64-core
```

Omit `--api` and `--isolate-api` for the full matrix. Use `composed.py` with
those compiler, fork and runs settings for the composed workloads. Each output
retains standard JSON inputs, compiled artifacts, source/compiler hashes,
calldata, oracle checks, gas and bytecode sizes. The local investigation's
artifacts are in `../solar/target/core-base64/{baseline,v4}/`.

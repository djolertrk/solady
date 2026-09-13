# Checked Solady experiment

**This is a partial port and a reproducible comparison. The CTO's full
API-compatibility and equal-or-better gas target is not met.**

The five implementations listed below in `src/utils/` contain neither inline assembly nor
`unchecked` blocks. Arithmetic and array indexing retain Solidity's checks;
explicit bit operations and `mulmod` keep their defined Solidity semantics.
This is the experiment's concrete meaning of “safe”, not a security audit.
The benchmark checks the compiler AST of every safe source and dependency,
including the generated harness. It never substitutes an upstream assembly
implementation for a missing safe operation.

The reference is Solady v0.1.26, commit
[`acd959aa4bd04720d640bf4e6a5c71037510cc4b`](https://github.com/Vectorized/solady/tree/acd959aa4bd04720d640bf4e6a5c71037510cc4b),
from the repository's pinned
[`upstream-solady-0.1.26.json.gz`](benchmarks/checked/upstream-solady-0.1.26.json.gz).
That archive contains a 90-source profile; it is not the entire current
upstream repository. Derived code retains the upstream MIT license in
[`LICENSE-UPSTREAM`](benchmarks/checked/LICENSE-UPSTREAM), including SafeCastLib's original
author attribution. `LibBit` uses upstream's bit-permutation masks, and
`LibSort` uses its `mulmod` hash with typed, bounds-checked array accesses.

This branch replaces only the five libraries below in `src/utils`. Other
upstream libraries and tests still contain assembly and unchecked blocks.
LibSort and LibString have reduced APIs, so the whole upstream suite and
consumers of missing functions are not expected to compile on this branch.
Use the scoped runner commands below for the published subset.

## Implemented surface

| Library | Implemented non-private functions | Pinned function surface |
|---|---:|---:|
| SafeCastLib | 95 | 95 |
| LibBit | 24 | 24 |
| Base64 | 4 | 4 |
| LibSort | 49 | 57 |
| LibString | 48 | 57 |

These are function-declaration counts, not a claim of complete source or
behavioral compatibility. The runner checks parameter names, types and locations,
return types and locations, visibility, and mutability against upstream.
This includes preserving named-call syntax. It records
the missing functions across the archive in `api-coverage.json`.

The port currently covers checked casts, bit operations, Base64, four typed
array overloads for sorting, copying, reversing, duplicate checks, sorted
search, and the sorted set operations, and the value-oriented string
functions (conversion, inspection, search, slicing, splitting, small
strings, escaping, and packing). The 17 declarations still absent need an
in-place memory resize, raw storage references, or a nonlocal return, which
ordinary checked Solidity cannot express with the original signature.
Tokens, authentication, proxies, cryptography, storage utilities, and other
libraries remain outside this port. Missing constants and user-defined
types are also outside the function audit.

## Run the comparison

Install `uv`, `anvil`, and the solc version pinned in
the compiler repository’s `.github/workflows/bench.yml`. The measured
run below used solc 0.8.37. Set `BENCH_SOLC` to its absolute binary path and
run from this fork’s root. The default compiler path assumes a sibling
`../solar` checkout; `--solar` accepts any compatible binary:

```sh
cargo build --manifest-path ../solar/Cargo.toml -p solar-compiler --bin solar
uv run benchmarks/checked/benchmark.py \
  --solc "$BENCH_SOLC" --solar ../solar/target/debug/solar \
  --runs 200 --evm-version cancun \
  --output target/safe-solady/run-200

uv run benchmarks/checked/benchmark.py \
  --solc "$BENCH_SOLC" --solar ../solar/target/debug/solar \
  --runs 1000000 --evm-version cancun \
  --output target/safe-solady/run-1000000
```

Output directories must be fresh. **The current comparison exits 1** because
of the compatibility discrepancies below; it still writes the full results.
There is no switch to count a mismatch as a performance win.

For each run, the exact same generated external wrappers, calldata, EVM fork,
optimizer runs, and metadata settings are used in six configurations:

| Compiler | Original Solady | Checked port |
|---|---|---|
| solc legacy | measured | measured |
| solc via-IR | measured | measured |
| Solar | measured | measured |

The primary comparison is the checked port compiled by Solar against the cheaper
of the two upstream solc results **for each call**. This is stricter than
selecting one solc pipeline for an entire deployed contract. The other three
configurations distinguish compiler effects from rewrite effects.

The runner starts an isolated Anvil instance, deploys each harness with the
normal code-size limit, and traces independent pure calls. Opcode gas includes
memory expansion, dispatch, decoding and encoding; it excludes transaction
intrinsic gas. Deployment gas and creation/runtime size are separate fields.
Harness size measures the same exposed function subset, not a production
application. Compilation time is one observed sample per configuration, not
a statistically meaningful compiler-speed benchmark.

Every call is checked against a Python oracle, including exact return or
revert bytes. A disagreement in **any** configuration excludes that case from
gas rankings. All cases, including failures, remain in `results.json` with
replay calldata. Coverage includes every integer narrowing boundary, every bit
position and population count, signed/unsigned/address/bytes32 extrema, empty
and duplicate arrays, partition thresholds, and buffer lengths across word
boundaries. Base64 uses Python's standard encoder as its independent oracle.

The output includes:

- `report.md`: summary, sizes, and compatibility failures.
- `api-gas.md`: per-function wins, ties, losses, and worst regressions.
- `results.json`: all six measurements for each case, deployment data,
  compiler versions/hashes, source hashes, and mismatches.
- `api-coverage.json`: declaration coverage and missing functions.
- `<configuration>/input.json` and `output.json`: exact compilation inputs,
  ABI, and bytecode, sufficient to reproduce a failing call.

## Measured result at 200 runs

The local run on branch `feat/safe-solady` used compiler commit `f9a57a2d3`,
solc `0.8.37+commit.f401782d`, Cancun, and no CBOR metadata. All **9,201** cases
matched the oracle in the three configurations compiling the checked source.
There were **120** mismatching upstream executions across **40** cases,
excluded from performance comparisons. These are bounded tests, not an
all-input equivalence proof.

Representative opcode gas measurements, including identical harness overhead:

| Call | Original / best solc | Checked / Solar |
|---|---:|---:|
| `SafeCastLib.toInt128(0)` | 461 | 215 |
| `LibBit.reverseBytes(0)` | 719 | 566 |
| `LibBit.reverseBits(0)` | 818 | 762 |
| `Base64.encode`, 256-byte input | 15,039 | 127,545 |
| `LibSort.sort(uint256[])`, 64 mixed values | 33,187 | 167,582 |
| `LibSort.insertionSort(uint256[])`, 64 descending values | 112,215 | 636,561 |

Both wins and losses are shown deliberately. These examples are not an
aggregate score. The full per-function report retains every regression.
Several simple operations already meet the gas target, but bulk bytes/string
processing and sorting need substantial further work.

A second full run at **1,000,000 optimizer runs** also checked 9,201 cases,
with the same 40 upstream discrepancies and no mismatches for checked code.
The target remains unmet at that setting. For example, checked signed
narrowing costs 215 gas versus 478 for upstream/best-solc, and byte reversal
costs 502 versus 618. Bit reversal costs 764 versus 760, so its small win at
200 runs does **not** generalize to this setting. Both full reports retain
the per-call measurements.

| Identical harness | Original / solc legacy bytes | Original / solc IR bytes | Checked / Solar bytes |
|---|---:|---:|---:|
| SafeCastLib | 7,352 | 6,597 | 3,425 |
| LibBit | 3,342 | 3,058 | 2,670 |
| Base64 | 1,300 | 1,673 | 2,285 |
| LibSort, partial | 2,777 | 2,505 | 8,330 |
| LibString, partial | 3,033 | 2,954 | 3,001 |

## Compiler optimization checkpoint, 2026-09-11

The first retained compiler change keeps a single loop counter on the EVM
stack in eligible branching loops with multiple byte stores. The checked
library sources are unchanged. The comparison uses the exact same six compiler
inputs as the fresh baseline, including wrappers and calldata.

| 256-byte input, 200 optimizer runs | Checked baseline gas | Checked candidate gas | Original / best solc gas |
|---|---:|---:|---:|
| `toHexString(bytes)` | 121,743 | 94,552 | 28,952 |
| `toHexStringNoPrefix(bytes)` | 121,365 | 94,192 | 28,798 |

The checked LibString harness shrinks from 3,001 to 2,900 runtime bytes.
At 1,000,000 runs the prefixed case falls from 121,674 to 94,483 gas and
its harness shrinks from 3,053 to 2,952 bytes. At each setting, 32 comparable
LibString cases improve, 328 stay equal, and 123 increase by exactly 1 gas
because of an additional executed `JUMPDEST`. Other checked library calls
and original-source calls have unchanged gas in this matrix. The 40 previously
excluded cases retain their original-source failures; all 9,201 checked-source
cases still match the oracle at both settings.

For the prefixed 256-byte case, executed `MLOAD`s fall from 5,898 to 2,057,
and `MSTORE`s from 1,806 to 12. The output still performs 512 `MSTORE8`s;
this improvement removes spill traffic rather than changing the source or
replacing byte processing with a word-at-a-time algorithm.

An additional 40 held-out hex cases through 1,024 input bytes matched Python’s
hex encoding oracle in four configurations: both original-source solc pipelines
and the baseline/candidate checked compiler builds. None regressed against the
checked baseline. Prefixed encoding at 1,024 bytes drops from 483,621 to 375,020
opcode gas; original / best solc uses 112,524 gas on that same call.

The compiler change also passes 3,110 codegen UI tests, 292 codegen unit tests,
and 54 Standard JSON tests. Its reduced checked encoder reports bounded compiler
agreement with solc. The shared runtime/project corpus has no measured per-call
gas or size regressions; all compiler-side entries succeed, and the original
solc v4-core compilation failure is unchanged. Compiler-time measurements ran
alongside local validation and do not establish compiler-time parity.

This is progress toward the codec milestone, not gas parity. At 200 runs,
that prefixed case remains 65,600 gas behind original Solady / best solc.
ASCII, Base64, sorting, broader API coverage, and the other milestones remain.

## Compiler optimization checkpoint, 2026-09-11, loop and codec work

The second retained compiler round keeps the checked library sources frozen
and changes only the compiler on `feat/safe-solady`: loop state stays on the
EVM stack through live join layouts, a memory-object argument is disjoint from
every allocation, call summaries ignore stores on reverting paths, the
free-memory-pointer and length reads hoist across memory-clean helper calls,
checked-loop relations prove `i < length / 2` and `length - 1 - i` bounds,
counters with constant start and step never wrap within the target's 64-bit
gas budget, fixed-bytes literals compare as words, and small lookup helpers
are cloned into the loops that call them when the loop's live words leave
room. The measurement below uses the same isolated harness, calldata, solc
`0.8.37`, Cancun, and 200 optimizer runs as the frozen baseline on compiler
commit `d68e26f14`; every executed checked-source case still matches the
independent oracle.

Opcode gas summed over each API's isolated cases. "Wins" counts cases at or
below the original / best solc envelope; the envelope column is that sum.

| API | Cases | Wins | Original / best solc | Checked baseline | Checked now | Change |
|---|---:|---:|---:|---:|---:|---:|
| `LibSort.insertionSort(uint256[])` | 46 | 37 | 590,226 | 2,350,568 | 536,435 | -77.2% |
| `LibSort.sort(uint256[])` | 46 | 29 | 318,592 | 1,463,708 | 518,895 | -64.5% |
| `LibSort.insertionSort(address[])` | 46 | 8 | 647,365 | 2,743,738 | 864,338 | -68.5% |
| `LibSort.copy(address[])` | 46 | 46 | 315,338 | 488,177 | 302,008 | -38.1% |
| `LibSort.reverse(address[])` | 46 | 0 | 282,276 | 484,518 | 379,324 | -21.7% |
| `LibSort.hasDuplicate(uint256[])` | 46 | 18 | 186,151 | 283,982 | 272,182 | -4.2% |
| `LibString.toHexString(bytes)` | 16 | 1 | 122,680 | 472,788 | 170,661 | -63.9% |
| `LibString.toString(uint256)` | 19 | 0 | 67,611 | 172,304 | 124,384 | -27.8% |
| `LibString.toCase(string,bool)` | 6 | 0 | 19,580 | 47,500 | 38,934 | -18.0% |
| `LibString.runeCount(string)` | 6 | 0 | 25,484 | 70,665 | 56,742 | -19.7% |
| `LibString.is7BitASCII(string)` | 9 | 9 | 8,787 | 45,615 | 7,915 | -82.6% |
| `LibBit.countZeroBytes(bytes)` | 17 | 17 | 17,014 | 116,351 | 13,223 | -88.6% |
| `LibBit.countZeroBytesCalldata(bytes)` | 17 | 17 | 16,339 | 98,602 | 10,929 | -88.9% |
| `LibBit.popCount(uint256)` | 776 | 776 | 371,704 | 465,626 | 285,594 | -38.7% |
| `LibBit.clz(uint256)` | 776 | 1 | 349,976 | 568,335 | 545,169 | -4.1% |
| `LibBit.toNibbles(bytes)` | 15 | 1 | 20,084 | 170,211 | 96,279 | -43.4% |
| `Base64.encode(bytes)` | 16 | 0 | 68,788 | 496,710 | 353,725 | -28.8% |
| `Base64.decode(string)` | 65 | 0 | 312,712 | 2,796,465 | 1,859,597 | -33.5% |
| `SafeCastLib.toUint40(uint256)` | 6 | 0 | 2,384 | 3,670 | 3,574 | -2.6% |

Five APIs now meet the envelope on every case: the two zero-byte counters,
7-bit ASCII, `popCount`, and `copy(address[])`. `insertionSort(uint256[])`
beats the envelope in aggregate and on 37 of 46 cases; the descending inputs
still trail. The insertion-sort inner loop keeps its counters and the element
value on the stack with no bounds branch, and the reversal loop carries no
check at all. The decode loop reads its input length once, keeps no wrap
check, and clones its lookup helper at all four sites; the encoder's helper
stays shared at three of four sites because the loop already holds ten live
words, and cloning it regardless costs the encoder more than half its gas in
spills, which locates the remaining codec gap in the backend's join layouts
rather than in the middle end.

The shared runtime corpus, compiled with the same compiler and compared
against the branch's previous head, improves geometric-mean runtime gas by
0.20% and runtime size by 0.36%. The largest per-case move is the upstream
LibString workload at -3.05% gas and -1.96% bytes; the only per-call
increases are 38 gas on two-element sorts and 15 gas on one flash-loan fee
path, and one contract grows by 8 bytes. All 3,630 codegen UI tests and
295 codegen unit tests pass. Isolated artifacts are under
`solar/target/safe-solady/m5/final-mixed-200/` and the corpus comparison under
`solar/target/codegen-bench/cmp-final.md`.

A follow-up compiler change converts the checked bit search's `if` steps
into the shift-and-or chain of the assembly original and lets memory stores
skip the cleanup of already-canonical words. Over the same matrix, `clz`
falls from 545,169 to 490,872 opcode gas, `sort` from 518,895 to 492,404
(37 of 46 wins), `insertionSort(uint256[])` from 536,435 to 509,874, and
`insertionSort(address[])` from 864,338 to 832,722; the other APIs are
unchanged. Those artifacts are under `solar/target/safe-solady/m5/ifc2-mixed-200/`.

At 1,000,000 optimizer runs the checked results are within a few hundred gas
of the 200-run figures, while the original-source envelope tightens:
`insertionSort(uint256[])` keeps 37 of 46 wins, `popCount` all 776, the zero
counters and 7-bit ASCII every case, but `copy(address[])` keeps only 12 of
46 against a reference that drops to 291,974 gas. The other APIs stay below
the envelope by the same margins as at 200 runs. Those artifacts are under
`solar/target/safe-solady/m5/final-mixed-1m/`.

## Compiler optimization checkpoint, 2026-09-12, codec control flow

The branch was rebased onto the rewritten `feat/isle-mir` (dispatcher
inlining and gas-observation barriers); on the same matrix the rebase alone
changes only the zero-byte counters, which gain about 5% from upstream. The
third compiler round then targets the branch control that dominated the
codec profiles: if-conversion now prices every small diamond or triangle
through the target cost model and also converts two literal arms
(`B + c * (A - B)`), a literal over an already-selected value whose
condition is implied (`x < 64 ? T1 : x < 96 ? T2 : T3` collapses one level
at a time), and any pair of cheap arms as `f + c * (t - f)`; a `loop-split`
pass duplicates a counted loop whose body tests `i + k < n` into a main loop
running while `i + K < n` and the original loop for the last groups, and
check elimination folds the lookahead guards in the main loop from that
bound. The checked sources stay frozen for this measurement.

| API | Cases | Original / best solc | Checked before | Checked now | Change |
|---|---:|---:|---:|---:|---:|
| `Base64.decode(string)` | 65 | 312,712 | 1,859,597 | 1,711,796 | -7.9% |
| `Base64.encode(bytes)` | 16 | 68,788 | 353,603 | 334,156 | -5.5% |
| `LibSort.sort(uint256[])` | 46 | 318,592 | 492,404 | 492,098 | -0.1% |
| `LibSort.insertionSort(uint256[])` | 46 | 590,226 | 509,874 | 509,568 | -0.1% |
| `LibSort.insertionSort(address[])` | 46 | 647,365 | 832,722 | 832,526 | 0.0% |
| `LibString.runeCount(string)` | 6 | 25,484 | 56,742 | 57,072 | +0.6% |

The other twelve APIs are unchanged and every executed checked-source case
still matches the oracle. On the 344-character decode case the decoder's
lookup helper is now straight-line arithmetic and the main loop carries no
`i + k < n` guard: control falls from 40,512 to 21,272 gas and the case from
102,571 to 93,565 gas. Its cost is now arithmetic (37%), stack movement and
spills (31%), and the remaining branches (23%): the two range tests of every
lookup, the three output-length guards, and the loop. The encoder's helper
keeps its two-table diamond because both arms compute a byte lookup, so it
stays a call at three of four sites.

A separately measured source change writes that helper in the table-select
form the decoder already uses (`bytes32 table = index < 32 ? ENCODE0 :
ENCODE1; return table[index & 31];`): the helper becomes six straight-line
instructions, the hot-leaf inliner clones it at every site, and
`Base64.encode(bytes)` falls further to 325,680 gas (82,287 on the 256-byte
case), with no oracle mismatch. That case now spends 26% of its gas in spill
traffic and 18% in stack movement, so the residual codec gap is register
pressure inside the group loop rather than branches or calls.

The shared runtime corpus compiled with the same compiler is unchanged in
geometric-mean gas and 0.01% smaller; the only per-call increases are the
upstream LibString rune-count differential tests at 344 to 707 gas, where
the smaller helper body now passes the single-use inliner's stack estimate
and is inlined into a test function whose live words the estimate does not
price. Artifacts: `solar/target/safe-solady/m5/rb-base-mixed-200/` (rebased,
before), `rb-cand1-mixed-200/` (compiler round), `rb-cand1-encsrc-200/`
(source change), and the corpus comparison `solar/target/codegen-bench/cmp-rb1.md`.

## Compiler optimization checkpoint, 2026-09-12, element canonicality

Element reads of typed memory arrays are masked to the element type, since
inline assembly may store dirty words and solc masks such reads too. The
fourth compiler round proves, per array, the widest word it can hold (a
least fixed point over the call graph: the widest word any reachable
function stores into an element, the element width ABI decoding validates
for an external parameter, zero for a zeroed allocation, the widest argument
any call site passes for an internal parameter, recursion included) and
drops the masks that cover the bound, while a mask narrower than the array's
words stays. The proved bounds also feed the ABI return proofs, so returned
arrays keep their bulk-copy encoding. Sources are frozen for this
measurement; the branch was first rebased onto the rewritten `feat/isle-mir`
at `ce9ddc81a`, which changed nothing on this matrix.

| API | Cases | Original / best solc | Checked before | Checked now | Change |
|---|---:|---:|---:|---:|---:|
| `LibSort.insertionSort(address[])` | 46 | 647,365 | 839,439 | 781,605 | -6.9% |
| `LibSort.reverse(address[])` | 46 | 282,276 | 379,324 | 366,164 | -3.5% |
| `LibSort.copy(address[])` | 46 | 315,338 | 302,008 | 288,540 | -4.5% |

`copy(address[])` keeps its 46 wins with a wider margin; the other sixteen
APIs are unchanged and every executed case matches the oracle. The complete
harness keeps 5 of its 27 address masks: two in `hasDuplicate(address[])`,
whose `uint256` scratch stores widen that function's bound, and three in the
ABI encoders. The shared runtime corpus is bit-identical. Two experiments
were measured and rejected: writing the decoder's lookup helper with a
validity table instead of its range test makes the helper branch-free and
inlined at every site but costs 14% more through stack traffic, and a wider
hot-leaf inlining budget for straight-line helpers changes no bytecode.
Artifacts: `solar/target/safe-solady/m5/rb-base3-mixed-200/` (before) and
`rb-cand4-mixed-200/` (after); corpus comparison
`solar/target/codegen-bench/cmp-rb4.md`.

## Port checkpoint, 2026-09-13, coverage, sizes, and both run settings

The port now implements 220 of the 237 non-private declarations of the five
libraries: every declaration of Base64, LibBit, and SafeCastLib, 49 of 57 in
LibSort, and 48 of 57 in LibString. This round added `searchSorted`,
`inSorted`, `difference`, `intersection`, and `union` for all four element
types and `clean` in LibSort, and `toHexStringChecksummed`, `replace`,
`indexOf` and `lastIndexOf` (both forms), `contains`, `startsWith`,
`endsWith`, `repeat`, `slice` (both forms), `indicesOf`, `split`,
`fromSmallString`, `normalizeSmallString`, `toSmallString`, `escapeHTML`,
`escapeJSON` (both forms), `encodeURIComponent`, `eqs`, `cmp`, `packOne`,
`unpackOne`, `packTwo`, and `unpackTwo` in LibString, each with an
independent Python oracle in the runner. The runner also accepts a run
without `--api` filters, which measures every implemented API.

The 17 declarations still absent are excluded by scope decision, not
omission: `uniquifySorted` and `groupSum` (eight declarations) shrink a
memory array in place, the eight `StringStorage` functions read and write
raw storage slots through a custom packing, and `directReturn` ends the
call from inside a library. Ordinary checked Solidity cannot express any of
them with the original signature, so a compatible port would need either an
API change or a compiler primitive; both are disclosed rather than
introduced.

At 200 runs the complete matrix has 20,421 cases. The checked source
matches the oracle on both compilers in every case. The 135 original-source
mismatches are the 114 fixed-width hexadecimal cases with byte count zero
and the 6 `toNibbles` cases recorded before, plus 15 new ones in `split`:
when the delimiter is longer than the subject, the original `indicesOf`
returns a null pointer that `split` dereferences, so the original's output
depends on scratch memory (solc's builds return an extra NUL element on
those inputs; our build of the same assembly happens to return the
documented result on 4 of the 11 cases). The checked `split` returns the
subject as its only element. All three classes stay excluded from rankings
and visible in the results.

The new APIs are correct but mostly not yet at parity. The binary searches
are: `searchSorted(uint256[])` and `(bytes32[])` win all 791 cases,
`inSorted(address[])` all 800, `searchSorted(int256[])` 857 of 870;
`startsWith` and `endsWith` win 62 of 72. The set operations and the
byte-loop string functions trail the assembly by the same per-byte
overhead as the codecs: worst cases are `repeat` (+251,501 gas on a
363-byte result), `split` (+50,050), `escapeHTML` (+44,729), `replace`
(+41,393), `encodeURIComponent` (+37,465), and `indicesOf` (+36,787), and
`union` wins none of its 184 cases. Their gates belong to M4-class
word-at-a-time work, not to further porting.

At 1,000,000 optimizer runs the frozen matrix keeps the same shape as at
200: the zero counters, `popCount`, `is7BitASCII`, and `copy(address[])`
win every case (`copy` 286,516 against an envelope of 291,974),
`insertionSort(uint256[])` and `sort` keep 37 of 46, `hasDuplicate` 17,
`clz` still 1 of 776 although it falls to 405,512 from 490,872, and the
codecs are unchanged. Runtime bytes of the identical harnesses at 200 runs,
checked source on our compiler against the original on solc legacy and
via-IR: Base64 3,635 against 1,300 and 1,673; LibBit 3,320 against 3,342
and 3,058; LibSort 7,365 against 2,777 and 2,505 (solc on the checked
source: 10,955 and 6,126); LibString 2,838 against 3,033 and 2,954;
SafeCastLib 4,224 against 7,352 and 6,597. Base64 and LibSort carry the
documented size cost of the typed byte and sort loops; the other three
harnesses are smaller than the original on solc. Artifacts:
`solar/target/safe-solady/m7/port-200/` (complete matrix) and
`solar/target/safe-solady/m5/rb-base4-mixed-1m/` (1,000,000 runs).

## Compatibility findings and remaining boundaries

The pinned original behaves differently from the intended value-level oracle
in two reproducible cases. Both solc pipelines and Solar reproduce
these differences when compiling the original source:

- `LibString.toHexString[NoPrefix](value, 0)` exhausts the call's gas budget.
  Its assembly loop runs at least once and decrements away from its initial
  end pointer. The checked port returns the empty representation for zero
  or `HexLengthInsufficient()` for a nonzero value. This is an explicit
  compatibility difference, never a gas win.
- `LibBit.toNibbles` returns corrupted bytes for the two 256-byte test inputs
  through the shared wrapper. The original uses the advanced input pointer
  `s`, instead of the input length `n`, when updating the free-memory pointer
  and zeroing after the result. The checked port returns the oracle's nibbles.

The original files for these cases were also compared byte-for-byte against
the pinned GitHub tag. No upstream source was patched for the comparison.
The raw failure records are retained for reproduction, not allowlisted.

Full API compatibility needs a separate decision for APIs ordinary Solidity
cannot express while retaining the original semantics:

- `LibString.directReturn` returns successfully from the enclosing external
  EVM call. An ordinary `return` in an internal helper only returns from that
  helper, so it cannot implement the same API.
- `LibSort.uniquifySorted` changes a memory array's length in place, including
  through aliases. Returning a newly allocated array changes its signature
  and alias behavior. Solidity does not expose a memory-array resize method.
- Raw storage-reference conversions and custom storage layouts require
  preserving existing representation and aliasing, not merely substituting
  ordinary state variables.

We must either exclude such APIs from the safe compatibility target or add
well-defined, checked language/compiler primitives for them. Hiding assembly
in a dependency or adding `assembly ("memory-safe")` does not meet this
experiment's policy. Implementing compiler primitives is a separate change;
none were added here.

Typed custom-error reverts can add error entries to the generated ABI that
the original assembly implementation did not expose. Callable ABI entries
are checked identically, and actual revert data is checked separately. The
whole JSON ABI is therefore not necessarily identical. Malformed Base64
inputs have unspecified output upstream; the comparison covers documented
alphabets and padding modes, not a claim about all malformed inputs.

## Runner checks

```sh
uv run --with eth-abi==5.2.0 --with 'eth-hash[pycryptodome]==0.7.1' \
  python -m unittest discover -s benchmarks/checked -p 'test_*.py'
```

The original pinned test suites for the three complete function surfaces
can also be run without checking out or modifying an external repository:

```sh
uv run benchmarks/checked/upstream_tests.py \
  --solc "$BENCH_SOLC" --solar ../solar/target/debug/solar \
  --output target/safe-solady/upstream-tests-new
```

The checked implementations passed **60 tests**, including fuzz tests at
256 runs, under both solc via-IR and Solar: 11 SafeCastLib tests,
34 LibBit tests, 13 Base64 tests, and two shared helper tests. The original
solc baseline passed 59 and failed `testToNibblesDifferential` with
`Insufficient memory allocation!`, independently reproducing the memory
allocation discrepancy above. The runner retains this baseline failure and
exits nonzero; it does not suppress the test.

Only the three target library files are replaced in the checked legs.
Original test helpers, including their assembly and LibString's reference
`replace` implementation, remain in the **test harness**. They are not
dependencies of the checked library implementations and are not included in
the safe-source gas benchmark. Test-contract gas is not used in performance
claims. Each leg's original/rewritten source hashes, raw Forge output and
reproduction data are preserved.

[`CompilerDifferential.sol`](test/checked/CompilerDifferential.sol) also provides small targets for the repository's
`../solar/fuzz/bin/solsymdiff` compiler check. For example:

```sh
../solar/fuzz/bin/solsymdiff \
  --source test/checked/CompilerDifferential.sol \
  --contract CompilerDifferential --signature 'popCount(uint256)' \
  --solc "$BENCH_SOLC" --solar ../solar/target/debug/solar --forge "$SYMBOLIC_FORGE" \
  --evm-version cancun --via-ir --timeout 180 --symbolic-timeout 60
```

`narrow(int256)` and `popCount(uint256)` reported bounded compiler agreement
locally. This compares the two compilers on the same checked source; it is
not a proof of equivalence to the original assembly implementation.

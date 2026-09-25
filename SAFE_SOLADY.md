# Checked Solady experiment

**This is a partial port and a reproducible comparison. The CTO's full
API-compatibility and equal-or-better gas target is not met.**

The implementations listed below in `src/utils/` contain neither inline assembly nor
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

This branch replaces only the libraries below in `src/utils`: five whole,
and `LibBytes` down to its storage operations. Other upstream libraries and
tests still contain assembly and unchecked blocks. LibString and LibBytes have
reduced APIs, so the whole upstream suite and consumers of missing functions
are not expected to compile on this branch.
Use the scoped runner commands below for the published subset.

## Code size, second round, 2026-09-25

Port commit: `2c640de`. Size builds flip case one byte at a time and compare
a prefix or suffix by hashing the range, as upstream does.

Solar commits since the previous section (unpushed): `ad19980f8` keeps a loop
counter on the stack when its starting literal is also used after the loop,
where size builds had given it a memory home loaded and stored on every
iteration; `3c3f5792a` prices the label of a jump that tail merging removes
as at least `PUSH1`; `873d1d528` stages short returns in the scratch words;
`19e484a01` and `ef0c71961` replaced the shared quicksort with a heapsort,
and `351829a6c` restores it, since the heapsort (and a Shell sort measured in
between) cost gas on every sort call;
`e11a046bf` retries a rejected specialization with its one-byte literals
alone; `a64377964` proves the arrays the shared set helpers return clean, so
an address result is not copied and masked; `5037f35ea` folds a right shift
past an argument's proved width; and `1a84ff0b7` duplicates a wide immediate
used again within four instructions. All change only builds that do not
optimize for gas, except `a64377964` and `5037f35ea`, which leave gas builds'
bytecode unchanged on both corpora.

Runtime bytes of each combined harness at one optimizer run:

| Harness | Upstream best | Before (`160f8a8fa`, `5685b37`) | Now (`351829a6c`, `2c640de`) |
|---|---:|---:|---:|
| Base64 | 1,294 | 1,084 | 1,043 |
| LibBit | 2,980 | 2,250 | 2,110 |
| LibBytes | 1,110 | 1,047 | 1,008 |
| LibSort | 5,545 | 5,050 | 4,811 |
| LibString | 8,324 | 8,169 | 7,207 |
| SafeCastLib | 5,486 | 2,027 | 2,025 |

Each API alone in its own harness: 223 of 243 are no larger than upstream's
best build (207 before), 49,183 bytes in total against upstream's 59,125
(54,105 before). `groupSum` (+252 to +301) and `insertionSort` (+213 to +232)
alone carry the whole quicksort, whose gas is worth more than those bytes.
Most of the other twelve still larger pay for checks that upstream's
assembly skips: `toHexString(value, length)` and its no-prefix twin (+62,
+72) check that twice the length neither overflows nor exceeds the
allocation limit, both address spellings (+16, +27) check their
allocation against the free-memory pointer's limit and pass the value to the
shared helper through memory, `LibBytes.get` and `LibString.get` (+47, +37)
zero their allocation before copying into it, and `fromSmallString` (+48)
checks its truncation. `Base64.encode` with flags (+19, +51), both
`setCalldata` (+6) and `unpackTwo` (+3) were not analysed further.

The compiler's own corpora agree: in size builds its UI codegen fixtures
shrink 4.40% (1,075 smaller, 9 larger), and the runtime corpus at one run
loses 1.92% of its runtime bytes with no case larger (upstream LibString
-8.0%, OpenZeppelin's governor -5.6%, SignatureChecker -4.7%).

The gas legs are unchanged: the gas builds of every harness are
byte-identical, so the combined matrix stays at 0.4934x of upstream's best
gas at 200 runs and 0.4839x at 1,000,000, with no losing call. Size builds'
own gas at one run is 0.7254x of upstream's best, with 2,020 of 21,471 calls
losing (0.7363x and 2,289 in the previous section); the benchmark's `sort`,
`insertionSort` and `groupSum` calls take 9.36M gas against upstream's
15.92M. Solar's builds match the oracle on every case, and 4,000 random calls
of the new case and prefix paths in size and gas builds agree with a Python
model. The compiler's UI suite and its in-repo Foundry projects pass, and
its external Foundry suite still differs from solc only on OpenZeppelin's
history-block test after `vm.roll`.

Measured and rejected: the wide stack-permutation search in size builds (UI
+4 bytes), passing single-site arguments on the stack (+28), letting size
builds' specialization raise gas (one fixture +265), sorting with a heapsort
or a Shell sort (368 and 439 bytes smaller in the LibSort harness, but the
sort calls took 20.46M and 11.25M gas against the quicksort's 9.36M, 1.5 to
4.7 and 1.05 to 2.1 times per call), and keeping immediates for sixteen
instructions instead of four (upstream LibString in the runtime corpus +55
bytes).

## Code size in size builds, 2026-09-25

Port commits: `f372883` and `5685b37`. Fast paths that only pay for
themselves in gas are guarded by `Build.gasFirst()` from the new
compiler-owned `solar:core/v1/Build.sol`, a constant that is false in builds
optimizing for size, and those builds take one compact path with the same
result: `get`, `set` and `setCalldata` of `LibBytes` with one head word and
one `Slots` copy of whole words for every length, `fromSmallString` and
`normalizeSmallString` by a scan to the first null, `cmp` and `toNibbles` by
byte loops, and `toHexStringChecksummed` from the lowercase spelling and a
loop over the hash. Gas builds compile to the same bytecode as before.

Solar commits since the previous section (unpushed), all changing only
builds that do not optimize for gas unless noted: `3f3d166eb` outlines open
instruction runs in gas mode where the run count pays for it, `3d2fff620`
builds repeated constants by division and multiplication where bytes come
first (also in gas builds' cold blocks and their EIP-170 rescue),
`5054930b8`, `e3146605a`, `a4ee817f7` and `85a6f1e08` lower Base64, the
escapes, hex and the string scans compactly, `8e1924e22` and `f12f66c3f`
share one body per operation for the hex spellings, `equalsAt`, the set
operations and the sorts (signed elements through a flip word), `e556c3291`
merges bodies that become identical after lowering, `1aa4246b0` stores the
free-memory pointer once before dispatch, `ec8c73ff0` adds `Build`,
`043840b9f` consumes loop-free single-use helpers in size builds too,
`3514d67d4` lets size builds substitute literal flags into no-inline helpers,
and `7ab617755` and `160f8a8fa` have them find duplicates by table alone and
sort without the scans for sorted input.

Runtime bytes of each combined harness at one optimizer run, where the
compiler optimizes for size, against upstream's best build:

| Harness | Upstream best | Before (`db94dc8ae`, `ac7c883`) | Now (`160f8a8fa`, `5685b37`) |
|---|---:|---:|---:|
| Base64 | 1,294 | 4,069 | 1,084 |
| LibBit | 2,980 | 2,821 | 2,250 |
| LibBytes | 1,110 | 1,266 | 1,047 |
| LibSort | 5,545 | 7,448 | 5,050 |
| LibString | 8,324 | 13,541 | 8,169 |
| SafeCastLib | 5,486 | 3,292 | 2,027 |

Every harness is now smaller than upstream's best build at one run. The gas
legs are unchanged: at 200 runs the combined matrix is 0.4934x of upstream's
best gas and at 1,000,000 runs 0.4839x, with no losing call at either.
Solar's builds of the port match the oracle on every case at all three
settings; the 48 to 50 mismatches per setting are upstream's own, as before.
The compiler's UI suite and its in-repo Foundry projects pass, and its
external Foundry suite still differs from solc only on OpenZeppelin's
history-block test after `vm.roll`.

Size builds put bytes first, so their calls cost more gas than the gas
builds': at one run the combined matrix is 0.7363x of upstream's best gas,
with 2,289 of 21,471 calls losing. Base64 is 4.15x, its decoder taking one
character at a time without a table (8.6x); a table would cost about 80
bytes for roughly half the decoder's gas, which at one run is about even.
LibBit is 1.18x and LibString 1.02x, while LibSort (0.59x) and SafeCastLib
(0.94x) still win.

Gas builds at 200 runs remain larger than upstream's: the combined LibString
harness is 16,957 bytes (21,588 before `3f3d166eb`) against 8,558. That is
the price of every call winning; closing it would bring back the losses the
gas legs closed.

Measured and rejected: a shared checked allocator (the call protocol and the
stack arrangement at each site cost more than the inline bump: LibString +7
bytes, Base64 +26), shared `Slots` byte copies (LibBytes +4), skipping the
hash for short needles in size builds (+16 bytes for about 40 gas per
match), consuming single-use helpers with loops too (LibSort +290: two
overloads that lower to one body can no longer merge), and consuming them
only after the merge (LibSort 5,423 bytes instead of 5,267).

## Last losses and EIP-170, 2026-09-24 (late night)

Port commit: `ac7c883`. `LibBytes.get` writes the one or two derived words of
a value shorter than 96 bytes directly and keeps the loop for longer ones.

Solar commits since the previous section (unpushed): `cc873cf14` rescues an
oversized gas build in stages, `377431a83` bounds a stable reread of an
object's length by the length stored at its allocation, `5dbc3d660` rebinds
loops whose phis start from a constant, `75e6c42b8` hands a loop header's phis
their inputs last, and `db94dc8ae` reads a calldata argument the callee keeps
across a loop from calldata instead of the callee's static frame.

| Harness | Runs | Before (`778800af4`, `d522300`) | Now (`db94dc8ae`, `ac7c883`) |
|---|---:|---:|---:|
| Combined | 200 | 0.4968x, no losses | 0.4933x, no losses |
| Combined | 1,000,000 | 0.4875x, no losses | 0.4839x, no losses |
| Isolated | 200 | 0.5166x, 8 losses | 0.5164x, no losses |
| Isolated | 1,000,000 | 0.5272x, 9 losses | 0.5270x, no losses |

No call loses anywhere, combined or alone, at either setting.

- **`get` alone.** `LibBytes.get` and `LibString.get` lost 4 of 13 calls, by
  up to 45 gas at 200 runs and 48 at 1,000,000. A value of 32 to 95 bytes now
  takes its derived words without the loop, and the compiler knows that
  `new bytes(n + 32)` holds at least 64 bytes when `n > 31`, so the bound
  checks of those writes fold. The block entering the loop for longer values
  leaves the loop's cursor below the constant slot, where the loop's header
  keeps it. A sweep of every length from 0 to 300 finds no loss at either
  setting; the tightest margin is 7 gas at 200 runs and 4 at 1,000,000, at 96
  bytes, which pay the port's extra comparison.
- **`escapeJSON(s, false)` at 1,000,000 runs.** The shared escape helper kept
  its quote flag across its loop, so the wrapper stored the flag in the
  helper's static frame and the helper read it back twice. The helper now
  reads the flag from calldata itself: the empty string goes from 5 gas over
  upstream's best build to 10 under.
- **EIP-170.** An oversized gas build first gives short recipes to the
  constants that cost the least gas per saved byte, just enough of them for
  the bytes over the limit. The combined LibString harness at 1,000,000 runs
  is 24,453 bytes, 25,436 before; LibString goes from 0.5621x to 0.5628x of
  upstream's best gas in that harness for it.

In the runtime corpus the five commits leave runtime gas unchanged and save
0.03% of runtime bytes. The compiler's UI suite and its in-repo Foundry
projects pass, and its external Foundry suite still differs from solc only on
OpenZeppelin's history-block test after `vm.roll`.

Measured and rejected: inlining a looping single-caller body into its ABI
wrapper even when its live words fit the stack budget (the corpus's sorts
still lose 55 to 373 gas per call), and reading every calldata-word parameter
in the callee (two corpus contracts grow by 34 and 61 bytes).

Code size itself is still open: at 200 runs the combined LibString harness is
21,588 bytes against upstream's best 8,558.

## Dispatch tables and compiler fixes, 2026-09-24 (night)

Port commit: unchanged (`d522300`).

The compiler branch is rebased onto main `b49d5306b`; the commits the previous
section names are now `ca0409555`, `9acb3d20e`, `5bb64fa8b`, `f88e35831`,
`6c785f661`, `6b840919d`, `960e23729`, `95dde31b8` and `17c9fe520`. Solar
commits since (unpushed): `7671728ba`, `19eadcfd0` and `c8df2bff7` fix three
miscompiles described below; `a69ca6d90` folds the phi that a revert helper's
dropped edge leaves behind; `778800af4` lets the selector switch dispatch
through short bucket tables.

| Harness | Runs | Before (`17c9fe520`) | Now (`778800af4`) | Now, 228 earlier APIs |
|---|---:|---:|---:|---:|
| Combined | 200 | 0.5108x, 12 losses | 0.4968x, no losses | 0.4442x, no losses |
| Combined | 1,000,000 | 0.4876x, no losses | 0.4875x, no losses | 0.4327x, no losses |
| Isolated | 200 | 0.5166x, 8 losses | 0.5166x, 8 losses | 0.4579x, no losses |
| Isolated | 1,000,000 | 0.5272x, 9 losses | 0.5272x, 9 losses | 0.4683x, 1 loss |

- **SafeCastLib dispatch.** The switch planner tried bucket tables with about
  one selector per slot and, below that, only a balanced tree: at 200 runs
  SafeCastLib's 95 selectors took a three-level tree with chains of twelve,
  which reached the lowest selectors 46 gas after solc's via-IR scan did. Tables
  of 4 to 64 slots now compete, and a power-of-two table hashes with a mask. The
  harness dispatches through 16 slots: one indexed jump replaces the tree's
  three levels. The ten reverting calls that lost by up to 11 gas win now, and
  SafeCastLib in the combined harness goes from 0.6675x to 0.4831x at 200 runs.
- **`LibString.get` in the combined harness.** Its two calls that lost 3 gas
  win now; LibString goes from 0.6267x to 0.5818x at 200 runs. At 1,000,000 runs
  its 56 selectors move from `mod 57` to `and 63`, cheaper per selector but
  second in their slot for some heavily sampled calls: LibString 0.5592x to
  0.5621x, the whole harness still 0.4876x to 0.4875x.
- **Cast wrappers.** A cast inlined into its ABI wrapper joins the passing
  path with the path through the outlined revert helper; once that helper is
  known not to return, the join kept a phi with one input, which the backend
  parked in memory. `toUint256(int256)` and `toInt256(uint256)` alone go from
  0.6981x to 0.5746x at 200 runs and from 0.7091x to 0.5836x at 1,000,000; no
  other API alone moves.

In the runtime corpus the two performance commits move runtime gas by -0.01%
and runtime bytes by -0.02%.

**Compiler fixes.** The compiler's external Foundry suite (morpho-blue,
solmate, solady, seaport, OpenZeppelin and v4-core) failed on main itself.
A void function ending in a call to a helper that returns a value jumped into
the helper and left the discarded value on its caller's stack (solady's
LibBitmap and MinHeap tests, a v4-core swap fuzz test); pointer casts hid heap
destinations from the spill-hazard analysis, so seaport's navigator helpers
failed to compile and an OpenZeppelin test created its token from corrupted
constructor arguments; and a free-memory-pointer load after a low-memory copy
was reloaded from a slot nothing had stored. All three are fixed with
regression tests. With this section's compiler the suite differs from solc
only on OpenZeppelin's history-block test after `vm.roll`, as before (v4-core's
unsound tick-relation fuzz test passes or fails with the fuzzer's draws). The
fixes leave every harness here byte-identical and shrink the runtime corpus's
code by 0.11%.

What still loses. Alone at 200 runs: each `get` on 4 of 13 calls, values of 32
to 64 bytes, by up to 45 gas (48 at 1,000,000). The loop that loads the words
enters with its cursor under six other words, the wrapper calls `get`, `new
bytes` zero-fills memory that `get` overwrites, and the allocation check cannot
see that the free-memory pointer is small; the last would need a whole-contract
bound on the pointer that only assembly-free code gives. At 1,000,000 runs,
`escapeJSON` on the empty string, by 5 gas: the call from its wrapper.

Measured and rejected: inlining a single-caller body that loops and returns
memory into its ABI wrapper. `escapeJSON("")` stops losing and `get` gains 2
gas, but the runtime corpus's sorts lose 55 to 373 gas per call and 52 bytes.

Code size is still open. At 200 runs the combined LibString harness is 21,515
bytes against upstream's best 8,558 and SafeCastLib's 2,964 against 6,597; at
1,000,000 runs LibString's is 25,436 bytes, over EIP-170.

## Storage words, loop entries and small inputs, 2026-09-24 (evening)

Port commit: `d522300` (`LibBytes.get` loads whole words from byte 31, and the
setters read a value's first word whole once it has 32 bytes or more).

Solar commits (unpushed): `e2162ebee` drops masks and sign extensions a range
check already makes idle, and lets a call that never returns cut its edge;
`d87847cb4` returns a static value of up to 64 bytes from scratch memory in
gas mode; `5579fd09b` spells fixed-width hex below sixteen bytes in one word;
`3652d90fb` counts a short string's runes inline; `73850579c` orders two masks
of one word and reads a reread length as the checked sum stored with it;
`3b7a31434` specializes a helper past callers no entry reaches; `839a1507c`
steps a byte cursor and a slot through `Slots`' byte moves; `ceace78c6`
replaces a reused branch condition with the truth its scope proves;
`35353ea31` enters a loop in the order the entering stack already holds the
words the loop carries.

| Harness | Runs | Before (`bc1bf96c6`, port `296a93b`) | Now (`35353ea31`, port `d522300`) | Now, 228 earlier APIs |
|---|---:|---:|---:|---:|
| Combined | 200 | 0.5139x, 64 losses | 0.5108x, 12 losses | 0.4591x, 10 losses |
| Combined | 1,000,000 | 0.4908x, 20 losses | 0.4876x, no losses | 0.4328x, no losses |
| Isolated | 200 | 0.5199x, 91 losses | 0.5166x, 8 losses | 0.4579x, no losses |
| Isolated | 1,000,000 | 0.5304x, 90 losses | 0.5272x, 9 losses | 0.4683x, 1 loss |

Each item below is measured with the API alone against upstream's best build
unless noted.

- **SafeCastLib.** Casts whose result the ABI would mask again keep the value
  the range check already bounded, and a static result of up to two words
  returns from scratch memory instead of the heap: `toUint136`, `toInt112` and
  `toInt208` together go from 0.7486x to 0.6616x at 200 runs, and the combined
  harness from 0.6934x to 0.6683x with 10 losing calls instead of 12.
- **Fixed-width hex.** A width below sixteen bytes is spelled in one word with
  one store; one-byte widths lost by up to 141 gas and now win by 7 to 19.
  `toHexString` and `toHexStringNoPrefix` with a width: 0.2850x with 24 losing
  calls to 0.2812x with none at 200 runs, 0.2965x to 0.2925x at 1,000,000.
- **`runeCount`.** A rune's length comes from a nibble table, so the count
  writes no memory and inlines; a subject of up to 31 bytes that is all ASCII
  returns at once. 0.2316x with 3 of 6 calls losing to 0.2222x with none at
  200 runs, 0.2313x to 0.2216x at 1,000,000.
- **Storage.** The three causes named in the previous section are closed where
  they came from. `get` loads whole words from byte 31, which the spare word's
  zeroing covers, and the compiler proves its range from the two masks of one
  word; the constant slot reaches `LibBytes` through `LibString`'s wrapper,
  because the wrapper the inliner left behind no longer blocks specialization;
  and `Slots`' byte moves step a cursor and a slot, so the hash has one use
  and the setters' arguments die before the loop and stay on the stack. The
  setters read a first word of 32 bytes or more whole. In the harness of the
  fourteen storage operations, losing calls go from 46 to none at 200 runs and
  from 35 to none at 1,000,000; `get` from 1.0007x to 0.9907x for `LibBytes`
  and from 1.0014x to 0.9889x for `LibString`, `setCalldata` from 1.0004x to
  0.9980x and from 0.9995x to 0.9967x, `set` from 0.9985x to 0.9970x and from
  0.9995x to 0.9980x (200 runs).
- **`split`.** Its two search loops carried eight words each in an order the
  entering block had to permute with five exchanges; the loops now take the
  order that block's stack holds. `split` goes from 0.7680x with 2 of 61 calls
  losing to 0.7628x with none at 200 runs and from 0.7730x to 0.7678x at
  1,000,000; `indicesOf` from 0.6893x to 0.6826x and `indexOf` from 0.8105x to
  0.7960x at 200 runs.

What still loses. In the combined harness at 200 runs: ten reverting calls to
five SafeCastLib casts, by up to 11 gas, and two `LibString.get` calls, by 3
gas. Both are dispatch positions: solc's via-IR build reaches the lowest
SafeCastLib selectors first in a plain scan, and its legacy build reaches
`get` through a different split, while the compiler's selector tree, which the
switch planner prices for 200 runs, reaches them later; the deposit weight
behind that price was measured and kept on 2026-09-14. Alone, the 228 earlier
APIs lose no call at 200 runs and one at 1,000,000 (`escapeJSON` on the empty
string, by 5 gas). Each `get` alone loses 4 of 13 calls on values of 32 to 64
bytes, by up to 45 gas at 200 runs and 48 at 1,000,000: in a contract of one
function solc's dispatcher does almost nothing, and the zero fill of `new
bytes` and the call from the ABI wrapper into `get` are left to pay for.
Inlining `get` into its wrapper spills around its loop again and costs more.

Code size is still open. At 200 runs the combined LibString harness is 21,469
bytes against upstream's best 8,558 (the short fixed-width hex path added
about 0.8 KB), Base64's 5,418 against 1,300, LibSort's 7,511 against 5,791 and
LibBit's 4,279 against 3,057; SafeCastLib's is 2,966 against 6,597. At
1,000,000 runs the combined LibString harness is 25,288 bytes, over EIP-170;
the runner lifts the node's limit, and the harness is an aggregate for
measurement, not a deployable application.

Measured and rejected this round: pricing `inline_returns` over the
deployment's lifetime (+0.70% runtime bytes in the corpus), an outlined zero
fill for the hex path (its call spilled), and inlining the storage getter into
its wrapper, which spills around the loop again (+71 gas at worst).

## String storage, direct returns and small inputs, 2026-09-24 (later)

Port commits: `268da3f` (`fromSmallString` tests its first eight bytes
before the word path), `76b0012` (`repeat` and `copy` call the compiler-owned
`Strings.repeat` and `WordArrays.copy`), `945ed37` (`normalizeSmallString`
tests its first seven bytes and spells the word path out), `e7d0b14`
(`reverse` and `toNibbles` return early from inputs with nothing to do),
`b617b64` (the runner measures storage APIs and `directReturn`), `cfd69c9`
(`StringStorage` and `directReturn`, below), `d0927e9` (the runner lifts the
node's code-size limit and marks the harnesses above it), `42d9e01` (storage
cases are set up and observed through the node, so the harness has no
assembly), `296a93b` (the storage operations move bytes in whole words).

Solar commits (unpushed): `7d56128a4` branches the set merges on each
comparison, steps `equalsAt` with one guard and compares every pair of up to
six words in `hasDuplicate`; `3d4957146` tests `2^64 - 1` bounds with a shift,
validates address arrays with a cursor tested at the bottom and returns any
real memory object in place; `fb742de66` adds `Strings.repeat` and
`WordArrays.copy`; `7d2bbe70d` adds the `Slots` and `Return` modules;
`9a9f70ee1` hoists slot hashes out of loops; `7738a4cac` keeps object lengths
across writes below the heap; `e20f37cb9` adds `Slots`' byte moves;
`bc1bf96c6` hashes constant slots at compile time when the constant is
cheaper over the deployment's lifetime.

| Harness | Runs | Before (`3e1f9415a`, port `82cbd9b`) | 228 APIs (`fb742de66`, port `e7d0b14`) | Same 228 (`bc1bf96c6`, port `296a93b`) | All 243 |
|---|---:|---:|---:|---:|---:|
| Combined | 200 | 0.4946x, 21 losses | 0.4617x, 17 losses | 0.4622x, 17 losses | 0.5139x, 64 losses |
| Combined | 1,000,000 | 0.4641x, 4 losses | 0.4367x, no losses | 0.4360x, no losses | 0.4908x, 20 losses |
| Isolated | 200 | 0.4971x, 386 losses | 0.4612x, 29 losses | 0.4612x, 29 losses | 0.5199x, 91 losses |
| Isolated | 1,000,000 | 0.5020x, 352 losses | 0.4716x, 31 losses | 0.4716x, 31 losses | 0.5304x, 90 losses |

The fifteen new APIs are reported apart as well because a storage case spends
most of its gas on `SSTORE` and `SLOAD`, where both compilers pay the same: in
the combined harness they take 7.4 million of the reference's 75.3 million gas
at 200 runs and pull the total toward 1.0x. The 228 earlier APIs cost what
they cost with `fb742de66`: alone, to the gas; in the combined harnesses, their
bodies too (at 200 runs, 26 of 20,957 calls move by 11 gas either way), while
their totals move with the dispatch positions of the fifteen added selectors,
in both legs. No harness exceeds EIP-170.

Per change, each API alone at 200 runs on the same port unless noted:

- The set operations branch on each comparison like the upstream assembly,
  each arm testing the cursors it advances, and return an output with no
  capacity at once: `union(uint256[])` 0.446x to 0.411x, and every set
  operation drops its 15 losing calls on empty inputs. Decoding does the rest
  for addresses: `intersection(address[])` goes from 0.766x with 55 losing
  calls to 0.626x with none.
- Decoding tests `2^64 - 1` bounds with `x >> 64`, which needs no wide
  constant, bounds a word array by its byte size, and validates address
  elements with a cursor tested at the bottom after the copy: 56 gas per
  element instead of 75. `hasDuplicate(address[])` 0.847x (7 losing) to 0.770x
  (0), where comparing every pair of up to six words also avoids the hash
  table.
- A terminal return writes the ABI offset below any real memory object, not
  only a fresh one: `toString(uint256)` 1.007x (15 losing) to 0.987x (0),
  `toString(int256)` 1.000x (7) to 0.978x (0), minimal hex 0.375x (7) to
  0.342x (0).
- `Strings.repeat` doubles the filled prefix with `mcopy` without the body's
  bounds checks and zero fill, and `WordArrays.copy` moves the length word and
  the elements with one `mcopy`: `repeat` 0.688x (10 losing) to 0.572x (0),
  `copy(uint256[])` 0.423x to 0.140x, `copy(address[])` 0.567x (4) to 0.293x
  (0).
- `reverse` returns before computing its cursors for arrays of fewer than two
  elements, as the upstream assembly does: those save 76 gas, longer arrays
  pay 22, and `reverse(address[])` loses no call at either setting.
- `equalsAt` steps one cursor behind one guard: `startsWith` 0.919x (9
  losing) to 0.903x (0). `toNibbles` returns an empty input at once (1 losing
  to 0), and `normalizeSmallString` stops losing in the combined harness.

### `StringStorage` and `directReturn`

Seven of the eight `StringStorage` functions and `directReturn` are now
ported, through two compiler-owned modules whose reference bodies are
memory-safe assembly, the same way as `Revert.raw`:

- `Slots` addresses the words at `keccak256` of a `Root` struct's slot and
  after it, where a dynamic array at that slot keeps its elements. `load` and
  `store` move one word at an index below `2^64`; `storeBytes`,
  `storeCalldataBytes` and `loadBytes` move a byte range of a buffer from word
  0, with the range and a count below `2^69` checked once before any access.
  A region cannot reach another variable's slots, and the root word is the
  owner's.
- `Return.abiEncoded` ends the call returning a string ABI-encoded, encoded
  where the string lies.

`LibString.StringStorage` holds a `LibBytes.BytesStorage`, which holds a
`Slots.Root`: one slot, the original's layout. The port's `LibBytes.sol`
carries only the seven `BytesStorage` operations. A differential test that
stores fourteen values from 0 to 300 bytes one after another, through both
setters, matches the original's results and all thirteen storage words after
every store. The runner writes each case's starting words with
`anvil_setStorageAt` and checks a store by running it and reading the words
back with `eth_getStorageAt`. Its first version wrote and read them with
assembly in the harness instead, which the audit had to exempt, and which
cost more than the exemption: a module with any assembly loses the compiler's
bound on memory-object lengths, and every LibString API in the combined
harness paid for checks it otherwise drops, up to 211 gas a call.

Two differences remain: stores write zeros past the end of the value where
the original copies whatever memory or calldata follows it, and `uint8At`
returns zero from the length on, as the original does since its stale-byte
fix, where the pinned release returns a byte a longer value left there (three
cases per library, counted as upstream mismatches). `bytesStorage` stays
out: it returns the nested `BytesStorage` from a `pure` function, and reaching
it without assembly is a storage access that needs `view`.

Each new API alone at 200 runs: `clear` 0.989x, `isEmpty` 0.972x, `length`
0.970x and `uint8At` 0.938x (`LibString`'s 0.945x) lose no call in either
library, and `directReturn` is 55 gas below upstream in every case (0.882x).
The setters and `get` total 1.000x to 1.008x. They lose on values of 32 to 100
bytes, which keep 31 bytes in the root slot and the rest in derived words, by
up to 98 gas for a setter and 257 for `get`, and win on shorter and longer
values, by up to 194 gas; `get` also loses at 254 bytes, `LibString.get` by 4
to 7 gas below 32 bytes, and `LibString.setCalldata` by up to 72 gas on long
values. At 1,000,000 runs they lose by up to 97 gas for a setter and 258 for
`get`. Three causes remain: `get` allocates with `new bytes`, whose zero fill
the byte move then overwrites; the backend passes the setters' arguments
through frame memory, one store per argument and one load per use, because its
stack argument layouts do not cover these callees; and `LibString` reaches
`LibBytes` through one more call, where the constant slot arrives as an
argument the specializer does not substitute, so its hash stays at run time.
Solar `bc1bf96c6` hashes a constant slot at compile time when the pushed
constant is cheaper over the deployment's lifetime; in one harness of the
fourteen storage operations at 200 runs, `LibBytes.uint8At` goes from 27 of
149 losing calls (by up to 12 gas) to none.

What still loses among the 228 earlier APIs: in the combined harness at 200
runs, SafeCastLib selectors whose position in the binary search costs up to
10 gas more than solc's (12 calls) and one-byte fixed-width `toHexString` (5
calls, 38 gas); at 1,000,000 runs, nothing. Alone, the fixed-width hex
functions lose at a one-byte width: `toHexString` by 127 gas on the 5 values
that fit and by 2 gas on the 14 that revert, `toHexStringNoPrefix` by up to 117
gas on the 5 that fit (141 and 128 at 1,000,000 runs). `runeCount` loses up to
57 gas on the empty string and two short multibyte strings, `split` 2 of 61
calls by up to 17 gas, and at 1,000,000 runs `groupSum(uint256[])` and
`escapeJSON` one call each, by 6 and 5 gas.

Code size is the largest open item. At 200 runs the combined harnesses take
5,422 bytes for Base64 against upstream's best 1,300, 20,743 for LibString
against 8,558, 7,557 for LibSort against 5,791 and 4,313 for LibBit against
3,057; only SafeCastLib is smaller (3,730 against 6,597).

## Reverts, dispatch tables and core set operations, 2026-09-24

Port commit: `82cbd9b` (`LibSort`'s `union`, `intersection` and
`difference` call the compiler-owned `WordArrays` versions, whose checked
bodies are the loops they replace).

Solar commits (unpushed): `c68609001` stages a custom error's payload in
scratch memory like a panic (`mstore(0, selector)`, `revert(28, 4 + 32n)`) for
up to three word arguments, and encodes longer ones and error strings at the
free-memory pointer without advancing it; `3f5d5694f` bounds decoded array
lengths by `2^64 - 1`, as solc does, instead of checking the byte size and the
header size for wrap; `7c47307b0` moves a bucket's first case comparison into
its dispatch-table entry and pads every entry to one stride when the expected
calls repay the padding; `42465ddcf` admits bucket tables up to 128 cases;
`9092bb771` returns a fresh array or string by writing the ABI offset in the
word below it instead of moving it up a word; `3e1f9415a` lowers the
`WordArrays` set operations to a branch-free merge with `mcopy` tails, leaving
out the bodies' index and truncation checks, which cannot fail.

| Harness | Runs | Before (`ec86751ca`, port `bed4f3b`) | After (`3e1f9415a`, port `82cbd9b`) |
|---|---:|---:|---:|
| Combined | 200 | 0.5293x, 139 losses | 0.4946x, 21 losses |
| Combined | 1,000,000 | 0.5054x, 803 losses | 0.4641x, 4 losses |
| Isolated | 200 | 0.5350x, 854 losses | 0.4971x, 386 losses |
| Isolated | 1,000,000 | 0.5449x, 757 losses | 0.5020x, 352 losses |

Per change, in the combined harnesses:

- The revert payload takes a reverting `toUint8` call from 96 gas after
  dispatch to 44, and a passing one from 74 to 65, since its entry no longer
  stores the free-memory pointer: 129 of SafeCastLib's 660 calls lost at 200
  runs, 12 now, and none after dispatch.
- The table entries take `popCount`'s dispatch from 94 gas to 80 at
  1,000,000 runs, from 3 gas above the reference to 11 below (776 calls). A
  bucket's first case skips the entry's jump; the padding of empty buckets is
  priced against the saved gas over the expected calls, so 200-run builds
  keep plain entries.
- The bucket cap lets SafeCastLib's 95 selectors use a modulo table at
  1,000,000 runs: 0.589x to 0.380x, no losses (18 before).
- LibSort goes from 0.5044x to 0.4638x at 200 runs, most of it from the set
  operations (0.4997x with every other change in place).

Outside Solady, the runtime corpus against `ec86751ca`: runtime gas
-0.01%, runtime bytes -1.25%, creation bytes -1.05%, deployment gas -0.95%,
no case worse; the byte savings are mostly custom-error reverts.

What still loses in the combined harnesses: SafeCastLib selectors whose
position in the 200-run binary search costs more than solc's (12 calls, up
to 10 gas), one-byte fixed-width `toHexString` (5 calls: the checked sizing
of a fixed-width string costs more than two digits), and
`normalizeSmallString` below five bytes (4 calls, the constant-time design).

In the isolated harnesses, LibSort goes from 764 losing calls to 302 at 200
runs. What remains is fixed cost on inputs of at most one element per side:
the set operations on two empty word arrays (15 calls each, 28 to 39 gas at
200 runs and 1 gas at 1,000,000), the address set operations, whose decoding
validates every element (up to 137 gas), empty `copy` and `reverse`, and small
address inputs of `hasDuplicate` and `isSorted`. Decoding an array still
builds `2^64 - 1` three times; comparing through a shift would drop it.
LibString's isolated losses are those listed in the previous section.

## String scans, stepped cursors and deterministic codegen, 2026-09-23

Port commits: `f39884e` (`repeat` allocates its result once and doubles the
filled prefix in place), `971dad7` (`toNibbles` spreads inputs shorter than
sixteen bytes from one zero-padded word instead of cascading through 8-, 4-,
2- and 1-byte blocks), `8baf20d` (`slice(subject, start)` takes the length as
its end instead of clamping `NOT_FOUND` at run time), `bed4f3b` (small strings
are masked from their null marks; `eqs` compares where `b`'s null marks start
with `a`'s length instead of counting `b`).

Solar commits (unpushed): `e65b86592` proves differences under ordering
facts, checked products whose zero test covers a zero divisor, loops that
step their input by a constant (`i + 16 <= n`) against a scaled capacity,
and rereads of unwritten parameter lengths; `a3eeaf50b` scans `replace`,
`indicesOf` and `split` with pointer cursors in separate loops for short
and long needles; `43d2007e2` spells minimal hex wider than two bytes a
word at a time; `b1c58dc1c` packs two strings from the words that already
hold each length byte ahead of its payload; `9e1872629` ties a fresh
object's reread length to its allocation; `ec86751ca` creates merge phis in
declaration order.

The last one matters for every comparison in this file. Phis were created
in the hash order of variable ids, which are numbered across the whole
compilation, so editing one library moved the bytecode of the others:
before it, a LibBit-only port change moved LibSort's isolated harnesses by
33,000 gas. After it, 227 of the 228 isolated harnesses compile to identical
bytecode from two snapshots that differ only in `LibBit.sol`; the 228th
exercises the changed function.

| Harness | Runs | Before (`c4dea32af`, port `d2202a2`) | After (`ec86751ca`, port `bed4f3b`) |
|---|---:|---:|---:|
| Combined | 200 | 0.5339x, 156 losses | 0.5293x, 139 losses |
| Combined | 1,000,000 | 0.5102x, 815 losses | 0.5054x, 803 losses |
| Isolated | 200 | 0.5403x, 1,053 losses | 0.5350x, 854 losses |
| Isolated | 1,000,000 | 0.5503x, 933 losses | 0.5449x, 757 losses |

Ratios are solar-safe gas over the per-call minimum of solc legacy and via-IR
on upstream Solady, summed over every comparable case (21,001 combined; each
isolated harness compiles one API alone). At 200 runs the isolated losses are
LibSort 764, LibString 87 and LibBit 3; Base64 and SafeCastLib lose none. At
1,000,000 runs they are LibSort 635, LibString 110, Base64 10 and LibBit 2.

Per API, at 200 runs: `replace` wins all 216 calls (69 losses before,
0.919x -> 0.819x), `indicesOf` all 72 (14 before), `packTwo` all 20 (20
before, 1.042x -> 0.910x), `slice(string,uint256)` all 63 (25 before),
`eqs` all 35 (6 before), `toHexString(uint256)` all 19 (19 before, 1.016x
-> 0.386x; a full word costs 987 gas against solc's 3,106) and `toNibbles`
loses 3 of 15 (15 before, 1.198x -> 0.950x).

What still loses, and why:

- The set operations on inputs of up to two elements per side. Their cost
  is fixed: decoding both arrays, the checked allocation, three loop headers
  with their setup, and the truncation. Two empty inputs cost `union` 194
  gas more than the original for `uint256[]` and 292 for `address[]`.
  Removing the per-store and truncation checks needs the invariant
  `k <= i + j` across three loops, which the compiler cannot state yet.
- `fromSmallString` and `normalizeSmallString` on strings of up to two
  bytes: their constant cost beats the original's byte scan from about five
  bytes up.
- `toString` by 1 to 3 gas a digit: the digit loop keeps the pointer on top
  of the stack, which costs one more stack operation per digit than via-IR's
  loop.
- Fixed-width `toHexString` of one byte, where the checked sizing (doubling
  overflow, length limit and allocation checks) costs more than the
  conversion.
- `repeat` with one to three copies of one or two bytes.
- In the combined harnesses, selectors whose dispatch position costs more
  than solc's: the lifetime-priced switch matches solc legacy's mean
  dispatch cost at 200 runs (220 against 223 gas) and beats it at 1,000,000
  (139 against 215), but individual selectors spread from 94 gas cheaper to
  128 dearer. SafeCastLib's small bodies cannot absorb the dearer positions
  at 200 runs, and `popCount` loses 3 gas at 1,000,000 through its table
  entry's extra jump.
- SafeCastLib's overflow reverts, by up to 7 gas after dispatch: the
  `Overflow()` payload is allocated at the free-memory pointer, which also
  makes every entry initialize that pointer.

## Combined matrix and code size, 2026-09-23

With Solar `fd44d3aae`, the combined five-harness matrix (21,001 calls, the
132 original-source mismatches excluded as before) stands at:

| Runs | Ratio to per-call solc envelope | Wins | Losses | LibSort losses |
|---|---:|---:|---:|---:|
| 200 | 0.535x | 20,789 | 168 | 1 |
| 1,000,000 | 0.511x | 20,140 | 817 | 0 |

At 1,000,000 runs, 776 of the 817 are `popCount`, whose body is 9 gas
cheaper than via-IR's but whose selector costs 12 gas more: the hashed
dispatch jumps through a table entry that jumps again to the bucket's
comparison. At 200 runs, 129 of the 168 are SafeCastLib calls under the
size-weighted dispatch. The rest are `toNibbles`, `startsWith`/`endsWith`
on long matches, `normalizeSmallString` (a software leading-zero count on
Cancun) and scattered single cases. Each API alone in its harness loses
more, because via-IR inlines a single entry point completely; the set
operations lose on inputs of up to two elements.

Runtime bytes of each combined harness, with deployment gas:

| Harness | Solar 200 | solc legacy | solc via-IR | Solar 1M | solc legacy | solc via-IR |
|---|---:|---:|---:|---:|---:|---:|
| Base64 | 5,440 | 1,300 | 1,673 | 6,808 | 1,443 | 2,063 |
| LibBit | 4,766 | 3,334 | 3,057 | 5,479 | 4,335 | 4,558 |
| LibSort | 9,197 | 5,791 | 6,374 | 9,818 | 6,098 | 8,203 |
| LibString | 15,584 | 7,531 | 8,176 | 18,635 | 8,447 | 10,979 |
| SafeCastLib | 4,212 | 7,352 | 6,597 | 5,572 | 8,943 | 10,755 |

The size gap is the price of the gas result, not of the checked source: solc
compiling the same checked port produces 10,526 (via-IR) and 18,124 (legacy)
bytes for LibSort, 6,624 and 7,547 for Base64, and about Solar's size for
LibString. At 200 runs the LibSort harness costs 736,495 more deployment gas
than original Solady under solc legacy and saves 28.2 million gas over the
matrix's 10,628 calls, about 2,650 a call, so it pays back after roughly 280
calls of this mix; Base64 costs 888,523 more and saves about 1,643 a call,
paying back after roughly 540. Every harness stays far below the EIP-170
limit. These are the documented trade-offs the size milestone asks for; the
sizes are not closed.

Artifacts: `solar/target/safe-solady/close-gaps/combined-v105-200-20260923/`
and `combined-v105-1000000-20260923/`.

## Search and length-bound update, 2026-09-23

`searchSorted` now tests `l <= h` before each probe and returns from the loop
on a match; an absent needle ends at `l == h + 1`, where the original's last
probe reads `h`, so the result is `(false, h - 1)` or `(false, 0)`. A model of
the original assembly agrees with the new loop on 13,071,869 searches over
sorted, reversed, unsorted and duplicate-heavy arrays, including needles equal
to the length word the original reads at probe 0.

With Solar `c3574e26e` the loop keeps no check at all: memory-object lengths
stay below the allocation limit in a module without inline assembly, a loop
header's range leaves out the paths that carry it unchanged, a halved sum lies
between its ordered addends, and `h = mid - 1` keeps `h` at or below the
length. Each API alone in its harness, the eight `inSorted` and `searchSorted`
APIs lose none of their 6,506 calls at 200 runs (0.491x of the per-call solc
envelope) or at 1,000,000 runs (0.512x); they lost 816 before.

The same length bound removes wrap checks from sums and small multiples of
lengths elsewhere: `union(uint256[])` loses 69 of 184 calls instead of 76,
`difference(uint256[])` 44 instead of 65 and `intersection(uint256[])` 42
instead of 53. What remains of those losses is fixed cost on inputs of up to
two elements per side. Artifacts are in
`solar/target/safe-solady/probe/v101-search-*` and `v103-sets-200/`.

## Base64 core update

The Base64 wrapper now uses the compiler-owned codec, with a checked portable
fallback. The latest [Base64 measurements](benchmarks/checked/base64-core.md)
show substantially lower gas for larger inputs, but short-input and bytecode
size gaps remain. Historical measurements below predate this change.

## Shared duplicate-check update

The four `LibSort.hasDuplicate` overloads now call the compiler-owned
`WordArrays` primitive. Its source fallback is ordinary checked Solidity; Solar
lowers every supported one-word array type to one shared open-addressed table
helper. Table entries retain input element addresses, which avoids a second
index calculation and preserves zero as the empty-slot marker.

In the isolated 200-run comparison, the Solar harness shrinks from 1,091 to 614
runtime bytes, below both original-Solady solc builds at 759 and 873 bytes. It
wins 101 of 184 calls against the per-call solc envelope, with zero execution
mismatches. At 1,000,000 optimizer runs it wins 98 calls, ties one, and loses
85; the worst residual is 3,109 gas for `address[]`, while the other three types
are within 675 gas. This closes the duplicate-check sharing and size problem,
but the remaining large-input gas losses keep the per-case M5 gate open.

Artifacts are retained in
`solar/target/safe-solady/close-gaps/duplicate-core-pointer-20260922/` and
`solar/target/safe-solady/close-gaps/duplicate-core-pointer-1000000-20260922/`.

## Shared sorting update

The eight typed `sort` and `insertionSort` entry points now use
`WordArrays.sort`. Solar shares one unsigned and one signed kernel. Each kernel
first recognizes sorted and descending input, then uses median-of-three Hoare
partitioning with insertion-sort leaves. It recurses into the smaller partition
and iterates over the larger one. The insertion leaves temporarily replace the
array length with a type-correct minimum sentinel and restore it before return;
this removes the lower-bound branch from every element shift without changing
the checked source contract.

At 200 optimizer runs, all 368 published calls match the oracle and the safe
Solar build records 364 wins, four ties, and no losses against the per-call
original-Solady solc envelope. At 1,000,000 runs all 368 calls win, with the
closest result still 23 opcode gas ahead. The isolated eight-API harness is
2,022 runtime bytes at 200 runs, down from 4,693 before this work; the original
Solady solc builds are 1,508 and 1,465 bytes. This closes the published sorting
gas gate at both run settings and makes the remaining size difference explicit.

Artifacts are retained in
`solar/target/safe-solady/close-gaps/sort-core-sentinel-20260922/` and
`solar/target/safe-solady/close-gaps/sort-core-sentinel-1000000-20260922/`.

## Shared sorted-array compaction update

The four `LibSort.uniquifySorted` overloads now call one compiler-owned
`WordArrays` operation. Solar lowers them to a branchless pointer loop that
stores the current canonical word, advances the output pointer only when it
differs from the preceding word, and truncates the array once. The portable
fallback remains ordinary checked Solidity.

All 184 calls match the oracle and beat the per-call original-Solady solc
envelope at both optimizer settings. At 200 runs the closest win is 126 opcode
gas and the largest is 11,665 gas. At 1,000,000 runs the margins are 204 to
10,743 gas. In the complete harness this also reduces Solar runtime size from
9,326 to 9,174 bytes at 200 runs.

Artifacts are retained in
`solar/target/safe-solady/close-gaps/uniquify-core-20260922/` and
`uniquify-core-1000000-20260922/`.

## Shared string replacement update

`LibString.replace` now calls the compiler-owned `Strings.replace` primitive.
Solar lowers it to one shared MIR kernel that scans once, compares short
needles with a masked word, confirms long matches with a hash, and copies
unmatched runs in bulk. It streams output at the free-memory pointer and
reserves the exact object after the scan, avoiding both a counting pass and
the later memory cost of a conservative allocation.

All 216 published calls match the oracle and beat the per-call original-Solady
solc envelope at both optimizer settings. At 200 runs the margin ranges from
45 to 2,809 opcode gas; at 1,000,000 runs it ranges from 60 to 2,824 gas. In
the complete 224-API harness, this change also reduces the Solar LibString
runtime from 14,197 to 13,521 bytes at 200 runs.

Artifacts are retained in
`solar/target/safe-solady/close-gaps/replace-core-stream-20260922/` and
`solar/target/safe-solady/close-gaps/replace-core-stream-1000000-20260922/`.

## Shared string-index update

`LibString.indicesOf` now calls `Strings.indicesOf`. Solar lowers it to one
shared MIR search kernel with the same masked short-needle and hash-confirmed
long-needle matching as replacement. Match offsets are streamed with pointer
induction at the free-memory pointer and the exact word array is reserved only
after the scan. The same kernel also feeds `split`.

All 72 published calls match the oracle at both optimizer settings. In the
complete 224-API harness at 200 runs, the result is net 30,653 opcode gas ahead
with a 69-gas worst tail. At 1,000,000 runs it is net 31,994 gas ahead with a
55-gas worst tail. The strict per-call gate remains open for those short
searches.

Artifacts are retained in
`solar/target/safe-solady/close-gaps/indices-core-20260922/` and
`solar/target/safe-solady/close-gaps/indices-core-1000000-20260922/`.

## Shared string-split update

`LibString.split` now calls `Strings.split`. Solar uses the shared search
kernel to leave one spare result word, appends the subject end, and turns the
offset array into the returned string array in place. Both the search and the
rewrite loop use pointer induction; nonempty pieces are copied in bulk and
empty pieces use Solidity's canonical empty-memory object.

All 61 comparable calls beat the per-call original-Solady solc envelope at
both optimizer settings. The margin is 190 to 12,249 opcode gas at 200 runs and
48 to 11,915 gas at 1,000,000 runs. The four excluded inputs are the existing
upstream Solady empty-delimiter discrepancy in each upstream compiler leg; the
safe source and Solar result agree with the independent oracle. The complete
LibString harness is 13,074 runtime bytes at 200 runs, down from 13,239 before
the fused split kernel.

Artifacts are retained in
`solar/target/safe-solady/close-gaps/string-search-core-closure-20260922/` and
`solar/target/safe-solady/close-gaps/string-search-core-closure-1000000-20260922/`.

## Minimal hexadecimal update

The two minimal hexadecimal APIs now call compiler-owned `Strings` operations.
Solar reserves one bounded memory region, writes two digits per iteration from
right to left through a scratch lookup table, then exposes the minimal slice by
adjusting its typed memory-object pointer. The checked Solidity fallback stays
portable and contains no assembly or `unchecked` block.

All 38 isolated calls match the oracle and beat the per-call original-Solady
solc envelope at both optimizer settings. At 200 runs the margins are 34 gas
for the prefixed form and 42 gas for the unprefixed form. At 1,000,000 runs the
margins range from 23 to 165 gas. The 200-run Solar harness is 348 runtime
bytes, 26 bytes above solc via IR; at 1,000,000 runs it remains 348 bytes and
is smaller than both solc builds at 473 and 542 bytes.

In the complete 224-API harness, both APIs win at 1,000,000 runs. At 200 runs
the unprefixed API wins every call while the prefixed selector has a fixed
21-gas dispatch-layout tail. The encoder kernel therefore closes its isolated
M4 gate; the integrated dispatch tail and the 200-run size difference remain
part of M6.

Artifacts are retained in
`solar/target/safe-solady/close-gaps/minimal-hex-core-v4-isolated-20260922/`,
`minimal-hex-core-1000000-20260922/`, and
`minimal-hex-core-full-1000000-20260922/`.

## Zero-byte scan integration update

The compiler's word-at-a-time zero counter now recognizes the raw memory
payload pointer and length left after an ordinary checked helper is inlined
into its ABI wrapper. This closes the integration gap that kept the safe
`LibBit` source on its byte loop even though the reduced MIR shape optimized.

At 200 runs on Cancun, the isolated memory and calldata APIs pass all 44
differential cases and beat the cheaper original-Solady solc pipeline in every
case. `countZeroBytes(bytes)` is ahead by 126 to 1,748 opcode gas and
`countZeroBytesCalldata(bytes)` by 97 to 1,711 gas. The two-API Solar harness
is still larger than solc, so this closes the M3 gas gate rather than the M6
size gate. The retained artifacts are in
`solar/target/safe-solady/close-gaps/zero-count-20260922/`.

## Bulk string construction update

The checked string port now avoids redundant full passes where the final
capacity has a cheap safe upper bound. HTML and URI escaping allocate their
maximum output once, emit fixed-width chunks through `solar:core/Bytes`, and
truncate the logical length. `indicesOf` similarly allocates the maximum
non-overlapping result count and truncates it after one scan. `replace` copies
unmatched runs and replacements in bulk, while both `slice` overloads use the
same checked bulk-copy primitive. The URI character test is one constant
bitset lookup, and the ASCII lookup builder validates the accumulated word
once after the loop.

On the complete 20,605-case matrix at 200 optimizer runs, these changes reduce
candidate opcode gas from 42,843,556 to 41,332,421. LibString falls from
7,157,296 gas (1.149x its original-Solady envelope) to 6,414,885 gas (1.030x),
and its identical-harness runtime size falls from 15,053 to 14,276 bytes. The
checked implementations still match the oracle in every case; the same 44
cases remain excluded because of 132 known upstream-source mismatches.

The focused 1,000,000-run rerun covers 879 cases across the eight changed
APIs. The three `slice`/ASCII APIs reach or nearly reach parity, while
`replace`, `split`, `indicesOf`, HTML escaping, and URI escaping retain
per-case gaps. Those residuals are dominated by checked output writes and are
therefore an open compiler bounds-proof/code-generation item rather than a
completed parity claim. Artifacts are retained in
`solar/target/safe-solady/close-gaps/full-20260922/` and
`solar/target/safe-solady/close-gaps/strings-1000000-20260922/`.

The follow-up compiler pass proves the output-cursor relation for these
maximum-capacity builders. It removes the per-write overflow and bounds
branches only when a zero-based input cursor advances by one, the output step
has a finite maximum, the checked allocation reserves at least that many bytes
per input item, and alias analysis keeps both lengths stable. Wider writes and
loop-local length mutations retain their checks.

On the same complete matrix, eight calls improve by another 6,586 opcode gas,
20,597 calls are unchanged, and none regress. The LibString harness shrinks by
another 75 runtime bytes, from 14,276 to 14,201. Focused HTML and URI escaping
retain zero mismatches at both optimizer-run settings. Artifacts are in
`solar/target/safe-solady/close-gaps/full-scaled-cursor-20260922/` and
`solar/target/safe-solady/close-gaps/scaled-cursor-1000000-20260922/`.

## Implemented surface

| Library | Implemented non-private functions | Pinned function surface |
|---|---:|---:|
| SafeCastLib | 95 | 95 |
| LibBit | 24 | 24 |
| Base64 | 4 | 4 |
| LibSort | 57 | 57 |
| LibString | 56 | 57 |
| LibBytes (storage operations only) | 7 | 42 |

These are function-declaration counts, not a claim of complete source or
behavioral compatibility. The runner checks parameter names, types and locations,
return types and locations, visibility, and mutability against upstream.
This includes preserving named-call syntax. It records
the missing functions across the archive in `api-coverage.json`.

The port currently covers checked casts, bit operations, Base64, four typed
array overloads for sorting, copying, reversing, duplicate checks, sorted
search, the sorted set operations, in-place compaction and grouped sums, and
the string functions (conversion, inspection, search, slicing, splitting,
small strings, escaping, packing, packed string storage, and direct returns):
236 of the five libraries' 237 non-private declarations, and the seven
`BytesStorage` operations of `LibBytes` that `StringStorage` is built on. The
in-place resizing of `uniquifySorted` and `groupSum` goes through the
compiler-owned `Arrays.truncate` and `WordArrays` primitives, packed storage
through `Slots`, and `directReturn` through `Return`; the AST audit lists
these modules as the trusted primitive layer. `bytesStorage` is the one
declaration still absent (see [Scope decision](#scope-decision-2026-09-24)).
Tokens, authentication, proxies, cryptography, storage utilities, and other
libraries remain outside this port. Missing constants and user-defined
types are also outside the function audit.

## Scope decision, 2026-09-24

The 2026-09-23 decision below left `StringStorage` and `directReturn` out
unless a disclosed compiler primitive covered them. Two now do, with
memory-safe assembly reference bodies that the safe-solc leg compiles:

- `Slots` reads and writes the words derived from a `Root` struct's slot,
  where a dynamic array at that slot keeps its elements: one word at an index
  below `2^64`, or a byte range of a buffer from word 0, checked before any
  access. It cannot address an arbitrary slot, only the region of a root the
  caller holds, so it is not the raw-slot primitive the earlier decision
  rejected. `StringStorage` keeps the original's layout on top of it.
- `Return.abiEncoded` ends the call returning a string, ABI-encoded.

`bytesStorage` stays out. It returns the struct's nested `BytesStorage` from a
`pure` function; without assembly, reaching the nested struct is a storage
access that needs `view`, and the API audit requires the original's
mutability. It stays listed as missing in `api-coverage.json`.

## Scope decision, 2026-09-23

The nine missing declarations stay outside the checked target:

- The eight `StringStorage` functions (`set`, `setCalldata`, `clear`,
  `isEmpty`, `length`, `get`, `uint8At`, `bytesStorage`) define a storage
  format of their own: a short string is packed with its length into the
  struct's slot and a longer one continues in slots derived from it, and
  `bytesStorage` retypes the struct as a `bytes storage` reference. Ordinary
  Solidity cannot address storage by a computed slot or retype a storage
  reference, and a port onto a native `string` field would change the stored
  representation that existing deployments and upgrades depend on. A core
  primitive for raw slots would reintroduce exactly the unchecked storage
  writes the experiment excludes.
- `directReturn` ends the external call from inside a library function. A
  `return` in an internal helper returns from the helper; halting the call
  would need a new control-flow primitive rather than a checked formulation.

Both stay listed as missing in `api-coverage.json` and outside every ranking.
Adding either later means a disclosed compiler primitive and a matching change
to the safe-solc leg, not a silent substitution.

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

To measure one API's code alone, without the other wrappers sharing its
dispatcher, pass `--api` and `--isolate-api`; the per-API sweep in the latest
update runs this once for each of the 228 APIs in `api-coverage.json`:

```sh
uv run benchmarks/checked/benchmark.py \
  --solc "$BENCH_SOLC" --solar ../solar/target/debug/solar \
  --runs 200 --evm-version cancun \
  --api 'LibSort.inSorted(uint256[],uint256)' --isolate-api \
  --output target/safe-solady/iso/inSorted-uint256
```

The runner reads `src/` and the compiler's core modules when it runs, so a long
sweep uses a frozen copy: a `git worktree add --detach` of this repository and
`--core-modules` pointing at a copy of `solar/crates/sema/src/core/v1`.

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

## Compiler optimization checkpoint, 2026-09-13, loop residency

The fifth compiler round keeps loop state on the stack. Memory lowering
materializes each element access as `add base, 32` plus an index term
inside the loop that reads it; a second loop-invariant code motion run after
lowering hoists that base, and cheap word arithmetic executed on every
iteration is hoisted as well, within a budget of five carried words per
loop. The backend then emits blocks in a loop-aware reverse postorder so a
branch can carry its stack into the latch it feeds; a carried invariant
condition is duplicated for the jump instead of spilled; a branch keeps up to
twelve carried words, matching the join planner; and a store sweeping low
memory through a loop pointer counts as a spill hazard. Sources are frozen
for this measurement.

| API | Cases | Original / best solc | Checked before | Checked now | Change |
|---|---:|---:|---:|---:|---:|
| `LibSort.insertionSort(uint256[])` | 46 | 585,478 | 505,343 | 361,120 | -28.5% |
| `LibSort.sort(uint256[])` | 46 | 311,155 | 487,109 | 346,776 | -28.8% |
| `LibSort.insertionSort(address[])` | 46 | 678,219 | 794,991 | 597,272 | -24.9% |
| `LibString.runeCount(string)` | 6 | 25,700 | 57,966 | 43,798 | -24.4% |
| `LibSort.reverse(address[])` | 46 | 305,975 | 376,422 | 321,938 | -14.5% |
| `Base64.encode(bytes)` | 16 | 68,788 | 325,680 | 280,884 | -13.8% |
| `LibBit.toNibbles(bytes)` | 15 | 20,084 | 96,279 | 83,949 | -12.8% |
| `LibSort.copy(address[])` | 46 | 331,217 | 291,714 | 262,284 | -10.1% |
| `LibSort.hasDuplicate(uint256[])` | 46 | 179,241 | 272,688 | 246,157 | -9.7% |
| `LibString.toHexString(bytes)` | 16 | 124,344 | 170,677 | 156,890 | -8.1% |
| `LibString.toCase(string,bool)` | 6 | 19,638 | 38,636 | 36,950 | -4.4% |
| `LibString.toString(uint256)` | 19 | 70,108 | 126,170 | 121,024 | -4.1% |
| `LibString.is7BitASCII(string)` | 12 | 15,659 | 10,792 | 10,518 | -2.5% |
| `LibBit.countZeroBytes(bytes)` | 22 | 37,376 | 27,226 | 26,888 | -1.2% |
| `LibBit.countZeroBytesCalldata(bytes)` | 22 | 35,621 | 23,679 | 23,589 | -0.4% |
| `Base64.decode(string)` | 65 | 312,712 | 1,711,796 | 1,706,612 | -0.3% |

`clz`, `popCount`, and `toUint40` are unchanged and every executed case
matches the oracle. `insertionSort(uint256[])` wins 39 of 46 cases, `sort`
38, `copy` 42, `hasDuplicate` 18; `insertionSort(address[])` is 12% under
its envelope in total but still wins only its 8 largest cases. The shared
runtime corpus improves 1.63% in runtime gas (lib-string -26.65%) and 0.44%
in runtime bytes, with a worst per-call loss of 33 gas on a zero-trip loop
whose hoisted base is now computed before the loop. The decoder's loop
carries a dozen live words and still spills; that is the open residual.
Artifacts: `solar/target/safe-solady/m5/rb-base5-mixed-200/` (before) and
`rb-cand9-mixed-200/` (after); corpus comparison
`solar/target/codegen-bench/cmp-rb9.md`.

## Compiler optimization checkpoint, 2026-09-13, decoder joins and stepped pointers

Two more rounds on frozen sources. The first lets a join with more than two
predecessors keep the words an enclosing loop carries, which the Base64
decoder's four three-way lookups had dropped on every iteration, and raises
the hot-leaf inliner's budget to the twelve words the backend now carries,
so all four lookups inline instead of two staying calls. The second steps
element addresses as pointers after memory lowering: scaled and descending
strides, invariant starts, and `a[j - 1]` derived from the `a[j]` pointer,
under a price model that leaves a lone scaled use alone.

| API | Cases | Original / best solc | Checked before | Checked now | Change |
|---|---:|---:|---:|---:|---:|
| `Base64.decode(string)` | 65 | 312,712 | 1,706,612 | 1,444,550 | -15.4% |
| `Base64.encode(bytes)` | 16 | 68,788 | 280,884 | 236,394 | -15.8% |
| `LibString.toCase(string,bool)` | 6 | 19,638 | 36,968 | 30,852 | -16.5% |
| `LibString.toHexString(bytes)` | 16 | 124,344 | 156,890 | 136,625 | -12.9% |
| `LibBit.toNibbles(bytes)` | 15 | 20,084 | 83,994 | 76,704 | -8.7% |
| `LibSort.sort(uint256[])` | 46 | 311,155 | 346,776 | 338,536 | -2.4% |
| `LibSort.insertionSort(uint256[])` | 46 | 585,478 | 361,120 | 352,687 | -2.3% |
| `LibSort.reverse(address[])` | 46 | 305,975 | 321,938 | 316,988 | -1.5% |
| `LibSort.insertionSort(address[])` | 46 | 678,219 | 597,272 | 593,267 | -0.7% |

`decode` wins its first two cases; the other APIs, the newly ported
`replace` included, are unchanged, and every executed case matches the
oracle. The shared runtime corpus is flat for both rounds (lib-string -0.69%
then -0.03%) with no per-call loss. The pointer rule was tuned against three
measured losses: reducing `copy`'s two single-use pointers cost 1.2%,
`toString`'s `out[--i]` cost 24%, and a byte pointer in `replace`'s search
loop cost 1.3%; all three now stay as they were. Artifacts:
`solar/target/safe-solady/m5/rb-rb10-mixed-200/` (before),
`rb-cand12-mixed-200/` (joins and inlining), `rb-cand22-mixed-200/`
(pointers); corpus comparisons `solar/target/codegen-bench/cmp-cand12.md`
and `cmp-cand22.md`.

## Compiler optimization checkpoint, 2026-09-13, counter elimination

The sixth round removes a loop's counter once its addresses are pointers:
the exit test compares an ascending pointer with its value at the bound
and the counter's phi and update are deleted, which also lets every
address family of the loop become a pointer at once. Sources are frozen.
Two defects the rebase onto upstream's halt-and-heap fix surfaced are
fixed in the same batch: merging equivalent functions now keeps the
proved element widths apart, so `copy(address[])` keeps its canonical
return, and a constructor's conditional halt stays an explicit `STOP`
ahead of the runtime bytes.

| API | Cases | Original / best solc | Checked before | Checked now | Change |
|---|---:|---:|---:|---:|---:|
| `LibSort.reverse(address[])` | 46 | 305,975 | 316,988 | 302,736 | -4.5% |
| `LibString.toHexString(bytes)` | 16 | 124,344 | 136,625 | 130,867 | -4.2% |
| `LibBit.toNibbles(bytes)` | 15 | 20,084 | 76,704 | 73,728 | -3.9% |
| `LibSort.copy(address[])` | 46 | 331,217 | 262,284 | 253,580 | -3.3% |
| `LibSort.insertionSort(address[])` | 46 | 678,219 | 593,267 | 575,499 | -3.0% |
| `LibSort.sort(uint256[])` | 46 | 311,155 | 338,536 | 329,698 | -2.6% |
| `LibSort.insertionSort(uint256[])` | 46 | 585,478 | 352,687 | 343,825 | -2.5% |

`reverse` now wins 31 of its 46 cases and is under its envelope in total;
`copy` keeps 42 wins. The other APIs are unchanged and every executed case
matches the oracle. The shared runtime corpus is flat (runtime gas -0.01%, bytes unchanged, no per-call loss). Artifacts:
`solar/target/safe-solady/m5/rb-cand22-mixed-200/` (before) and
`rb-cand30-mixed-200/` (after); corpus comparison
`solar/target/codegen-bench/cmp-cand30.md`.

## Compiler optimization checkpoint, 2026-09-14, returned array parameters

Returning an array parameter re-encoded its elements one at a time and cleaned
them first, although ABI decoding had already validated them. The element
widths the compiler proves per array parameter now also settle the return: an
array the wrapper decoded for one of its own parameters returns with a single
payload copy, the shape word arrays already had. Inline assembly that stores a
full word keeps the per-element path. Sources are frozen for this measurement.

| API | Cases | Original / best solc | Checked before | Checked now | Change |
|---|---:|---:|---:|---:|---:|
| `LibSort.reverse(address[])` | 46 | 305,975 | 302,736 | 149,749 | -50.5% |
| `LibSort.insertionSort(address[])` | 46 | 678,219 | 575,499 | 423,406 | -26.4% |

`reverse(address[])` now beats the envelope on all 46 cases and
`insertionSort(address[])` on 38, up from 31 and 8. The other APIs are
unchanged and the shared runtime corpus is unchanged. In the complete
20,421-case matrix the thirteen `address[]` APIs meet the envelope on 1,915 of
their 2,512 cases, and every case matches the oracle on both compilers of the
checked source. Artifacts: `solar/target/safe-solady/m5/rb-cand30-mixed-200/`
(before), `rb-cand32-mixed-200/` (after) and `full-cand32/` (complete matrix).

## Compiler optimization checkpoint, 2026-09-14, arrays a function builds

The element widths the compiler proves now also settle the return of an array a
function allocates and fills, not only one it received as a parameter. Sources
are frozen for this measurement.

| API | Cases | Original / best solc | Checked before | Checked now | Change |
|---|---:|---:|---:|---:|---:|
| `LibSort.copy(address[])` | 46 | 331,217 | 253,580 | 180,915 | -28.7% |
| `LibSort.union(address[],address[])` | 184 | 1,224,878 | 2,094,772 | 1,680,521 | -19.8% |
| `LibSort.intersection(address[],address[])` | 184 | 909,764 | 1,311,070 | 1,134,819 | -13.4% |
| `LibSort.difference(address[],address[])` | 184 | 1,064,762 | 1,400,831 | 1,232,695 | -12.0% |

`copy(address[])` beats the envelope on all 46 cases. The three set operations
now cost what their `uint256[]` and `bytes32[]` variants cost, so the distance
left to the envelope is the two-pass merge the port uses rather than the
element type. All 20,421 cases match the oracle on both compilers of the
checked source, and 14,225 of the 20,370 comparable cases meet the envelope.
Artifacts: `solar/target/safe-solady/m5/full-cand32/` (before) and
`full-cand39/` (after).

## Measured and rejected, 2026-09-14: branch removal in the Base64 decoder

Each of the decoder's four lookups per iteration guards its table select with a
two-part range test, and the decoder executes sixteen times the envelope's
control-flow steps. Four compiler changes were built to remove those guards:
fusing the two branches of a short-circuit test whose join receives the same
value on both edges, converting again after inlining creates that join, a larger
speculation limit, and a cost model that no longer counts a speculated arm's
bytes twice. Together they changed nothing across the 20,421-case matrix and
nothing on the shared runtime corpus, and all four were reverted.

The conversion is correctly rejected: the table select costs 55 gas and running
it on both paths exceeds the 40 gas of branches removed. The saving is real only
because valid Base64 always takes the in-range path, which a model without
execution frequencies cannot know. This is recorded so the experiment is not
repeated; closing it needs profile information, not a better local rule.

## Measured and rejected, 2026-09-14: selector dispatch deposit weight

The external selector switch chooses its lowering by lifetime cost: the runtime
term is the summed dispatch gas of every route times the expected calls, and the
deposit term is the code size times the deposit price times the number of cases.
Dropping that last factor lets the combined harness afford wider tables. Across
the 20,421-case matrix that measured 52,522,656 to 51,811,866 opcode gas, a 1.35%
saving, with the envelope met on 14,405 cases instead of 14,225 and LibBit alone
7.70% cheaper, for 230 more runtime bytes in the harness.

The shared runtime corpus rejects it. Runtime gas moved 0.01% while runtime bytes
grew 0.96%, creation bytes 0.81% and deployment gas 0.75%, with individual
contracts up to 5.89% larger. The factor is also correct as written: the runtime
term already sums over every route, so under the documented model of one
deployment answering `expected_executions` equally likely calls both terms carry
the same factor. Removing it does not fix a mis-weighting, it silently multiplies
the assumed call count by the number of public functions. Reverted.

## Checked-source algorithm checkpoint, 2026-09-14: tables, one-pass merges, fast scans

The compiler is frozen at `solar` commit `b8076df70` for this measurement, so
every number below comes from the checked sources alone. The earlier checkpoints
showed the remaining distance to assembly was no longer the compiler: on the same
checked sources our compiler already produced 2.2 to 2.5 times less gas than solc
for the codecs, and beat solc on the original assembly sources too. What was left
was written into the port.

Four rewrites, all still free of assembly and of `unchecked`:

- **Base64** builds one alphabet in memory per call, patching the two URL-safe
  characters in place, instead of testing the mode and selecting between two
  word tables for every output character. Decoding indexes a reverse table that
  spans the whole byte range, so a lookup needs neither a range test nor a bounds
  check. Both loops split complete groups from the tail, which removes four
  per-iteration guards.
- **LibSort** replaces the two-pass `for (pass; pass < 2)` merge in all twelve set
  operations with one counting helper per element type. With sorted, uniquified
  inputs the three result lengths are exact functions of a single count, so each
  operation walks the inputs once for the count and once to fill, with no
  per-element test of which pass is running.
- **LibString** tests a needle's first byte before the full comparison and skips
  the comparison entirely for one-byte needles, which removes a call at nearly
  every scan position; `indicesOf` and `replace` lose the same two-pass loop;
  `repeat` doubles an accumulated chunk with `bytes.concat` instead of copying a
  byte at a time; and the escape helpers return a word and a length rather than
  allocating a `bytes` for every scanned byte.
- **LibBit** narrows `fls` and `clz` to their top byte in five branch-free steps
  and then reads the bit index from a table, in place of an eight-step cascade.
  `ffs` follows from `fls`.

| API | Cases | Original / best solc | Checked before | Checked now | Change |
|---|---:|---:|---:|---:|---:|
| `Base64.decode(string)` | 65 | 312,712 | 1,444,550 | 634,543 | -56.1% |
| `Base64.encode(bytes,bool,bool)` | 64 | 283,220 | 1,005,018 | 587,296 | -41.6% |
| `LibSort.union(address[],address[])` | 184 | 1,224,890 | 1,680,521 | 1,273,605 | -24.2% |
| `LibSort.union(bytes32[],bytes32[])` | 184 | 1,036,183 | 1,420,802 | 1,026,925 | -27.7% |
| `LibSort.difference(address[],address[])` | 184 | 1,060,073 | 1,232,695 | 1,064,382 | -13.7% |
| `LibString.replace(string,string,string)` | 216 | 698,202 | 2,112,701 | 1,597,428 | -24.4% |
| `LibString.indicesOf(string,string)` | 72 | 196,058 | 615,340 | 401,792 | -34.7% |
| `LibString.indexOf(string,string,uint256)` | 494 | 702,855 | 970,505 | 823,711 | -15.1% |
| `LibString.repeat(string,uint256)` | 20 | 36,407 | 217,254 | 28,359 | -86.9% |
| `LibBit.clz(uint256)` | 776 | 349,976 | 490,872 | 366,272 | -25.4% |
| `LibBit.fls(uint256)` | 776 | 314,280 | 409,474 | 339,112 | -17.2% |
| `LibBit.ffs(uint256)` | 776 | 403,520 | 455,972 | 385,447 | -15.5% |

Whole-matrix totals, against the per-call cheaper of the two upstream solc
pipelines:

| Library | Envelope | Checked before | Checked now | Before | Now |
|---|---:|---:|---:|---:|---:|
| Base64 | 805,836 | 3,189,407 | 1,664,601 | 3.96x | 2.07x |
| LibBit | 3,465,505 | 3,007,289 | 2,727,813 | 0.87x | 0.79x |
| LibSort | 43,892,809 | 35,744,940 | 33,041,074 | 0.81x | 0.75x |
| LibString | 6,121,520 | 10,343,017 | 8,889,614 | 1.69x | 1.45x |
| SafeCastLib | 297,552 | 238,003 | 238,003 | 0.80x | 0.80x |
| Total | 54,583,222 | 52,522,656 | 46,561,105 | 0.962x | 0.853x |

`repeat`, `ffs`, and the `bytes32[]` and `int256[]` set operations now beat the
assembly envelope outright. Across the matrix 15,732 of the 20,370 comparable
cases meet it, against 14,225 before. All 20,421 cases still match the oracle on
both compilers of the checked source; the 135 retained failures are unchanged and
all sit in the upstream variants.

Deployment size moved with it. The Base64 harness dropped from 3,638 to 1,974
runtime bytes, which is 52% above the cheaper upstream solc build where it was
180% above. LibSort is unchanged at 12,589 bytes, LibBit grew 111 bytes for its
two tables, and LibString grew 508 bytes for the split scan paths, so the five
harnesses together are 1,048 bytes smaller.

What remains is per-byte memory traffic that checked Solidity cannot express away.
Base64 at 2.07x reads its three input bytes with three loads and writes its four
output characters with four `MSTORE8`s, where the assembly reads one word and
writes one word. `escapeHTML` and `escapeJSON` moved only 5% because their cost is
the two per-byte scans, not the allocation that was removed. Closing those needs
either a compiler that fuses adjacent byte accesses into word accesses or a
language-level way to move a run of bytes.

Artifacts: `solar/target/safe-solady/m5/full-cand46/` (before) and
`solar/target/safe-solady/m6/src8/` (after).

### Second round: decimal length, letter case, escape membership

A follow-up pass took the three scalar APIs the plan still named. `toString`
finds its digit count by halving the remaining magnitude in seven steps rather
than dividing by ten once per digit. `toCase` hoists the letter range out of the
loop and converts with the single bit that separates the two cases, instead of
two guarded compound conditions per byte. The escape scans test membership of the
escaped set with one shift and mask, so a byte that needs no escape never reaches
the helper.

| API | Cases | Original / best solc | Checked before | Checked now | Change |
|---|---:|---:|---:|---:|---:|
| `LibString.toString(uint256)` | 19 | 70,108 | 121,081 | 105,872 | -12.6% |
| `LibString.toString(int256)` | 19 | 67,879 | 115,447 | 101,911 | -11.7% |
| `LibString.toCase(string,bool)` | 6 | 19,638 | 30,852 | 25,256 | -18.1% |
| `LibString.escapeJSON(string,bool)` | 12 | 34,136 | 124,553 | 77,581 | -37.7% |
| `LibString.escapeJSON(string)` | 6 | 15,485 | 59,515 | 37,160 | -37.6% |
| `LibString.escapeHTML(string)` | 5 | 14,426 | 89,667 | 76,800 | -14.3% |

One change in this round was measured and reverted: counting how many of the five
UTF-8 thresholds a byte reaches makes `runeCount` branch-free but 12.6% more
expensive, because the first test already settles every ASCII byte and the
short-circuit never evaluates the rest.

The `toHexString(uint256,uint256)` pair rose 10% over the same interval without
its source changing, and `searchSorted` and `inSorted` moved by comparable
amounts in both directions. Compiling the same sources with the previous compiler
reproduces the new numbers exactly, so this is the combined harness moving: these
per-call figures include selector dispatch, and the LibString harness grew 581
bytes in this round. Isolated, the hexadecimal loop is six instructions per
nibble with no bounds check.

### Where the port stands

| Library | Envelope | Checked before | Checked now | Before | Now | Wins | Losses |
|---|---:|---:|---:|---:|---:|---:|---:|
| Base64 | 805,836 | 3,189,407 | 1,664,445 | 3.96x | 2.07x | 2 | 175 |
| LibBit | 3,465,505 | 3,007,289 | 2,727,813 | 0.87x | 0.79x | 4,844 | 1,719 |
| LibSort | 43,892,809 | 35,744,940 | 32,900,521 | 0.81x | 0.75x | 8,637 | 1,407 |
| LibString | 6,121,520 | 10,343,017 | 8,902,513 | 1.69x | 1.45x | 1,747 | 1,165 |
| SafeCastLib | 297,552 | 238,003 | 238,003 | 0.80x | 0.80x | 504 | 156 |
| Total | 54,583,222 | 52,522,656 | 46,433,295 | 0.962x | 0.851x | 15,734 | 4,622 |

The twelve costliest remaining gaps are the two Base64 directions (2.03x and
2.07x), `replace` (2.28x), `split` (2.08x), `indicesOf` (2.06x), the
`toHexString(uint256,uint256)` pair (1.68x), `toHexStringChecksummed` (2.39x),
`hasDuplicate` (1.41x across all four element types), `slice` (1.20x) and
`indexOf` (1.17x). Every one of them is a loop that reads or writes memory one
byte at a time where the assembly moves a word, which is the boundary this port
cannot cross from the source side.


## Composed workloads, 2026-09-14

Per-API numbers do not say what an application pays, so
`benchmarks/checked/composed.py` measures three workloads that chain several
libraries in one call: an ERC-721 style `tokenURI` that escapes a name, renders
an identifier and a checksummed owner and Base64s the document; a `mergeLists`
set pipeline that sorts two lists and takes their union, intersection and
difference; and a `decodeAndScan` path that Base64-decodes a payload then counts,
measures and searches it. The workload source is byte-identical across every leg
and uses only APIs whose declarations the port shares with the pinned archive, so
the same contract compiles against the checked sources and against the original
assembly. There is no separate Python oracle: the check is that all six legs
return the same bytes, which is agreement between two independent implementations
under three compiler pipelines. All 18 cases agree.

| Workload | solc upstream legacy | solc upstream IR | solc safe legacy | solc safe IR | our compiler, upstream | our compiler, checked |
|---|---:|---:|---:|---:|---:|---:|
| `tokenURI` | 114,494 | 117,711 | 762,137 | 678,777 | 100,272 | 256,865 |
| `mergeLists` | 164,390 | 169,921 | 586,149 | 673,405 | 130,612 | 310,333 |
| `decodeAndScan` | 154,509 | 167,271 | 882,055 | 791,789 | 131,501 | 240,256 |
| Total | 433,393 | 454,903 | 2,230,341 | 2,143,971 | 362,385 | 807,454 |

Held against the same source, our compiler costs 0.84 times solc's cheaper
pipeline on the original assembly and 0.38 times solc's cheaper pipeline on the
checked rewrite. The checked port compiled by us costs 1.88 times the assembly
envelope, ranging from 1.56x on the decode path to 2.25x on the metadata URI.

The identical workload contract deploys at 7,969 runtime bytes from the checked
sources against 4,139 for the original assembly under solc via-IR, and 4,929 when
we compile that same assembly. Whole-application deployment cost is therefore the
place where this port is furthest behind, and it is not hidden by the gas result.

Both rewrites in this round touched libraries the pinned upstream suites cover.
Re-running those suites after them reproduces the earlier result exactly: the
checked implementations pass all 60 tests under both solc via-IR and our
compiler, and the original solc baseline still fails only
`testToNibblesDifferential`.

This is the honest statement the workloads support: a library collection written
in ordinary checked Solidity, compiled by us, runs these three application
workloads for 1.88 times the gas of the assembly original compiled by solc, and
for 0.38 times what solc charges for the same checked sources. It is not parity,
and the three workloads are not an application.

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

## Checkpoint — 2026-09-22: packed short strings

Solar and the checked LibString now route `packOne`, `unpackOne`,
`packTwo`, and `unpackTwo` through compiler-owned `Strings` entry points.
The portable bodies remain ordinary checked Solidity. The intrinsic packers
replace per-byte loops with bounded word loads, masks, and shifts; the
unpackers use word stores and preserve the two-value return ABI.

The full UI suite passes 4,044 cases. The 200-run full 224-API harness covers
45 packing cases with zero mismatches. Against the cheaper upstream solc
legacy/via-IR result per call:

- `packOne` wins all five cases by 30–33 opcode gas.
- `packTwo` wins all twenty cases by 331–334 opcode gas.
- `unpackOne` is still 67 opcode gas behind in all four cases.
- `unpackTwo` is still 114–120 opcode gas behind in all sixteen cases.

Artifacts are in
`solar/target/safe-solady/close-gaps/string-packing-core-20260922/`.

**Stop point:** packing is closed. Unpacking is correct but has not met the gas
gate. Its MIR still uses the general dynamic-bytes allocator, including
rounding and overflow checks even though the decoded lengths are bounded by
31 and 30. The next experiment is an exact 64-byte allocation for
`unpackOne` and one 128-byte allocation split into two 64-byte objects for
`unpackTwo`, followed by the full 200- and 1,000,000-run gas/size matrices.
Do not mark the unpacking APIs complete until every case reaches parity.

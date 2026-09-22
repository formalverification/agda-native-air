<!-- File: docs/import-closure.md -->

# Import closure: what this repository's Agda costs to check and to ship

Every one of the 110 obligation and gold files under `data/benchmarks/` opens
`AgdaDojang.Debug`, which opens `AgdaDojang.Prelude`, and each fixture adds a
few standard-library imports of its own.  An `open import` drags the whole
transitive closure of the module it names, and Agda deserializes that closure on
every check.  The cost is paid three times: in type-checking time on every cold
build, in interface bytes for anything that has to ship the closure (a
browser-hosted Agda fetches the `.agdai` files of whatever it checks), and in
the size of the name space a searcher or an agent sees.

This note is the durable record of what that costs here.  It states the danger,
gives the measurement recipe, reports what has been measured, and records the
two decisions that came out of it: issue [#168], which cut the prelude, and
issue [#167], which declined to cut the fixtures.  The procedure is also
packaged as the `changing-a-shared-agda-module` skill in the `claude-tooling`
repository.

## The danger, and the three rules that follow

The danger is that an import looks free at the call site.  `Data.Bool` instead
of `Data.Bool.Base` is one character of difference and re-exports a whole
boolean-algebra development; `Data.String.Properties._==_` is `isYes (s₁ ≟ s₂)`
and brings in most of the relation and order hierarchy behind it.  Neither line
looks expensive, and until 2026-09 the two of them together cost every file in
this repository 154 modules and 31.0 MB of interfaces.

Three rules follow, and the rest of this note is the evidence for them.

+  **In `AgdaDojang.Prelude`, prefer the primitive or the `.Base` module**.  The
   prelude is opened by everything, so an import added there is paid by
   everything.  Reach for an `Agda.Builtin.*` primitive or a `.Base` module
   before the full standard-library wrapper that re-exports a properties module
   alongside it.
+  **In a benchmark fixture, import the module a person would import**.  The
   fixtures exist so that a model's performance on them transfers to real Agda,
   and real Agda imports `Relation.Binary.PropositionalEquality`, not its
   `.Core`.  Trimming a fixture's imports to shrink its closure optimizes the
   benchmark against a property the benchmark is not measuring.  See the
   decision below, which is measured rather than asserted.
+  **A byte-budgeted consumer carries its own trimmed copy**.  Shipping one
   obligation to a browser is the consumer's problem and the consumer solves it
   in its own repository, as `williamdemeo/website` does.  The corpus stays
   idiomatic.

## How to measure it

`agda --dependency-graph` writes the module closure as a Dot file; the interface
bytes are then one `stat` per module against the pinned store paths named in
`agda/libraries`.  Use a file that **exits 0**, because a file with an open hole
does not get a graph written.

```sh
agda --no-default-libraries --library-file <libs> --library standard-library \
     --library agda-dojang --dependency-graph=deps.dot -i <dir> <file>
grep -oE 'label="[^"]+"' deps.dot | sed 's/label="//;s/"//' | sort -u
```

Four things decide whether the resulting number means anything.

+  **State which set the byte column covers**.  `Agda.Builtin.*` and
   `Agda.Primitive` ship no `.agdai` in the `agdaWithPackages` store path, and
   neither do this repository's own modules until they are built locally.  They
   are in the module count and contribute nothing to the byte column.
+  **Quote the delta, not the endpoint**.  Endpoints move with whichever modules
   an accounting chooses to include; the delta is stable and is what reproduces.
   The two accountings used on [#167] differ by a constant 319,755 raw bytes and
   agree on the delta to the byte.
+  **Measure candidate imports together, not one at a time**.  Two expensive
   imports hide behind each other, and measuring either alone concludes that
   neither is worth fixing.  Build one tree per subset: each candidate alone,
   and all of them.
+  **Across a suite, take the union, not the sum**.  A per-file closure counts
   every shared module once per file, so summing 55 of them counts the standard
   library 55 times and reports a saving nobody can spend.

Timings must be cold, serial, single-file, and from a fresh tree.  A whole-suite
wall clock is confounded, because files checked in sequence share an interface
cache and the tier that runs second is measured against a cache the first tier
filled.

## What the prelude cost: issue #168

Two imports in `AgdaDojang.Prelude`, replaced in [#173] by `Data.Bool.Base` and
a local `_==_ = primStringEquality`.  Import closure of `AgdaDojang.Debug`:

| Variant | Modules | Interface bytes | Saved |
|---|---:|---:|---:|
| before | 190 | 31,736,596 | |
| `Data.Bool` to `Data.Bool.Base` alone | 189 | 31,714,757 | 1 module, 21,839 B |
| `_==_` to `primStringEquality` alone | 88 | 10,858,493 | 102 modules, 20,878,103 B |
| both | **36** | **758,382** | **154 modules, 30,978,214 B** |

The middle two rows are the compounding trap in the flesh: the `Data.Bool` line
measured on its own is worth 21,839 bytes, and measured after the string import
is gone the same one-line change is worth 52 modules and 10,100,111 bytes.

The effect on one benchmark gold, `Bool-not-involutive`, with a cold check in a
fresh tree:

| Variant | Modules | Interfaces | Gzipped | Cold check |
|---|---:|---:|---:|---:|
| before | 191 | 31,736,596 | 26,918,858 | 2.85 s |
| after | 73 | 6,573,402 | 5,603,097 | 0.76 s |

Agda's output was byte-identical before and after on all 110 benchmark files,
all seven `agda-dojang` modules and the twelve fixtures under
`agda-dojang/data/fixtures/`.  This was a pure win with no trade-off, and it is
done.

## What the fixtures cost: issue #167

What remained after [#168] was one line in the fixtures themselves,
`open import Relation.Binary.PropositionalEquality using ( _≡_ ; refl )`, and
importing `.Core` instead takes that gold from 70 modules to 34.  Whether to do
it was measured over the whole suite on 2026-09-21 at `bc86f4a`.

### The trim is mechanically safe, and moves 15 rows of 55

29 of the 55 rows carry the import, across 58 of the 110 files.  The names those
lines list are exactly `_≡_`, `refl`, `cong`, `sym` and `cong₂`, and `.Core`
exports all five.  Substituting `.Core` in all 58 and checking every file in a
fresh tree: all 55 golds exit 0, all 55 obligations exit 42
(`UnsolvedInteractionMetas`, the expected verdict for a file with a hole), and
all 110 transcripts are byte-identical to the unmodified tree's.  So no gold
uses anything outside `.Core`.

What is not uniform is how many rows the trim would change at all, because most
rows already pay for the full module through something else they import.

| Tier | n | carry the import | closure shrinks |
|---|---:|---:|---:|
| `agda-stdlib` (frozen) | 22 | 18 | **13** |
| `agda-stdlib-haystack` | 12 | 8 | **2** |
| `agda-algebras` | 21 | 3 | **0** |
| total | 55 | 29 | **15** |

By difficulty: `routine` 5 of 16, `compositional` 10 of 25, `non-obvious` 0 of
14.  The 40 rows that do not move are 21 `agda-algebras` rows, whose
`Overture`/`Setoid` imports dwarf everything; 17 rows that import
`Data.Nat.Properties`, `Data.List.Properties` or `Data.Bool.Properties`, each of
which pulls the full `Relation.Binary.PropositionalEquality` in anyway; and 2
that never import it.

The 15 that do move come in five shapes.  Module counts are on the issue's
convention (the closure less this repository's own three modules, which ship no
interface); byte columns cover the store-shipped standard-library interfaces
only.

| Rows | Closure | Interfaces raw | Gzipped |
|---|---:|---:|---:|
| `stdlib-bool-not-involutive` | 70 to 34 | 6,573,402 to 758,382 | 5,603,097 to 662,330 |
| `stdlib-maybe-map-nothing` | 72 to 36 | 6,667,912 to 852,892 | 5,686,003 to 745,236 |
| six `Nat` rows | 74 to 42 | 6,823,246 to 1,239,995 | 5,820,680 to 1,079,638 |
| five `List` rows | 78 to 47 | 7,452,430 to 1,881,181 | 6,364,227 to 1,633,842 |
| two haystack `Bool` rows | 96 to 85 | 11,596,540 to 10,836,654 | 9,829,409 to 9,172,301 |

A cold, fresh-tree, single-file check of `stdlib-bool-not-involutive`'s gold
goes from 0.78 s to 0.26 s natively, and [#167] measured 3.58 s to 1.52 s under
wasm32.

### The suite's union closure does not move at all

This is the finding that decided the issue.

| Accounting | Modules | Interfaces raw | Gzipped |
|---|---:|---:|---:|
| sum of the 55 per-row figures, before | 8,478 | 1,319,819,448 | 1,121,392,718 |
| sum of the 55 per-row figures, after | 8,037 | 1,245,313,885 | 1,058,098,791 |
| *apparent* saving | 441 | 74,505,563 | **63,293,927** |
| **union over the suite, before** | **370** | **61,488,041** | **52,363,547** |
| **union over the suite, after** | **370** | **61,488,041** | **52,363,547** |
| actual saving | **0** | **0** | **0** |

Per tier the union is unchanged too: `agda-stdlib` 161 modules,
`agda-stdlib-haystack` 180, `agda-algebras` 336, before and after.  Even inside
the frozen tier alone, where 13 of the 22 rows shrink, the union does not move,
because `stdlib-nat-plus-comm` and the four `Nat`-properties rows beside it hold
the whole closure open on their own.

So a consumer holding the corpus, a tier of it, or even the frozen tier alone
saves nothing.  The saving exists only for a consumer that ships **one** row,
and only if that row is one of the 15.

### The consumer that asked for it does not need the corpus to change

The consumer is `williamdemeo/website`'s `/playground/`, a browser-hosted Agda
behind a consent gate.  It has shipped: image 6,073,683 gzipped bytes, 73
compiled interfaces, 1,082 to 1,277 ms a check in steady state, inside its
30 MB page budget and under Cloudflare Pages' 25 MiB per-file limit.

It keeps the obligation as a **literal seed string** in
`scripts/python/build_playground_assets.py`, "verbatim but for its module name",
and never reads `data/benchmarks/`; its only coupling to this repository is a
path to the `agda-dojang` library.  Running that builder's own seed under the
flake's Agda gives 73 modules with the full module and 37 with `.Core`, both
exit 0.  The consumer therefore takes its second exercise from 5.8 MB to under
1 MB by editing one line in its own repository.

### The decision: leave the fixtures alone

The suite union is identical either way, so no corpus holder saves a byte; the
only consumer that asked already ships and can trim its own copy; and the 15
rows that would move are 13 rows of a frozen tier plus 2 haystack rows.  Against
that, trimming would break the byte-identity the P1 and P2 baselines are quoted
against, fail 46 of the 170 archived agent-bench final files on the preservation
gate, and take roughly 38 names and the `≡-Reasoning` module out of qualified
reach on exactly the rows whose job is to look like ordinary Agda.

One further measurement is worth recording, because it says what the domain's
idiom is rather than asserting it.  Across the 170 archived subject files of the
agent-in-the-loop evaluation ([#154]), the only standard-library import any
model ever added to a fixture was
`open import Relation.Binary.PropositionalEquality using ( trans )`, 14 times,
never the `.Core` form, although `trans` is in `.Core`.  None of those 14 is on
one of the 15 rows, so this does not erode the saving; it is evidence about what
a model writes when left to itself.

The full comment with every table is on [#167].

## Who reads a fixture from the working tree

An import edit to a fixture is not only an Agda question.  Several things here
read an obligation from the working tree and pair it with a file frozen
elsewhere, so an edit desynchronizes them silently.  Check each before proposing
one.

+  **The agent-bench archive**.  `Outcomes.judgeOne` reads the live obligation
   and the archived final file under
   `reports/agent-bench/<run>/subjects/<id>/final/`.  The preservation gate
   requires every original import line to be present in the final, so changing
   one fails that row on the next `make agent-bench-rejudge`, with a message
   that describes the edit rather than the subject.  Trimming the 15 rows of
   [#167] would fail 46 of 170 archived files; trimming all 58 would fail 90.
+  **The demo page**.  `scripts/python/demo/replays.py` reads the live
   obligation, reads the archived final, and publishes `marked_diff` of the two,
   so a fixture edit appears on the published page as a line the subject
   changed.  Its replay subjects are named in that file.
+  **The frozen tier**.  `agda-stdlib-v0` is frozen because the P1 baseline
   ([#113]) is quoted against it, and its 22 obligations are recorded as
   byte-identical to the P1 and P2 baselines' fixtures.
+  **The action space**.  `open import M using ( … )` grants *qualified* access
   to everything in `M`, which is what the haystack tier is built on.  Swapping
   `M` for a smaller `M.Core` removes names from what `search_in_scope`, the
   retrieval proposer and an agent subject can reach on that row, even though
   the `using` list is unchanged.
+  **What CI runs**.  The `benchmark-gold` lane triggers on `data/benchmarks/`,
   `strux-driver/`, `agda-dojang/` and the toolchain pin, and runs
   `eval-benchmark-smoke`, which is nine rows.  The rest of the suite is covered
   only by a local `make eval-benchmark`.

## Reproducing any of this

+  Two trees extracted with `git archive`, one per variant, each with its own
   `.agdai` cache and its own libraries file, so no editor state leaks in.
+  Every file driven through the consumer's real argument vector, which for the
   benchmark suite is `struxdriver.benchmark.EvalBenchmark.agdaCommand`, with
   `--library agda-algebras` given only to rows whose `source` is
   `agda-algebras`.
+  Combined output plus exit code captured, the variant's own root normalized
   out of every path, Agda's progress lines dropped, and the transcripts diffed.
   Agda 2.8.0 writes diagnostics to stdout, so `2>&1` is what captures them.
+  Never warm one variant's cache and not the other: a file whose `.agdai` is
   current prints nothing at all, so its transcript differs from the same file
   checked cold even though the verdict is identical.

The gates that cover a change of this kind are `make -C agda-dojang check`,
`make eval-benchmark`, `make eval-benchmark-smoke`,
`make eval-proof-completion-smoke` (in `nix develop .#all`), and the
agda-dojang Python unit tests (in `nix develop .#mlPipeline`).

## References

+  [#168] and its pull request [#173]: the prelude fix, with the measurement
   table this note's first half quotes.
+  [#167]: the fixtures question, its three options, and the measured comment
   that answers it.
+  [#113] for the P1 baseline the frozen tier is quoted against, [#129] for the
   haystack tier's design, and [#154] for the agent-in-the-loop archive.
+  [`data/benchmarks/README.md`](../data/benchmarks/README.md) for the suite and
   its fixture convention, and
   [`docs/benchmarks/taxonomy.md`](benchmarks/taxonomy.md) for the difficulty
   tiers.
+  [`agda-dojang/README.md`](../agda-dojang/README.md) for the library whose
   prelude everything opens.

[#113]: https://github.com/formalverification/agda-native-air/issues/113
[#129]: https://github.com/formalverification/agda-native-air/issues/129
[#154]: https://github.com/formalverification/agda-native-air/issues/154
[#167]: https://github.com/formalverification/agda-native-air/issues/167
[#168]: https://github.com/formalverification/agda-native-air/issues/168
[#173]: https://github.com/formalverification/agda-native-air/pull/173

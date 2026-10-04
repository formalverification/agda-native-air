<!-- File: reports/auto-floor/README.md -->

# The proof-search floor: Agda's own search on every obligation

This directory holds the measurement of issue [#205]: Agda's own proof search,
run at the hole of every benchmark obligation with no model and no ranking,
each term it finds judged by the batch `fill_hole` under `--safe`.  Every
number here is a denominator no model had to earn: a later claim about an
agent or the loop on a tier reads differently when Agda alone already solves
part of it.

The search is **Mimer**, the one the pinned Agda 2.8.0 runs for
`Cmd_autoOne` (an editor's `C-c C-a`).  The issues call it Agsy, which is the
search Agda shipped until 2.6; the Agda 2.7.0 release notes record that
"Mimer, a re-implementation of the 'auto' term synthesizer, replaces Agsy",
and that it does no case splitting (Agsy's `-c`), disproving, or refining.

## How the rows were made

`make auto-floor`, whose driver is [`scripts/python/auto_floor.py`], asks
`agda-mcp`'s `auto` tool (registered with `--auto`) at each obligation's one
hole, with the subjects' flags and Agda's default options (a 1,000 ms bound
on the search's CPU time), and gives every term found to `fill_hole` on a
server whose flags add `--safe`, parenthesized as the loop parenthesizes a
candidate.  A row is solved when that status is `ok`: batch `agda`'s verdict,
never the lane's.

+  `auto-floor-1/`: all 81 obligations, 2026-10-03.
+  `auto-floor-comp-needles-1/`: the composition tier again, with each row's
   `needle:` tags (the lemmas its gold strings together, issue [#160]) passed
   as hints.  A needle goes in only when `type_of` types it at the hole, since
   `auto` refuses a whole call when one hint names nothing in scope; all 33
   typed.

Each run directory holds `rows.jsonl`, one record per obligation in index
order (the outcome, the term or the message, the error's stage, code and
first 300 characters, the search's milliseconds, the hints sent and any
dropped, `fill_hole`'s status, and `solved`), and `summary.json`, the
configuration and the per-tier counts.  Each run was made twice, the second
time into this directory, and was regenerated on 2026-10-04 the same way
with the script and server as they stand after review (the summary's
`unjudged` and `unmeasured` fields date from then).  The regenerated runs
agree with the first ones on every outcome, term, code, and status, and so
do all four runs of the composition tier with needles; one regeneration
pass of the whole suite differed on one row, the bound-sensitive
`algebras-kernels-quotient-proj-hom` below.  A row the script could not
measure names why (`failure` for a search with no usable answer, a `found`
with no term included, `judgeFailure` for a found term the judge never
ruled on, counted per tier as `unjudged` and listed in the summary as
`unmeasured`), and the script then exits 1; neither run here has such a
row.

## The floor

| tier | solved | found, not solved | no solution | out of scope | other refusal |
|---|---:|---:|---:|---:|---:|
| agda-stdlib (22) | 6 | 0 | 16 | 0 | 0 |
| agda-stdlib/haystack (12) | 0 | 0 | 12 | 0 | 0 |
| agda-algebras (21) | 11 | 0 | 8 | 2 | 0 |
| agda-stdlib/hard (6) | 0 | 0 | 6 | 0 | 0 |
| agda-algebras/hard (8) | 0 | 0 | 7 | 1 | 0 |
| agda-algebras/composition (12) | 1 | 0 | 9 | 1 | 1 |
| **total (81)** | **18** | 0 | 58 | 4 | 1 |
| composition, needles as hints (12) | 2 | 0 | 7 | 1 | 2 |

What the table says:

+  **Every term the search found was a solve**.  Eighteen terms came back and
   `fill_hole` accepted all eighteen, each after a search of 12 ms or less
   (54 ms with hints).  The search's misses are misses, not wrong answers.
+  **On the benchmark's original 55 rows the floor is 17**, the measurement
   the issue reported, and the tool reproduces it row for row against the
   hand-driven reference (`agsy-suite.py` in claude-tooling's
   `driving-agda-mcp` skill): the same 17 rows, the same 17 terms.  The one
   row of 81 where the two differed is not a solve:
   `algebras-kernels-quotient-proj-hom` printed a term it could not read back
   (out of scope) after 486 and 523 ms of search in this tool's two first
   runs and after 977 ms in the regenerated one here, and ran out of its
   1,000 ms CPU bound in the reference run and in one regeneration pass; the
   issue's own first measurement saw the out-of-scope answer.  A search that
   needs half its bound can come out either way on a busy machine, and
   neither way is a solve.
+  **No solved term names the lemma its row restates**.
   `algebras-homs-mon-to-hom` is solved from the record's own fields,
   `m .Overture.proj₁ Setoid.Algebras., m .proj₂ .IsMon.isHom` (a qualified
   `_,_` written infix, which `fill_hole` accepts).
+  **The haystack and both hard tiers are zero**.  The haystack's golds apply
   a library lemma the search is never given (the loop's retrieval supplies
   exactly those, issue [#206]), and the hard tier's rows have no proof on
   disk to assemble.
+  **Four terms were found and could not be written**: each is a record field
   printed by the full name of a module the file never imports
   (`Relation.Binary.Structures.IsEquivalence.trans` and `.refl`,
   `Function.Bundles.Func.cong`, `Setoid.Congruences.Generation.Gen.base`).
   Re-spelling them in the file's scope might recover some; nothing here
   tries.
+  **One refusal is Agda's own**: on `comp-group-normal-of-equivalent-congruence`
   the search printed a term (`Data.Product.Σ (…)`) that Agda could not read
   back as the type it had found (`ShouldBePi`).  With the needles as hints, a
   second row, `comp-congruence-simple-equivalent-total`, ends in an internal
   error inside the search (`__IMPOSSIBLE__` in
   `Agda.TypeChecking.Records`), which the tool reports in band and the lane
   survives.

## The composition tier, with its needles

The second run is an upper bound on what handing over the right lemmas buys:
every needle of every row, typed at its hole, given to the search as hints.
It solves **2 of 12**, one more than without: `comp-homomorphism-isomorph-is-image`,
by `HomImage-≅' IdHomImage A≅B`, which is the row's gold.  So on this tier
finding is not the whole difficulty: with every needle in hand, Agda's search
still assembles only two of twelve, and the rest are composition its term
search does not reach within a second (seven), terms it prints and cannot read
back (one), and the two refusals above.  The frontier models write a checking
proof for every row of the tier ([`docs/reading-the-results.md`]), so on this
tier the floor is far below them.

## Reproducing

From the repository root, inside `nix develop .#backend`, with the server built
(`make agda-mcp-build`) and nothing else running against the fixtures, since
`fill_hole` patches each obligation in place and restores it:

```sh
make auto-floor AUTO_FLOOR_RUN_ID=auto-floor-1
make auto-floor AUTO_FLOOR_RUN_ID=auto-floor-comp-needles-1 \
  AUTO_FLOOR_ARGS="--hints needles --tiers agda-algebras-composition-v0"
```

Each takes about two minutes once the libraries' interfaces are built.

[#160]: https://github.com/formalverification/agda-native-air/issues/160
[#205]: https://github.com/formalverification/agda-native-air/issues/205
[#206]: https://github.com/formalverification/agda-native-air/issues/206
[`scripts/python/auto_floor.py`]: ../../scripts/python/auto_floor.py
[`docs/reading-the-results.md`]: ../../docs/reading-the-results.md

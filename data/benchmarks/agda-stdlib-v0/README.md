# The agda-stdlib tier (v0)

File: `data/benchmarks/agda-stdlib-v0/README.md`

The 22 obligations of the original [M1-5] cut, mined from the Agda standard
library; the tier's place in the suite, its difficulty tiers, and its index
conventions are in `../README.md`.  This file records the tier's freeze and
what each fixture's header used to say.

## The freeze

The proof-search loop's P1 baseline (issue [#113], 6 of 22 solved in the
fixed space) is quoted against this tier, so its code is frozen: the
statements, the imports, the holes, and the golds only ever grow by whole new
tiers, never by edits.  Its header comments are not code.  A subject of the
agent bench works on a byte-for-byte copy of its obligation, comments
included, and until issue [#219] every header carried a `Source:` line naming
the library module, a `Strategy:` line sketching the proof, and on six rows
a `Note:` naming the key move; three archived subjects quote such lines.  The
three were removed from the obligations and golds on 2026-09-29.

The loop reads only a fixture's `open import` lines (`Imports` in
`strux-driver/src/main/scala/struxdriver/search/Propose.scala`), so the
removal cannot move a loop number, and it was run to show it: the fixed space
over the 22 rows, at the published knobs (beam 4, depth 6, 60 probes, script
dedup, the peek on), on the fixtures before the removal
(`stdlib219-before-1`) and after it (`stdlib219-after-1`), both on
2026-09-29: 6 of 22 solved, 16 exhausted, 137
probes, no anomaly, and every row's status, solve, script, probe count,
depth, expansions, final checks, and peeks identical between the two.  That
is the P1 baseline's 6 of 22.  The runs stay out of the repository, like every
loop run; the reports are `data/benchmarks/reports/proof-search/<run id>/`
on the machine that ran them.

## What the headers said

Per row, as the header had it; the index's `module` field names the same
source module, and its `goldTerm` carries the same sketch.

| #  | id | difficulty | source | strategy | note |
|----|----|------------|--------|----------|------|
| 1  | `stdlib-nat-plus-identity-l` | routine | `Data.Nat.Properties` | refl (0 + n reduces to n by definition of _+_) |  |
| 2  | `stdlib-bool-not-involutive` | routine | `Data.Bool.Properties` | case split on the boolean; each branch is refl |  |
| 3  | `stdlib-unit-trivial` | routine | `standalone` | inhabit the unit type with its constructor |  |
| 4  | `stdlib-prod-mk-pair` | routine | `standalone` | apply the product constructor |  |
| 5  | `stdlib-maybe-map-nothing` | routine | `Data.Maybe.Base` | refl (map f nothing reduces to nothing) |  |
| 6  | `stdlib-list-length-nil` | routine | `Data.List.Base` | refl (length [] reduces to 0) |  |
| 7  | `stdlib-nat-zero-lt-suc` | routine | `Data.Nat.Base` | apply the _≤_ constructors (s≤s, z≤n) |  |
| 8  | `stdlib-nat-plus-comm` | compositional | `Data.Nat.Properties` | induction on m, using +-identityʳ (base) and +-suc (step) | the obligation provides +-identityʳ and +-suc as imports so the agent has access to the key lemmas.  The challenge is composing them correctly in the inductive proof. |
| 9  | `stdlib-nat-plus-identity-r` | compositional | `Data.Nat.Properties` | induction on n; base refl, step cong suc IH |  |
| 10 | `stdlib-nat-plus-suc` | compositional | `Data.Nat.Properties` | induction on m; base refl, step cong suc IH |  |
| 11 | `stdlib-nat-plus-assoc` | compositional | `Data.Nat.Properties` | induction on m; base refl, step cong suc IH |  |
| 12 | `stdlib-nat-mul-zero-r` | compositional | `Data.Nat.Properties` | induction on n; base refl, step is the IH (0 + n * 0 reduces to n * 0) |  |
| 13 | `stdlib-nat-mul-identity-r` | compositional | `Data.Nat.Properties` | induction on n; base refl, step cong suc IH |  |
| 14 | `stdlib-list-length-append` | compositional | `Data.List.Properties` | induction on xs; base refl, step cong suc IH |  |
| 15 | `stdlib-list-map-id` | compositional | `Data.List.Properties` | induction on xs; base refl, step cong (x ∷_) IH |  |
| 16 | `stdlib-list-append-assoc` | compositional | `Data.List.Properties` | induction on xs; base refl, step cong (x ∷_) IH |  |
| 17 | `stdlib-list-map-compose` | compositional | `Data.List.Properties` | induction on xs; base refl, step cong (f (g x) ∷_) IH |  |
| 18 | `stdlib-nat-mul-comm` | non-obvious | `Data.Nat.Properties` | induction on m; base sym (*-zeroʳ n), step an equational chain using *-suc | *-zeroʳ and *-suc are provided as imports; the challenge is the non-obvious composition (the recursive call sits under cong, and the final step rewrites with *-suc backwards). |
| 19 | `stdlib-nat-mul-distrib-r` | non-obvious | `Data.Nat.Properties` | induction on n; equational chain using +-assoc (backwards) | +-assoc is provided as an import; the agent must reassociate the middle term to expose the suc-case redex. |
| 20 | `stdlib-nat-mul-distrib-l` | non-obvious | `Data.Nat.Properties` | reduce to right-distributivity via commutativity (no induction here) | *-comm and *-distribʳ-+ are provided; the non-obvious move is to use commutativity to convert the goal into the right-distributive form. |
| 21 | `stdlib-nat-mul-assoc` | non-obvious | `Data.Nat.Properties` | induction on m; equational chain pivoting on *-distribʳ-+ | *-distribʳ-+ is the non-local lemma that unlocks the suc case. |
| 22 | `stdlib-dec-map` | non-obvious | `Relation.Nullary.Decidable.Core` | case split on the decision; transport the witness / refutation | requires understanding the Dec structure (yes / no pattern synonyms) and constructing a refutation of B from a refutation of A. |

[#113]: https://github.com/formalverification/agda-native-air/issues/113
[#219]: https://github.com/formalverification/agda-native-air/issues/219

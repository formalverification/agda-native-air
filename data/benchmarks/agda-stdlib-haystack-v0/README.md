# The agda-stdlib haystack tier (v0)

File: `data/benchmarks/agda-stdlib-haystack-v0/README.md`

The 12 obligations built to measure retrieval (issue [#129]): each gold
applies one standard-library lemma, the *needle*, that the fixture imports
but does not name in its `using` list.  The tier's design constraints, its
gates, and its index conventions are in `../README.md`, "agda-stdlib-haystack
tier: design constraints and gates".  This file keeps what each fixture's
header used to say.

A subject's work file is a byte-for-byte copy of its obligation, comments
included, and until issue [#219] every header on this tier named the
haystack module, the needle itself, the strategy ("one saturated application
of the needle over the goal's context"), a note on the instance, and a
paragraph on the tier's design, which read as follows:

> Haystack tier (issue #129): the Properties module is opened with a deliberately narrow `using` list of decoys that cannot close the goal, so the needle is import-reachable only by its qualified name.  A gold that names it qualified is the same text the retrieval ladder renders.

All of it was removed from the obligations and golds on 2026-09-29.  The
index's `goldTerm` still names each needle, qualified, and the rest is
recorded here, per row, as it was.

| #  | id | difficulty | haystack | needle | note |
|----|----|------------|----------|--------|------|
| 1  | `haystack-nat-plus-suc-diag` | routine | `Data.Nat.Properties` | `Data.Nat.Properties.+-suc` | the diagonal instance of +-suc; the goal's operators spell the needle. |
| 2  | `haystack-nat-plus-zero-diag` | non-obvious | `Data.Nat.Properties` | `Data.Nat.Properties.m+n≡0⇒m≡0` | a hypothesis-consuming instance; the goal m ≡ 0 carries no signal, the hypothesis does (m+n≡0⇒n≡0 closes it too).  The hypothesis is bound in the clause because the proposer saturates every visible binder of a lemma, so a Π-typed goal could only be closed by a partial application, which is not one of the three committed candidate shapes (found on the retrieve-k 32 ledger). |
| 3  | `haystack-nat-plus-mono-diag` | compositional | `Data.Nat.Properties` | `Data.Nat.Properties.+-mono-≤` | alias-typed needle (Monotonic₂) instantiated twice at the one hypothesis. |
| 4  | `haystack-nat-mul-mono-sq` | compositional | `Data.Nat.Properties` | `Data.Nat.Properties.*-mono-≤` | alias-typed needle (Monotonic₂) instantiated twice at the one hypothesis. |
| 5  | `haystack-nat-plus-monus-assoc` | compositional | `Data.Nat.Properties` | `Data.Nat.Properties.+-∸-assoc` | a hypothesis-consuming instance whose goal signals ∸ and +. |
| 6  | `haystack-nat-plus-mono-lt-diag` | non-obvious | `Data.Nat.Properties` | `Data.Nat.Properties.+-mono-<` | the ≤ sibling is using-listed and insufficient; the goal displays as suc (m + m) ≤ n + n, so the needle's own < is a misfit token for the ranker. |
| 7  | `haystack-nat-plus-le-hyp` | non-obvious | `Data.Nat.Properties` | `Data.Nat.Properties.m+n≤o⇒m≤o` | the goal m ≤ n carries no signal; the two-step ≤-trans (m≤m+n m m) le is expressible from the decoys but not in term mode (m+n≤o⇒n≤o closes it too). |
| 8  | `haystack-list-length-append-diag` | routine | `Data.List.Properties` | `Data.List.Properties.length-++` | the diagonal instance of length-++; its implicit ys is solved by unification. |
| 9  | `haystack-list-cons-injective-head` | non-obvious | `Data.List.Properties` | `Data.List.Properties.∷-injectiveˡ` | the goal x ≡ y carries no signal; the decoy is the needle's own sibling. |
| 10 | `haystack-list-map-append-diag` | compositional | `Data.List.Properties` | `Data.List.Properties.map-++` | the diagonal instance of map-++, arity 3 over a two-name context. |
| 11 | `haystack-bool-and-assoc-diag` | routine | `Data.Bool.Properties` | `Data.Bool.Properties.∧-assoc` | an instance of the alias-typed ∧-assoc (Associative) with its outer variables identified. |
| 12 | `haystack-bool-and-distrib-diag` | compositional | `Data.Bool.Properties` | `Data.Bool.Properties.∧-distribˡ-∨` | an instance of the alias-typed ∧-distribˡ-∨ (DistributesOverˡ) with two variables identified. |

[#129]: https://github.com/formalverification/agda-native-air/issues/129
[#219]: https://github.com/formalverification/agda-native-air/issues/219

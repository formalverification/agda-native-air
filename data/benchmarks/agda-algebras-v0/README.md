# The agda-algebras tier (v0)

File: `data/benchmarks/agda-algebras-v0/README.md`

The 21 obligations mined from agda-algebras (issue [#127]); what the tier
is, how its rows were chosen, its two import strata, and its index
conventions are in `../README.md`, "agda-algebras tier: selection criteria
and provenance".  This file keeps what each fixture's header used to say.

A subject's work file is a byte-for-byte copy of its obligation, comments
included, and until issue [#219] the header carried a `Source:` line naming
the library module that holds the original proof and a `Strategy:` line
naming the proof's shape.  Both were removed from the obligations on
2026-09-29 (the golds carry their own header; one of them,
`Overture-lift-lower`, had the two lines as well and lost them) and are
recorded here, per row, as they were.  The index's `module` field names the
same module on every row.

| #  | id | difficulty | source | strategy |
|----|----|------------|--------|----------|
| 1  | `algebras-overture-lift-lower` | routine | Overture.Basic (agda-algebras) | refl (lift and lower cancel definitionally) |
| 2  | `algebras-overture-lower-lift` | routine | Overture.Basic (agda-algebras) | refl |
| 3  | `algebras-overture-proj-op` | routine | Overture.Operations (agda-algebras) | lambda |
| 4  | `algebras-functions-lift-lower` | routine | Setoid.Functions.Basic (agda-algebras) | refl |
| 5  | `algebras-inverses-image-f-f` | routine | Setoid.Functions.Inverses (agda-algebras) | constructor |
| 6  | `algebras-inverses-inv-inverse-l` | routine | Setoid.Functions.Inverses (agda-algebras) | refl |
| 7  | `algebras-surjective-surjinv-inverse-r` | compositional | Setoid.Functions.Surjective (agda-algebras) | application |
| 8  | `algebras-injective-comp-injective` | compositional | Setoid.Functions.Injective (agda-algebras) | composition |
| 9  | `algebras-homs-id-hom` | compositional | Setoid.Homomorphisms.Basic (agda-algebras) | pairing |
| 10 | `algebras-homs-comp-hom` | compositional | Setoid.Homomorphisms.Properties (agda-algebras) | pairing |
| 11 | `algebras-homs-mon-to-hom` | compositional | Setoid.Homomorphisms.Basic (agda-algebras) | application |
| 12 | `algebras-inverses-range-to-image` | compositional | Setoid.Functions.Inverses (agda-algebras) | constructor |
| 13 | `algebras-subalgebras-sup-refl` | compositional | Setoid.Subalgebras.Properties (agda-algebras) | composition |
| 14 | `algebras-subalgebras-sup-trans` | compositional | Setoid.Subalgebras.Properties (agda-algebras) | application |
| 15 | `algebras-homs-mon-to-intohom` | compositional | Setoid.Homomorphisms.Basic (agda-algebras) | pairing |
| 16 | `algebras-kernels-quotient-proj-hom` | compositional | Setoid.Homomorphisms.Kernels (agda-algebras) | application |
| 17 | `algebras-subalgebras-sub-reflexive` | non-obvious | Setoid.Subalgebras.Properties (agda-algebras) | pairing |
| 18 | `algebras-subalgebras-sub-trans` | non-obvious | Setoid.Subalgebras.Properties (agda-algebras) | pairing |
| 19 | `algebras-subalgebras-sub-trans-iso` | non-obvious | Setoid.Subalgebras.Properties (agda-algebras) | pairing |
| 20 | `algebras-kernels-ker-con` | non-obvious | Setoid.Homomorphisms.Kernels (agda-algebras) | record-assembly |
| 21 | `algebras-kernels-ker-in-con` | non-obvious | Setoid.Homomorphisms.Kernels (agda-algebras) | identity-function |

[#127]: https://github.com/formalverification/agda-native-air/issues/127
[#219]: https://github.com/formalverification/agda-native-air/issues/219

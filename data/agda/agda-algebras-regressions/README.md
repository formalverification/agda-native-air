# agda-algebras regressions

This folder contains regression fixtures inspired by the `agda-algebras` corpus.

## NoetherLike.agda
A minimal, hermetic reproduction of "anonymous module section" names:
Agda qnames often contain anonymous section markers like `Module._` or `qname._.name`,
but our extractor should normalize these so that `prettyModule` and `prettyQname` have
no `._` / `._.` *segments* (though `._` may still appear inside longer identifiers).
## Noether.jsonl
A golden snapshot produced by running the extractor on:

  src/Base/Homomorphisms/Noether.agda

We keep this JSONL to regression-test schema + normalization behavior without
vendoring the full dependency closure of that module.

## License

`NoetherLike.agda` is written for this repository and is covered by its code
license, [Apache-2.0](../../../LICENSE).

`Noether.jsonl` is a golden snapshot extracted from `ualib/agda-algebras`
(`src/Base/Homomorphisms/Noether.agda`), so it is a derivative work of that
library and is redistributed under **its** license, Apache-2.0, with attribution
to that project.  See the "Licensing" section of the top-level `README.md`.

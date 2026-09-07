<!-- File: docs/corpora/README.md -->

# Corpus dataset cards

This directory holds one dataset card per corpus cut.  The card is the committed description of a published corpus (provenance, coverage, statistics, known gaps, and the reproduction recipe) while the corpus artifacts themselves (`corpus.jsonl.gz` and its companions) are **release assets**, never repository files: everything under `data/` is gitignored, and a GitHub release is what makes a cut durable, citable, and downloadable.

## Publishing a corpus release

A GitHub release binds three things:

+ a git tag (pointing at one commit),
+ a notes page, and
+ attached asset files that GitHub stores outside git history.

One `gh release create` produces all three.

The worked example is the [`agda-algebras-corpus-v0` release](https://github.com/formalverification/agda-native-air/releases/tag/agda-algebras-corpus-v0); the procedure below reproduces it for any cut.

+  **Publish after the corpus PR merges**.

   The release is created with `--target main`, so the tag lands on main's HEAD at that moment; publishing first would tag a main that lacks the card, and the notes' links into the repository would dangle.

+  **Stage two files beside the artifacts** (in the gitignored output directory `data/corpora/<library>/<version>/`): `RELEASE_NOTES.md`, the page text, mirroring the v0 release's sections (intro with a link to the card on main, asset table, provenance with digests, coverage, contents, usage, reproduction recipe, license); and `DATASET_CARD.md`, a verbatim copy of the card from `docs/corpora/`, which ships under that stable asset name.

+  **Create the release as a draft**, from the output directory, with the tag `<library>-corpus-<version>`:

   ```sh
   cd data/corpora/<library>/<version>

   gh release create <library>-corpus-<version> \
     --target main \
     --title "<library> corpus <version>" \
     --notes-file RELEASE_NOTES.md \
     --draft \
     corpus.jsonl.gz coverage.json provenance.json stats.json stats.md DATASET_CARD.md
   ```

+  **Six assets** (and only six): the gzip'd corpus, the three JSON companions, `stats.md`, and the card copy.

   The uncompressed `corpus.jsonl` is not uploaded (consumers `gunzip -k`), and `RELEASE_NOTES.md` is not an asset; `--notes-file` consumes it as the page text.

+  **Inspect, then publish**.  `--draft` keeps the tag, page, and uploads visible only to you; open the printed URL, check the digests and links, then publish with `gh release edit <tag> --draft=false` (or the page's Publish button).  Publishing is effectively one-way: assets are downloadable the moment the release is live, which is why the draft step exists.

+  **Repairs**.

   +  A wrong asset is replaced with `gh release upload <tag> <file> --clobber`;
   +  a wrong draft is removed cleanly with `gh release delete <tag> --cleanup-tag`.

   Prefer fixing drafts to editing published releases.

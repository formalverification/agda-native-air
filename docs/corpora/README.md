<!-- File: docs/corpora/README.md -->

# Corpus dataset cards

This directory holds one dataset card per corpus cut.  The card is the committed description of a published corpus (provenance, coverage, statistics, known gaps, and the reproduction recipe) while the corpus artifacts themselves (`corpus.jsonl.gz` and its companions) are **release assets**, never repository files: corpus outputs under `data/corpora/` are gitignored, and a GitHub release is what makes a cut durable, citable, and downloadable.

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

+  **Keep the release out of the software's Zenodo record**.  Since v0.2.0 ([#279]) this repository's releases are archived on Zenodo, and Zenodo archives every published release, pre-releases included, as a new version of the software's record under its concept DOI, keeping only the source zipball and never the assets.  A corpus release published while the integration is on would therefore become the newest version of the software, and the concept DOI would resolve to it.  Before publishing, switch `formalverification/agda-native-air` off at <https://zenodo.org/account/settings/github/>, and switch it on again after.  Zenodo does not document whether the next software release after such a pause continues the same concept DOI (its code suggests it does), so check the next software release's record against the concept DOI.  A corpus that should have a DOI of its own is uploaded to Zenodo by hand, as a dataset.

+  **Inspect, then publish**.  `--draft` keeps the tag, page, and uploads visible only to you; open the printed URL, check the digests and links, then publish with `gh release edit <tag> --draft=false --latest=false` (or the page's Publish button, with "Set as the latest release" unchecked).  `--latest=false` keeps GitHub's "Latest" marker on the software release, which a newly published release otherwise takes.  Publishing is effectively one-way: assets are downloadable the moment the release is live, which is why the draft step exists.

+  **Repairs**.

   +  A wrong asset is replaced with `gh release upload <tag> <file> --clobber`;
   +  a wrong draft is removed cleanly with `gh release delete <tag> --cleanup-tag`.

   Prefer fixing drafts to editing published releases.

[#279]: https://github.com/formalverification/agda-native-air/issues/279

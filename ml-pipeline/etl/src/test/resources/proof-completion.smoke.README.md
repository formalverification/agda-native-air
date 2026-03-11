<!-- File: ml-pipeline/etl/src/test/resources/proof-completion.smoke.README.md -->

# How the proof-completion.smoke.jsonl fixture was generated

The file `ml-pipeline/etl/src/test/resources/proof-completion.smoke.jsonl` was
generated from the `combined.jsonl` dataset with the following command:

```sh
python3 scripts/python/utils/make_proof_completion_fixture.py \
  --in  data/agda-algebras/raw/jsonl/combined.jsonl \
  --out ml-pipeline/etl/src/test/resources/proof-completion.smoke.jsonl \
  --k 200 \
  --max-per-module 10 \
  --oversample-factor 20 \
  --minimal \
  --max-row-bytes 6144
```

The `combined.jsonl` file was generated from running the extractor and the etl
pipeline on the `agda-algebras` library using the following commands:

```sh
make extract-lib LIB_NAME=agda-algebras
make etl-agda-algebras
```

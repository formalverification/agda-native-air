"""
filter_jsonl.py
===============

File: ml-pipeline/python/model/filter_jsonl.py
Copyright: (c) 2025 Thmpr Lab, LLC.

Purpose
-------

This module provides a small command-line tool that:

1. Reads a JSON Lines (JSONL) file containing *AgdaData-style* records.
2. Applies a few simple *schema-aware* filters:
   - Removes rows with very short or missing `agdaType` and `proof` fields.
   - Optionally enforces user-provided minimum lengths for `agdaType` and `proof`.
   - Deduplicates rows based on a stable key (e.g. `(file, name, agdaType, proof)`).
3. Writes the filtered result back as JSONL.

The goal is to create a saner, more ML-friendly dataset from a noisy or
heterogeneous extraction.


Expected Input Schema
---------------------

The input JSONL file is assumed to have the following the structure
(produced by the Scala `AgdaExtractor`):

    {
      "file":      "<relative-or-absolute-path>",
      "module":    "<Agda module name (optional)>",
      "name":      "<theorem or definition name>",
      "agdaType":  "<type as Agda concrete syntax>",
      "proof":     "<right-hand side / proof term>",
      "premises":  ["List", "of", "depended-on", "names"]  (optional)
    }

Not all fields are guaranteed to be present, but `agdaType` and `proof`
are the main focus of this filter.


Command-line Usage
------------------

Typical usage from the repository root:

    python -m ml_pipeline.python.model.filter_jsonl \\
        --input data/train-stdlib-2.2.jsonl \\
        --out   data/train-stdlib-2.2.filtered.jsonl \\
        --min-type-len 5 \\
        --min-proof-len 5

Or via the Makefile (recommended):

    make filter TRAIN_DATA=data/train-stdlib-2.2.jsonl

which internally invokes this script with the appropriate arguments.


Design Notes
------------

- We prefer **vectorized / column-wise operations** in Pandas whenever
  possible (functional style on columns instead of row-by-row loops).
- We *do* use a small amount of mutation (e.g. `df["col"] = ...`).
  This is explicitly documented where it occurs; it is a pragmatic
  compromise because the Pandas API is built around in-place
  transformations, but the operations themselves are still “pure”
  transformations of entire columns.
"""

from __future__ import annotations

from pathlib import Path
from typing import List

import argparse
import pandas as pd


def parse_args() -> argparse.Namespace:
    """
    Parse command-line arguments for this script.

    Returns
    -------
    argparse.Namespace
        A namespace with the following attributes:

        - input: Path to the input JSONL file (AgdaData records).
        - out: Path for the filtered JSONL output.
        - min_type_len: Minimum length for the `agdaType` field.
        - min_proof_len: Minimum length for the `proof` field.
    """
    parser: argparse.ArgumentParser = argparse.ArgumentParser(
        description=(
            "Filter an AgdaData JSONL dataset by basic quality criteria "
            "(non-empty type/proof, minimum lengths, deduplication)."
        )
    )

    parser.add_argument(
        "--input",
        type=Path,
        required=True,
        help="Input JSONL file containing AgdaData-style records.",
    )
    parser.add_argument(
        "--out",
        type=Path,
        required=True,
        help="Output JSONL file for the filtered dataset.",
    )
    parser.add_argument(
        "--min-type-len",
        type=int,
        default=5,
        help="Minimum length of `agdaType` to keep (default: 5).",
    )
    parser.add_argument(
        "--min-proof-len",
        type=int,
        default=5,
        help="Minimum length of `proof` to keep (default: 5).",
    )

    return parser.parse_args()


def _normalize_text_columns(df: pd.DataFrame, columns: List[str]) -> pd.DataFrame:
    """
    Ensure that the given columns exist and contain strings (no NaNs).

    This function prefers a *functional style*: it returns a new
    DataFrame (copy) rather than mutating the original, even though
    under the hood Pandas may optimize column assignment in-place.

    Parameters
    ----------
    df : pd.DataFrame
        The original DataFrame.
    columns : List[str]
        Column names that should be treated as text.

    Returns
    -------
    pd.DataFrame
        A new DataFrame where each column in `columns` exists and
        contains only strings (empty string for missing values).
    """
    result: pd.DataFrame = df.copy()

    for col in columns:
        # Imperative-style assignment here is essentially a column-level
        # transformation. We choose this over a more elaborate functional
        # composition because:
        #
        # 1. Pandas' idioms are naturally expressed as "assign this column
        #    to the result of this expression".
        # 2. The transformation is still pure at the level of `col`:
        #    it depends only on the previous `col` values.
        if col not in result.columns:
            result[col] = ""

        result[col] = (
            result[col]
            .fillna("")   # replace NaN with empty string
            .astype(str)  # ensure string type
        )

    return result


def _deduplicate(df: pd.DataFrame) -> pd.DataFrame:
    """
    Deduplicate rows based on a stable key.

    We consider the combination `(file, name, agdaType, proof)` as a
    canonical key, if these columns exist. If some of them are missing,
    we only use the subset that is present.

    Parameters
    ----------
    df : pd.DataFrame
        Input DataFrame, assumed to already be filtered by length.

    Returns
    -------
    pd.DataFrame
        Deduplicated DataFrame.
    """
    candidate_key: List[str] = ["file", "name", "agdaType", "proof"]
    key_cols: List[str] = [c for c in candidate_key if c in df.columns]

    if not key_cols:
        # If there are no key columns, we simply return the DataFrame as-is.
        # We intentionally avoid creating artificial row IDs here because
        # deduplication would then trivially remove nothing.
        return df

    # `drop_duplicates` is a vectorized / declarative operation.
    # It avoids explicit Python loops over rows and is thus more in line
    # with a functional style than writing our own row iterator.
    return df.drop_duplicates(subset=key_cols)


def filter_dataset(
    input_path: Path,
    output_path: Path,
    min_type_len: int,
    min_proof_len: int,
) -> None:
    """
    Perform the core filtering pipeline on an AgdaData JSONL dataset.

    Steps
    -----
    1. Read JSONL into a pandas DataFrame.
    2. Normalize `agdaType` and `proof` into well-typed string columns.
    3. Filter rows by minimum length constraints.
    4. Deduplicate by `(file, name, agdaType, proof)`.
    5. Write the result as JSONL.

    Parameters
    ----------
    input_path : Path
        Path to the input JSONL file.
    output_path : Path
        Path to the output JSONL file.
    min_type_len : int
        Minimum length of `agdaType` to keep.
    min_proof_len : int
        Minimum length of `proof` to keep.
    """
    # Pandas directly supports reading JSON Lines into a DataFrame.
    df: pd.DataFrame = pd.read_json(input_path, lines=True)

    original_count: int = len(df)

    # Step 2: normalize the core textual columns
    df_norm: pd.DataFrame = _normalize_text_columns(df, ["agdaType", "proof"])

    # Step 3: apply length-based filters in a column-wise / declarative way
    type_len = df_norm["agdaType"].str.len()
    proof_len = df_norm["proof"].str.len()

    mask = (type_len >= min_type_len) & (proof_len >= min_proof_len)

    # This boolean mask application is also a vectorized, functional-style
    # operation: we produce a new filtered DataFrame instead of iterating
    # row-by-row.
    df_filtered: pd.DataFrame = df_norm[mask].copy()

    # Step 4: deduplicate
    df_dedup: pd.DataFrame = _deduplicate(df_filtered)

    # Step 5: write to JSONL
    output_path.parent.mkdir(parents=True, exist_ok=True)
    df_dedup.to_json(
        output_path,
        orient="records",
        lines=True,
        force_ascii=False,
    )

    final_count: int = len(df_dedup)
    print(
        f"✅ filter_jsonl: {original_count} → {final_count} rows "
        f"(min_type_len={min_type_len}, min_proof_len={min_proof_len}) -> {output_path}"
    )


def main() -> None:
    """
    Entry point for command-line execution.

    Delegates to `filter_dataset` with arguments obtained from `parse_args()`.
    """
    args: argparse.Namespace = parse_args()
    filter_dataset(
        input_path=args.input,
        output_path=args.out,
        min_type_len=args.min_type_len,
        min_proof_len=args.min_proof_len,
    )


if __name__ == "__main__":
    main()

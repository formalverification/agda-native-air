"""
filter_jsonl.py

File: ml-pipeline/python/model/filter_jsonl.py

Description:
  This module provides a small command-line tool that:

  1.  Reads a JSON Lines (JSONL) file containing records from either:
      - the canonical Haskell backend (`agda-json --format full`), or
      - the legacy Scala extractor (AgdaData-style).
  2.  Applies a few simple *schema-aware* filters:
      - Removes rows with very short or missing type/body fields.
      - Optionally enforces user-provided minimum lengths.
      - Deduplicates rows based on a stable join key when available (prefer `prettyQname`).
  3.  Writes the filtered result back as JSONL.

  The goal is to create a saner, more ML-friendly dataset from a noisy or
  heterogeneous extraction.

Expected Input Schema:
  We accept either
  +  Canonical backend schema (preferred):
     {
       "file":      "<relative-or-absolute-path>",
       "prettyQname":"<stable join key>",
       "type":      "<pretty-printed type>",
       "typeAstVersion": "0.3-v0",
       "typeAst":   { ... },
       "body":      "<pretty-printed clauses>" | null
     }

  +  Legacy Scala extractor schema:
     uses `agdaType` + `proof` instead of `type` + `body`.

Command-line Usage:
  Typical usage from the repository root:

    python -m ml_pipeline.python.model.filter_jsonl \\
        --input data/train-stdlib-2.2.jsonl \\
        --out   data/train-stdlib-2.2.filtered.jsonl \\
        --min-type-len 5 \\
        --min-proof-len 5

  Or via the Makefile (recommended):

    make filter TRAIN_DATA=data/train-stdlib-2.2.jsonl

  which internally invokes this script with the appropriate arguments.

Design Notes:
  -  We prefer **vectorized / column-wise operations** in Pandas whenever
     possible (functional style on columns instead of row-by-row loops).
  -  We *do* use a small amount of mutation (e.g. `df["col"] = ...`).
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
        help="Minimum length of the type field to keep (default: 5).",
    )
    parser.add_argument(
        "--min-proof-len",
        type=int,
        default=5,
        help="Minimum length of the body/proof field to keep (default: 5).",
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


def _deduplicate(df: pd.DataFrame, type_col: str, body_col: str) -> pd.DataFrame:
    """
    Deduplicate rows based on a stable key.

    When `prettyQname` is present, we prefer the combination
    `(prettyQname, type_col, body_col, typeAstVersion)` as the canonical key.
    Otherwise, we fall back to `(file, name, type_col, body_col)`.
    If some of these columns are missing, we only use the subset that is present.

    Parameters
    ----------
    df : pd.DataFrame
        Input DataFrame, assumed to already be filtered by length.
    type_col : str
        Name of the column containing the type/signature text (e.g., "typeText" or "agdaType").
    body_col : str
        Name of the column containing the body/proof text (e.g., "bodyText" or "proof").

    Returns
    -------
    pd.DataFrame
        Deduplicated DataFrame.
    """
    # Prefer stable join key when present; otherwise fall back to legacy-ish tuple.
    if "prettyQname" in df.columns:
        candidate_key: List[str] = ["prettyQname", type_col, body_col, "typeAstVersion"]
    else:
        candidate_key = ["file", "name", type_col, body_col]
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
    2. Normalize type/body columns into well-typed string columns.
    3. Filter rows by minimum length constraints.
    4. Deduplicate (prefer `prettyQname` when present).
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
    # --- Step 1. Read JSONL into a pandas DataFrame. ---
    # Pandas directly supports reading JSON Lines into a DataFrame.
    df: pd.DataFrame = pd.read_json(input_path, lines=True)

    original_count: int = len(df)

    # --- Step 2: Normalize *all* possible source columns we may reference. ---
    cols_to_norm = [c for c in ["type", "agdaType", "body", "proof"] if c in df.columns]
    df_norm: pd.DataFrame = _normalize_text_columns(df, cols_to_norm)

    def _first_nonempty(a: pd.Series, b: pd.Series) -> pd.Series:
        # Prefer a when it is a non-empty string; otherwise fallback to b.
        aa = a.fillna("").astype(str).str.strip()
        bb = b.fillna("").astype(str).str.strip()
        return aa.where(aa.str.len() > 0, bb)

    # Compute canonical text columns used for filtering/dedup.
    if "type" in df_norm.columns and "agdaType" in df_norm.columns:
        df_norm["typeText"] = _first_nonempty(df_norm["type"], df_norm["agdaType"])
    elif "type" in df_norm.columns:
        df_norm["typeText"] = df_norm["type"].fillna("").astype(str).str.strip()
    elif "agdaType" in df_norm.columns:
        df_norm["typeText"] = df_norm["agdaType"].fillna("").astype(str).str.strip()
    else:
        df_norm["typeText"] = ""

    if "body" in df_norm.columns and "proof" in df_norm.columns:
        df_norm["bodyText"] = _first_nonempty(df_norm["body"], df_norm["proof"])
    elif "body" in df_norm.columns:
        df_norm["bodyText"] = df_norm["body"].fillna("").astype(str).str.strip()
    elif "proof" in df_norm.columns:
        df_norm["bodyText"] = df_norm["proof"].fillna("").astype(str).str.strip()
    else:
        df_norm["bodyText"] = ""

    # --- Step 3: apply length-based filters in a column-wise / declarative way ---
    type_len = df_norm["typeText"].str.len()
    body_len = df_norm["bodyText"].str.len()

    # We require a non-trivial type. Body/proof can be empty for some defs,
    # but for "training rows" we usually want non-empty bodies.
    mask = (type_len >= min_type_len) & (body_len >= min_proof_len)

    # This boolean mask application is also a vectorized, functional-style
    # operation: we produce a new filtered DataFrame instead of iterating
    # row-by-row.
    df_filtered: pd.DataFrame = df_norm[mask].copy()

    # --- Step 4: deduplicate ---
    # Use canonical columns for dedup fallback so it works regardless of schema.
    # (We still let `_deduplicate` prefer prettyQname when present.)
    df_dedup: pd.DataFrame = _deduplicate(
        df_filtered,
        type_col="typeText",
        body_col="bodyText",
    )


    # --- Step 5: write to JSONL ---
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

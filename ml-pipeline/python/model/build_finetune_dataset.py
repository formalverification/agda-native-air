"""
build_finetune_dataset.py
=========================

File: ml-pipeline/python/model/build_finetune_dataset.py
Copyright: (c) 2025 Thmpr Lab, LLC.

Purpose
-------

This module converts a filtered AgdaData JSONL dataset into a
*fine-tuning-ready* JSONL file suitable for instruction-tuning or
supervised learning.

Each output record is a JSON object with the following fields:

    {
      "instruction": "<natural-language instruction>",
      "input":       "<context, including module/name/type>",
      "output":      "<proof term or RHS>"
    }

The aim is to move from a *schema tuned to extraction* (Agda-specific
fields like `file`, `module`, `name`, `agdaType`, `proof`) to a
*schema tuned to language models*, which expect textual (instruction,
input, output) triples.

Expected Input Schema
---------------------

We assume the input JSONL file has the same structure as produced by the
Scala `AgdaExtractor` and optionally filtered by `filter_jsonl.py`, i.e.:

    {
      "file":      "...",   # optional
      "module":    "...",   # optional Agda module name
      "name":      "...",   # theorem or definition name
      "agdaType":  "...",   # type as a string
      "proof":     "...",   # proof term / RHS as a string
      ...
    }

Missing fields are handled gracefully; we only require `proof` to be
present (or at least convertable to string).

Command-Line Usage
------------------

From the repository root:

    python -m ml_pipeline.python.model.build_finetune_dataset \\
        --input data/train-stdlib-2.2.filtered.jsonl \\
        --out   data/train-stdlib-2.2.finetune.jsonl

Or via Make (recommended):

    make finetune-dataset

which will call this script with the appropriate paths.

Design Notes
------------

- The `instruction` string is intentionally simple and generic:
  "Complete the Agda proof for the following type."
  You can later parameterize this by module or library.
- The `input` field combines optional `module` and `name` information
  with the `agdaType`, separated by blank lines. This gives the model
  more context without forcing a particular Agda syntax representation.
- We use a **list comprehension** to produce the sequence of output
  records; this is close to a functional `map`, and avoids imperative
  row-by-row mutation.

If you later want multiple *task flavors* (e.g. “predict premises”
vs “complete proof”), this script is a good place to add them, perhaps
with a `--task` CLI flag.
"""

from __future__ import annotations

from pathlib import Path
from typing import Dict, Iterable, List

import argparse
import json
import pandas as pd


def parse_args() -> argparse.Namespace:
    """
    Parse command-line arguments for this script.

    Returns
    -------
    argparse.Namespace
        A namespace with two attributes:

        - input: Path to the filtered AgdaData JSONL file.
        - out: Path for the instruction-tuning JSONL output.
    """
    parser: argparse.ArgumentParser = argparse.ArgumentParser(
        description=(
            "Convert a filtered AgdaData JSONL dataset into "
            "instruction/input/output fine-tuning format."
        )
    )

    parser.add_argument(
        "--input",
        type=Path,
        required=True,
        help="Input JSONL file (AgdaData-style records, typically filtered).",
    )
    parser.add_argument(
        "--out",
        type=Path,
        required=True,
        help="Output JSONL file (instruction/input/output triples).",
    )

    return parser.parse_args()


def _make_instruction() -> str:
    """
    Construct the generic natural-language instruction.

    We keep this as a tiny, separate function so that future task
    variants (e.g. 'suggest premises' vs 'complete proof') can be
    expressed as alternative instruction builders.

    Returns
    -------
    str
        A natural-language instruction for the model.
    """
    return "Complete the Agda proof for the following type."


def _build_input_text(module: str, name: str, agda_type: str) -> str:
    """
    Build the `input` text field from module, name, and type.

    The intent is to provide enough contextual scaffolding for a language
    model, without overcommitting to a particular prompt layout.

    Current layout:

        module <Module.Name>
        lemma <lemma-name>

        <agdaType>

    Parameters
    ----------
    module : str
        Agda module name (possibly empty).
    name : str
        Theorem or definition name (possibly empty).
    agda_type : str
        The type as a string.

    Returns
    -------
    str
        A multi-line input string for the fine-tuning example.
    """
    header_lines: List[str] = []

    if module:
        header_lines.append(f"module {module}")
    if name:
        header_lines.append(f"lemma {name}")

    if header_lines:
        # If we have module or name, put them above a blank line
        # followed by the type.
        return "\n".join(header_lines) + "\n\n" + agda_type

    # If we have no contextual info, just return the type itself.
    return agda_type


def _row_to_example(row: pd.Series) -> Dict[str, str]:
    """
    Convert a single AgdaData row into an instruction-tuning example.

    This function is written in an almost purely functional style: it
    takes an immutable `row` and returns a new dictionary without
    mutating the input. The only “state” involved is the construction
    of local variables.

    Parameters
    ----------
    row : pd.Series
        One record of the filtered AgdaData DataFrame.

    Returns
    -------
    Dict[str, str]
        A dictionary with keys: "instruction", "input", "output".
    """
    module: str = str(row.get("module", "") or "")
    name: str = str(row.get("name", "") or "")
    agda_type: str = str(row.get("agdaType", "") or "")
    proof: str = str(row.get("proof", "") or "")

    instruction: str = _make_instruction()
    input_text: str = _build_input_text(module=module, name=name, agda_type=agda_type)

    return {
        "instruction": instruction,
        "input": input_text,
        "output": proof,
    }


def dataframe_to_examples(df: pd.DataFrame) -> Iterable[Dict[str, str]]:
    """
    Convert an entire DataFrame of AgdaData into a sequence of examples.

    Implementation notes
    --------------------
    - We use a **list comprehension** over `DataFrame.iterrows()` rather
      than a manual `for` loop with `append`. This is closer to a
      functional `map` and avoids explicit mutation of a list.
    - We could also use `df.apply(_row_to_example, axis=1)`, but that
      returns a Series that then needs conversion to Python dicts. The
      comprehension version is more explicit and slightly easier to
      debug while remaining high-level.

    Parameters
    ----------
    df : pd.DataFrame
        DataFrame of filtered AgdaData rows.

    Returns
    -------
    Iterable[Dict[str, str]]
        An iterable of dicts ready to be written as JSONL.
    """
    return (_row_to_example(row) for _, row in df.iterrows())


def build_finetune_dataset(input_path: Path, output_path: Path) -> None:
    """
    Convert a filtered AgdaData JSONL file into instruction-tuning JSONL.

    Parameters
    ----------
    input_path : Path
        Path to the filtered AgdaData JSONL file.
    output_path : Path
        Path to the fine-tuning JSONL output.

    Notes
    -----
    - This function does not perform any additional filtering; it assumes
      that `input_path` already contains reasonably clean data
      (e.g. output from `filter_jsonl.py`).
    - Each output line is a single JSON object with keys:
      "instruction", "input", "output".
    """
    df: pd.DataFrame = pd.read_json(input_path, lines=True)
    examples: Iterable[Dict[str, str]] = dataframe_to_examples(df)

    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Here we *do* use a simple for-loop to stream-write JSON lines.
    # Justification:
    #   - Writing line-by-line is I/O-bound; vectorizing it brings no
    #     real benefit and can actually increase memory usage.
    #   - The loop is side-effecting only in terms of file I/O, which is
    #     unavoidable. The data transformation itself is still handled
    #     functionally by `_row_to_example`.
    count: int = 0
    with output_path.open("w", encoding="utf-8") as f:
        for ex in examples:
            f.write(json.dumps(ex, ensure_ascii=False) + "\n")
            count += 1

    print(f"✅ build_finetune_dataset: wrote {count} examples to {output_path}")


def main() -> None:
    """
    Entry point for command-line execution.

    Delegates to `build_finetune_dataset` with arguments obtained from
    `parse_args()`.
    """
    args: argparse.Namespace = parse_args()
    build_finetune_dataset(input_path=args.input, output_path=args.out)


if __name__ == "__main__":
    main()

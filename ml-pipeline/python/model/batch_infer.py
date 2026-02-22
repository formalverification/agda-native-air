"""
batch_infer.py

File: ml-pipeline/python/model/batch_infer.py

Description:
  Performs batch inference using a pre-trained TorchScript model.

  This is a simple script to load a trained TorchScript model and run batch inference
  on a Parquet file of features, saving the predictions back to a new CSV file.

  It reads input features from a Parquet file, makes predictions, and writes the
  results to a CSV file.

  It assumes the input Parquet file is at "features/test.parquet" and contains
  columns 'feature1' and 'feature2'. The output CSV file will be saved as
  "features/test_with_preds.csv" with an additional 'prediction' column.

  This version adds a tiny CLI to avoid hard-coded paths/columns.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import torch
import pandas as pd
import pyarrow.parquet as pq

def default_paths() -> tuple[Path, Path, Path]:
    ml_root = Path(__file__).resolve().parents[2]  # .../ml-pipeline
    model = ml_root / "models" / "model_scripted.pt"
    inp = ml_root / "features" / "test.parquet"
    out = ml_root / "features" / "test_with_preds.csv"
    return model, inp, out


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    d_model, d_inp, d_out = default_paths()
    p = argparse.ArgumentParser(description="Batch inference with TorchScript model.")
    p.add_argument("--model", type=Path, default=d_model, help="TorchScript model path (.pt).")
    p.add_argument("--input", type=Path, default=d_inp, help="Input Parquet file.")
    p.add_argument("--out", type=Path, default=d_out, help="Output CSV path.")
    p.add_argument(
        "--columns",
        default="feature1,feature2",
        help="Comma-separated list of numeric feature columns (default: feature1,feature2).",
    )
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    args.out.parent.mkdir(parents=True, exist_ok=True)

    cols = [c.strip() for c in str(args.columns).split(",") if c.strip()]
    if not cols:
        raise SystemExit("ERROR: --columns must name at least one column")

    model = torch.jit.load(str(args.model), map_location="cpu")
    model.eval()

    df = pq.read_table(str(args.input)).to_pandas()
    missing = [c for c in cols if c not in df.columns]
    if missing:
        raise SystemExit(f"ERROR: input is missing columns: {missing} (have: {list(df.columns)})")

    X = torch.tensor(df[cols].values, dtype=torch.float32)

    with torch.no_grad():
        logits = model(X)
        pred = torch.argmax(logits, dim=1).cpu().numpy()
    df["prediction"] = pred
    df.to_csv(str(args.out), index=False)
    print(f"✅ wrote predictions: {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

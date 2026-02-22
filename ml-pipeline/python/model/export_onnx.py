"""
export_onnx.py

File: ml-pipeline/python/model/export_onnx.py

Description:
  Export a trained PyTorch checkpoint as ONNX.

  A simple script to load a trained PyTorch model and export it as an ONNX file
  for efficient deployment/interoperability with other frameworks.

  This script loads the model checkpoint, creates a dummy input, and exports the
  model to ONNX format.

  The default checkpoint path is "models/model.pt" and the default output path is
  "models/model.onnx", both relative to the ml-pipeline root directory.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import torch

def _import_simplemlp():
    try:
        from .train import SimpleMLP  # type: ignore
        return SimpleMLP
    except Exception:
        here = Path(__file__).resolve().parent
        if str(here) not in sys.path:
            sys.path.insert(0, str(here))
        from train import SimpleMLP  # type: ignore
        return SimpleMLP


def default_paths() -> tuple[Path, Path]:
    ml_root = Path(__file__).resolve().parents[2]  # .../ml-pipeline
    ckpt = ml_root / "models" / "model.pt"
    out = ml_root / "models" / "model.onnx"
    return ckpt, out


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    d_ckpt, d_out = default_paths()
    p = argparse.ArgumentParser(description="Export checkpoint as ONNX.")
    p.add_argument("--checkpoint", type=Path, default=d_ckpt, help="Path to model.pt checkpoint.")
    p.add_argument("--out", type=Path, default=d_out, help="Path to write model.onnx.")
    p.add_argument("--opset", type=int, default=11, help="ONNX opset version.")
    p.add_argument("--input-dim", type=int, default=2, help="Input feature dimension.")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    args.out.parent.mkdir(parents=True, exist_ok=True)

    SimpleMLP = _import_simplemlp()
    model = SimpleMLP()
    state = torch.load(args.checkpoint, map_location="cpu")
    model.load_state_dict(state)
    model.eval()

    dummy = torch.randn(1, int(args.input_dim))
    torch.onnx.export(
        model,
        (dummy,),
        str(args.out),
        input_names=["input"],
        output_names=["output"],
        dynamic_axes={"input": {0: "batch_size"}, "output": {0: "batch_size"}},
        opset_version=int(args.opset),
    )
    print(f"✅ wrote ONNX: {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

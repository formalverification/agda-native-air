"""
export_script.py

File: ml-pipeline/python/model/export_script.py

Description:
  Export a trained PyTorch checkpoint as TorchScript.

  A simple script to load a trained PyTorch model and export it as a TorchScript file
  for efficient deployment. This script loads the model checkpoint, scripts it using
  torch.jit.script, and saves the scripted model to disk.

  The default checkpoint path is "models/model.pt" and the default output path is
  "models/model_scripted.pt", both relative to the ml-pipeline root directory.

Why this exists:
  - Avoid hard-coded CWD-dependent paths.
  - Avoid brittle imports when invoked from different working directories.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import torch


def _import_simplemlp():
    """
    Robust import that works in both cases:
      (A) run as a module (package context):  from .train import SimpleMLP
      (B) run as a plain script:             add this dir to sys.path; import train
    """
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
    """Compute default --checkpoint and --out paths relative to this file."""
    ml_root = Path(__file__).resolve().parents[2]  # .../ml-pipeline
    ckpt = ml_root / "models" / "model.pt"
    out = ml_root / "models" / "model_scripted.pt"
    return ckpt, out


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    d_ckpt, d_out = default_paths()
    p = argparse.ArgumentParser(description="Export checkpoint as TorchScript.")
    p.add_argument("--checkpoint", type=Path, default=d_ckpt, help="Path to model.pt checkpoint.")
    p.add_argument("--out", type=Path, default=d_out, help="Path to write model_scripted.pt.")
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    args.out.parent.mkdir(parents=True, exist_ok=True)

    SimpleMLP = _import_simplemlp()
    model = SimpleMLP()
    state = torch.load(args.checkpoint, map_location="cpu")
    model.load_state_dict(state)
    model.eval()

    scripted = torch.jit.script(model)
    scripted.save(str(args.out))
    print(f"✅ wrote TorchScript: {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

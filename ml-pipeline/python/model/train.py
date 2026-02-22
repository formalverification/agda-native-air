"""
train.py

File: ml-pipeline/python/model/train.py

Description:
  A simple PyTorch training script that reads data from a Parquet file,
  trains a basic MLP model, and saves the trained model.

  Assumes the Parquet file has columns 'feature1', 'feature2', and 'label'.
"""

from __future__ import annotations

from pathlib import Path
from typing import Tuple
import argparse
import os
import pandas as pd
import pyarrow.parquet as pq
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

# ---------- CLI ----------

def default_paths() -> Tuple[Path, Path]:
    """Compute default --input and --out paths relative to this file."""
    repo_root = Path(__file__).resolve().parents[2]  # .../ml-pipeline
    default_in = repo_root / "features" / "train.parquet"
    default_out = repo_root / "models" / "model.pt"
    return default_in, default_out


def parse_args() -> argparse.Namespace:
    din, dout = default_paths()
    p = argparse.ArgumentParser()
    p.add_argument("--input", type=Path, default=din,
                   help="Parquet features (default: ml-pipeline/features/train.parquet)")
    p.add_argument("--out", type=Path, default=dout,
                   help="Model checkpoint path (default: ml-pipeline/models/model.pt)")
    p.add_argument("--epochs", type=int, default=10)
    p.add_argument("--batch-size", type=int, default=32)
    p.add_argument("--lr", type=float, default=1e-2)
    return p.parse_args()


# ---------- Data ----------

def load_data_old(path: Path) -> Tuple[torch.Tensor, torch.Tensor]:
    """Load Parquet into (X, y) tensors."""
    table = pq.read_table(path)
    df = table.to_pandas()
    X = df[["feature1", "feature2"]].to_numpy()
    y = df["label"].to_numpy()
    X_t = torch.tensor(X, dtype=torch.float32)
    y_t = torch.tensor(y, dtype=torch.long)
    return X_t, y_t


def load_data(path) -> Tuple[torch.Tensor, torch.Tensor]:
    """
    Load JSONL dataset into (X, y) **tensors**.

    If 'feature1'/'feature2' are absent, synthesize them from the
    lengths of 'agdaType' and 'proof' strings so we always have
    a 2D numeric feature space.
    """
    # Pandas happily accepts a Path or string here
    df = pd.read_json(path, lines=True)

    # If our toy feature columns are missing, synthesize them
    if not {"feature1", "feature2"} <= set(df.columns):
        # Prefer canonical backend columns; fall back to legacy.
        type_col = "type" if "type" in df.columns else "agdaType"
        body_col = "body" if "body" in df.columns else "proof"

        def length_col(col: str):
            if col in df.columns:
                return (
                    df[col]
                    .fillna("")        # avoid NaNs
                    .astype(str)       # ensure strings
                    .str.len()         # length in characters
                )
            else:
                # Column missing altogether: just zeros
                return pd.Series([0] * len(df), index=df.index)

        df["feature1"] = length_col(type_col)
        df["feature2"] = length_col(body_col)

    X_np = df[["feature1", "feature2"]].to_numpy()
    y_np = df.get("label", pd.Series([0] * len(df), index=df.index)).to_numpy()

    X = torch.tensor(X_np, dtype=torch.float32)
    y = torch.tensor(y_np, dtype=torch.long)

    return X, y


def make_loader(X: torch.Tensor, y: torch.Tensor, batch_size: int) -> DataLoader:
    """Create a DataLoader without hidden side-effects."""
    ds = TensorDataset(X, y)
    return DataLoader(ds, batch_size=batch_size, shuffle=True)


# ---------- Model ----------

class SimpleMLP(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(2, 16),
            nn.ReLU(),
            nn.Linear(16, 2),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)


def build_model() -> nn.Module:
    return SimpleMLP()


# ---------- Training ----------

@torch.no_grad()
def evaluate(model: nn.Module, loader: DataLoader, device: torch.device) -> float:
    """Return accuracy on a loader."""
    model.eval()
    correct = 0
    total = 0
    for Xb, yb in loader:
        Xb = Xb.to(device)
        yb = yb.to(device)
        logits = model(Xb)
        pred = logits.argmax(dim=1)
        correct += (pred == yb).sum().item()
        total += yb.numel()
    return (correct / total) if total else 0.0


def train(
    model: nn.Module,
    loader: DataLoader,
    epochs: int,
    lr: float,
    device: torch.device,
) -> nn.Module:
    """Pure(ish): returns the trained model (no globals)."""
    model.to(device)
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    loss_fn = nn.CrossEntropyLoss()

    for ep in range(epochs):
        model.train()
        last_loss = 0.0
        for Xb, yb in loader:
            Xb = Xb.to(device)
            yb = yb.to(device)
            opt.zero_grad()
            logits = model(Xb)
            loss = loss_fn(logits, yb)
            loss.backward()
            opt.step()
            last_loss = float(loss.item())
        print(f"epoch {ep+1}/{epochs}  loss={last_loss:.4f}")

    return model


# ---------- Main ----------

def main() -> None:
    args = parse_args()
    args.out.parent.mkdir(parents=True, exist_ok=True)

    X, y = load_data(args.input)
    loader = make_loader(X, y, args.batch_size)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = build_model()
    model = train(model, loader, epochs=args.epochs, lr=args.lr, device=device)

    torch.save(model.state_dict(), args.out)
    print(f"✅ saved model to {args.out}")


if __name__ == "__main__":
    main()

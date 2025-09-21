"""
A simple PyTorch training script that reads data from a Parquet file,
trains a basic MLP model, and saves the trained model.

Assumes the Parquet file has columns 'feature1', 'feature2', and 'label'.

File: agda-ai-prover/ml-pipeline/python/model/train.py

Copyright (c) 2025 Thmpr.
"""

import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset
import pandas as pd
import pyarrow.parquet as pq
import argparse, os

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--train", default=os.path.join(os.path.dirname(__file__), "..", "features", "train.parquet"))
    return p.parse_args()

def load_data(path: Path) -> Tuple[torch.Tensor, torch.Tensor]:
    table = pq.read_table(path)
    df = table.to_pandas()
    X = df[['feature1', 'feature2']].values
    y = df['label'].values
    return torch.tensor(X, dtype=torch.float32), torch.tensor(y, dtype=torch.long)

class SimpleMLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(2, 16),
            nn.ReLU(),
            nn.Linear(16, 2)
        )
    def forward(self, x):
        return self.net(x)

def train(X_train: torch.Tensor, y_train: torch.Tensor) -> None:
    dataset = TensorDataset(X_train, y_train)
    loader = DataLoader(dataset, batch_size=32, shuffle=True)

    model = SimpleMLP()
    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=0.01)

    for epoch in range(10):
        for X_batch, y_batch in loader:
            preds = model(X_batch)
            loss = criterion(preds, y_batch)
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
        print(f"Epoch {epoch+1} Loss: {loss.item():.4f}")

    torch.save(model.state_dict(), "models/model.pt")

if __name__ == "__main__":
    args = parse_args()
    X_train, y_train = load_data(args.train)
    train()

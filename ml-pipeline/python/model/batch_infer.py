"""
batch_infer.py

File: agda-ai-prover/ml-pipeline/python/model/batch_infer.py

Purpose
-------
  Performs batch inference using a pre-trained TorchScript model.
  It reads input features from a Parquet file, makes predictions, and
  writes the results to a CSV file.
  Assumes the Parquet file has columns 'feature1' and 'feature2'.
"""

import torch
import pandas as pd
import pyarrow.parquet as pq

model = torch.jit.load("models/model_scripted.pt")
model.eval()

df = pq.read_table("features/test.parquet").to_pandas()
X = torch.tensor(df[['feature1', 'feature2']].values, dtype=torch.float32)

with torch.no_grad():
    preds = model(X)
    predicted_labels = torch.argmax(preds, dim=1).numpy()

df["prediction"] = predicted_labels
df.to_csv("features/test_with_preds.csv", index=False)

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

"""
main.py

File: agda-native-air/ml-pipeline/python/api/main.py

Description:
  This module sets up a FastAPI application that loads a pre-trained
  PyTorch model and provides an endpoint for making predictions based on
  input data.
"""

from functools import lru_cache

from fastapi import FastAPI
from pydantic import BaseModel
import torch

# For now keep simple relative path; maybe make it repo-root based later
MODEL_PATH = "models/model_scripted.pt"

@lru_cache(maxsize=1)
def load_model() -> torch.nn.Module:
    """
    Lazily load the TorchScript model the first time it is needed.

    This avoids failing at import time if the model file has not yet
    been created, and makes it easy to substitute a fake model in tests
    (e.g. via pytest's `monkeypatch`).
    """
    model = torch.jit.load(MODEL_PATH)
    model.eval()
    return model

app = FastAPI()

class InputData(BaseModel):
    feature1: float
    feature2: float

@app.post("/predict")
def predict(data: InputData):
    with torch.no_grad():
        input_tensor = torch.tensor([[data.feature1, data.feature2]])
        model = load_model()
        output = model(input_tensor)
        predicted_class = torch.argmax(output, dim=1).item()
        return {"prediction": predicted_class}

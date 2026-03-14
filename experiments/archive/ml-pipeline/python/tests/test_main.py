"""
test_main.py

File: ml-pipeline/python/tests/test_main.py

Description:
  Unit tests for the FastAPI application defined in ../api/main.py, focusing on the
  /predict endpoint.  Uses pytest and FastAPI's TestClient to simulate requests to
  the API.  The test includes a dummy model to avoid dependencies on the actual model
  file, allowing the test to run even if the model has not been created yet.

Usage:
  From the repository root, run:
    pytest -v ml-pipeline/python/tests/test_main.py

  or via Make:
    make test-ml-pipeline
"""

from fastapi.testclient import TestClient
from api import main

import pytest
torch = pytest.importorskip("torch")

class DummyModel:
    """Simple stand-in for a trained TorchScript model."""

    def __call__(self, input_tensor: torch.Tensor) -> torch.Tensor:
        # Simulate a 2-class classifier that always prefers class 1.
        # Shape: (batch_size=1, num_classes=2)
        return torch.tensor([[0.1, 0.9]], dtype=torch.float32)


def test_prediction(monkeypatch):
    # Arrange: replace the real model loader with a dummy implementation.
    monkeypatch.setattr(main, "load_model", lambda: DummyModel())

    client = TestClient(main.app)

    # Act
    response = client.post("/predict", json={"feature1": 1.0, "feature2": 2.0})

    # Assert
    assert response.status_code == 200
    body = response.json()
    assert "prediction" in body
    # For this dummy model, argmax is always 1, but we only assert that
    # it's a reasonable class index.
    assert body["prediction"] in (0, 1)

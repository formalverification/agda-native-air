"""
export_onnx.py

File: ml-pipeline/python/model/export_onnx.py

Description:
  A simple script to load a trained PyTorch model and export it as an ONNX file
  for interoperability with other frameworks.
"""

import torch
from train import SimpleMLP

model = SimpleMLP()
model.load_state_dict(torch.load("models/model.pt"))
model.eval()

dummy_input = torch.randn(1, 2)
torch.onnx.export(model, (dummy_input,), "models/model.onnx",
                  input_names=["input"], output_names=["output"],
                  dynamic_axes={"input": {0: "batch_size"}, "output": {0: "batch_size"}},
                  opset_version=11)

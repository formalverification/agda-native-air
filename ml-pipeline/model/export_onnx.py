# file: agda-ai-prover/ml-pipeline/model/export_onnx.py
import torch
from train import SimpleMLP

model = SimpleMLP()
model.load_state_dict(torch.load("models/model.pt"))
model.eval()

dummy_input = torch.randn(1, 2)
torch.onnx.export(model, dummy_input, "models/model.onnx",
                  input_names=["input"], output_names=["output"],
                  dynamic_axes={"input": {0: "batch_size"}, "output": {0: "batch_size"}},
                  opset_version=11)

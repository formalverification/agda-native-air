"""
export_script.py

File: ml-pipeline/python/model/export_script.py

Description:
  A simple script to load a trained PyTorch model and export it as a TorchScript
  file.

  Assumes the trained model checkpoint is at "models/model.pt" and saves the
  scripted model to "models/model_scripted.pt".
"""
import torch
from train import SimpleMLP

model = SimpleMLP()
model.load_state_dict(torch.load("models/model.pt"))
model.eval()

scripted_model = torch.jit.script(model)
scripted_model.save("models/model_scripted.pt")

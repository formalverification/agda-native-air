import torch
from train import SimpleMLP

model = SimpleMLP()
model.load_state_dict(torch.load("models/model.pt"))
model.eval()

scripted_model = torch.jit.script(model)
scripted_model.save("models/model_scripted.pt")

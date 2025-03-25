from fastapi import FastAPI
from pydantic import BaseModel
import torch

model = torch.jit.load("models/model_scripted.pt")
model.eval()

app = FastAPI()

class InputData(BaseModel):
    feature1: float
    feature2: float

@app.post("/predict")
def predict(data: InputData):
    with torch.no_grad():
        input_tensor = torch.tensor([[data.feature1, data.feature2]])
        output = model(input_tensor)
        predicted_class = torch.argmax(output, dim=1).item()
        return {"prediction": predicted_class}

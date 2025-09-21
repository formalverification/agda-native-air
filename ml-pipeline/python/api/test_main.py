from fastapi.testclient import TestClient
from api.main import app

client = TestClient(app)

def test_prediction():
    response = client.post("/predict", json={"feature1": 1.0, "feature2": 2.0})
    assert response.status_code == 200
    assert "prediction" in response.json()

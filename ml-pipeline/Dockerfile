FROM python:3.11-slim

WORKDIR /app

COPY ./api /app/api
COPY ./models/model_scripted.pt /app/models/model_scripted.pt

RUN pip install fastapi uvicorn torch

CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]

#!/bin/bash
source ~/venvs/mlpipeline/bin/activate
uvicorn api.main:app --reload --host 0.0.0.0 --port 8000

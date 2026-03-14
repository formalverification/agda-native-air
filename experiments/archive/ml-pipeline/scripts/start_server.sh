#!/bin/bash
# start_server.sh
#
# File: ml-pipeline/scripts/start_server.sh
#
# Description:
#   Start the FastAPI server for the ML pipeline.
#
# Usage: ./start_server.sh
#
# Notes:
#   Ensure that the virtual environment is set up and dependencies are installed
#   before running this script.
source ~/venvs/mlpipeline/bin/activate
uvicorn api.main:app --reload --host 0.0.0.0 --port 8000

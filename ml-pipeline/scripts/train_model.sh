#!/bin/bash
#
# train_model.sh
#
# File: ml-pipeline/scripts/train_model.sh
#
# Description:
#  Train the machine learning model and export it for inference.
#
# Usage: ./train_model.sh
#
# Notes:
# Ensure that the virtual environment is set up and dependencies are installed
# before running this script.
#
source ~/venvs/mlpipeline/bin/activate
python3 model/train.py
python3 model/export_script.py

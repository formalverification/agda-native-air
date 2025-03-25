#!/bin/bash
source ~/venvs/mlpipeline/bin/activate
python3 model/train.py
python3 model/export_script.py

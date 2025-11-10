##
# ml-pipeline — subproject Makefile
#
# @file agda-ai-prover/ml-pipeline/Makefile
# @version 0.1
# Focus: Scala/Spark ETL, Python ML model training and API serving
##

SHELL := /bin/bash
ETL_DIR=etl
MODEL_DIR=model
API_DIR=api

.PHONY: etl train export_onnx export_script serve test ci all

seed:
	mkdir -p data/raw
	echo "feature1,feature2,label" > data/raw/data.csv
	echo "1.2,3.4,0" >> data/raw/data.csv
	echo "2.1,4.3,1" >> data/raw/data.csv
	echo "0.5,1.5,0" >> data/raw/data.csv
	echo "3.3,2.2,1" >> data/raw/data.csv
	echo "1.0,1.0,0" >> data/raw/data.csv
	echo "2.5,3.5,1" >> data/raw/data.csv

etl:
	cd $(ETL_DIR) && sbt run

train:
	source ~/venvs/mlpipeline/bin/activate && python3 $(MODEL_DIR)/train.py

export_onnx:
	source ~/venvs/mlpipeline/bin/activate && python3 $(MODEL_DIR)/export_onnx.py

export_script:
	source ~/venvs/mlpipeline/bin/activate && python3 $(MODEL_DIR)/export_script.py

serve:
	source ~/venvs/mlpipeline/bin/activate && uvicorn api.main:app --reload

test:
	source ~/venvs/mlpipeline/bin/activate && pytest api/test_main.py

ci: etl train export_script test

all: etl train export_script serve

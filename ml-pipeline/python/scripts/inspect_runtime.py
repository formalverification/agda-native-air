"""
inspect_runtime.py

File: agda-ai-prover/ml-pipeline/python/scripts/inspect_runtime.py

Purpose
-------
  Prints information about the Python runtime and torch installation.
  Used by the Makefile for debugging environment + GPU/CPU status.

"""
import sys
print(f"Python executable : {sys.executable}")
try:
    import torch
    print(f"torch version     : {torch.__version__}")
    cuda = torch.cuda.is_available()
    print(f"CUDA available    : {cuda}")
    if cuda:
        print(f"CUDA device       : {torch.cuda.get_device_name(0)}")
        print("🔥 USING GPU TORCH")
    else:
        print("🧊 USING CPU-ONLY TORCH")
except Exception as e:
    print(f"⚠️  torch import failed: {e}")

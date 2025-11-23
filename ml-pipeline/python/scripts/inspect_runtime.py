#!/usr/bin/env python3
"""
inspect_runtime.py
------------------

Prints information about the Python runtime and torch installation.
Used by the Makefile for debugging environment + GPU/CPU status.
"""

import sys

print(f"Python executable : {sys.executable}")

try:
    import torch
    print(f"torch version     : {torch.__version__}")
    print(f"CUDA available    : {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"CUDA device       : {torch.cuda.get_device_name(0)}")
except Exception as e:
    print(f"⚠️  torch import failed: {e}")

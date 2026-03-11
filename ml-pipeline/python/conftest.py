"""
conftest.py

File: ml-pipeline/python/conftest.py

Description:
  Pytest configuration for the ml-pipeline project.

  Ensures that the `python/` directory is on sys.path so that imports like
  `from api.main import app` work when running pytest from the `ml-pipeline`
  root (as done in CI and `make test-ml-pipeline`).
"""

import sys
from pathlib import Path

# Directory containing this file: .../ml-pipeline/python
this_dir = Path(__file__).resolve().parent

if str(this_dir) not in sys.path:
    # Prepend so it wins over any accidentally installed `api` modules
    sys.path.insert(0, str(this_dir))

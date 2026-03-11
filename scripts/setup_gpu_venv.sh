#!/bin/sh
#
# File: scripts/setup_gpu_venv.sh
#
# Description:
#   Create/refresh a local Python venv (`.venv-cu121`) with CUDA 12.1 PyTorch wheels
#   (torch/vision/audio) and pyarrow using host (local) Python.
#
# Usage:
#   ./scripts/setup_gpu_venv.sh
#
# Examples:
#   ./scripts/setup_gpu_venv.sh && ./scripts/pycuda.sh -c 'import torch; print(torch.cuda.is_available())'
#
# Notes:
#   - Neutralizes conda only inside the process. No global env changes.
#   - Uses host Python (prefers /usr/bin/python3) for ABI compatibility.
#
# (c) 2025 Thmpr Lab, LLC.

set -eu

# Neutralize conda in THIS process
if [ -n "${CONDA_PREFIX-}" ] || [ -n "${CONDA_SHLVL-}" ]; then
  if command -v conda >/dev/null 2>&1; then
    # prevent base auto-activation
    CONDA_AUTO_ACTIVATE_BASE=false; export CONDA_AUTO_ACTIVATE_BASE
    # drain all activation levels
    while [ "${CONDA_SHLVL:-0}" -gt 0 ]; do conda deactivate || true; done
  fi
  unset CONDA_PREFIX CONDA_SHLVL
fi

# Prefer host python; fallback to whatever python3 is on PATH
PYTHON="/usr/bin/python3"
if ! command -v "$PYTHON" >/dev/null 2>&1; then
  PYTHON="$(command -v python3)"
fi

# Create venv if missing
if [ ! -d ".venv-cu121" ]; then
  "$PYTHON" -m venv .venv-cu121
fi

# Activate and install wheels
# shellcheck disable=SC1091
. .venv-cu121/bin/activate
unset PYTHONHOME PYTHONPATH

python -m pip install -U pip
python -m pip install --index-url https://download.pytorch.org/whl/cu121 \
  torch torchvision torchaudio
python -m pip install pyarrow

# Show versions (no CUDA probing yet)
python - <<'PY'
import torch, sys
print("torch:", torch.__version__)
print("torch cuda build:", torch.version.cuda)
print("python:", sys.version)
PY

echo "✅ Ready: .venv-cu121"

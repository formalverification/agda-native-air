#!/usr/bin/env sh
set -euo pipefail
ENV_DIR="${1:-$HOME/venvs/aap-gpu}"
PY="${PYTHON:-python3}"

$PY -m venv "$ENV_DIR"
source "$ENV_DIR/bin/activate"

# CUDA 12.1 wheels from PyTorch’s index (no compiling!)
pip install --upgrade pip
pip install --index-url https://download.pytorch.org/whl/cu121 torch torchvision torchaudio
pip install pyarrow fastapi uvicorn

python - <<'PY'
import torch, sys
print("torch:", torch.__version__, "cuda:", torch.cuda.is_available())
if torch.cuda.is_available(): print("device:", torch.cuda.get_device_name(0))
PY

echo "✅ GPU venv at $ENV_DIR (activate with: source \"$ENV_DIR/bin/activate\")"

#!/bin/sh
#
# File: scripts/pycuda.sh
#
# Description:
#   Run the venv Python with a local LD_LIBRARY_PATH that prefers wheel CUDA libs,
#   then the host driver.  Uses the venv’s Python with a narrow, local
#   `LD_LIBRARY_PATH` that
#   1. puts the wheel-bundled CUDA libs first (so they beat any system CUDA),
#   2. then appends the host driver dir (so `libcuda.so.1` is found),
#   3. then any existing `LD_LIBRARY_PATH`.
#
# Usage:
#   ./scripts/pycuda.sh -c 'import torch; print(torch.cuda.is_available())'
#
# Examples:
#   ./scripts/pycuda.sh -c 'import torch; print("devices:", torch.cuda.device_count())'
#
# Notes:
#   - Finds libcuda.so.1 via ldconfig (requires proprietary NVIDIA driver).
#   - Avoids touching the login shell’s environment.
#
# (c) 2025 Thmpr Lab, LLC.

set -eu

if [ ! -x ".venv-cu121/bin/python" ]; then
  echo "No .venv-cu121 found. Run scripts/setup_gpu_venv.sh first." >&2
  exit 1
fi

# Neutralize conda in THIS process
if [ -n "${CONDA_PREFIX-}" ] || [ -n "${CONDA_SHLVL-}" ]; then
  if command -v conda >/dev/null 2>&1; then
    CONDA_AUTO_ACTIVATE_BASE=false; export CONDA_AUTO_ACTIVATE_BASE
    while [ "${CONDA_SHLVL:-0}" -gt 0 ]; do conda deactivate || true; done
  fi
  unset CONDA_PREFIX CONDA_SHLVL
fi

# Find host driver dir containing libcuda.so.1
DRV="$(ldconfig -p 2>/dev/null | awk '/libcuda\.so\.1/ {print $NF; exit}' | xargs -r dirname || true)"
if [ -z "$DRV" ] && [ -e /usr/lib/x86_64-linux-gnu/libcuda.so.1 ]; then
  DRV=/usr/lib/x86_64-linux-gnu
fi
if [ -z "$DRV" ]; then
  echo "libcuda.so.1 not found; install the proprietary NVIDIA driver." >&2
  exit 1
fi

# Activate venv so python can resolve site-packages
# shellcheck disable=SC1091
. .venv-cu121/bin/activate >/dev/null 2>&1
unset PYTHONHOME PYTHONPATH LD_PRELOAD

# Build WHEEL_LIBS by scanning common subdirs (nvjitlink, cusparse, cublas, cufft, runtime, cupti)
VENV_SITE="$(python - <<'PY'
import sys, site
c = []
try:
    c = site.getsitepackages()
except Exception:
    pass
if not c:
    for p in sys.path:
        if p.endswith("site-packages"):
            c.append(p)
print(c[0] if c else "")
PY
)"
WHEEL_LIBS=""
if [ -n "$VENV_SITE" ]; then
  for d in torch/lib nvidia/nvjitlink/lib nvidia/cusparse/lib nvidia/cublas/lib nvidia/cufft/lib nvidia/cuda_runtime/lib nvidia/cupti/lib
  do
    if [ -d "$VENV_SITE/$d" ]; then
      if [ -z "$WHEEL_LIBS" ]; then WHEEL_LIBS="$VENV_SITE/$d"; else WHEEL_LIBS="$WHEEL_LIBS:$VENV_SITE/$d"; fi
    fi
  done
fi

# Compose LD_LIBRARY_PATH locally (avoid "unbound" issues)
LDPATH="$DRV"
if [ -n "$WHEEL_LIBS" ]; then
  LDPATH="$WHEEL_LIBS:$LDPATH"
fi
if [ -n "${LD_LIBRARY_PATH-}" ]; then
  LDPATH="$LDPATH:$LD_LIBRARY_PATH"
fi

LD_LIBRARY_PATH="$LDPATH" exec python "$@"

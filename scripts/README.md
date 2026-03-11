# scripts

This directory contains miscellaneous utility scripts.  In particular, there are two
**tiny, nix-free** helper scripts that should work reliably across "weird" env machines.

+  `setup_gpu_venv.sh` -- POSIX-safe setup of `.venv-cu121` with PyTorch CUDA 12.1 wheels and
   PyArrow using the host's (local) Python.

+  `pycuda.sh` -- Run the `venv` Python with a local `LD_LIBRARY_PATH` that prefers wheel CUDA libs.

They avoid all the Nix/Bash headaches and keep state **local to the commands that need it**.

They don’t modify your shell globally and don’t fight conda; they just neutralize it when needed.

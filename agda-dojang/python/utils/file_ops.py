# python/utils/file_ops.py
# file: python/utils/file_ops.py
"""
Provides pure, functional wrappers for file system operations.
"""
from __future__ import annotations
import json
import shutil
import pathlib, time, shutil
# from pathlib import Path
from typing import List, Dict
from contextlib import contextmanager
from dataclasses import dataclass

@dataclass(frozen=True)
class Scratch:
    root: pathlib.Path
    path: pathlib.Path

@contextmanager
def scratch_module(prefix: str, keep: bool) -> Scratch:
    base = pathlib.Path(".scratch_" + prefix) if keep else pathlib.Path.cwd() / f".tmp_{int(time.time()*1000)}"
    base.mkdir(parents=True, exist_ok=True)
    p = base / "TrySandbox.agda"
    try:
        yield Scratch(root=base, path=p)
    finally:
        if not keep:
            try:
                shutil.rmtree(base)
            except Exception:
                pass



"""
file_ops.py

File: agda-dojang/python/utils/file_ops.py

Description:
  Utilities for file operations, including atomic writes and temporary directories.
  Provides pure, functional wrappers for file system operations.
"""
from __future__ import annotations
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Optional
import os, shutil, tempfile, time

# --- Tiny value type for backwards-compat scratch_module API ---
@dataclass(frozen=True)
class Scratch:
    root: Path
    path: Path

# ---------- Pure helpers ----------

def ensure_dir(p: Path) -> Path:
    p.mkdir(parents=True, exist_ok=True)
    return p

@contextmanager
def temp_dir(keep: bool, prefix: str = "agda-dojang_") -> Iterator[Path]:
    """
    If keep=True: returns a stable '.scratch_try' directory and leaves it.
    If keep=False: creates a unique temp directory and deletes it on exit.
    Never raises on cleanup.
    """
    if keep:
        d = Path(".scratch_try")
        d.mkdir(exist_ok=True)
        yield d
        return
    d = Path(tempfile.mkdtemp(prefix=prefix))
    try:
        yield d
    finally:
        try:
            shutil.rmtree(d)
        except Exception:
            pass

def write_text_atomic(path: Path, content: str, encoding: str = "utf-8") -> None:
    """
    Atomic write (POSIX): write to a temp sibling then os.replace().
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(dir=str(path.parent), prefix=path.name + ".tmp_")
    tmp = Path(tmp_name)
    try:
        os.write(fd, content.encode(encoding))
        os.close(fd)
        os.replace(tmp, path)
    finally:
        try:
            if tmp.exists():
                tmp.unlink()
        except Exception:
            pass

# ---------- Backwards-compat layer (optional) ----------

@contextmanager
def scratch_module(prefix: str, keep: bool) -> Iterator[Scratch]:
    """
    Legacy API maintained for callers that expect Scratch(root, path).
    Creates a directory and yields a canonical 'TrySandbox.agda' path inside.
    """
    base = Path(".scratch_" + prefix) if keep else (Path.cwd() / f".tmp_{int(time.time()*1000)}")
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

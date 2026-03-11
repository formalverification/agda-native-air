"""
command_runner.py

File: agda-native-air/agda-dojang/python/utils/command_runner.py

Description:
  Utility for running subprocess commands with a consistent interface and error handling.
"""
from __future__ import annotations
from pathlib import Path
from typing import List, Optional, Dict
import subprocess, os

from .result import Ok, Err, Result
from .types import CommandResult, PipelineError

def run_command(
    command: List[str],
    *,
    cwd: Optional[Path] = None,
    timeout: Optional[float] = None,
    merge_stderr: bool = True,
    env: Optional[Dict[str, str]] = None,
) -> Result[CommandResult, PipelineError]:
    try:
        p = subprocess.run(
            command,
            cwd=str(cwd) if cwd is not None else None,
            text=True,
            stdout=subprocess.PIPE,
            stderr=(subprocess.STDOUT if merge_stderr else subprocess.PIPE),
            timeout=timeout,
            env=(os.environ | env) if env else None,
        )
        stdout = p.stdout or ""
        stderr = "" if merge_stderr else (p.stderr or "")
        if p.returncode == 0:
            return Ok(CommandResult(command, 0, stdout, stderr))
        else:
            return Err(PipelineError(
                kind="NonZeroExit", cmd=command, rc=p.returncode,
                stdout=stdout, stderr=stderr,
                message=f"command exited with {p.returncode}",
            ))
    except subprocess.TimeoutExpired as e:
        return Err(PipelineError(
            kind="Timeout", cmd=command, rc=124,
            stdout=(e.stdout or ""), stderr=(e.stderr or ""),
            message="command timed out",
        ))
    except OSError as e:
        return Err(PipelineError(
            kind="OSError", cmd=command, rc=-1,
            stdout="", stderr="",
            message=str(e),
        ))

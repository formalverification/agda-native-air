"""
types.py

File: agda-dojang/python/utils/types.py

Description:
  Types used across the command runner and pipeline, for better structure and
  type safety.  Notably, these are all frozen dataclasses, so they can be safely
  shared across the codebase without worrying about mutation or aliasing.
"""
from __future__ import annotations
from dataclasses import dataclass
from typing import Optional, List, Dict, Any

# --- High-level config passed around the runner ---
@dataclass(frozen=True)
class RunConfig:
    goal: str
    imports: List[str]
    agda_dir: str
    agda_bin: str
    timeout: float | None
    keep_scratch: bool
    agda_flags: str

# --- Normalized subprocess results & errors ---
@dataclass(frozen=True)
class CommandResult:
    cmd: List[str]
    rc: int
    stdout: str
    stderr: str

@dataclass(frozen=True)
class PipelineError:
    kind: str           # "Timeout" | "OSError" | "NonZeroExit"
    cmd: List[str]
    rc: int             # 124 timeout, -1 spawn error, >0 non-zero exit
    stdout: str
    stderr: str
    message: str

# --- Result output for a single attempt (uniform for candidate/tactic) ---
@dataclass(frozen=True)
class TryResult:
    candidate: Optional[str]   # None for tactic runs
    tactic: Optional[str]      # None for candidate runs
    ok: bool
    rc: int
    agda_output: str           # merged stdout+stderr

# --- Structured subgoal report (JSON-friendly) ---
@dataclass(frozen=True)
class Subgoal:
    index: int
    visibility: str            # "visible" | "hidden" | "instance" | "?arg"
    type: str                  # Agda-rendered

@dataclass(frozen=True)
class SubgoalReport:
    kind: str                  # "subgoal-report"
    source: str                # "applyReport" | "applySolveReport"
    goals: List[Subgoal]
    raw: Dict[str, Any] | None


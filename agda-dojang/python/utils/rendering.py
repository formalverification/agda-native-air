"""
rendering.py

File: agda-dojang/python/utils/rendering.py

Description:
  Utilities to render Agda code snippets for building scratch (TrySandbox) modules.

Features:
  * no I/O, no subprocess—just string assembly;
  * ensures scratch module imports the AgdaDojang macros and user’s imports;
  * keeps tactic syntax ergonomic (`applyReport:_+_` → `applyReport⟨ _+_ ⟩`)
    unless user explicitly wrote `⟨…⟩`.
"""
from __future__ import annotations
from typing import List

# ---------- Tactic syntax helpers ----------

def normalize_tactic_syntax(tactic: str) -> str:
    """
    Accept CLI-friendly forms like:
      - 'applyReport:_+_'
      - 'applyWith1:_+_, zero'
      - 'applyWith:_+_, [ zero , suc zero ]'
    If the user already supplied '⟨ … ⟩', leave as-is.
    If there is a colon, wrap the payload in '⟨ … ⟩'.
    Nullary tactics like 'intro' pass through untouched.
    """
    s = tactic.strip()
    if "⟨" in s and "⟩" in s:
        return s
    if ":" not in s:
        return s
    name, payload = s.split(":", 1)
    return f"{name.strip()}⟨ {payload.strip()} ⟩"

# ---------- Bodies (terms placed in the proof position) ----------

def render_body_for_candidate(candidate: str) -> str:
    # Candidate is already a surface term (e.g., "suc zero").
    # Succeeds iff candidate solves the goal → exit code 0
    return candidate.strip()
    # return f"refine⟨ {candidate} ⟩"

def render_body_for_tactic(tactic: str) -> str:
    # Wrap into macro-call syntax if needed.
    return normalize_tactic_syntax(tactic)

# ---------- Whole scratch module ----------

def render_module(goal: str, user_imports: List[str], body_term: str) -> str:
    """
    Build a minimal Agda module that:
      - brings AgdaDojang macros into scope,
      - includes user-supplied imports,
      - declares a single goal with the given body term.
    """
    # Required for tactics/macros
    jang_imports = [
        "open import AgdaDojang.Prelude",
        "open import AgdaDojang.Refine",
        "open import AgdaDojang.Apply",
        "open import AgdaDojang.Debug",
    ]
    # De-duplicate while preserving order
    seen = set()
    all_imports = []
    for line in (user_imports + jang_imports):
        s = line.strip()
        if not s:
            continue
        if s not in seen:
            seen.add(s)
            all_imports.append(s)

    imports_block = "\n".join(all_imports)
    g = goal.strip()
    b = body_term.strip()

    return f"""\
module TrySandbox where

{imports_block}

_ : {g}
_ = {b}
"""

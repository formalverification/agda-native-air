"""
Tests for `scripts/python/utils/command_runner.py`.

File: scripts/python/tests/test_command_runner.py

Description
-----------
Pins `run_command`'s stdin contract (issue #205, PR #230 review): text given
as `input_text` reaches the command's stdin, and the two combinations the
docstring rules out (streaming, and bytes mode) are refused before anything
runs, rather than dropping the input in silence or failing opaquely.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_command_runner.py`
"""

from __future__ import annotations

from scripts.python.utils.command_runner import run_command
from scripts.python.utils.pipeline_types import ErrorType


def test_input_text_reaches_stdin() -> None:
    r = run_command(["cat"], capture_output=True, text=True, input_text="one\ntwo\n")
    assert r.is_ok
    assert r.unwrap().stdout == "one\ntwo\n"


def test_input_text_with_streaming_is_refused_before_running() -> None:
    r = run_command(["cat"], text=True, stream_output=True, input_text="lost")
    assert r.is_err
    assert r.unwrap_err().error_type == ErrorType.INVALID_CONFIG


def test_input_text_in_bytes_mode_is_refused_before_running() -> None:
    r = run_command(["cat"], capture_output=True, text=False, input_text="x")
    assert r.is_err
    assert r.unwrap_err().error_type == ErrorType.INVALID_CONFIG
    assert "text=True" in r.unwrap_err().message


def test_no_input_text_leaves_the_old_behavior() -> None:
    r = run_command(["true"], capture_output=True, text=False)
    assert r.is_ok

"""
Tests for `scripts/python/launch_to_ready.py`.

File: scripts/python/tests/test_launch_to_ready.py

Description
-----------
The driver's definition of ready is what makes two launchers comparable, so
it is pinned here: only the response to initialize, with its id and a
protocol version, ends the interval; a banner, an error response, or another
id does not.  The pure pieces (the request, the environment, the summary, the
options) are tested directly.  `measure_once` is driven against three tiny
Python stand-ins for a server (one answers, one exits first, one never
answers), which take milliseconds and need no Agda.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_launch_to_ready.py`
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from scripts.python.launch_to_ready import (
    Options,
    Summary,
    child_environment,
    initialize_request,
    is_ready,
    measure_once,
    parse_assignment,
    parse_options,
    summarize,
    table_row,
)

# The first line agda-mcp writes, trimmed: its result begins with
# "capabilities", which is why readiness is read from the parsed line.
AGDA_MCP_ANSWER = json.dumps({"id": 1, "jsonrpc": "2.0", "result": {
    "capabilities": {"tools": {}}, "instructions": "...",
    "protocolVersion": "2024-11-05", "serverInfo": {"name": "agda-mcp"}}})


def test_initialize_request_is_one_json_line() -> None:
    line = initialize_request(7)
    assert line.endswith("\n") and line.count("\n") == 1
    assert json.loads(line) == {"jsonrpc": "2.0", "id": 7, "method": "initialize", "params": {}}


def test_ready_on_the_initialize_response() -> None:
    assert is_ready(AGDA_MCP_ANSWER + "\n", 1)


def test_not_ready_on_anything_else() -> None:
    assert not is_ready("[agda] AGDA_DIR=/x/agda\n", 1)
    assert not is_ready("", 1)
    assert not is_ready("[1, 2]\n", 1)
    assert not is_ready(AGDA_MCP_ANSWER, 2)
    assert not is_ready(json.dumps({"id": 1, "jsonrpc": "2.0",
                                    "error": {"code": -32603, "message": "x"}}), 1)
    assert not is_ready(json.dumps({"id": 1, "jsonrpc": "2.0", "result": {"tools": []}}), 1)
    assert not is_ready(json.dumps({"jsonrpc": "2.0", "method": "notifications/x"}), 1)


def test_child_environment_unsets_then_sets_and_leaves_inputs_alone() -> None:
    base = {"PATH": "/usr/bin", "LD_LIBRARY_PATH": "/nix/lib", "HOME": "/h"}
    env = child_environment(base, [("AGDA_MCP_BIN", "/b/agda-mcp"), ("HOME", "/h2")],
                            ["LD_LIBRARY_PATH"])
    assert env == {"PATH": "/usr/bin", "HOME": "/h2", "AGDA_MCP_BIN": "/b/agda-mcp"}
    assert base == {"PATH": "/usr/bin", "LD_LIBRARY_PATH": "/nix/lib", "HOME": "/h"}


def test_summarize_and_row() -> None:
    assert summarize("x", []) is None
    summary = summarize("fast", [0.020, 0.014, 0.015])
    assert summary == Summary(label="fast", runs=3, minimum=0.014, median=0.015, maximum=0.020)
    assert table_row(summary) == "| fast | 3 | 0.014 | 0.015 | 0.020 |"


def test_parse_assignment() -> None:
    assert parse_assignment("A=b=c").unwrap() == ("A", "b=c")
    assert parse_assignment("A=").is_ok
    assert parse_assignment("A").is_err
    assert parse_assignment("=b").is_err


def test_parse_options_takes_the_command_after_the_separator() -> None:
    options = parse_options(["--runs", "2", "--from", "/w", "--env", "A=1", "--unset", "B",
                             "--", "/r/scripts/run-server.sh", "--cwd", "${PWD}"]).unwrap()
    assert options == Options(command=("/r/scripts/run-server.sh", "--cwd", "${PWD}"),
                              start_dir=Path("/w"), sets=(("A", "1"),), unsets=("B",),
                              runs=2, timeout=120.0, label="run-server.sh")


def test_parse_options_refuses_what_it_cannot_run() -> None:
    assert parse_options(["--"]).is_err
    assert parse_options(["--runs", "0", "--", "x"]).is_err
    assert parse_options(["--timeout", "0", "--", "x"]).is_err
    assert parse_options(["--env", "NOVALUE", "--", "x"]).is_err


def stand_in(source: str, timeout: float = 10.0) -> Options:
    """Options running SOURCE as a Python server stand-in."""
    return Options(command=(sys.executable, "-c", source), start_dir=Path("."), sets=(),
                   unsets=(), runs=1, timeout=timeout, label="stand-in")


def test_measure_once_ends_at_the_answer_not_the_banner() -> None:
    answering = ("import sys\n"
                 "print('banner on stdout first', flush=True)\n"
                 "sys.stdin.readline()\n"
                 f"print({AGDA_MCP_ANSWER!r}, flush=True)\n"
                 "sys.stdin.read()\n")
    seconds = measure_once(stand_in(answering), {"PATH": "/usr/bin:/bin"})
    assert seconds.is_ok and 0 < seconds.unwrap() < 10


def test_measure_once_names_an_early_exit_with_stderr() -> None:
    refused = "import sys\nsys.stderr.write('agda-mcp: server binary is not an executable file\\n')\nsys.exit(1)\n"
    result = measure_once(stand_in(refused), {"PATH": "/usr/bin:/bin"})
    assert result.is_err
    error = result.unwrap_err()
    assert error.message == "exited before answering initialize (exit 1)"
    assert "not an executable file" in error.context["stderr_tail"]


def test_measure_once_times_out() -> None:
    # Reads to the end and never answers: closing stdin ends it at once.
    silent = "import sys\nsys.stdin.readline()\nsys.stdin.read()\n"
    result = measure_once(stand_in(silent, timeout=0.5), {"PATH": "/usr/bin:/bin"})
    assert result.is_err and result.unwrap_err().message.startswith("timed out")


def test_measure_once_names_a_command_that_cannot_start() -> None:
    options = Options(command=("/nonexistent/agda-mcp",), start_dir=Path("."), sets=(),
                      unsets=(), runs=1, timeout=1.0, label="x")
    result = measure_once(options, {})
    assert result.is_err and result.unwrap_err().message == "cannot start /nonexistent/agda-mcp"

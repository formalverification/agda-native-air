"""
File: scripts/python/launch_to_ready.py

Description: Launch to ready (issue #249): how long an MCP client waits
  between starting a server's command and the server's answer to initialize.

  The interval is defined so that two ways of launching one server can be
  compared on it, as follows:

  +  It starts immediately before the command is spawned, with the argv
     exactly as a registration writes it, from the directory the client
     starts in.
  +  The initialize request is written to the command's stdin at once, as a
     client writes it; a launcher still entering a shell leaves it waiting in
     the pipe.
  +  It ends when the first stdout line arrives that is the JSON-RPC 2.0
     success response to that request, carrying result.protocolVersion as a
     string.  agda-mcp's result
     object begins with "capabilities", so the end is read from the parsed
     line, never matched as text.

  After each run stdin is closed, which the server takes as shutdown, the
  process is waited for, and then whatever is left of its process group (the
  command leads one of its own) is killed, so no descendant of one run, such
  as a shellHook's child holding the pipes, lives into the next.

  Usage, from the repository root (`make agda-mcp-launch-time` wraps it with
  the agda-algebras registration's arguments):

    PYTHONPATH=. python3 scripts/python/launch_to_ready.py --runs 5 \\
      --from DIR [--env NAME=VALUE ...] [--unset NAME ...] [--label TEXT] \\
      [--timeout SECONDS] -- COMMAND [ARGS...]

  Output: one line per run on stderr, then one Markdown table row on stdout
  (label, runs, min, median, max, in seconds).  The exit status is 1 when any run did not reach
  ready (a timeout, an exit first, or a command that cannot start), each named
  on stderr with the tail of the command's stderr.

Design notes:
  +  The core is pure: the request, the readiness test on one line, the child's
     environment, and the summary.  Only `measure_once` touches a process.
  +  `measure_once` uses subprocess.Popen directly rather than
     utils.command_runner.run_command, which returns output only when the
     command has exited; the measurement is the moment one line arrives.
     Standard output and standard error are each drained on a thread, so a
     shell banner that fills the stderr pipe cannot stall the server.
"""

from __future__ import annotations

import argparse
import json
import os
import queue
import signal
import statistics
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import IO, Dict, List, Mapping, Optional, Sequence, Tuple

from scripts.python.utils.pipeline_types import (
    ErrorType,
    PipelineError,
    Result,
    collect_errors,
)

REQUEST_ID: int = 1
DEFAULT_RUNS: int = 5
DEFAULT_TIMEOUT_SECONDS: float = 120.0
# How long a server may take to exit once stdin is closed before it is killed.
SHUTDOWN_GRACE_SECONDS: float = 10.0
STDERR_TAIL_CHARS: int = 2000


@dataclass(frozen=True)
class Options:
    """One measurement: what to launch, from where, with what, how often."""

    command: Tuple[str, ...]
    start_dir: Path
    sets: Tuple[Tuple[str, str], ...]
    unsets: Tuple[str, ...]
    runs: int
    timeout: float
    label: str


@dataclass(frozen=True)
class Summary:
    """The seconds of every run that reached ready, summarized."""

    label: str
    runs: int
    minimum: float
    median: float
    maximum: float


# ---------------------------------------------------------------------------
# The pure core
# ---------------------------------------------------------------------------

def initialize_request(request_id: int) -> str:
    """The line a client sends first: initialize, as agda-mcp's smoke sends it."""
    return json.dumps({"jsonrpc": "2.0", "id": request_id, "method": "initialize",
                       "params": {}}) + "\n"


def is_ready(line: str, request_id: int) -> bool:
    """True when LINE is the JSON-RPC 2.0 success response to initialize
    REQUEST_ID, naming its protocol version as a non-empty string.

    A banner line, a notification, an error response, a response to some other
    id, an envelope that is not JSON-RPC 2.0, and a version that is not a
    string are not readiness.
    """
    try:
        message = json.loads(line)
    except ValueError:
        return False
    if not isinstance(message, dict) or message.get("jsonrpc") != "2.0":
        return False
    if message.get("id") != request_id or "error" in message:
        return False
    result = message.get("result")
    version = result.get("protocolVersion") if isinstance(result, dict) else None
    return isinstance(version, str) and version != ""


def child_environment(base: Mapping[str, str], sets: Sequence[Tuple[str, str]],
                      unsets: Sequence[str]) -> Dict[str, str]:
    """BASE without UNSETS, then with SETS; the inputs are left untouched."""
    dropped = frozenset(unsets)
    kept = {name: value for name, value in base.items() if name not in dropped}
    return {**kept, **dict(sets)}


def summarize(label: str, seconds: Sequence[float]) -> Optional[Summary]:
    """Min, median, and max of SECONDS, or None when no run reached ready."""
    if not seconds:
        return None
    return Summary(label=label, runs=len(seconds), minimum=min(seconds),
                   median=statistics.median(seconds), maximum=max(seconds))


def table_row(summary: Summary) -> str:
    """One Markdown table row: label, runs, min, median, max (seconds)."""
    cells = (summary.label, str(summary.runs), f"{summary.minimum:.3f}",
             f"{summary.median:.3f}", f"{summary.maximum:.3f}")
    return "| " + " | ".join(cells) + " |"


def parse_assignment(text: str) -> Result[Tuple[str, str], PipelineError]:
    """NAME=VALUE as a pair; VALUE may be empty, NAME may not."""
    name, sep, value = text.partition("=")
    if not sep or not name:
        return Result.err(PipelineError(ErrorType.INVALID_CONFIG,
                                        f"--env wants NAME=VALUE, got {text!r}"))
    return Result.ok((name, value))


def parse_options(argv: Sequence[str]) -> Result[Options, PipelineError]:
    """The command line, checked; never exits (argparse's own errors aside)."""
    parser = argparse.ArgumentParser(
        description="Time an MCP server from launch to its answer to initialize.")
    parser.add_argument("--runs", type=int, default=DEFAULT_RUNS)
    parser.add_argument("--from", dest="start_dir", default=".",
                        help="the directory the command is started in")
    parser.add_argument("--env", action="append", default=[],
                        help="NAME=VALUE added to the inherited environment")
    parser.add_argument("--unset", action="append", default=[],
                        help="NAME removed from the inherited environment")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS)
    parser.add_argument("--label", default="")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(list(argv))
    # argparse keeps the "--" that separates the command from the options.
    command = tuple(args.command[1:] if args.command[:1] == ["--"] else args.command)
    if not command:
        return Result.err(PipelineError(ErrorType.INVALID_CONFIG, "no command after --"))
    if args.runs < 1 or args.timeout <= 0:
        return Result.err(PipelineError(ErrorType.INVALID_CONFIG,
                                        "--runs must be at least 1 and --timeout positive"))
    assignments, bad = collect_errors([parse_assignment(a) for a in args.env])
    if bad:
        return Result.err(bad[0])
    return Result.ok(Options(command=command, start_dir=Path(args.start_dir),
                             sets=tuple(assignments), unsets=tuple(args.unset),
                             runs=args.runs, timeout=args.timeout,
                             label=args.label or Path(command[0]).name))


# ---------------------------------------------------------------------------
# The effectful edge
# ---------------------------------------------------------------------------

def _drain(stream: IO[str], sink: "queue.Queue[Tuple[float, str]]") -> None:
    """Put each line of STREAM on SINK with its arrival time, then an EOF marker."""
    for line in stream:
        sink.put((time.monotonic(), line))
    sink.put((time.monotonic(), ""))


def _kill_group(process: "subprocess.Popen[str]") -> None:
    """SIGKILL whatever is left of the command's process group.

    The command leads a group of its own (start_new_session), so this reaches
    every descendant that did not leave it: a shellHook's child (the banner's
    sbt probe, cabal) or a forked helper holding the pipes.  Without a group,
    killing the leader alone left such a child running into the next run.
    """
    if not hasattr(os, "killpg"):
        process.kill()  # no process groups (Windows): the leader is all we reach
        return
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        pass  # the group is empty already


def _stop(process: "subprocess.Popen[str]", grace: float) -> None:
    """Close stdin (the server's shutdown), wait up to GRACE seconds, then
    kill the rest of the process group, so no part of one run outlives it."""
    try:
        if process.stdin is not None:
            process.stdin.close()
        process.wait(timeout=grace)
    except (OSError, subprocess.TimeoutExpired):
        pass  # the group kill below ends it
    _kill_group(process)
    process.wait()


def measure_once(options: Options, env: Mapping[str, str],
                 grace: float = SHUTDOWN_GRACE_SECONDS) -> Result[float, PipelineError]:
    """Seconds from spawn to the initialize response, for one launch.

    GRACE bounds the wait for a clean exit after stdin closes; the tests
    shorten it."""
    started = time.monotonic()
    try:
        process = subprocess.Popen(options.command, cwd=options.start_dir, env=dict(env),
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, encoding="utf-8",
                                   errors="replace", start_new_session=True)
    except OSError as exc:
        return Result.err(PipelineError(ErrorType.COMMAND_FAILED,
                                        f"cannot start {options.command[0]}", cause=exc))
    out: "queue.Queue[Tuple[float, str]]" = queue.Queue()
    err: "queue.Queue[Tuple[float, str]]" = queue.Queue()
    drains = tuple(threading.Thread(target=_drain, args=(stream, sink), daemon=True)
                   for stream, sink in ((process.stdout, out), (process.stderr, err)))
    for drain in drains:
        drain.start()
    try:
        assert process.stdin is not None
        process.stdin.write(initialize_request(REQUEST_ID))
        process.stdin.flush()
    except OSError:
        pass  # the command died already (a refused launch); the read below says how
    deadline = started + options.timeout
    outcome: Optional[float] = None
    reason = "timed out"
    while outcome is None:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            arrived, line = out.get(timeout=remaining)
        except queue.Empty:
            break
        if line == "":
            reason = "exited before answering initialize"
            break
        if is_ready(line, REQUEST_ID):
            outcome = arrived - started
    _stop(process, grace)
    if outcome is not None:
        return Result.ok(outcome)
    # The whole group is gone, so its pipes close and both drains finish.
    for drain in drains:
        drain.join(timeout=grace)
    tail = "".join(line for _, line in list(err.queue))[-STDERR_TAIL_CHARS:]
    return Result.err(PipelineError(ErrorType.COMMAND_FAILED,
                                    f"{reason} (exit {process.returncode})",
                                    context={"stderr_tail": tail}))


def run(options: Options) -> Tuple[List[float], List[PipelineError]]:
    """Every run, in order, one after another."""
    env = child_environment(os.environ, options.sets, options.unsets)
    return collect_errors([measure_once(options, env) for _ in range(options.runs)])


def main(argv: Sequence[str]) -> int:
    parsed = parse_options(argv)
    if parsed.is_err:
        print(f"launch-to-ready: {parsed.unwrap_err()}", file=sys.stderr)
        return 2
    options = parsed.unwrap()
    seconds, errors = run(options)
    # Each run is progress, on stderr; stdout carries the table row alone, so a
    # caller can collect rows from several measurements.
    for value in seconds:
        print(f"launch-to-ready: {options.label}: {value:.3f} s", file=sys.stderr)
    for error in errors:
        print(f"launch-to-ready: {options.label}: FAILED: {error.message}", file=sys.stderr)
        print(error.context.get("stderr_tail", ""), file=sys.stderr)
    summary = summarize(options.label, seconds)
    if summary is not None:
        print(table_row(summary))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

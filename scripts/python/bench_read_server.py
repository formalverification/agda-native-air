"""
File: scripts/python/bench_read_server.py

Description: The read tool of a Codex agent-bench subject (issue #239): a
  stdio MCP server with one tool, `read`, that returns a file's lines
  numbered from 1, confined to the directories the subject may read.

  Why it exists.  A `claude -p` subject on the `mcp` arm reads files with
  Claude Code's Read tool, which the client confines to the subject's work
  directory and the libraries' source roots, and it has no shell.  Codex has
  no read tool at all: its subjects read through a shell, and a shell can
  search (grep a library, list a directory), which is the instrument the
  `mcp` arm withholds.  So a Codex subject's shell is switched off and this
  server gives it back exactly a Read: one file at a time, by absolute
  path, inside the roots, with an optional range.

  The answer has the shape of Claude Code's Read answer, one line per line
  of the file as `N<TAB>text`, so the readers of a transcript treat both
  alike.  A path outside the roots (after symbolic links are resolved), a
  relative path, a directory, or a missing file is refused with a message
  and `isError`, the way the client refuses a Read outside its directories.

  Usage (the harness writes this into the subject's Codex configuration):

    python3 scripts/python/bench_read_server.py --root DIR [--root DIR ...]

Design notes:
  +  Self-contained and stdlib-only on purpose: Codex starts it with a
     whitelisted environment from any directory, so it imports nothing from
     the repository.  The core is pure (a request to a reply, a path and the
     roots to a verdict, a text to its numbered lines); reading stdin,
     reading a file, and writing stdout are the edges.
  +  The protocol is JSON-RPC 2.0, one message per line, as MCP's stdio
     transport has it: `initialize`, `ping`, `tools/list`, `tools/call`;
     notifications get no reply, and any other request a method-not-found
     error.  The protocol version answered is the client's own.
  +  A line longer than 2,000 characters is cut there, and a read returns at
     most 2,000 lines unless `limit` says otherwise, Claude Code's limits.
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from typing import Callable, Iterable, Optional, Sequence, Union

SERVER_NAME = "files"
SERVER_VERSION = "1"
DEFAULT_LIMIT = 2000
LINE_CHARS = 2000

TOOL = {
    "name": "read",
    "description": (
        "Read one file: the file you were given, or a source file of the libraries it imports.  "
        "Pass an ABSOLUTE file_path.  The answer is the file's lines numbered from 1, one per line as "
        "N<TAB>text, at most 2000 lines; to read part of a long file, pass offset (the line to start at, "
        "from 1) and limit (how many lines).  A path outside the directories you may read is refused."
    ),
    "inputSchema": {
        "type": "object",
        "properties": {
            "file_path": {"type": "string", "description": "The absolute path of the file to read."},
            "offset": {"type": "integer", "description": "The line to start at, from 1."},
            "limit": {"type": "integer", "description": "How many lines to read."},
        },
        "required": ["file_path"],
        "additionalProperties": False,
    },
}


@dataclass(frozen=True)
class Refusal:
    """Why a read was refused, as the subject will read it."""

    message: str


@dataclass(frozen=True)
class Allowed:
    """A read the roots admit: the resolved path to open."""

    path: str


Verdict = Union[Refusal, Allowed]


def verdict(file_path: object, roots: Sequence[str], realpath: Callable[[str], str],
            is_dir: Callable[[str], bool], is_file: Callable[[str], bool]) -> Verdict:
    """May this path be read?  Pure over the three filesystem questions,
    which the caller answers (os.path in the server, a table in a test)."""
    if not isinstance(file_path, str) or not file_path:
        return Refusal("file_path is required, as an absolute path")
    if not os.path.isabs(file_path):
        return Refusal(f"{file_path}: not an absolute path; pass the absolute path")
    if "\x00" in file_path:
        return Refusal(f"{file_path!r}: a path cannot contain a NUL byte")
    try:
        real = realpath(file_path)
        inside = any(real == r or real.startswith(r.rstrip("/") + "/") for r in roots)
        if not inside:
            return Refusal(f"{file_path} is outside the directories you may read")
        if is_dir(real):
            return Refusal(f"{file_path} is a directory, not a file")
        if not is_file(real):
            return Refusal(f"{file_path} does not exist")
    except ValueError:
        # A path the operating system cannot name (an unpaired surrogate).
        return Refusal(f"{file_path!r} is not a path")
    return Allowed(real)


def numbered(text: str, offset: int, limit: int) -> str:
    """The lines from `offset` (from 1), at most `limit` of them, as
    `N<TAB>text`, each cut at LINE_CHARS characters."""
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]
    start = max(offset, 1)
    chosen = lines[start - 1:start - 1 + max(limit, 0)]
    return "\n".join(f"{start + i}\t{line[:LINE_CHARS]}" for i, line in enumerate(chosen))


def int_arg(args: dict, key: str, default: int) -> Optional[int]:
    """An integer argument, its default when absent, None when it is not an integer."""
    value = args.get(key, default)
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def tool_result(text: str, is_error: bool) -> dict:
    return {"content": [{"type": "text", "text": text}], "isError": is_error}


def call(arguments: object, roots: Sequence[str], read_text: Callable[[str], Optional[str]],
         realpath: Callable[[str], str], is_dir: Callable[[str], bool], is_file: Callable[[str], bool]) -> dict:
    """The reply to one `tools/call` of `read`."""
    args = arguments if isinstance(arguments, dict) else {}
    offset, limit = int_arg(args, "offset", 1), int_arg(args, "limit", DEFAULT_LIMIT)
    if offset is None or limit is None:
        return tool_result("offset and limit must be integers", True)
    v = verdict(args.get("file_path"), roots, realpath, is_dir, is_file)
    if isinstance(v, Refusal):
        return tool_result(v.message, True)
    text = read_text(v.path)
    if text is None:
        return tool_result(f"{args.get('file_path')} could not be read", True)
    return tool_result(numbered(text, offset, limit), False)


def reply(message: dict, handle_call: Callable[[object], dict]) -> Optional[dict]:
    """The reply to one JSON-RPC message, or None for a notification."""
    if "id" not in message:
        return None
    rid, method, params = message.get("id"), message.get("method"), message.get("params") or {}
    if method == "initialize":
        version = params.get("protocolVersion", "2025-06-18") if isinstance(params, dict) else "2025-06-18"
        result: dict = {"protocolVersion": version, "capabilities": {"tools": {}},
                        "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION}}
    elif method == "ping":
        result = {}
    elif method == "tools/list":
        result = {"tools": [TOOL]}
    elif method == "tools/call":
        name = params.get("name") if isinstance(params, dict) else None
        if name != TOOL["name"]:
            return {"jsonrpc": "2.0", "id": rid, "error": {"code": -32602, "message": f"no tool named {name}"}}
        result = handle_call(params.get("arguments"))
    else:
        return {"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": f"method not found: {method}"}}
    return {"jsonrpc": "2.0", "id": rid, "result": result}


def roots_of(argv: Sequence[str]) -> list[str]:
    """The `--root DIR` arguments, each resolved, so a root reached through a link still contains its files."""
    return [os.path.realpath(argv[i + 1]) for i, a in enumerate(argv[:-1]) if a == "--root"]


def read_file(path: str) -> Optional[str]:
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def serve(lines: Iterable[str], handle_call: Callable[[object], dict], write: Callable[[str], None]) -> None:
    """Answer every request line by line.  No request ends the server: a
    line that is no JSON is skipped, and a handler that raises answers its
    request with an error, so the subject keeps its Read."""
    for line in lines:
        if not line.strip():
            continue
        try:
            message = json.loads(line)
        except Exception:  # noqa: BLE001 (ValueError, or RecursionError on deep nesting)
            continue
        try:
            out = reply(message, handle_call) if isinstance(message, dict) else None
        except Exception as e:  # noqa: BLE001
            rid = message.get("id") if isinstance(message, dict) else None
            out = None if rid is None else {"jsonrpc": "2.0", "id": rid, "error": {"code": -32603, "message": f"internal error: {type(e).__name__}"}}
        if out is not None:
            try:
                text = json.dumps(out, ensure_ascii=False)
                write(text + "\n")
            except UnicodeEncodeError:
                write(json.dumps(out) + "\n")


def main(argv: Sequence[str]) -> int:
    roots = roots_of(argv)
    if not roots:
        sys.stderr.write("usage: bench_read_server.py --root DIR [--root DIR ...]\n")
        return 2
    handle = lambda arguments: call(arguments, roots, read_file, os.path.realpath, os.path.isdir, os.path.isfile)

    def write(text: str) -> None:
        sys.stdout.write(text)
        sys.stdout.flush()

    serve(sys.stdin, handle, write)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

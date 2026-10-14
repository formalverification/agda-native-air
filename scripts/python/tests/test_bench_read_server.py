"""
File: scripts/python/tests/test_bench_read_server.py

Description: Pins the read tool of a Codex agent-bench subject (issue #239):
  what it refuses (a relative path, a path outside the roots by `..` or by a
  symbolic link, a directory, a missing file), the shape of its answer (lines
  numbered from 1 as `N<TAB>text`, an offset and a limit, long lines cut), its
  JSON-RPC replies, one round trip over stdio as Codex drives it, and a
  path with a NUL byte, a handler that raises, and a line nested past the
  parser's depth, none of which ends the server.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import bench_read_server as rs  # noqa: E402


def make_tree(tmp: Path) -> tuple[Path, Path, Path]:
    work = tmp / "work"
    lib = tmp / "lib"
    secret = tmp / "gold"
    for d in (work, lib, secret):
        d.mkdir()
    (work / "F.agda").write_text("module F where\n\nx = {!!}\n", encoding="utf-8")
    (lib / "L.agda").write_text("".join(f"line {i}\n" for i in range(1, 11)), encoding="utf-8")
    (secret / "F.agda").write_text("module F where\n\nx = refl\n", encoding="utf-8")
    (work / "link.agda").symlink_to(secret / "F.agda")
    return work, lib, secret


def read(args: dict, roots: list[str]) -> dict:
    return rs.call(args, roots, rs.read_file, os.path.realpath, os.path.isdir, os.path.isfile)


def test_reads_inside_the_roots_numbered_from_one(tmp_path: Path) -> None:
    work, lib, _ = make_tree(tmp_path)
    roots = rs.roots_of(["--root", str(work), "--root", str(lib)])
    out = read({"file_path": str(work / "F.agda")}, roots)
    assert out == {"content": [{"type": "text", "text": "1\tmodule F where\n2\t\n3\tx = {!!}"}], "isError": False}
    part = read({"file_path": str(lib / "L.agda"), "offset": 4, "limit": 2}, roots)
    assert part["content"][0]["text"] == "4\tline 4\n5\tline 5"


def test_refuses_what_a_confined_read_refuses(tmp_path: Path) -> None:
    work, lib, secret = make_tree(tmp_path)
    roots = rs.roots_of(["--root", str(work), "--root", str(lib)])
    cases = {
        "F.agda": "not an absolute path",
        str(secret / "F.agda"): "outside the directories you may read",
        str(work / ".." / "gold" / "F.agda"): "outside the directories you may read",
        str(work / "link.agda"): "outside the directories you may read",
        str(lib): "is a directory",
        str(work / "Missing.agda"): "does not exist",
    }
    for path, why in cases.items():
        out = read({"file_path": path}, roots)
        assert out["isError"] is True, path
        assert why in out["content"][0]["text"], path
    assert read({}, roots)["isError"] is True
    assert read({"file_path": str(work / "F.agda"), "offset": "1"}, roots)["isError"] is True


def test_a_root_is_a_directory_prefix_not_a_string_prefix(tmp_path: Path) -> None:
    work, _, _ = make_tree(tmp_path)
    twin = tmp_path / "work2"
    twin.mkdir()
    (twin / "G.agda").write_text("x\n", encoding="utf-8")
    out = read({"file_path": str(twin / "G.agda")}, rs.roots_of(["--root", str(work)]))
    assert out["isError"] is True


def test_long_lines_are_cut_and_the_default_limit_holds(tmp_path: Path) -> None:
    long = tmp_path / "long.txt"
    long.write_text("y" * 2500 + "\n" + "".join("z\n" for _ in range(3000)), encoding="utf-8")
    text = read({"file_path": str(long)}, [str(tmp_path)])["content"][0]["text"]
    lines = text.split("\n")
    assert len(lines) == rs.DEFAULT_LIMIT
    assert lines[0] == "1\t" + "y" * rs.LINE_CHARS


def test_json_rpc_replies() -> None:
    handle = lambda _args: rs.tool_result("ok", False)
    init = rs.reply({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-03-26"}}, handle)
    assert init is not None and init["result"]["protocolVersion"] == "2025-03-26"
    assert init["result"]["serverInfo"]["name"] == "files"
    assert rs.reply({"jsonrpc": "2.0", "method": "notifications/initialized"}, handle) is None
    tools = rs.reply({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}, handle)
    assert tools is not None and [t["name"] for t in tools["result"]["tools"]] == ["read"]
    assert tools["result"]["tools"][0]["inputSchema"]["required"] == ["file_path"]
    other = rs.reply({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "write"}}, handle)
    assert other is not None and other["error"]["code"] == -32602
    unknown = rs.reply({"jsonrpc": "2.0", "id": 4, "method": "resources/list"}, handle)
    assert unknown is not None and unknown["error"]["code"] == -32601


def test_one_round_trip_over_stdio(tmp_path: Path) -> None:
    work, _, _ = make_tree(tmp_path)
    requests = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "read", "arguments": {"file_path": str(work / "F.agda")}}},
    ]
    proc = subprocess.run([sys.executable, str(HERE.parent / "bench_read_server.py"), "--root", str(work)],
                          input="\n".join(json.dumps(r) for r in requests) + "\n", capture_output=True, text=True, timeout=30)
    replies = [json.loads(line) for line in proc.stdout.splitlines()]
    assert [r["id"] for r in replies] == [1, 2]
    assert replies[1]["result"]["content"][0]["text"].startswith("1\tmodule F where")
    assert proc.returncode == 0


def test_a_bad_path_is_refused_and_the_server_keeps_answering(tmp_path: Path) -> None:
    work, _, _ = make_tree(tmp_path)
    nul = read({"file_path": "/x\x00y"}, [str(work)])
    assert nul["isError"] is True and "NUL" in nul["content"][0]["text"]
    requests = [
        {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "read", "arguments": {"file_path": "/x\u0000y"}}},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "read", "arguments": {"file_path": str(work / "F.agda")}}},
    ]
    proc = subprocess.run([sys.executable, str(HERE.parent / "bench_read_server.py"), "--root", str(work)],
                          input="\n".join(json.dumps(r) for r in requests) + "\n", capture_output=True, text=True, timeout=30)
    replies = [json.loads(line) for line in proc.stdout.splitlines()]
    assert [r["id"] for r in replies] == [1, 2]
    assert replies[0]["result"]["isError"] is True
    assert replies[1]["result"]["content"][0]["text"].startswith("1\tmodule F where")
    assert proc.returncode == 0


def test_a_handler_that_raises_answers_with_an_error_and_the_loop_goes_on() -> None:
    def handle(arguments: object) -> dict:
        if isinstance(arguments, dict) and arguments.get("boom"):
            raise RuntimeError("boom")
        return rs.tool_result("ok", False)
    lines = [
        json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "read", "arguments": {"boom": True}}}),
        "[" * 5000,
        json.dumps({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "read", "arguments": {}}}),
    ]
    out: list[str] = []
    rs.serve(lines, handle, out.append)
    replies = [json.loads(o) for o in out]
    assert [r["id"] for r in replies] == [1, 2]
    assert replies[0]["error"]["code"] == -32603
    assert replies[1]["result"]["content"][0]["text"] == "ok"

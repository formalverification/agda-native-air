#!/usr/bin/env python3
"""
make_proof_completion_fixture.py

Build a small, *committable*, deterministic JSONL fixture for the proof-completion
dataset builder.

Why this exists
---------------
Our canonical Agda backend JSONL can be large (e.g. combined.jsonl ~46MB). CI
needs a tiny, stable slice checked into the repo, e.g.:

  ml-pipeline/etl/src/test/resources/proof-completion.smoke.jsonl

We want this slice to be:
  - deterministic and order-independent (doesn't depend on input file ordering)
  - aligned with v0 builder constraints (hasBody, has typeAst, etc.)
  - small enough for CI (e.g. 200 rows)

Deterministic sampling strategy
------------------------------
By default we score each candidate row by SHA1(prettyQname) and select the K rows
with the smallest scores. This is independent of input ordering and stable across
machines.

Basic usage
-----------
  python3 scripts/python/utils/make_proof_completion_fixture.py \
    --in  data/agda-algebras/raw/jsonl/combined.jsonl \
    --out ml-pipeline/etl/src/test/resources/proof-completion.smoke.jsonl \
    --k   200

Then validate (from repo root):
  make etl-proof-completion-dataset-smoke PROOF_COMPLETION_SMOKE_LIMIT=200

Notes
-----
- "simple body" means: non-empty and contains no whitespace. This matches v0's
  default smoke intent and avoids multi-line/pretty-printed bodies.
- The builder already accepts either "typeAstJson" (string) or "typeAst" (object),
  so this script keeps whichever is present.
"""

from __future__ import annotations

import argparse
import contextlib
import gzip
import hashlib
import json
import os
import re
import sys
from dataclasses import dataclass
from typing import Any, Dict, Iterator, List, Optional, Tuple

AT_INDEX_RE = re.compile(r"^@\d+$")


@dataclass(frozen=True)
class Candidate:
    score: int
    pretty_qname: str
    module_key: str
    obj: Dict[str, Any]


def _eprint(*args: Any) -> None:
    print(*args, file=sys.stderr)


def _is_simple_body(s: Optional[str]) -> bool:
    if s is None:
        return False
    t = s.strip()
    if not t:
        return False
    return not any(ch.isspace() for ch in t)


def _get_pretty_qname(obj: Dict[str, Any]) -> str:
    # tiny back-compat: prettyQname vs prettyQName
    pq = obj.get("prettyQname") or obj.get("prettyQName") or ""
    return pq.strip() if isinstance(pq, str) else ""


def _get_module_key(obj: Dict[str, Any], pq: str) -> str:
    """
    A stable "module-ish" key used for optional diversity caps.

    Preference:
      1) prettyModule (if present)
      2) derive from prettyQname by dropping last segment
    """
    pm = obj.get("prettyModule")
    if isinstance(pm, str) and pm.strip():
        return pm.strip()

    parts = [p for p in pq.split(".") if p]
    if len(parts) <= 1:
        return pq
    return ".".join(parts[:-1])


def _stable_score(pretty_qname: str, salt: str) -> int:
    """
    Deterministic score: lower is "better"/selected first.
    Uses sha1(salt + pretty_qname).
    """
    h = hashlib.sha1((salt + pretty_qname).encode("utf-8")).hexdigest()
    # use 64-bit prefix (16 hex chars) for easy sorting & stable across Python versions
    return int(h[:16], 16)

def _json_compact(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":"))

def _byte_len_utf8(s: str) -> int:
    return len(s.encode("utf-8"))

def _typeast_bytes(obj: Dict[str, Any]) -> Optional[int]:
    """
    Returns byte length (utf-8) of whichever typeAst encoding is present.
    """
    if isinstance(obj.get("typeAstJson"), str) and obj["typeAstJson"].strip():
        return _byte_len_utf8(obj["typeAstJson"])
    if obj.get("typeAst") is not None:
        try:
            return _byte_len_utf8(_json_compact(obj["typeAst"]))
        except Exception:
            return None
    return None

def _read_jsonl(path: str) -> Iterator[Tuple[int, str, Dict[str, Any]]]:
    """
    Read JSONL from:
      - a plain .jsonl file
      - a gzipped .jsonl.gz file
      - stdin, if path == "-"
    """

    @contextlib.contextmanager
    def _open_text(p: str):
        if p == "-":
            yield sys.stdin
            return
        if p.endswith(".gz"):
            with gzip.open(p, "rt", encoding="utf-8") as f:
                yield f
        else:
            with open(p, "r", encoding="utf-8") as f:
                yield f

    with _open_text(path) as f:
        for lineno, line in enumerate(f, start=1):
            raw = line.strip()
            if not raw:
                continue
            try:
                obj = json.loads(raw)
            except Exception as e:
                _eprint(f"⚠️  skipping invalid JSON at {path}:{lineno}: {e}")
                continue
            if not isinstance(obj, dict):
                _eprint(f"⚠️  skipping non-object JSON at {path}:{lineno}")
                continue
            yield lineno, raw, obj


def _passes_filters(
    obj: Dict[str, Any],
    *,
    simple_only: bool,
    require_typeast: bool,
    require_fields: bool,
    prefer_at_index: bool,
    max_ast_size: Optional[int],
    max_typeast_bytes: Optional[int],
    max_row_bytes: Optional[int],
    minimal_projection: bool,
    projected_for_rowbytes: Optional[Dict[str, Any]] = None,
) -> bool:
    # hasBody must be true
    if obj.get("hasBody") is not True:
        return False

    body = obj.get("body")
    if not isinstance(body, str) or not body.strip():
        return False

    if simple_only and not _is_simple_body(body):
        return False

    if prefer_at_index and not AT_INDEX_RE.match(body.strip()):
        return False

    # require structural info so @i resolution is meaningful
    if require_typeast and not (obj.get("typeAstJson") or obj.get("typeAst")):
        return False

    if require_fields:
        # minimal set the builder expects to produce meaningful rows
        pq = _get_pretty_qname(obj)
        if not pq:
            return False
        if not isinstance(obj.get("file"), str) or not obj["file"].strip():
            return False
        if not isinstance(obj.get("type"), str) or not obj["type"].strip():
            return False

    # Filter by astSize if present and numeric.
    if max_ast_size is not None:
        v = obj.get("astSize")
        if isinstance(v, int):
            if v > max_ast_size:
                return False

    # Filter by typeAst payload bytes (best-effort).
    if max_typeast_bytes is not None:
        tb = _typeast_bytes(obj)
        if tb is not None and tb > max_typeast_bytes:
            return False

    # Filter by output row bytes (based on what we'd write).
    if max_row_bytes is not None:
        cand_obj = projected_for_rowbytes
        if cand_obj is None:
            cand_obj = _project_minimal(obj) if minimal_projection else obj
        try:
            line = _json_compact(cand_obj)
            if _byte_len_utf8(line) > max_row_bytes:
                return False
        except Exception:
            # If we can't serialize compactly, drop it.
            return False

    return True


def _project_minimal(obj: Dict[str, Any]) -> Dict[str, Any]:
    """
    Keep only fields we expect the builder to read (plus a few helpful extras).
    This helps keep fixtures smaller and reduces accidental schema drift.
    """
    keep = {
        "file",
        "module",
        "name",
        "qname",
        "prettyModule",
        "prettyName",
        "prettyQname",
        "prettyQName",  # tolerate alt spelling if present
        "type",
        "typeAstVersion",
        "typeAstJson",
        "typeAst",
        "body",
        "hasBody",
        "defKind",
        "kind",
        "dependencies",
        "astSize",
    }
    out: Dict[str, Any] = {}
    for k in keep:
        if k in obj:
            out[k] = obj[k]
    return out


def build_fixture(
    *,
    in_path: str,
    out_path: str,
    k: int,
    salt: str,
    simple_only: bool,
    require_typeast: bool,
    require_fields: bool,
    max_per_module: Optional[int],
    oversample_factor: int,
    minimal: bool,
    prefer_at_index: bool,
    max_ast_size: Optional[int],
    max_typeast_bytes: Optional[int],
    max_row_bytes: Optional[int],
    gzip_out: bool,
    report_largest: int,
) -> Tuple[int, int, int]:
    """
    Returns (scanned, candidates, written).
    """
    scanned = 0
    candidates = 0

    # If we enforce max-per-module, we usually want to oversample so we can still fill K.
    target = k if max_per_module is None else max(k * max(1, oversample_factor), k)

    # Keep best "target" by score.
    # We'll store as a *max* heap via negative score semantics implemented manually with list+sort at end,
    # since target is small (<= a few thousand) and avoids extra imports/complexity.
    best: List[Candidate] = []

    for _lineno, _raw, obj in _read_jsonl(in_path):
        scanned += 1
        keep_obj = _project_minimal(obj) if minimal else obj
        if not _passes_filters(
            obj,
            simple_only=simple_only,
            require_typeast=require_typeast,
            require_fields=require_fields,
            prefer_at_index=prefer_at_index,
            max_ast_size=max_ast_size,
            max_typeast_bytes=max_typeast_bytes,
            max_row_bytes=max_row_bytes,
            minimal_projection=minimal,
            projected_for_rowbytes=keep_obj,
        ):
            continue

        pq = _get_pretty_qname(obj)
        if not pq:
            continue

        candidates += 1
        score = _stable_score(pq, salt)
        module_key = _get_module_key(obj, pq)

        cand = Candidate(score=score, pretty_qname=pq, module_key=module_key, obj=keep_obj)

        if len(best) < target:
            best.append(cand)
        else:
            # Replace current worst if this is better.
            # Find worst lazily: maintain best sorted occasionally.
            # For target ~1000 this is fine.
            worst_ix = max(range(len(best)), key=lambda i: (best[i].score, best[i].pretty_qname))
            if (cand.score, cand.pretty_qname) < (best[worst_ix].score, best[worst_ix].pretty_qname):
                best[worst_ix] = cand

    # Sort deterministically by (score, pretty_qname)
    best_sorted = sorted(best, key=lambda c: (c.score, c.pretty_qname))

    # Apply optional diversity cap
    picked: List[Candidate] = []
    per_mod: Dict[str, int] = {}

    for c in best_sorted:
        if len(picked) >= k:
            break
        if max_per_module is not None:
            n = per_mod.get(c.module_key, 0)
            if n >= max_per_module:
                continue
            per_mod[c.module_key] = n + 1
        picked.append(c)

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    if gzip_out:
        with gzip.open(out_path, "wt", encoding="utf-8") as out:
            for c in picked:
                out.write(_json_compact(c.obj))
                out.write("\n")
    else:
        with open(out_path, "w", encoding="utf-8") as out:
            for c in picked:
                out.write(_json_compact(c.obj))
                out.write("\n")

    if report_largest > 0 and picked:
        sizes: List[Tuple[int, str]] = []
        for c in picked:
            try:
                sizes.append((_byte_len_utf8(_json_compact(c.obj)), c.pretty_qname))
            except Exception:
                continue
        top = sorted(sizes, key=lambda t: (-t[0], t[1]))[:report_largest]
        _eprint("Largest selected rows (bytes, prettyQname):")
        for b, pq in top:
            _eprint(f"  - {b:7d}  {pq}")

    return scanned, candidates, len(picked)


def main(argv: List[str]) -> int:
    ap = argparse.ArgumentParser(
        description="Generate a deterministic proof-completion fixture JSONL (order-independent)."
    )
    ap.add_argument(
        "--in", dest="in_path", required=True,
        help='Input JSONL (canonical backend full rows). Supports ".gz" and "-" for stdin.'
    )
    ap.add_argument("--out", dest="out_path", required=True, help="Output JSONL (committable fixture).")
    ap.add_argument("--k", type=int, default=200, help="Number of rows to write. Default: 200")

    ap.add_argument(
        "--salt",
        type=str,
        default="proof-completion.v0",
        help="Salt for deterministic hashing score. Default: proof-completion.v0",
    )

    body_group = ap.add_mutually_exclusive_group()
    body_group.add_argument(
        "--simple-only",
        action="store_true",
        help="Require body to be non-empty and contain no whitespace (v0 default).",
    )
    body_group.add_argument(
        "--all-bodies",
        action="store_true",
        help="Allow bodies with whitespace (multi-token / lambda / etc.).",
    )

    ap.add_argument(
        "--prefer-at-index",
        action="store_true",
        help="Further restrict to bodies matching ^@\\d+$ (good for testing @-resolution).",
    )

    ap.add_argument(
        "--no-require-typeast",
        action="store_true",
        help="Do not require (typeAstJson or typeAst) to be present. (Not recommended for v0.)",
    )
    ap.add_argument(
        "--no-require-fields",
        action="store_true",
        help='Do not require basic fields like prettyQname/file/type. (Not recommended.)',
    )

    ap.add_argument(
        "--max-per-module",
        type=int,
        default=None,
        help="Optional diversity cap: max examples per module_key (prettyModule or derived from prettyQname).",
    )
    ap.add_argument(
        "--oversample-factor",
        type=int,
        default=5,
        help="When --max-per-module is set, consider k*factor candidates before applying the cap. Default: 5",
    )
    ap.add_argument(
        "--minimal",
        action="store_true",
        help="Write only a curated subset of keys (keeps fixtures smaller).",
    )

    ap.add_argument("--max-ast-size", type=int, default=None, help="Skip rows with astSize > N (when astSize exists).")
    ap.add_argument("--max-typeast-bytes", type=int, default=None, help="Skip rows whose typeAst payload exceeds N bytes.")
    ap.add_argument("--max-row-bytes", type=int, default=None, help="Skip rows whose output JSON line exceeds N bytes.")
    ap.add_argument("--gzip", action="store_true", help="Write gzipped JSONL (recommended for committable fixtures).")
    ap.add_argument("--report-largest", type=int, default=0, help="Print the N largest rows (by output line bytes).")

    args = ap.parse_args(argv)

    simple_only = True
    if args.all_bodies:
        simple_only = False
    elif args.simple_only:
        simple_only = True
    # default is simple_only True

    scanned, candidates, written = build_fixture(
        in_path=args.in_path,
        out_path=args.out_path,
        k=max(0, args.k),
        salt=args.salt,
        simple_only=simple_only,
        require_typeast=not args.no_require_typeast,
        require_fields=not args.no_require_fields,
        max_per_module=args.max_per_module,
        oversample_factor=max(1, args.oversample_factor),
        minimal=args.minimal,
        prefer_at_index=args.prefer_at_index,
        max_ast_size=args.max_ast_size,
        max_typeast_bytes=args.max_typeast_bytes,
        max_row_bytes=args.max_row_bytes,
        gzip_out=args.gzip,
        report_largest=max(0, args.report_largest),
    )

    if args.gzip and not args.out_path.endswith(".gz"):
        _eprint('⚠️  --gzip enabled but --out does not end with ".gz" (that is fine, but surprising).')

    print(f"IN={args.in_path}")
    print(f"OUT={args.out_path}")
    print(f"scanned={scanned} candidates_after_filters={candidates} wrote={written}")

    try:
        sz = os.path.getsize(args.out_path)
        print(f"out_bytes={sz}")
    except Exception as exc:
        _eprint(f"⚠️  could not determine output size for {args.out_path!r}: {exc}")

    if written <= 0:
        _eprint("❌ wrote 0 rows. Try:")
        _eprint("  - removing --prefer-at-index")
        _eprint("  - using --all-bodies (if too restrictive)")
        _eprint("  - increasing --k")
        _eprint("  - adding/raising --oversample-factor if using --max-per-module")
        return 2

    if written < args.k:
        _eprint(f"⚠️  wrote fewer than requested: wrote={written} k={args.k}")
        if args.max_per_module is not None:
            _eprint("   (This can happen with --max-per-module; try raising --oversample-factor.)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

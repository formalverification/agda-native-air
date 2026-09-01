"""
File: scripts/python/corpus/mine_benchmark_candidates.py

Description: Mine benchmark-obligation candidates from a library corpus.

  The agda-algebras benchmark tier (issue #127) is cut from the corpus
  itself, so that the benchmark and the corpus can never drift apart:
  a candidate is a corpus row whose committed proof is a SINGLE TERM
  (the P1 term-mode searcher cannot restructure clauses, so a fixture
  whose gold needs pattern matching would price the tier out of the
  instrument it exists to calibrate).  This filter is the reproducible
  half of curation; the by-hand half (taxonomy tier, import stratum,
  deprecation checks against the library source) happens on its output.

  Usage, from the repository root:

    python3 scripts/python/corpus/mine_benchmark_candidates.py \
      --corpus data/corpora/agda-algebras/v0.1/corpus.jsonl.gz \
      --namespaces Overture,Setoid --max-body-chars 250

  Candidate rows (a projection of the corpus row: name, module, type,
  body, astSize) stream to stdout as JSONL; a one-line summary goes to
  stderr.

Design notes:

  Bodies in the corpus are Agda's pretty-printed internal terms.  Two
  facts drive the predicates below, both observed on the real corpus:
  clause-defined functions concatenate their clause bodies (so any
  multi-clause definition is long), and --cubical-compatible elaboration
  litters transport helpers with primTransp/primHComp/primComp — never
  surface syntax a fixture author could write.  `@N` de Bruijn markers
  for the definition's own binders are fine: they name the ∀-bound
  variables an obligation restates explicitly.
"""

from __future__ import annotations

import argparse
import gzip
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import IO, Iterator, Sequence, Tuple

# Elaboration artifacts that cannot appear in a hand-written gold term.
TRANSPORT_MARKERS: Tuple[str, ...] = ("primTransp", "primHComp", "primComp")

# Definitions Agda generates rather than the author: extended lambdas,
# with-functions, and absurd lambdas get .-prefixed or with-N segments.
GENERATED_NAME_MARKERS: Tuple[str, ...] = (".with-", ".extendedlambda", ".absurdlambda")


@dataclass(frozen=True)
class Candidate:
    """The projection of a corpus row that curation needs."""

    pretty_qname: str
    pretty_module: str
    type_: str
    body: str
    ast_size: int

    def to_json(self) -> str:
        return json.dumps(
            {
                "prettyQname": self.pretty_qname,
                "prettyModule": self.pretty_module,
                "type": self.type_,
                "body": self.body,
                "astSize": self.ast_size,
            },
            ensure_ascii=False,
        )


def open_corpus(path: Path) -> IO[str]:
    """Text handle over a corpus, transparently gunzipping *.gz."""
    if path.suffix == ".gz":
        return gzip.open(path, "rt", encoding="utf-8")
    return open(path, "r", encoding="utf-8")


def in_namespaces(qname: str, namespaces: Sequence[str]) -> bool:
    return any(qname.startswith(ns + ".") for ns in namespaces)


def is_generated_name(qname: str) -> bool:
    return any(marker in qname for marker in GENERATED_NAME_MARKERS)


def is_single_term_body(body: str, max_chars: int) -> bool:
    """A body a fixture author could restate as one proof term.

    Length bounds out multi-clause concatenations (and certificate-scale
    terms); the marker scan bounds out cubical transport helpers.
    """
    return (
        0 < len(body) <= max_chars
        and not any(marker in body for marker in TRANSPORT_MARKERS)
    )


def is_candidate(row: dict, namespaces: Sequence[str], max_body_chars: int) -> bool:
    return (
        row.get("defKind") == "function"
        and bool(row.get("hasBody"))
        and isinstance(row.get("body"), str)
        and in_namespaces(row.get("prettyQname", ""), namespaces)
        and not is_generated_name(row.get("prettyQname", ""))
        and is_single_term_body(row["body"], max_body_chars)
    )


def candidates_in(lines: Iterator[str], namespaces: Sequence[str], max_body_chars: int) -> Iterator[Candidate]:
    rows = (json.loads(line) for line in lines if line.strip())
    return (
        Candidate(
            pretty_qname=row["prettyQname"],
            pretty_module=row.get("prettyModule", ""),
            type_=row.get("type", ""),
            body=row["body"],
            ast_size=int(row.get("astSize", 0)),
        )
        for row in rows
        if is_candidate(row, namespaces, max_body_chars)
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Mine benchmark-obligation candidates from a corpus.")
    parser.add_argument("--corpus", type=Path, required=True, help="corpus.jsonl or corpus.jsonl.gz")
    parser.add_argument(
        "--namespaces",
        default="Overture,Setoid",
        help="comma-separated top-level namespaces to mine (default: Overture,Setoid)",
    )
    parser.add_argument(
        "--max-body-chars",
        type=int,
        default=250,
        help="single-term bound on the pretty-printed body (default: 250)",
    )
    args = parser.parse_args()

    namespaces = tuple(ns.strip() for ns in args.namespaces.split(",") if ns.strip())
    if not args.corpus.exists():
        print(f"error: no corpus at {args.corpus}", file=sys.stderr)
        return 1

    emitted = 0
    with open_corpus(args.corpus) as handle:
        for candidate in candidates_in(iter(handle), namespaces, args.max_body_chars):
            print(candidate.to_json())
            emitted += 1

    print(
        f"[mine-benchmark-candidates] {emitted} candidates "
        f"(namespaces={','.join(namespaces)}, max-body-chars={args.max_body_chars})",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

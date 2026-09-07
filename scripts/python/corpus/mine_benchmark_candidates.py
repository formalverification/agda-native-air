"""
File: scripts/python/corpus/mine_benchmark_candidates.py

Description: Mine benchmark-obligation candidates from a library corpus.

  The agda-algebras benchmark tier (issue #127) is cut from the corpus
  itself, so that the benchmark and the corpus can never drift apart:
  a candidate is a corpus row whose committed proof plausibly restates
  as a SINGLE TERM (the P1 term-mode searcher cannot restructure
  clauses, so a fixture whose gold needs pattern matching would price
  the tier out of the instrument it exists to calibrate).  This filter
  is the reproducible half of curation; the by-hand half (taxonomy
  tier, import stratum, deprecation checks against the library source,
  and the single-term restatement itself) happens on its output.

  Usage, from the repository root:

    python3 scripts/python/corpus/mine_benchmark_candidates.py \
      --corpus data/corpora/agda-algebras/v0.1/corpus.jsonl.gz \
      --namespaces Overture,Setoid --max-body-chars 250

  Candidate rows (a projection of the corpus row: name, module, type,
  body, astSize) stream to stdout as JSONL; a one-line summary goes to
  stderr.

Design notes:

  Bodies in the corpus are Agda's pretty-printed internal terms.  Three
  facts drive the predicates below, all observed on the real corpus:
  clause-defined functions join their clause bodies with newlines; the
  printer ALSO wraps long single terms across lines (on v0.1, 12 of the
  tier's 21 single-term source lemmas carry layout newlines), so a
  newline cannot serve as a clause signal; and --cubical-compatible
  elaboration litters transport helpers with primTransp/primHComp/
  primComp — never surface syntax a fixture author could write.  `@N`
  de Bruijn markers for the definition's own binders are fine: they name
  the ∀-bound variables an obligation restates explicitly.

  The length bound is therefore an APPROXIMATION of single-term-ness,
  tuned for recall: it rejects long clause concatenations and
  certificate-scale terms, but a short multi-clause definition passes
  it (#132 review).  The corpus schema records no per-row clause count —
  that field is the precise signal and is tracked as an agda-strux
  follow-up — so single-term-ness is ESTABLISHED during the by-hand
  half: a candidate only becomes a fixture once its gold is restated
  and type-checked as one term.
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


def is_candidate_body(body: str, max_chars: int) -> bool:
    """A body a fixture author could PLAUSIBLY restate as one proof term.

    An approximation, not a guarantee (see the module design notes): the
    length bound rejects long clause concatenations and certificate-scale
    terms but admits a short multi-clause body, and newlines are layout
    as often as clause joins, so they are deliberately not consulted.
    The marker scan bounds out cubical transport helpers.  Single-term-
    ness is established downstream, when the gold is authored and
    type-checked as one term.
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
        and is_candidate_body(row["body"], max_body_chars)
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

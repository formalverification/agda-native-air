"""
File: scripts/python/corpus/check_haystack_exclusion.py

Description: Check the haystack benchmark tier's exclusion constraints against
  a library corpus.

  The haystack tier (issue #129, `data/benchmarks/agda-stdlib-haystack-v0/`)
  exists to measure retrieval, so its obligations are built so that the P2
  target-exclusion policy has nothing to fire on: the gold lemma's bare name
  must differ from the hole's name, and the obligation's stated type must not
  normalize to any corpus row's type.  This script is the mechanical half of
  that promise.  For every selected index row it reports, against every row
  of the corpus, the following three checks:

    name       the hole name is not the `prettyName` of ANY corpus row (the
               proposer's rule is scoped to the fixture's imports; the check
               here is deliberately wider, so a fixture cannot drift into a
               collision when its imports change);
    statement  the stated type does not normalize to a corpus row's type
               under the proposer's own normalization (`Statements.normalize`
               in strux-driver's Retrieve.scala: whitespace collapsed, `∀`
               dropped, binder names renamed positionally), reimplemented
               below token for token;
    nearAlias  a stricter reading of the statement rule with teeth on real
               data: corpus types are printed fully qualified and the index
               prose is not (`Agda.Builtin.Nat.+` against `+`), so the
               proposer's syntactic rule can never match them; after
               dequalifying every token and dropping parentheses, an
               expanded-form alias IS caught (`∀ (m n : ℕ) → m + suc n ≡
               suc (m + n)` against `+-suc`), while a diagonal or
               hypothesis-consuming instance is not.  Alias-typed rows
               (`Commutative _+_`) stay outside its reach; the lane-form
               check inside the retrieval sweep covers those.

  Usage, from the repository root:

    python3 scripts/python/corpus/check_haystack_exclusion.py \
      --corpus data/corpora/agda-stdlib/v0/corpus.jsonl \
      --index data/benchmarks/benchmark-index.jsonl --tag stratum:haystack

  One JSON verdict per selected row streams to stdout; a summary goes to
  stderr; the exit code is 0 only when every row passes all three checks.

Design notes:

  Like its sibling `mine_benchmark_candidates.py`, this is a pure predicate
  over corpus rows behind a thin streaming shell: the normalization and the
  checks are total functions over strings and tuples, tested directly; the
  corpus is streamed once and projected to the four fields the checks read.
"""

from __future__ import annotations

import argparse
import gzip
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import IO, Dict, Iterator, Sequence, Tuple

DELIMS: frozenset = frozenset("(){}⦃⦄")
OPENERS: frozenset = frozenset("({⦃")
# Corpus types print builtin naturals as `Agda.Builtin.Nat.Nat`; fixtures write
# the standard library's `ℕ`.  One spelling for the near-alias comparison.
DEQUALIFIED_SPELLINGS: Dict[str, str] = {"Nat": "ℕ"}


@dataclass(frozen=True)
class CorpusRow:
    """The projection of a corpus row the checks read."""

    pretty_qname: str
    pretty_name: str
    pretty_module: str
    tpe: str


@dataclass(frozen=True)
class IndexRow:
    """The projection of a benchmark-index row the checks read."""

    id: str
    hole: str
    tpe: str
    gold_term: str
    tags: Tuple[str, ...]


@dataclass(frozen=True)
class Verdict:
    """What one index row's checks found: the offending corpus qnames per rule."""

    id: str
    hole: str
    needle: str
    needle_in_corpus: bool
    name_hits: Tuple[str, ...]
    statement_hits: Tuple[str, ...]
    near_alias_hits: Tuple[str, ...]

    @property
    def passed(self) -> bool:
        return not (self.name_hits or self.statement_hits or self.near_alias_hits)

    def to_json(self) -> Dict:
        return {
            "id": self.id,
            "hole": self.hole,
            "needle": self.needle,
            "needleInCorpus": self.needle_in_corpus,
            "name": list(self.name_hits),
            "statement": list(self.statement_hits),
            "nearAlias": list(self.near_alias_hits),
            "passed": self.passed,
        }


# ---------------------------------------------------------------------------
# The proposer's normalization, token for token (Retrieve.scala, `Statements`)
# ---------------------------------------------------------------------------

def tokens(s: str) -> Tuple[str, ...]:
    """Tokenize as the proposer does: delimiters are single tokens, everything
    else splits on whitespace."""
    out = []
    cur = []
    for c in s:
        if c.isspace():
            if cur:
                out.append("".join(cur))
                cur = []
        elif c in DELIMS:
            if cur:
                out.append("".join(cur))
                cur = []
            out.append(c)
        else:
            cur.append(c)
    if cur:
        out.append("".join(cur))
    return tuple(out)


def binder_names(ts: Sequence[str]) -> Tuple[str, ...]:
    """The binder names of a token stream: inside each opened group, the tokens
    before a `:` at that group's own level; a group without a `:` binds nothing."""
    names = []
    for i, t in enumerate(ts):
        if t in OPENERS:
            pending = []
            for u in ts[i + 1:]:
                if u == ":":
                    names.extend(pending)
                    break
                if u in DELIMS:
                    break
                pending.append(u)
    return tuple(names)


def rename_positionally(ts: Sequence[str]) -> Tuple[str, ...]:
    """Rename binder names to x1, x2, … in order of first binding."""
    seen = []
    for n in binder_names(ts):
        if n not in seen:
            seen.append(n)
    renames = {n: f"x{i + 1}" for i, n in enumerate(seen)}
    return tuple(renames.get(t, t) for t in ts)


def normalize(stmt: str) -> str:
    """`Statements.normalize`: whitespace collapsed, `∀` dropped, binders renamed
    positionally."""
    return " ".join(rename_positionally(tuple(t for t in tokens(stmt) if t != "∀")))


# ---------------------------------------------------------------------------
# The stricter near-alias reading
# ---------------------------------------------------------------------------

def dequalify_token(t: str) -> str:
    """A token reduced to its last dot segment (`Agda.Builtin.Nat.+` → `+`), with
    the builtin spelling mapped to the fixtures' (`Nat` → `ℕ`).  Delimiters and
    operator glyphs carry no dots and pass through."""
    seg = t[t.rfind(".") + 1:] if "." in t and not t.startswith(".") else t
    return DEQUALIFIED_SPELLINGS.get(seg, seg)


def dequalify(stmt: str) -> str:
    """The near-alias form: tokens dequalified, `∀` and parentheses dropped (the
    corpus parenthesizes infix applications the index prose leaves bare), then
    binders renamed positionally."""
    ts = tuple(dequalify_token(t) for t in tokens(stmt) if t != "∀")
    return " ".join(rename_positionally(tuple(t for t in ts if t not in ("(", ")"))))


# ---------------------------------------------------------------------------
# The checks
# ---------------------------------------------------------------------------

def needle_of(gold_term: str) -> str:
    """The head of a single-application gold: its first whitespace-separated
    token, the qualified needle name."""
    parts = gold_term.split()
    return parts[0] if parts else ""


def check_row(row: IndexRow, corpus: Sequence[CorpusRow]) -> Verdict:
    """All three checks for one index row against the whole corpus."""
    stmt = normalize(row.tpe)
    near = dequalify(row.tpe)
    needle = needle_of(row.gold_term)
    return Verdict(
        id=row.id,
        hole=row.hole,
        needle=needle,
        needle_in_corpus=any(c.pretty_qname == needle for c in corpus),
        name_hits=tuple(c.pretty_qname for c in corpus if c.pretty_name == row.hole),
        statement_hits=tuple(c.pretty_qname for c in corpus if normalize(c.tpe) == stmt),
        near_alias_hits=tuple(c.pretty_qname for c in corpus if dequalify(c.tpe) == near),
    )


def check_rows(rows: Sequence[IndexRow], corpus: Sequence[CorpusRow]) -> Tuple[Verdict, ...]:
    return tuple(check_row(r, corpus) for r in rows)


# ---------------------------------------------------------------------------
# Streaming shell
# ---------------------------------------------------------------------------

def corpus_row(raw: Dict) -> CorpusRow:
    return CorpusRow(
        pretty_qname=str(raw.get("prettyQname", "")),
        pretty_name=str(raw.get("prettyName", "")),
        pretty_module=str(raw.get("prettyModule", "")),
        tpe=str(raw.get("type", "")),
    )


def index_row(raw: Dict) -> IndexRow:
    return IndexRow(
        id=str(raw.get("id", "")),
        hole=str(raw.get("hole", "")),
        tpe=str(raw.get("type", "")),
        gold_term=str(raw.get("goldTerm", "")),
        tags=tuple(str(t) for t in raw.get("tags", ())),
    )


def read_jsonl(handle: IO[str]) -> Iterator[Dict]:
    return (json.loads(line) for line in handle if line.strip())


def open_text(path: Path) -> IO[str]:
    """Plain or gzip-compressed text, by suffix."""
    if path.suffix == ".gz":
        return gzip.open(path, "rt", encoding="utf-8")
    return open(path, "r", encoding="utf-8")


def select(rows: Iterator[IndexRow], tag: str, ids: Tuple[str, ...]) -> Tuple[IndexRow, ...]:
    """The index rows to check: those carrying `tag`, or those named in `ids`."""
    return tuple(r for r in rows if (tag and tag in r.tags) or r.id in ids)


def main(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--corpus", type=Path, required=True, help="corpus.jsonl or corpus.jsonl.gz")
    parser.add_argument("--index", type=Path, required=True, help="benchmark-index.jsonl")
    parser.add_argument("--tag", default="stratum:haystack", help="check the rows carrying this tag (default stratum:haystack)")
    parser.add_argument("--ids", default="", help="also check these comma-separated ids")
    args = parser.parse_args(argv)

    ids = tuple(i.strip() for i in args.ids.split(",") if i.strip())
    with open_text(args.index) as h:
        rows = select((index_row(r) for r in read_jsonl(h)), args.tag, ids)
    with open_text(args.corpus) as h:
        corpus = tuple(corpus_row(r) for r in read_jsonl(h))

    verdicts = check_rows(rows, corpus)
    for v in verdicts:
        sys.stdout.write(json.dumps(v.to_json(), ensure_ascii=False) + "\n")
    failed = [v for v in verdicts if not v.passed]
    sys.stderr.write(
        f"check_haystack_exclusion: {len(verdicts)} rows against {len(corpus)} corpus rows; "
        f"{len(verdicts) - len(failed)} passed, {len(failed)} failed\n"
    )
    return 0 if verdicts and not failed else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

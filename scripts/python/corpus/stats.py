#!/usr/bin/env python3
"""
File: scripts/python/corpus/stats.py

Description: Summary statistics for an agda-strux JSONL corpus.

  Reads a corpus assembled by `scripts/python/corpus/assemble.py` and reports
  what a dataset card has to state:

    +  definitions by kind and by top-level namespace;
    +  module count, and definitions per module;
    +  type and term size distributions (`astSize`, body length, Π-arity);
    +  dependency-graph shape, both at definition level (from each row's
       `dependencies`) and at module level (from Agda's own
       `--dependency-graph` DOT file, when one is supplied).

  Outputs `stats.json` (the machine-readable record) and `stats.md` (the same
  numbers as tables, for the card and the release).

Design Principles:
  +  Pure core.  Each row is projected once into a small immutable
     `RowSummary`; every statistic is a pure function over those summaries.
     Only `load_corpus` and `main` touch the filesystem.
  +  Streaming projection.  A corpus row carries a full `typeAst` and runs to
     hundreds of kilobytes, so rows are projected as they are read and the
     parsed JSON is dropped immediately.
  +  Say what is external.  A dependency token that resolves to no definition
     in the corpus is a real edge to somewhere else (the standard library,
     Agda's primitives).  Counting those separately is the difference between
     a graph statistic and a guess.
"""

from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Optional, Sequence, Tuple

from scripts.python.utils.file_ops import read_text, write_json
from scripts.python.utils.pipeline_types import (
    ErrorType,
    PipelineError,
    Result,
)

STATS_SCHEMA = "agda-strux.stats.v0"

# Percentiles reported for every size distribution.  p50/p90/p99 say more about
# a heavy-tailed corpus than a mean does, and Agda types are heavy-tailed.
PERCENTILES: Tuple[int, ...] = (50, 75, 90, 95, 99)

# How many entries to list for "most depended upon" style rankings.
TOP_N = 20

# Node lines in Agda's --dependency-graph output: `m3[label="Overture.Basic"];`
_DOT_NODE = re.compile(r'^\s*(\w+)\s*\[label="([^"]*)"\]')
# Edge lines: `m3 -> m7;`
_DOT_EDGE = re.compile(r"^\s*(\w+)\s*->\s*(\w+)")


# ---------------------------------------------------------------------------
# Domain types
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class RowSummary:
    """The projection of one corpus row that every statistic here is computed from."""

    pretty_qname: str
    pretty_name: str
    module: str
    namespace: str
    def_kind: str
    type_ast_version: str
    ast_size: int
    body_size: int
    has_body: bool
    pi_arity: int
    dependencies: Tuple[str, ...]


@dataclass(frozen=True)
class Distribution:
    """A size distribution, in the terms a card quotes."""

    count: int
    total: int
    minimum: int
    maximum: int
    mean: float
    median: float
    percentiles: Dict[str, int]

    def to_json(self) -> Dict:
        return {
            "count": self.count,
            "total": self.total,
            "min": self.minimum,
            "max": self.maximum,
            "mean": round(self.mean, 2),
            "median": round(self.median, 2),
            "percentiles": dict(self.percentiles),
        }


# ---------------------------------------------------------------------------
# Pure core — projection
# ---------------------------------------------------------------------------


def namespace_of(module: str) -> str:
    """The library subtree a module lives in: `Overture.Basic` -> `Overture`."""
    return module.split(".", 1)[0] if module else ""


def pi_arity(type_ast: object) -> int:
    """Number of top-level Π binders in a `typeAst` (0.3-v0 encoding).

    This is the definition's *interface width* — how many arguments, implicit
    and explicit, a caller must supply before reaching the codomain.  It is
    read structurally rather than by counting arrows in the pretty-printed
    type, which would also count arrows nested inside arguments.
    """
    depth = 0
    node = type_ast
    while isinstance(node, dict):
        term = node.get("term") if node.get("tag") == "Type" else node
        if not isinstance(term, dict) or term.get("tag") != "Pi":
            return depth
        depth += 1
        node = term.get("cod")
    return depth


def project_row(row: Dict) -> RowSummary:
    """Project one canonical JSONL row (docs/representation.md §3) for statistics."""
    module = str(row.get("prettyModule", "") or row.get("module", ""))
    body = row.get("body")
    return RowSummary(
        pretty_qname=str(row.get("prettyQname", "")),
        pretty_name=str(row.get("prettyName", "")),
        module=module,
        namespace=namespace_of(module),
        def_kind=str(row.get("defKind", "unknown")),
        type_ast_version=str(row.get("typeAstVersion", "")),
        # `astSize` is the backend's own measure (length of the pretty type);
        # fall back to measuring the string so a row missing the field still
        # contributes rather than skewing the distribution to zero.
        ast_size=int(row.get("astSize", len(str(row.get("type", ""))))),
        body_size=len(body) if isinstance(body, str) else 0,
        has_body=bool(row.get("hasBody", isinstance(body, str) and bool(body))),
        pi_arity=pi_arity(row.get("typeAst")),
        dependencies=tuple(str(d) for d in row.get("dependencies", [])),
    )


# ---------------------------------------------------------------------------
# Pure core — statistics
# ---------------------------------------------------------------------------


def percentile(values: Sequence[int], p: int) -> int:
    """Nearest-rank percentile of a sorted-on-demand sequence.

    Nearest rank (rather than an interpolating definition) keeps every reported
    number a value that actually occurs in the corpus.
    """
    if not values:
        return 0
    ordered = sorted(values)
    rank = max(1, min(len(ordered), (p * len(ordered) + 99) // 100))
    return ordered[rank - 1]


def distribution(values: Sequence[int]) -> Distribution:
    """Summarize a size distribution; an empty input summarizes to zeros."""
    if not values:
        return Distribution(0, 0, 0, 0, 0.0, 0.0, {f"p{p}": 0 for p in PERCENTILES})
    return Distribution(
        count=len(values),
        total=sum(values),
        minimum=min(values),
        maximum=max(values),
        mean=statistics.fmean(values),
        median=statistics.median(values),
        percentiles={f"p{p}": percentile(values, p) for p in PERCENTILES},
    )


def counts_by(key: Callable[[RowSummary], str], rows: Sequence[RowSummary]) -> Dict[str, int]:
    """Frequency table over a projection of the rows, largest first."""
    tally: Dict[str, int] = {}
    for row in rows:
        k = key(row)
        tally[k] = tally.get(k, 0) + 1
    return dict(sorted(tally.items(), key=lambda kv: (-kv[1], kv[0])))


def top_n(tally: Dict[str, int], n: int = TOP_N) -> List[Dict[str, object]]:
    """The n largest entries of a frequency table, as a JSON-friendly list."""
    return [{"name": k, "count": v} for k, v in list(tally.items())[:n]]


def looks_qualified(token: str) -> bool:
    """Whether a dependency token even has the shape of a qualified name.

    Tokens are tokenized out of a pretty-printed type, so the list also holds
    bound variables (`ρᵃ`, `lc`), bare words (`OK`), and truncations that end
    in a dot (`Agda.Primitive.`).  A token with at least one interior dot and
    no empty segment could denote a definition somewhere else; the rest could
    not.  This is a *shape* test and nothing more — it says a token is
    eligible to be a name, not that any name exists.
    """
    parts = token.split(".")
    return len(parts) > 1 and all(parts)


@dataclass(frozen=True)
class DefinitionGraph:
    """Definition-level dependency shape, computed from the rows' `dependencies`.

    Nodes are `prettyQname`s, and rows sharing one are merged (their dependency
    tokens unioned), so every quantity here is at the same granularity.
    Counting 11,666 rows as sources against 10,520 named nodes — which an
    earlier version did — makes out-degree and in-degree describe different
    graphs.
    """

    rows: int
    nodes: int
    collapsed_rows: int
    internal_edges: int
    unresolved_occurrences: int
    unresolved_qualified_looking: int
    distinct_unresolved: int
    self_loops: int
    out_degree: Distribution
    in_degree: Distribution
    most_depended_upon: List[Dict[str, object]]
    most_referenced_unresolved: List[Dict[str, object]]

    def to_json(self) -> Dict:
        return {
            "rows": self.rows,
            "nodes": self.nodes,
            "collapsedRows": self.collapsed_rows,
            "internalEdges": self.internal_edges,
            "unresolvedOccurrences": self.unresolved_occurrences,
            "unresolvedQualifiedLooking": self.unresolved_qualified_looking,
            "distinctUnresolvedTokens": self.distinct_unresolved,
            "selfLoops": self.self_loops,
            "outDegree": self.out_degree.to_json(),
            "inDegreeInternal": self.in_degree.to_json(),
            "mostDependedUpon": self.most_depended_upon,
            "mostReferencedUnresolved": self.most_referenced_unresolved,
        }


def definition_graph(rows: Sequence[RowSummary]) -> DefinitionGraph:
    """Dependency shape at definition level, keyed by `prettyQname`.

    An edge is *internal* when its token names a definition in this corpus.  A
    token that names none is reported as an **unresolved token occurrence**,
    not as an edge leaving the corpus: `dependencies` is heuristic, and calling
    every unmatched token an external dependency would count `ρᵃ` and
    `Agda.Primitive.` among a definition's dependencies.  `looks_qualified`
    splits out the subset that could denote something elsewhere, which is a
    lower bound on the real outward edges — resolving them properly needs an
    index of the standard library, which this corpus does not have.

    Even so, the split is the number that matters when choosing a corpus for
    retrieval: a graph with as many outward candidates as internal edges is a
    different object from a closed one.
    """
    # Merge rows that share a name, unioning their tokens: 1,146 of
    # agda-algebras' 11,666 rows share a `prettyQname` with another row.
    targets_by_name: Dict[str, Dict[str, None]] = {}
    for row in rows:
        if not row.pretty_qname:
            continue
        merged = targets_by_name.setdefault(row.pretty_qname, {})
        # dict-as-ordered-set: two occurrences of one token are one dependency.
        for token in row.dependencies:
            merged.setdefault(token, None)

    known = set(targets_by_name)

    internal_in: Dict[str, int] = {}
    unresolved_hits: Dict[str, int] = {}
    internal_edges = 0
    unresolved_occurrences = 0
    unresolved_qualified = 0
    self_loops = 0
    out_degrees: List[int] = []

    for name, targets in targets_by_name.items():
        out_degrees.append(len(targets))
        for token in targets:
            if token in known:
                internal_edges += 1
                if token == name:
                    self_loops += 1
                internal_in[token] = internal_in.get(token, 0) + 1
            else:
                unresolved_occurrences += 1
                if looks_qualified(token):
                    unresolved_qualified += 1
                unresolved_hits[token] = unresolved_hits.get(token, 0) + 1

    in_degrees = [internal_in.get(name, 0) for name in known]
    ranked_internal = dict(sorted(internal_in.items(), key=lambda kv: (-kv[1], kv[0])))
    ranked_unresolved = dict(sorted(unresolved_hits.items(), key=lambda kv: (-kv[1], kv[0])))

    return DefinitionGraph(
        rows=len(rows),
        nodes=len(known),
        collapsed_rows=len(rows) - len(known),
        internal_edges=internal_edges,
        unresolved_occurrences=unresolved_occurrences,
        unresolved_qualified_looking=unresolved_qualified,
        distinct_unresolved=len(unresolved_hits),
        self_loops=self_loops,
        out_degree=distribution(out_degrees),
        in_degree=distribution(in_degrees),
        most_depended_upon=top_n(ranked_internal),
        most_referenced_unresolved=top_n(ranked_unresolved),
    )


@dataclass(frozen=True)
class ModuleGraph:
    """Module-level import shape, read from Agda's own dependency graph."""

    nodes: int
    edges: int
    roots: int
    leaves: int
    longest_path: Optional[int]
    acyclic: bool
    out_degree: Distribution
    in_degree: Distribution
    most_imported: List[Dict[str, object]]

    def to_json(self) -> Dict:
        return {
            "nodes": self.nodes,
            "edges": self.edges,
            "roots": self.roots,
            "leaves": self.leaves,
            "longestPath": self.longest_path,
            "acyclic": self.acyclic,
            "outDegree": self.out_degree.to_json(),
            "inDegree": self.in_degree.to_json(),
            "mostImported": self.most_imported,
        }


def parse_dot(text: str, exclude: Sequence[str] = ()) -> Tuple[Tuple[str, ...], Tuple[Tuple[str, str], ...]]:
    """Node labels and label-to-label edges from an Agda `--dependency-graph` DOT.

    `exclude` drops synthetic roots (the metadata script's `MetadataEverything`
    imports every module and would otherwise dominate every degree statistic).
    """
    ids: Dict[str, str] = {}
    for line in text.splitlines():
        m = _DOT_NODE.match(line)
        if m:
            ids[m.group(1)] = m.group(2)

    dropped = set(exclude)
    nodes = tuple(sorted(label for label in ids.values() if label not in dropped))

    edges: List[Tuple[str, str]] = []
    for line in text.splitlines():
        m = _DOT_EDGE.match(line)
        if not m:
            continue
        src, dst = ids.get(m.group(1)), ids.get(m.group(2))
        if src and dst and src not in dropped and dst not in dropped:
            edges.append((src, dst))
    return nodes, tuple(sorted(set(edges)))


def longest_path_length(
    nodes: Sequence[str], edges: Sequence[Tuple[str, str]]
) -> Optional[int]:
    """Longest path in a DAG, in edges; `None` when the graph has a cycle.

    Computed by Kahn topological order plus one relaxation pass, which is
    linear and needs no recursion (some import chains are deep).
    """
    succ: Dict[str, List[str]] = {n: [] for n in nodes}
    indeg: Dict[str, int] = {n: 0 for n in nodes}
    for src, dst in edges:
        if src in succ and dst in indeg:
            succ[src].append(dst)
            indeg[dst] += 1

    order: List[str] = [n for n in nodes if indeg[n] == 0]
    remaining = dict(indeg)
    topo: List[str] = []
    while order:
        node = order.pop()
        topo.append(node)
        for nxt in succ[node]:
            remaining[nxt] -= 1
            if remaining[nxt] == 0:
                order.append(nxt)

    if len(topo) != len(nodes):
        return None

    depth: Dict[str, int] = {n: 0 for n in nodes}
    for node in topo:
        for nxt in succ[node]:
            depth[nxt] = max(depth[nxt], depth[node] + 1)
    return max(depth.values()) if depth else 0


def module_graph(text: str, exclude: Sequence[str] = ()) -> ModuleGraph:
    """Module-level shape from a DOT dependency graph."""
    nodes, edges = parse_dot(text, exclude)

    out_tally: Dict[str, int] = {n: 0 for n in nodes}
    in_tally: Dict[str, int] = {n: 0 for n in nodes}
    for src, dst in edges:
        out_tally[src] = out_tally.get(src, 0) + 1
        in_tally[dst] = in_tally.get(dst, 0) + 1

    ranked = dict(sorted(in_tally.items(), key=lambda kv: (-kv[1], kv[0])))
    longest = longest_path_length(nodes, edges)

    return ModuleGraph(
        nodes=len(nodes),
        edges=len(edges),
        roots=sum(1 for n in nodes if in_tally.get(n, 0) == 0),
        leaves=sum(1 for n in nodes if out_tally.get(n, 0) == 0),
        longest_path=longest,
        acyclic=longest is not None,
        out_degree=distribution([out_tally[n] for n in nodes]),
        in_degree=distribution([in_tally[n] for n in nodes]),
        most_imported=top_n(ranked),
    )


def build_stats(
    rows: Sequence[RowSummary],
    library: str,
    dot_text: Optional[str],
    dot_exclude: Sequence[str],
) -> Dict:
    """The `stats.json` document: every statistic, computed purely from `rows`."""
    by_module = counts_by(lambda r: r.module, rows)
    bodies = [r.body_size for r in rows if r.has_body and r.body_size > 0]

    stats: Dict = {
        "schema": STATS_SCHEMA,
        "library": library,
        "totals": {
            "definitions": len(rows),
            "distinctPrettyQnames": len({r.pretty_qname for r in rows}),
            "modules": len(by_module),
            "namespaces": len(counts_by(lambda r: r.namespace, rows)),
            "withBody": sum(1 for r in rows if r.has_body),
            "typeAstVersions": counts_by(lambda r: r.type_ast_version, rows),
        },
        "byDefKind": counts_by(lambda r: r.def_kind, rows),
        "byNamespace": counts_by(lambda r: r.namespace, rows),
        "definitionsPerModule": distribution(list(by_module.values())).to_json(),
        "largestModules": top_n(by_module),
        "sizes": {
            "typeLength": distribution([r.ast_size for r in rows]).to_json(),
            "bodyLength": distribution(bodies).to_json(),
            "piArity": distribution([r.pi_arity for r in rows]).to_json(),
        },
        "dependencyGraph": definition_graph(rows).to_json(),
    }

    if dot_text is not None:
        stats["moduleGraph"] = module_graph(dot_text, dot_exclude).to_json()

    return stats


# ---------------------------------------------------------------------------
# Pure core — Markdown rendering
# ---------------------------------------------------------------------------


def _table(header: Sequence[str], rows: Iterable[Sequence[object]]) -> str:
    """A GitHub-flavoured Markdown table."""
    lines = [
        "| " + " | ".join(header) + " |",
        "|" + "|".join(["---"] * len(header)) + "|",
    ]
    lines.extend("| " + " | ".join(str(c) for c in row) + " |" for row in rows)
    return "\n".join(lines)


def _distribution_rows(name: str, d: Dict) -> Sequence[object]:
    p = d["percentiles"]
    return (name, d["count"], d["min"], d["median"], p["p90"], p["p99"], d["max"], d["mean"])


def render_markdown(stats: Dict) -> str:
    """Render `stats.json` as the tables a dataset card and a release quote."""
    totals = stats["totals"]
    sizes = stats["sizes"]
    dep = stats["dependencyGraph"]

    parts: List[str] = [
        f"# Corpus statistics — {stats['library']}",
        "",
        f"Schema `{stats['schema']}`.  Generated by `scripts/python/corpus/stats.py`.",
        "",
        "## Totals",
        "",
        _table(
            ("Quantity", "Value"),
            (
                ("Definitions (rows)", totals["definitions"]),
                ("Distinct `prettyQname`", totals["distinctPrettyQnames"]),
                ("Modules", totals["modules"]),
                ("Top-level namespaces", totals["namespaces"]),
                ("Definitions with a body", totals["withBody"]),
            ),
        ),
        "",
        "## Definitions by kind",
        "",
        _table(("Kind", "Count"), sorted(stats["byDefKind"].items(), key=lambda kv: -kv[1])),
        "",
        "## Definitions by namespace",
        "",
        _table(("Namespace", "Count"), sorted(stats["byNamespace"].items(), key=lambda kv: -kv[1])),
        "",
        "## Size distributions",
        "",
        _table(
            ("Measure", "n", "min", "median", "p90", "p99", "max", "mean"),
            (
                _distribution_rows("Type length (chars)", sizes["typeLength"]),
                _distribution_rows("Body length (chars)", sizes["bodyLength"]),
                _distribution_rows("Π-arity (binders)", sizes["piArity"]),
                _distribution_rows("Definitions per module", stats["definitionsPerModule"]),
            ),
        ),
        "",
        "## Dependency graph (definition level)",
        "",
        "Nodes are `prettyQname`s; rows sharing a name are merged and their "
        "dependency tokens unioned, so every quantity below is at one "
        "granularity.  A token matching no definition here is an *unresolved "
        "token*, not an edge leaving the corpus: `dependencies` is heuristic "
        "and holds bound variables and truncated names as well as real ones.  "
        "The qualified-looking subset is a lower bound on the real outward "
        "edges.",
        "",
        _table(
            ("Quantity", "Value"),
            (
                ("Corpus rows", dep["rows"]),
                ("Nodes (distinct names)", dep["nodes"]),
                ("Rows merged into a shared name", dep["collapsedRows"]),
                ("Edges within the corpus", dep["internalEdges"]),
                ("Unresolved token occurrences", dep["unresolvedOccurrences"]),
                ("…of which qualified-looking", dep["unresolvedQualifiedLooking"]),
                ("Distinct unresolved tokens", dep["distinctUnresolvedTokens"]),
                ("Self-loops (recursive definitions)", dep["selfLoops"]),
            ),
        ),
        "",
        "### Most depended upon, within the corpus",
        "",
        _table(
            ("Definition", "In-degree"),
            ((e["name"], e["count"]) for e in dep["mostDependedUpon"]),
        ),
        "",
        "### Most referenced unresolved tokens",
        "",
        _table(
            ("Token", "Occurrences"),
            ((e["name"], e["count"]) for e in dep["mostReferencedUnresolved"]),
        ),
    ]

    if "moduleGraph" in stats:
        mod = stats["moduleGraph"]
        parts.extend(
            [
                "",
                "## Import graph (module level)",
                "",
                _table(
                    ("Quantity", "Value"),
                    (
                        ("Modules", mod["nodes"]),
                        ("Import edges", mod["edges"]),
                        ("Roots (nothing imports them)", mod["roots"]),
                        ("Leaves (import nothing)", mod["leaves"]),
                        ("Longest import chain (edges)", mod["longestPath"]),
                        ("Acyclic", mod["acyclic"]),
                    ),
                ),
                "",
                "### Most imported modules",
                "",
                _table(
                    ("Module", "In-degree"),
                    ((e["name"], e["count"]) for e in mod["mostImported"]),
                ),
            ]
        )

    return "\n".join(parts) + "\n"


# ---------------------------------------------------------------------------
# Effectful shell
# ---------------------------------------------------------------------------


def load_corpus(path: Path) -> Result[Tuple[RowSummary, ...], PipelineError]:
    """Project every row of a JSONL corpus, one row at a time."""
    rows: List[RowSummary] = []
    try:
        with path.open("r", encoding="utf-8") as handle:
            for lineno, line in enumerate(handle, start=1):
                line = line.strip()
                if not line:
                    continue
                try:
                    rows.append(project_row(json.loads(line)))
                except json.JSONDecodeError as exc:
                    return Result.err(
                        PipelineError(
                            ErrorType.PARSING_ERROR,
                            f"{path}:{lineno} is not valid JSON",
                            cause=exc,
                        )
                    )
    except OSError as exc:
        return Result.err(
            PipelineError(ErrorType.FILE_NOT_FOUND, f"cannot read {path}", cause=exc)
        )

    if not rows:
        return Result.err(
            PipelineError(ErrorType.VALIDATION_ERROR, f"{path} contains no rows")
        )
    return Result.ok(tuple(rows))


def compute(args: argparse.Namespace) -> Result[Dict, PipelineError]:
    """Load the corpus, optionally the DOT graph, and build the statistics."""
    dot_text: Optional[str] = None
    if args.dependency_graph:
        dot = read_text(Path(args.dependency_graph))
        if dot.is_err:
            return Result.err(dot.unwrap_err())
        dot_text = dot.unwrap()

    return load_corpus(Path(args.corpus)).map(
        lambda rows: build_stats(rows, args.library, dot_text, tuple(args.dot_exclude))
    )


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _summary() -> str:
    """The `Description:` line of this module's docstring, for `--help`.

    Read by name rather than by line number: indexing into `__doc__` silently
    produced an empty description the first time.
    """
    for line in (__doc__ or "").splitlines():
        if line.startswith("Description:"):
            return line.split(":", 1)[1].strip()
    return ""


def _parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=_summary())
    p.add_argument("--corpus", required=True, help="assembled corpus.jsonl")
    p.add_argument("--out-dir", required=True, help="where to write stats.json and stats.md")
    p.add_argument("--library", default="agda-algebras", help="library name for the record")
    p.add_argument(
        "--dependency-graph",
        default=None,
        help="Agda --dependency-graph DOT file, for module-level shape",
    )
    p.add_argument(
        "--dot-exclude",
        nargs="*",
        default=["MetadataEverything"],
        help="node labels to drop from the module graph (synthetic roots)",
    )
    return p


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = _parser().parse_args(argv)
    result = compute(args)

    if result.is_err:
        print(f"[stats] {result.unwrap_err()}", file=sys.stderr)
        return 1

    stats = result.unwrap()
    out_dir = Path(args.out_dir)
    json_path = out_dir / "stats.json"
    md_path = out_dir / "stats.md"

    written = write_json(json_path, stats)
    if written.is_err:
        print(f"[stats] {written.unwrap_err()}", file=sys.stderr)
        return 1

    try:
        md_path.parent.mkdir(parents=True, exist_ok=True)
        md_path.write_text(render_markdown(stats), encoding="utf-8")
    except OSError as exc:
        print(f"[stats] cannot write {md_path}: {exc}", file=sys.stderr)
        return 1

    totals = stats["totals"]
    print(f"[stats] {json_path}")
    print(f"[stats] {md_path}")
    print(
        f"[stats] {totals['definitions']} definitions in {totals['modules']} modules; "
        f"{totals['withBody']} with a body"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""
Tests for `scripts/python/corpus/stats.py`.

File: scripts/python/tests/test_corpus_stats.py

Description
-----------
Every statistic here is a pure function over `RowSummary` values, so the tests
are direct: build rows, assert the number.  The cases that matter are the ones
a dataset card would get wrong on its own — Π-arity read structurally rather
than by counting arrows, and the split between dependency edges that stay
inside the corpus and edges that leave it for the standard library.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_corpus_stats.py`
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Sequence

from scripts.python.corpus.stats import (
    RowSummary,
    _summary,
    build_stats,
    counts_by,
    definition_graph,
    distribution,
    load_corpus,
    longest_path_length,
    module_graph,
    namespace_of,
    parse_dot,
    percentile,
    pi_arity,
    project_row,
    render_markdown,
)


def row(
    qname: str,
    *,
    kind: str = "function",
    ast_size: int = 10,
    body_size: int = 0,
    arity: int = 0,
    deps: Sequence[str] = (),
) -> RowSummary:
    module = qname.rsplit(".", 1)[0]
    return RowSummary(
        pretty_qname=qname,
        pretty_name=qname.rsplit(".", 1)[-1],
        module=module,
        namespace=namespace_of(module),
        def_kind=kind,
        type_ast_version="0.3-v0",
        ast_size=ast_size,
        body_size=body_size,
        has_body=body_size > 0,
        pi_arity=arity,
        dependencies=tuple(deps),
    )


# ---------------------------------------------------------------------------
# Projection
# ---------------------------------------------------------------------------


def test_namespace_of_takes_the_first_segment() -> None:
    assert namespace_of("Overture.Signatures") == "Overture"
    assert namespace_of("Everything") == "Everything"
    assert namespace_of("") == ""


def test_pi_arity_counts_top_level_binders_only() -> None:
    # {A : Set} → (A → A) → A : two top-level binders, and the arrow inside
    # the second argument must not count.
    inner = {"tag": "Type", "term": {"tag": "Pi", "dom": {}, "cod": {}}}
    ast = {
        "tag": "Type",
        "term": {
            "tag": "Pi",
            "binder": {"hiding": "implicit", "nameHint": "A"},
            "dom": {"tag": "Type", "term": {"tag": "Sort"}},
            "cod": {
                "tag": "Type",
                "term": {
                    "tag": "Pi",
                    "binder": {"hiding": "explicit", "nameHint": "_"},
                    "dom": inner,
                    "cod": {"tag": "Type", "term": {"tag": "Var", "ix": 1}},
                },
            },
        },
    }
    assert pi_arity(ast) == 2


def test_pi_arity_of_a_non_function_type_is_zero() -> None:
    assert pi_arity({"tag": "Type", "term": {"tag": "Sort"}}) == 0


def test_pi_arity_tolerates_a_missing_or_odd_ast() -> None:
    assert pi_arity(None) == 0
    assert pi_arity({}) == 0
    assert pi_arity("not an ast") == 0


def test_project_row_reads_the_canonical_fields() -> None:
    r = project_row(
        {
            "prettyQname": "Algebras.Basic.Algebra",
            "prettyName": "Algebra",
            "prettyModule": "Algebras.Basic",
            "defKind": "record",
            "typeAstVersion": "0.3-v0",
            "type": "(S : Signature) -> Set",
            "astSize": 24,
            "dependencies": ["Signature", "Set"],
            "body": None,
            "hasBody": False,
            "typeAst": {"tag": "Type", "term": {"tag": "Pi", "dom": {}, "cod": {}}},
        }
    )
    assert r.namespace == "Algebras"
    assert r.def_kind == "record"
    assert r.ast_size == 24
    assert r.has_body is False
    assert r.body_size == 0
    assert r.pi_arity == 1
    assert r.dependencies == ("Signature", "Set")


def test_project_row_measures_the_type_when_astsize_is_absent() -> None:
    r = project_row({"prettyQname": "M.f", "type": "A → B"})
    assert r.ast_size == len("A → B")


def test_project_row_counts_a_body_as_a_body() -> None:
    r = project_row({"prettyQname": "M.f", "body": "f x = x", "hasBody": True})
    assert r.has_body is True
    assert r.body_size == len("f x = x")


# ---------------------------------------------------------------------------
# Distributions
# ---------------------------------------------------------------------------


def test_percentile_is_nearest_rank() -> None:
    values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    assert percentile(values, 50) == 5
    assert percentile(values, 90) == 9
    assert percentile(values, 100) == 10


def test_percentile_of_nothing_is_zero() -> None:
    assert percentile([], 50) == 0


def test_distribution_reports_the_shape() -> None:
    d = distribution([1, 2, 3, 4])
    assert (d.count, d.total, d.minimum, d.maximum) == (4, 10, 1, 4)
    assert d.median == 2.5
    assert d.percentiles["p50"] == 2


def test_distribution_of_nothing_is_zeros_not_an_error() -> None:
    d = distribution([])
    assert d.to_json()["count"] == 0
    assert d.to_json()["percentiles"]["p99"] == 0


def test_counts_by_orders_largest_first() -> None:
    rows = (row("M.a"), row("M.b"), row("N.c", kind="record"))
    assert list(counts_by(lambda r: r.namespace, rows)) == ["M", "N"]


# ---------------------------------------------------------------------------
# Definition graph
# ---------------------------------------------------------------------------


def test_definition_graph_separates_internal_from_external_edges() -> None:
    rows = (
        row("M.f", deps=("M.g", "Agda.Primitive.Level")),
        row("M.g", deps=("Data.Nat.ℕ",)),
    )
    g = definition_graph(rows)

    assert g.nodes == 2
    assert g.internal_edges == 1
    assert g.external_edges == 2
    assert g.unresolved_tokens == 2
    assert g.most_depended_upon[0] == {"name": "M.g", "count": 1}


def test_definition_graph_dedupes_repeated_tokens_in_one_type() -> None:
    rows = (row("M.f", deps=("M.g", "M.g", "M.g")), row("M.g"))
    g = definition_graph(rows)
    assert g.internal_edges == 1
    assert g.out_degree.maximum == 1


def test_definition_graph_counts_recursion_as_a_self_loop() -> None:
    g = definition_graph((row("M.f", deps=("M.f",)),))
    assert g.self_loops == 1
    assert g.internal_edges == 1


def test_definition_graph_ranks_the_external_targets_too() -> None:
    rows = (
        row("M.f", deps=("Agda.Primitive.Level",)),
        row("M.g", deps=("Agda.Primitive.Level",)),
        row("M.h", deps=("Data.Nat.ℕ",)),
    )
    g = definition_graph(rows)
    assert g.most_external_targets[0] == {"name": "Agda.Primitive.Level", "count": 2}


# ---------------------------------------------------------------------------
# Module graph
# ---------------------------------------------------------------------------


DOT = """digraph dependencies {
  m0[label="MetadataEverything"];
  m1[label="Overture.Basic"];
  m2[label="Overture.Signatures"];
  m3[label="Algebras.Basic"];
  m0 -> m1;
  m0 -> m3;
  m3 -> m2;
  m2 -> m1;
}
"""


def test_parse_dot_reads_labels_and_maps_edges() -> None:
    nodes, edges = parse_dot(DOT)
    assert set(nodes) == {
        "MetadataEverything",
        "Overture.Basic",
        "Overture.Signatures",
        "Algebras.Basic",
    }
    assert ("Algebras.Basic", "Overture.Signatures") in edges


def test_parse_dot_drops_the_synthetic_root_and_its_edges() -> None:
    nodes, edges = parse_dot(DOT, exclude=("MetadataEverything",))
    assert "MetadataEverything" not in nodes
    assert all("MetadataEverything" not in edge for edge in edges)
    assert len(edges) == 2


def test_longest_path_length_on_a_chain() -> None:
    nodes = ("a", "b", "c")
    edges = (("a", "b"), ("b", "c"))
    assert longest_path_length(nodes, edges) == 2


def test_longest_path_length_detects_a_cycle() -> None:
    assert longest_path_length(("a", "b"), (("a", "b"), ("b", "a"))) is None


def test_module_graph_reports_shape() -> None:
    g = module_graph(DOT, exclude=("MetadataEverything",))
    assert g.nodes == 3
    assert g.edges == 2
    assert g.acyclic is True
    assert g.longest_path == 2
    # `Overture.Basic` imports nothing; `Algebras.Basic` is imported by nothing.
    assert g.leaves == 1
    assert g.roots == 1
    assert g.most_imported[0] == {"name": "Overture.Basic", "count": 1}


# ---------------------------------------------------------------------------
# Whole document
# ---------------------------------------------------------------------------


def test_build_stats_shape() -> None:
    rows = (
        row("Overture.Basic.f", ast_size=10, body_size=4, arity=1, deps=("Overture.Basic.g",)),
        row("Overture.Basic.g", kind="record", ast_size=30, arity=2),
        row("Algebras.Basic.Algebra", kind="record", ast_size=50, arity=3),
    )
    stats = build_stats(rows, "agda-algebras", DOT, ("MetadataEverything",))

    assert stats["totals"]["definitions"] == 3
    assert stats["totals"]["modules"] == 2
    assert stats["totals"]["namespaces"] == 2
    assert stats["totals"]["withBody"] == 1
    assert stats["byDefKind"] == {"record": 2, "function": 1}
    assert stats["sizes"]["typeLength"]["max"] == 50
    # Only the one row with a body contributes to the body distribution.
    assert stats["sizes"]["bodyLength"]["count"] == 1
    assert stats["dependencyGraph"]["internalEdges"] == 1
    assert stats["moduleGraph"]["nodes"] == 3


def test_build_stats_omits_the_module_graph_when_no_dot_is_given() -> None:
    stats = build_stats((row("M.f"),), "agda-algebras", None, ())
    assert "moduleGraph" not in stats


def test_render_markdown_covers_every_section() -> None:
    stats = build_stats((row("M.f", deps=("M.g",)), row("M.g")), "agda-algebras", DOT, ())
    md = render_markdown(stats)

    for heading in (
        "# Corpus statistics — agda-algebras",
        "## Totals",
        "## Definitions by kind",
        "## Size distributions",
        "## Dependency graph (definition level)",
        "## Import graph (module level)",
    ):
        assert heading in md
    # Tables render as GFM, so a card can paste them unchanged.
    assert "|---|" in md


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------


def test_load_corpus_projects_every_row(tmp_path: Path) -> None:
    corpus = tmp_path / "corpus.jsonl"
    corpus.write_text(
        json.dumps({"prettyQname": "M.f", "prettyModule": "M", "astSize": 3})
        + "\n\n"
        + json.dumps({"prettyQname": "M.g", "prettyModule": "M", "astSize": 5})
        + "\n",
        encoding="utf-8",
    )
    rows = load_corpus(corpus).unwrap()
    assert [r.pretty_qname for r in rows] == ["M.f", "M.g"]


def test_load_corpus_names_the_offending_line(tmp_path: Path) -> None:
    corpus = tmp_path / "corpus.jsonl"
    corpus.write_text('{"prettyQname":"M.f"}\nbroken\n', encoding="utf-8")
    err = load_corpus(corpus).unwrap_err()
    assert "corpus.jsonl:2" in err.message


def test_load_corpus_rejects_an_empty_corpus(tmp_path: Path) -> None:
    corpus = tmp_path / "corpus.jsonl"
    corpus.write_text("\n", encoding="utf-8")
    assert load_corpus(corpus).is_err


def test_load_corpus_reports_a_missing_file(tmp_path: Path) -> None:
    assert load_corpus(tmp_path / "absent.jsonl").is_err


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def test_summary_finds_the_description_line() -> None:
    assert _summary().startswith("Summary statistics")

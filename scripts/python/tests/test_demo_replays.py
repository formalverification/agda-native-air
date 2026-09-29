"""
Tests for `scripts/python/demo/replays.py` and `build_data.py`.

File: scripts/python/tests/test_demo_replays.py

Description
-----------
These run the real build over the committed archive, because the properties
worth pinning are properties of what gets published.

+  No absolute path reaches the page.  `paths.check_clean` is asserted on the
   encoded output of every replay, not only on the transcript it came from:
   `outcome.json` carries the machine's paths too, in the isolation audit's
   record of a refused Read.
+  Every verdict on the page is the archive's.  Each replay's verdict fields
   are compared with the `outcome.json` they were read from, so no later
   convenience can turn a restatement into a solve on the way to the HTML.
+  The contrasts the page is built around still hold.  If the archive is
   ever regenerated and `algebras-homs-mon-to-hom` stops being a solve beside
   a restatement, the page's claim about it becomes false, and this is where
   that is found out.
+  The composition tier's three sessions (Issue #224) say what their blurbs
   say: which call each needle came from, that the first of them met the
   middle point and named it, that the second wrote no needle at all, and
   that the third wrote the gold's proof and lost the preservation gate.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_demo_replays.py`
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict

import pytest

from scripts.python.demo.build_data import ARCHIVE, INDEX, manifest, run
from scripts.python.demo.numbers import (
    COMP_OPUS_MCP_RUN,
    COMP_SONNET_MCP_RUN,
    COMPOSITION_README,
)
from scripts.python.demo.paths import check_clean
from scripts.python.demo.replays import (
    COMPOSITION,
    ROSTER,
    index_rows,
    marked_diff,
    tag_value,
    tag_values,
)

REPO = Path(__file__).resolve().parents[3]

#: Every replay the page carries, in the order the build writes them.
EVERY = ROSTER + COMPOSITION


# --------------------------------------------------------------- pure

def test_marked_diff_marks_only_what_changed() -> None:
    before = "a\nb\nc"
    after = "a\nB\nc\nd"
    marked = marked_diff(before, after)
    assert (" ", "a") in marked
    assert ("-", "b") in marked
    assert ("+", "B") in marked
    assert ("+", "d") in marked
    # ndiff's intra-line hint lines would render as noise and are dropped.
    assert all(mark in " +-" for mark, _ in marked)


def test_marked_diff_of_an_unchanged_file_marks_nothing() -> None:
    marked = marked_diff("a\nb", "a\nb")
    assert {mark for mark, _ in marked} == {" "}


def test_marked_diff_never_marks_a_comment_line() -> None:
    # The obligation lost two header lines after the run (issue #219); the
    # final file still has them, and one code line changed.  Every comment
    # line is listed unmarked, in place; the marks are ndiff's over the code
    # lines alone; and the final file's lines keep their order.
    before = "-- File: X.agda\n--\nmodule X where\nf = {!!}\ng = 1"
    after = "-- File: X.agda\n-- Strategy: refl\n--\nmodule X where\nf = refl\n-- trailing note"
    marked = marked_diff(before, after)
    comments = [(mark, text) for mark, text in marked if text.startswith("--")]
    assert comments == [(" ", "-- File: X.agda"), (" ", "-- Strategy: refl"), (" ", "--"), (" ", "-- trailing note")]
    assert [pair for pair in marked if pair[0] == "+"] == [("+", "f = refl")]
    assert {pair for pair in marked if pair[0] == "-"} == {("-", "f = {!!}"), ("-", "g = 1")}
    assert [text for mark, text in marked if mark != "-"] == after.splitlines()


def test_tags_are_read_by_prefix() -> None:
    tags = ["stratum:using", "restates:M.f", "target:M.g", "target:M.h"]
    assert tag_value(tags, "restates") == "M.f"
    assert tag_value(tags, "absent") is None
    assert tag_values(tags, "target") == ("M.g", "M.h")


def test_the_manifest_lists_the_roster_in_order() -> None:
    replays = [{"id": f"r{i}", "label": "l", "modelLabel": "m",
                "subject": "s", "run": "x", "verdict": {"kind": "solved"}}
               for i in range(3)]
    listed = manifest(replays, replays[:1])
    assert [entry["file"] for entry in listed["replays"]] == \
        ["r0.json", "r1.json", "r2.json"]
    assert [entry["file"] for entry in listed["composition"]] == ["r0.json"]


# --------------------------------------------------- against the archive

def _built(tmp_path: Path) -> Dict[str, Dict[str, Any]]:
    outcome = run(REPO, tmp_path)
    assert outcome.is_ok, str(outcome.unwrap_err())
    return {path.stem: json.loads(path.read_text(encoding="utf-8"))
            for path in tmp_path.glob("*.json")}


def test_the_build_writes_one_file_per_replay_and_the_table(tmp_path: Path) -> None:
    built = _built(tmp_path)
    assert len(built) == len(EVERY) + 2           # + manifest and numbers
    for key, roster in (("replays", ROSTER), ("composition", COMPOSITION)):
        listed = built["manifest"][key]
        assert [entry["id"] for entry in listed] == \
            [f"{choice.run}--{choice.subject}" for choice in roster]
        for entry in listed:
            assert entry["id"] in built


def test_no_absolute_path_reaches_the_page(tmp_path: Path) -> None:
    for name, data in _built(tmp_path).items():
        encoded = json.dumps(data, ensure_ascii=False)
        problem = check_clean(encoded)
        assert problem.is_ok, f"{name}: {problem.unwrap_err()}"


def test_every_verdict_is_the_archives(tmp_path: Path) -> None:
    built = _built(tmp_path)
    for choice in EVERY:
        replay = built[f"{choice.run}--{choice.subject}"]
        outcome = json.loads(
            (REPO / ARCHIVE / choice.run / "subjects" / choice.subject
             / "outcome.json").read_text(encoding="utf-8"))
        verdict = replay["verdict"]
        assert verdict["solved"] == bool(outcome["solved"])
        assert verdict["restated"] == bool(outcome["restated"])
        assert verdict["gate"] == outcome.get("gate")
        assert verdict["turns"] == outcome["turns"]
        assert verdict["toolCalls"] == outcome["toolCallsTotal"]
        assert verdict["agdaExit"] == outcome["agdaExit"]
        assert verdict["restatementEvidence"] == \
            (outcome.get("restatementEvidence") or [])
        # Issue #215: the judge's `original` reading travels with the
        # verdict, every field but the file as the archive has it, and the
        # file anchored rather than absolute.
        original = outcome.get("original")
        if original is None:
            assert verdict["original"] is None
            continue
        for field in ("inView", "how", "at", "reads", "refusedReads"):
            assert verdict["original"][field] == original[field], field
        assert original["file"].startswith("/nix/store/")
        assert verdict["original"]["file"].startswith("<nix>/")


def test_the_final_file_on_the_page_is_the_one_the_judge_read(tmp_path: Path) -> None:
    built = _built(tmp_path)
    for choice in EVERY:
        replay = built[f"{choice.run}--{choice.subject}"]
        on_disk = (REPO / replay["final"]["path"]).read_text(encoding="utf-8")
        assert replay["final"]["text"] == on_disk
        obligation = (REPO / replay["obligation"]["path"]).read_text(
            encoding="utf-8")
        assert replay["obligation"]["text"] == obligation
        # The marked listing is the diff of those two and nothing else.
        assert [tuple(pair) for pair in replay["final"]["marked"]] == \
            list(marked_diff(obligation, on_disk))


def test_each_replay_has_an_exchange_with_an_answer(tmp_path: Path) -> None:
    built = _built(tmp_path)
    for choice in EVERY:
        replay = built[f"{choice.run}--{choice.subject}"]
        calls = [s for s in replay["session"]["steps"] if s["kind"] == "call"]
        assert calls, choice.subject
        assert all(call["answer"] is not None for call in calls)
        # Every session ends on a check the server answered.
        assert calls[-1]["display"] == "check_file"
        assert calls[-1]["answer"]["headline"][0] == ["success", "true"]
        assert replay["session"]["serverStatus"] == "connected"
        # The call count the page shows is the judge's own tally.
        assert len(calls) == replay["verdict"]["toolCalls"]


def test_the_flagship_contrast_still_holds(tmp_path: Path) -> None:
    # The page's central claim: one obligation, the same fourteen tools, two
    # verdicts.  If the archive ever stops saying that, the page is wrong.
    built = _built(tmp_path)
    opus = built["suite219-opus5-mcp-1--algebras-homs-mon-to-hom"]
    sonnet = built["suite219-sonnet5-mcp-1--algebras-homs-mon-to-hom"]
    assert opus["obligation"]["path"] == sonnet["obligation"]["path"]
    assert opus["verdict"]["kind"] == "solved"
    assert sonnet["verdict"]["kind"] == "restated"
    assert sonnet["verdict"]["agdaExit"] == 0
    assert sonnet["verdict"]["restatementEvidence"] == \
        ["ref Setoid.Homomorphisms.Basic.mon→hom"]
    assert "mon→hom _ _ m" in sonnet["final"]["text"]
    assert "IsMon.isHom (proj₂ m)" in opus["final"]["text"]
    # The blurb's first probe: `_,_` not in scope, then the qualified one.
    probes = [s for s in opus["session"]["steps"]
              if s["kind"] == "call" and s["display"] == "fill_hole"]
    assert len(probes) == 2
    assert "Not in scope" in probes[0]["answer"]["body"]
    assert ["status", "ok"] in probes[1]["answer"]["headline"]
    # Neither session had the original's proof in view.
    assert opus["verdict"]["original"]["inView"] is False
    assert sonnet["verdict"]["original"]["inView"] is False


def test_the_gate_contrast_still_holds(tmp_path: Path) -> None:
    # Both arms needed `trans`; the two final files differ by one import
    # line, and that line is the whole difference between a solve and a gate.
    built = _built(tmp_path)
    opus = built["suite219-opus5-mcp-1--stdlib-nat-mul-comm"]
    sonnet = built["suite219-sonnet5-mcp-1--stdlib-nat-mul-comm"]
    assert opus["verdict"]["kind"] == "solved"
    assert opus["verdict"]["addedImports"] == [
        "open import Relation.Binary.PropositionalEquality using ( trans )"]
    assert sonnet["verdict"]["kind"] == "gate"
    assert sonnet["verdict"]["gate"] == "preservation"
    assert sonnet["verdict"]["agdaExit"] == 0
    assert sonnet["verdict"]["addedImports"] == []
    added = [text for mark, text in marked_diff(opus["final"]["text"],
                                                sonnet["final"]["text"])
             if mark == "+"]
    assert any("; trans )" in line for line in added)
    assert opus["verdict"]["turns"] == 4


def test_the_wholesale_session_still_holds(tmp_path: Path) -> None:
    # A wholesale row solved through a located definition and one
    # `search_in_scope` question, whose one in-scope row is the proof's.
    replay = _built(tmp_path)[
        "suite219-opus5-mcp-1--algebras-subalgebras-sub-reflexive"]
    assert replay["verdict"]["kind"] == "solved"
    assert replay["obligation"]["stratum"] == "agda-algebras/wholesale"
    calls = [s for s in replay["session"]["steps"] if s["kind"] == "call"]
    names = [call["display"] for call in calls]
    assert "definition_of" in names and names.count("search_in_scope") == 1
    asked = next(call for call in calls if call["display"] == "search_in_scope")
    assert "Setoid.Homomorphisms.Basic.𝒾𝒹" in asked["answer"]["body"]
    assert "𝒾𝒹 , (λ z → z)" in replay["final"]["text"]


def test_the_index_row_of_every_replay_exists() -> None:
    rows = index_rows(REPO / INDEX)
    assert rows.is_ok
    known = rows.unwrap()
    for choice in EVERY:
        assert choice.subject in known


# ------------------------------- the composition tier's sessions (#224)

@pytest.fixture(scope="module")
def comp(tmp_path_factory) -> Dict[str, Dict[str, Any]]:
    """The build's replays, once for every test below."""
    out = tmp_path_factory.mktemp("comp")
    outcome = run(REPO, out)
    assert outcome.is_ok, str(outcome.unwrap_err())
    return {path.stem: json.loads(path.read_text(encoding="utf-8"))
            for path in out.glob("*.json")}


def _calls(replay: Dict[str, Any]):
    return [s for s in replay["session"]["steps"] if s["kind"] == "call"]


def _source(replay: Dict[str, Any], name: str) -> Dict[str, Any]:
    return next(s for s in replay["needles"] if s["name"] == name)


def test_a_composition_row_names_needles_and_no_original(comp) -> None:
    # The trap the kick-off named: `original` is null on every composition
    # row, so the page reads the needles instead, and a mined row has none.
    for choice in COMPOSITION:
        replay = comp[f"{choice.run}--{choice.subject}"]
        assert replay["verdict"]["original"] is None
        assert replay["obligation"]["restates"] is None
        assert replay["obligation"]["stratum"] == "agda-algebras/composition"
        assert len(replay["obligation"]["needles"]) >= 2
        assert [s["needle"] for s in replay["needles"]] == \
            replay["obligation"]["needles"]
    for choice in ROSTER:
        assert comp[f"{choice.run}--{choice.subject}"]["needles"] == []


def test_no_verdict_sentence_claims_a_citation_was_absent(comp) -> None:
    # A row whose index entry names no original gets no sentence saying the
    # definition does not cite it: the judge looks for no citation there.
    for replay in comp.values():
        if "verdict" not in replay or replay["verdict"]["kind"] != "solved":
            continue
        cited = "does not refer to the library's own lemma"
        if replay["obligation"]["restates"] is None:
            assert cited not in replay["verdict"]["sentence"]
            assert "names no library original" in replay["verdict"]["sentence"]
        else:
            assert cited in replay["verdict"]["sentence"]


def test_sonnets_row_ten_takes_the_golds_route(comp) -> None:
    replay = comp[f"{COMP_SONNET_MCP_RUN}--"
                  "comp-group-normal-of-smaller-congruence"]
    calls = _calls(replay)
    # Both needles come from call 2, an `exports_of` on the module the
    # fixture opens, and the final file uses both.
    for name in ("≤ⁿ-trans", "normalOf-mono"):
        found = _source(replay, name)
        assert (found["origin"], found["label"], found["call"],
                found["used"]) == ("answer", "exports_of", 2, True)
        assert name in calls[1]["answer"]["body"]
    assert calls[1]["display"] == "exports_of"
    assert dict(calls[1]["args"])["module"] == "GroupCongruences"
    # The middle point: the first check, both arguments written, leaves
    # metas unsolved; the last, with the implicits named, passes.
    checks = [c for c in calls if c["display"] == "check_file"]
    first = json.loads(checks[0]["answer"]["body"])
    assert first["success"] is False
    assert {d["code"] for d in first["diagnostics"]} >= \
        {"UnsolvedMetaVariables"}
    edits = [c for c in calls if c["display"] == "Edit"]
    assert "≤ⁿ-trans (normalOf-mono θ φ θ⊆φ) φ≤N" in \
        dict(edits[0]["args"])["new_string"]
    assert json.loads(checks[-1]["answer"]["body"])["success"] is True
    assert "≤ⁿ-trans {ℓ} {normalOf θ} {normalOf φ} {𝑵}" in \
        replay["final"]["text"]
    # The gold names the same three, middle point included.
    row = index_rows(REPO / INDEX).unwrap()[replay["subject"]]
    assert "{𝑴 = normalOf φ}" in row["goldTerm"]
    # And `_≤ⁿ_` is a function space, as the blurb says: its definition came
    # back in one of the session's reads.
    assert any("𝑴 ≤ⁿ 𝑵 = set 𝑴 ⊆ set 𝑵" in c["answer"]["body"]
               for c in calls if c["display"] == "Read")
    assert replay["verdict"]["kind"] == "solved"


def test_opus_row_ten_writes_no_needle(comp) -> None:
    replay = comp[f"{COMP_OPUS_MCP_RUN}--"
                  "comp-group-normal-of-smaller-congruence"]
    calls = _calls(replay)
    never = _source(replay, "≤ⁿ-trans")
    assert (never["origin"], never["used"]) == ("never", False)
    read = _source(replay, "normalOf-mono")
    assert (read["origin"], read["label"], read["call"], read["located"],
            read["used"]) == ("answer", "Read", 5, True, False)
    assert calls[4]["display"] == "Read"
    # The file it read is the one `definition_of` located, at call 2.
    assert calls[1]["display"] == "definition_of"
    path = dict(calls[4]["args"])["file_path"]
    assert path in calls[1]["answer"]["body"]
    # `get_goal` printed the goal unfolded, a membership to a membership.
    goals = [c for c in calls if c["display"] == "get_goal"
             and not c["answer"]["isError"]]
    assert goals and "θ .proj₁ x" in json.loads(goals[0]["answer"]["body"])[
        "goal"]
    probe = next(c for c in calls if c["display"] == "fill_hole")
    assert dict(probe["args"])["candidate"] == "λ p → φ≤N (θ⊆φ p)"
    assert ["status", "ok"] in probe["answer"]["headline"]
    assert "= λ p → φ≤N (θ⊆φ p)" in replay["final"]["text"]
    assert replay["verdict"]["kind"] == "solved"


def test_the_gate_session_wrote_the_golds_proof(comp) -> None:
    replay = comp[f"{COMP_SONNET_MCP_RUN}--comp-lattice-below-join-bound"]
    calls = _calls(replay)
    for name in ("≤-trans", "∨-least"):
        found = _source(replay, name)
        assert (found["origin"], found["label"], found["call"],
                found["used"]) == ("answer", "exports_of", 2, True)
    assert dict(calls[1]["args"])["module"] == "Lattice-Order"
    verdict = replay["verdict"]
    assert (verdict["kind"], verdict["gate"], verdict["agdaExit"],
            verdict["statementEqual"]) == ("gate", "preservation", 0, True)
    assert "using ( _≤_ ; ≤-refl )" in verdict["gateDetail"]
    assert "using ( _≤_ ; ≤-refl ; ≤-trans ; ∨-least )" in \
        replay["final"]["text"]
    assert verdict["addedImports"] == []
    # The gold's proof, qualified there and opened here.
    proof = "≤-trans x≤y∨z (∨-least y≤w z≤w)"
    assert proof in replay["final"]["text"]
    row = index_rows(REPO / INDEX).unwrap()[replay["subject"]]
    assert row["goldTerm"] == ("Lattice-Order.≤-trans 𝑳 x≤y∨z "
                               "(Lattice-Order.∨-least 𝑳 y≤w z≤w)")
    # And its root lemma is one the loop reached for and was refused: the
    # tier's README records it under gate 1.
    readme = " ".join((REPO / COMPOSITION_README).read_text(
        encoding="utf-8").split())
    assert "**The root lemma**, refused in both of the loop's forms" in readme
    assert "row 5's `Lattice-Order.≤-trans`" in readme


def test_the_composition_sessions_are_short_enough_to_read(comp) -> None:
    # The kick-off asked for sessions short enough to read; the three are
    # the arm's, and the gate session is the shortest of Sonnet's nine
    # preservation losses in that arm.
    turns = [comp[f"{c.run}--{c.subject}"]["verdict"]["turns"]
             for c in COMPOSITION]
    assert max(turns) < 20
    report = json.loads((REPO / ARCHIVE / COMP_SONNET_MCP_RUN / "report.json")
                        .read_text(encoding="utf-8"))
    kept = [o for o in report["outcomes"] if o.get("gate") == "preservation"]
    assert len(kept) == 9
    assert min(o["turns"] for o in kept) == turns[2]

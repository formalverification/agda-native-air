"""
Tests for `scripts/python/site/check_requirements_pins.py`.

File: scripts/python/tests/test_site_pins.py

Description
-----------
The parser and the comparison, against a pretend environment passed in as
functions, so the cases run wherever pytest does: a matching environment, a
version off by a patch, a missing package, an extra the package does not
provide, an extra whose dependency is absent, and the two lines that are
errors rather than skips (an unpinned requirement, an empty file).  The real
environment is checked by `make site-pins-check` and the flake.

Usage
-----
+  With `pytest`, from the repo root:
     `PYTHONPATH=. python -m pytest scripts/python/tests/test_site_pins.py`
"""

from __future__ import annotations

from pathlib import Path
from typing import Dict, Optional, Tuple

from scripts.python.site.check_requirements_pins import Pin, check_pins, main, parse_pins

REPO = Path(__file__).resolve().parents[3]

TEXT = """# a comment
mkdocs==1.6.1

mkdocs-material[imaging]==9.5.49  # trailing comment
"""


def _env(versions: Dict[str, str]):
    return lambda name: versions.get(name)


def _extras(table: Dict[str, Tuple[Tuple[str, Tuple[str, ...]], ...]]):
    return lambda name: table.get(name)


def test_the_committed_requirements_parse_to_the_two_expected_pins() -> None:
    pins = parse_pins((REPO / "requirements.txt").read_text(encoding="utf-8"))
    assert pins.is_ok, str(pins.unwrap_err())
    assert pins.unwrap() == (
        Pin("mkdocs", "1.6.1", ()),
        Pin("mkdocs-material", "9.5.49", ("imaging",)),
    )


def test_comments_and_blank_lines_are_skipped() -> None:
    assert parse_pins(TEXT).unwrap() == (
        Pin("mkdocs", "1.6.1", ()), Pin("mkdocs-material", "9.5.49", ("imaging",)))


def test_an_unpinned_line_is_an_error_not_a_skip() -> None:
    outcome = parse_pins("mkdocs>=1.6\n")
    assert outcome.is_err and "not a `name==version` pin" in str(outcome.unwrap_err())


def test_an_empty_file_cannot_pass() -> None:
    outcome = parse_pins("# nothing here\n")
    assert outcome.is_err and "vacuously" in str(outcome.unwrap_err())


GOOD = {"mkdocs": "1.6.1", "mkdocs-material": "9.5.49", "pillow": "12.1.0", "cairosvg": "2.8.2"}
PROVIDES = {"mkdocs-material": (("imaging", ("cairosvg", "pillow")), ("recommended", ("mkdocs-rss-plugin",)))}


def test_a_matching_environment_has_no_problems() -> None:
    pins = parse_pins(TEXT).unwrap()
    assert check_pins(pins, _env(GOOD), _extras(PROVIDES)) == ()


def test_each_kind_of_drift_is_named() -> None:
    pins = parse_pins(TEXT).unwrap()
    off = check_pins(pins, _env({**GOOD, "mkdocs": "1.6.0"}), _extras(PROVIDES))
    assert off == ("mkdocs: requirements.txt pins 1.6.1, the environment has 1.6.0",)
    missing = check_pins(pins, _env({k: v for k, v in GOOD.items() if k != "mkdocs"}),
                         _extras(PROVIDES))
    assert missing == ("mkdocs: requirements.txt pins 1.6.1, but it is missing from the environment",)
    no_pillow = check_pins(pins, _env({k: v for k, v in GOOD.items() if k != "pillow"}),
                           _extras(PROVIDES))
    assert no_pillow == ("mkdocs-material[imaging]: pip would install pillow, but it is missing from the environment",)
    no_extra = check_pins(pins, _env(GOOD), _extras({"mkdocs-material": (("recommended", ()),)}))
    assert no_extra[0].startswith("mkdocs-material: requirements.txt names extra [imaging], which the package does not provide")


def test_main_reads_a_file_and_reports(tmp_path: Path, capsys) -> None:
    unpinned = tmp_path / "r.txt"
    unpinned.write_text("mkdocs\n", encoding="utf-8")
    assert main([str(unpinned)]) == 1
    assert "not a `name==version` pin" in capsys.readouterr().err

"""
Tests for `agda_lib_metadata.py`.

File: scripts/python/tests/test_agda_lib_metadata.py

Description
-----------
Tests for the functions in `agda_lib_metadata.py`, which handle parsing
Agda library metadata files and generating "Everything" modules.

Usage
-----
+  With `pytest`:
     From repo root, run `python -m pytest scripts/python/tests/test_agda_lib_metadata.py`

+  Without `pytest`:
     `PYTHONPATH=. python scripts/python/tests/test_agda_lib_metadata.py`

   This way, `scripts` is a package rooted at the repo root, not at `scripts/python/tests`.
"""

from pathlib import Path
from textwrap import dedent

from scripts.python.agda_lib_metadata import (
    SYNTHETIC_ROOT_MODULE,
    is_valid_agda_module_name,
    parse_agda_lib,
    scan_local_modules,
    generate_everything_module,
    parse_dependency_graph_modules,
)


def test_parse_agda_lib(tmp_path: Path) -> None:
    lib_file = tmp_path / "foo.agda-lib"
    lib_file.write_text(
        dedent(
            """
            name: my-lib
            include: src src-extra
            -- some comment
            """
        ),
        encoding="utf-8",
    )
    name, includes = parse_agda_lib(lib_file)
    assert name == "my-lib"
    # Both include paths should be resolved relative to the lib file
    assert len(includes) == 2
    assert (tmp_path / "src").resolve() in includes
    assert (tmp_path / "src-extra").resolve() in includes


def test_scan_local_modules(tmp_path: Path) -> None:
    src = tmp_path / "src"
    src.mkdir()
    (src / "Algebra").mkdir()
    (src / "Algebra" / "Base.agda").write_text("module Algebra.Base where\n", encoding="utf-8")
    (src / "Algebra" / "Lattice.lagda.md").write_text("module Algebra.Lattice where\n", encoding="utf-8")
    (src / "Everything.agda").write_text("module Everything where\n", encoding="utf-8")

    mods = scan_local_modules([src])
    assert "Algebra.Base" in mods
    assert "Algebra.Lattice" in mods
    # `Everything` is a module the library has, so it is one of ours to scan.
    # It used to be discarded because the synthetic root was once called that;
    # the root is `MetadataEverything` now and the discard excluded a real
    # module from every module list (issue #84).
    assert "Everything" in mods
    assert len(mods) == 3


def test_scan_local_modules_excludes_only_the_synthetic_root(tmp_path: Path) -> None:
    src = tmp_path / "src"
    src.mkdir()
    (src / "Real.agda").write_text("module Real where\n", encoding="utf-8")
    (src / f"{SYNTHETIC_ROOT_MODULE}.agda").write_text("-- generated\n", encoding="utf-8")

    mods = scan_local_modules([src])
    assert mods == {"Real"}


def test_scan_local_modules_takes_an_explicit_exclusion_set(tmp_path: Path) -> None:
    src = tmp_path / "src"
    src.mkdir()
    (src / "Keep.agda").write_text("module Keep where\n", encoding="utf-8")
    (src / "Drop.agda").write_text("module Drop where\n", encoding="utf-8")

    assert scan_local_modules([src], exclude={"Drop"}) == {"Keep"}
    # An empty exclusion set keeps everything, including the synthetic root.
    assert scan_local_modules([src], exclude=set()) == {"Keep", "Drop"}


def test_generate_everything_module(tmp_path: Path) -> None:
    modules = {"Algebra.Base", "Algebra.Lattice"}
    include_dirs = [tmp_path / "src"]  # not used directly here

    everything, ordered, root_module = generate_everything_module(
        tmp_path, include_dirs, modules
    )
    content = everything.read_text(encoding="utf-8")

    # The synthetic root is `MetadataEverything`, not `Everything`: a library
    # may already have a module of its own by that name (agda-algebras does).
    assert root_module == "MetadataEverything"
    assert everything.name == "MetadataEverything.agda"
    # We should get a header and two open imports
    assert f"module {root_module} where" in content
    assert "open import Algebra.Base" in content
    assert "open import Algebra.Lattice" in content
    # ordered list is sorted
    assert ordered == sorted(modules)


def test_parse_dependency_graph_modules(tmp_path: Path) -> None:
    dot = dedent(
        """
        digraph dependencies {
          m0[label="Agda.Primitive"];
          m1[label="Everything"];
          m2[label="Algebra.Base"];
          m3[label="Algebra.Lattice"];
          m1 -> m2;
          m2 -> m0;
        }
        """
    )
    dot_file = tmp_path / "dependency-graph.dot"
    dot_file.write_text(dot, encoding="utf-8")

    mods = parse_dependency_graph_modules(dot_file, root_module_name="Everything")
    # Should include all labels except "Everything"
    assert "Agda.Primitive" in mods
    assert "Algebra.Base" in mods
    assert "Algebra.Lattice" in mods
    assert "Everything" not in mods


def test_is_valid_agda_module_name_accepts_a_hyphen() -> None:
    # `src/agda-algebras.lagda.md` declares `module agda-algebras where` and
    # `Everything` imports it, so a validator that rejected hyphens excluded a
    # real module (issue #84).  Agda reserves whitespace and `.;{}()@"`, not
    # `-`.
    assert is_valid_agda_module_name("agda-algebras")
    assert is_valid_agda_module_name("A-B.C-D")


def test_is_valid_agda_module_name_accepts_ordinary_names() -> None:
    assert is_valid_agda_module_name("Overture.Signatures")
    assert is_valid_agda_module_name("Everything")
    assert is_valid_agda_module_name("_private")
    assert is_valid_agda_module_name("Term'")


def test_is_valid_agda_module_name_still_rejects_filename_junk() -> None:
    for bad in ("", "1Leading", "has space", "a..b", ".leading", "trailing."):
        assert not is_valid_agda_module_name(bad), bad

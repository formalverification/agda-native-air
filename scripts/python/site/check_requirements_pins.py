#!/usr/bin/env python3
"""
File: scripts/python/site/check_requirements_pins.py

Description: Assert that requirements.txt and the Python environment this
  runs in install the same versions (Issue #169).

  The flake is the primary way to get the site's toolchain and
  requirements.txt is the supported fallback for a machine without Nix.
  Two dependency sets are only safe while they agree, and nothing else makes
  them agree, so this fails when they drift.  It runs in the flake's
  `site-requirements-pins` check against the site's Python environment, and
  as `make site-pins-check` inside `nix develop .#site`.

  A pin may carry extras, `mkdocs-material[imaging]==9.5.49`.  An extra is a
  claim with no version in it, so what is checked is that the package
  provides the extra and that every dependency the extra would make pip
  install is present in the environment: an environment missing Pillow while
  requirements.txt promises it is exactly the disagreement this exists for.

  The shape is williamdemeo/website's nix/requirements-pins-check.py, with
  the environment lookups passed in so the core can be tested against a
  pretend environment.

Usage:

    PYTHONPATH=. python3 -m scripts.python.site.check_requirements_pins requirements.txt

Design Principles:
  +  Parsing and comparison are pure and take the environment as functions;
     only `installed_versions` and `main` touch `importlib.metadata`.
  +  An unpinned line is an error, not a skip: silently passing over it
     would hide the drift the check is for.
  +  Zero pins is an error, so an empty or misnamed file cannot pass.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, List, Optional, Sequence, Tuple

from scripts.python.utils.file_ops import read_text
from scripts.python.utils.pipeline_types import (
    ErrorType,
    PipelineError,
    Result,
)

#: A pinned direct dependency: `name==version`, or `name[extra,...]==version`.
PIN = re.compile(
    r"(?P<name>[A-Za-z0-9._-]+)"
    r"(?:\[(?P<extras>[A-Za-z0-9._,-]+)\])?"
    r"==(?P<version>[A-Za-z0-9.*+!-]+)")

#: Inside a dependency's environment marker, the clause naming its extra,
#: `extra == "imaging"`.  Quoting varies between packaging tools.
EXTRA_MARKER = re.compile(r"""extra\s*==\s*['"](?P<extra>[^'"]+)['"]""")

#: The bare name at the front of a requirement string.
DEP_NAME = re.compile(r"^[A-Za-z0-9._-]+")


@dataclass(frozen=True)
class Pin:
    """One line of requirements.txt, parsed."""

    name: str
    version: str
    extras: Tuple[str, ...]


#: The version of an installed distribution, or None if it is not installed.
Installed = Callable[[str], Optional[str]]

#: The extras a distribution provides, and the dependencies each pulls in.
#: Returns None when the distribution is not installed.
Extras = Callable[[str], Optional[Tuple[Tuple[str, Tuple[str, ...]], ...]]]


def parse_pins(text: str) -> Result[Tuple[Pin, ...], PipelineError]:
    """Every pin in the file; an unpinned or malformed line is an error."""
    pins: List[Pin] = []
    problems: List[str] = []
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        match = PIN.fullmatch(line)
        if match is None:
            problems.append(f"line {number}: {line!r} is not a `name==version` pin")
            continue
        extras = tuple(e.strip() for e in (match.group("extras") or "").split(",") if e.strip())
        pins.append(Pin(match.group("name"), match.group("version"), extras))
    if problems:
        return Result.err(PipelineError(ErrorType.PARSING_ERROR, "; ".join(problems)))
    if not pins:
        return Result.err(PipelineError(
            ErrorType.VALIDATION_ERROR,
            "no pins found: the check would pass vacuously"))
    return Result.ok(tuple(pins))


def check_pins(pins: Sequence[Pin], installed: Installed,
               extras: Extras) -> Tuple[str, ...]:
    """Every disagreement between the pins and the environment."""
    problems: List[str] = []
    for pin in pins:
        got = installed(pin.name)
        if got is None:
            problems.append(f"{pin.name}: requirements.txt pins {pin.version}, "
                            "but it is missing from the environment")
            continue
        if got != pin.version:
            problems.append(f"{pin.name}: requirements.txt pins {pin.version}, "
                            f"the environment has {got}")
            continue
        provided = dict(extras(pin.name) or ())
        for extra in pin.extras:
            if extra not in provided:
                problems.append(
                    f"{pin.name}: requirements.txt names extra [{extra}], which "
                    f"the package does not provide (has: {', '.join(sorted(provided)) or 'none'})")
                continue
            problems.extend(
                f"{pin.name}[{extra}]: pip would install {dep}, but it is "
                "missing from the environment"
                for dep in provided[extra] if installed(dep) is None)
    return tuple(problems)


# ----------------------------------------------------------- the environment

def installed_version(name: str) -> Optional[str]:
    """`importlib.metadata`'s answer, or None."""
    from importlib.metadata import PackageNotFoundError, version
    try:
        return version(name)
    except PackageNotFoundError:
        return None


def provided_extras(name: str) -> Optional[Tuple[Tuple[str, Tuple[str, ...]], ...]]:
    """Each extra a distribution provides, with the dependencies it adds."""
    from importlib.metadata import PackageNotFoundError, metadata, requires
    try:
        provided = metadata(name).get_all("Provides-Extra") or []
        requirements = requires(name) or []
    except PackageNotFoundError:
        return None

    def deps_of(extra: str) -> Tuple[str, ...]:
        found = []
        for requirement in requirements:
            spec, _, marker = requirement.partition(";")
            match = EXTRA_MARKER.search(marker)
            name_match = DEP_NAME.match(spec.strip())
            if match and match.group("extra") == extra and name_match:
                found.append(name_match.group(0))
        return tuple(found)

    return tuple((extra, deps_of(extra)) for extra in provided)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Check that requirements.txt matches this Python environment.")
    parser.add_argument("requirements", type=Path)
    args = parser.parse_args(argv)

    pins = read_text(args.requirements).and_then(parse_pins)
    if pins.is_err:
        print(f"pins-check: {pins.unwrap_err()}", file=sys.stderr)
        return 1
    problems = check_pins(pins.unwrap(), installed_version, provided_extras)
    if problems:
        print(f"pins-check: {args.requirements} and this environment disagree:",
              file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        print("Fix by bumping requirements.txt, or the override in flake.nix, so "
              "both paths install the same versions.", file=sys.stderr)
        return 1
    for pin in pins.unwrap():
        print(f"pins-check: {pin.name} {pin.version}"
              + (f" [{', '.join(pin.extras)}]" if pin.extras else ""))
    print(f"pins-check: {len(pins.unwrap())} pinned dependencies match this environment")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

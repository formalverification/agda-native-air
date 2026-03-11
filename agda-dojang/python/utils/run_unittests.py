#!/usr/bin/env python3
"""
run_unittests.py

File: agda-dojang/python/tools/run_unittests.py

Description:
  Pretty-ish unittest runner (stdlib only).

Usage:
  PYTHONPATH=python python3 python/tools/run_unittests.py
"""

from __future__ import annotations

import sys
import time
import unittest
from typing import Any


RESET = "\033[0m"
GREEN = "\033[32m"
RED = "\033[31m"
YELLOW = "\033[33m"
DIM = "\033[2m"


def _supports_color(stream: Any) -> bool:
    return hasattr(stream, "isatty") and stream.isatty()


class PrettyResult(unittest.TextTestResult):
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self._use_color = _supports_color(self.stream)

    def _c(self, s: str, color: str) -> str:
        if not self._use_color:
            return s
        return f"{color}{s}{RESET}"

    def _line(self, status: str, test: unittest.case.TestCase, extra: str = "") -> None:
        name = self.getDescription(test)
        msg = f"{status} {name}"
        if extra:
            msg += f" {self._c(extra, DIM)}"
        self.stream.writeln(msg)

    def addSuccess(self, test: unittest.case.TestCase) -> None:
        super().addSuccess(test)
        self._line(self._c("✅", GREEN), test)

    def addFailure(self, test: unittest.case.TestCase, err: Any) -> None:
        super().addFailure(test, err)
        self._line(self._c("❌", RED), test)

    def addError(self, test: unittest.case.TestCase, err: Any) -> None:
        super().addError(test, err)
        self._line(self._c("💥", RED), test)

    def addSkip(self, test: unittest.case.TestCase, reason: str) -> None:
        super().addSkip(test, reason)
        self._line(self._c("⏭", YELLOW), test, extra=f"(skipped: {reason})")


def main() -> int:
    t0 = time.monotonic()
    loader = unittest.TestLoader()
    suite = loader.discover("python/tests", pattern="test_*.py")

    runner = unittest.TextTestRunner(
        verbosity=2,  # ensures getDescription includes test method names
        resultclass=PrettyResult,
    )
    result = runner.run(suite)
    dt = time.monotonic() - t0

    passed = result.testsRun - len(result.failures) - len(result.errors) - len(result.skipped)
    sys.stdout.write(
        f"\n✅ {passed} passed, ❌ {len(result.failures)} failed, 💥 {len(result.errors)} errors, "
        f"⏭ {len(result.skipped)} skipped in {dt:.3f}s\n"
    )
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())

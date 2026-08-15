#!/bin/sh
# =============================================================================
# fake-slow-agda.sh
#
# File: agda-native-air/agda-mcp/test/resources/fake-slow-agda.sh
#
# Purpose
#   Stand in for the `agda` binary in the tier-1 timeout tests (issue #77) so
#   they can prove that AgdaMCP.Agda.runAgda enforces `--timeout` without
#   needing a real Agda, a real library, or a genuinely hung typechecker.
#
#   It is pointed at by `agdaBin` and ignores every argument it is handed (the
#   Agda flags and the file path), because the behaviour under test is process
#   management, not typechecking.
#
# Protocol (all via the environment, so a test can vary one run at a time)
#   AGDA_MCP_FAKE_SLEEP   seconds to sleep before "finishing"      (default 30)
#   AGDA_MCP_FAKE_MARKER  file to create *after* the sleep         (default none)
#   AGDA_MCP_FAKE_EXIT    exit status on natural completion        (default 0)
#
# Design notes
#   The "Checking ..." line is printed *before* the sleep, and unbuffered, for
#   two reasons: it is the line AgdaMCP.Agda.checkedFromSourceOf keys on, and
#   emitting it up front lets a test assert that output written before a kill is
#   still captured rather than discarded.
#
#   The marker file is the zombie/orphan check.  A test sets a sleep longer than
#   the timeout, waits past that sleep, and asserts the marker never appears: if
#   it does, the subprocess outlived the tool call, which is exactly the leak
#   that killing only the waiting Haskell thread (System.Timeout.timeout over
#   readProcessWithExitCode) would have produced.
# =============================================================================

echo "Checking FakeSlow (fake-slow-agda.agda)."

sleep "${AGDA_MCP_FAKE_SLEEP:-30}"

# Only reached if we were NOT killed: this is what the test asserts against.
if [ -n "${AGDA_MCP_FAKE_MARKER:-}" ]; then
  : > "${AGDA_MCP_FAKE_MARKER}"
fi

echo "fake-slow-agda: completed normally"
exit "${AGDA_MCP_FAKE_EXIT:-0}"

#!/bin/sh
# =============================================================================
# fake-project-gate.sh
#
# File: agda-native-air/agda-mcp/test/resources/fake-project-gate.sh
#
# Purpose
#   Stand in for a project's acceptance gate in the tier-1f check_project tests
#   (issue #78), so they can pin the tool's contract without running a real
#   `make check` over a real library — which is the 10-20 minute job the tool
#   exists to run, and exactly the wrong thing to put in a unit test suite.
#
#   It prints Agda-shaped output (progress lines, and an error block copied from
#   what Agda 2.8.0 actually emits) and then exits the way the mode says.
#
# Usage
#   fake-project-gate.sh MODE [SECONDS] [MARKER]
#
#   pass    print two "Checking" lines and exit 0, after sleeping SECONDS
#           (default 0) so a test can assert elapsedMs measured something real.
#   fail    print the same progress plus a [NotInScope] error block, exit 1 —
#           a gate that fails mid-run and says so.
#   masked  print exactly what `fail` prints, let a command fail, and then end
#           with an `echo`.  THE TRAP: a shell's exit status is its last
#           command's, so this wrapper reports 0 for a build that failed.  This
#           is the field-session hazard of § 3.5 of
#           docs/feedback/flrp-agda-mcp-improvements.md, reproduced verbatim so
#           the test suite can pin that check_project reports it as
#           maskedFailure rather than as a pass.
#   slow    print one "Checking" line and then sleep SECONDS (default 30),
#           for the timeout path.  If MARKER is given, a BACKGROUNDED SUBSHELL
#           creates that file after the sleep — so a test that outwaits the
#           sleep and finds no marker has proved the whole process group was
#           killed, not merely the leader.  A gate spawns children by design
#           (make runs agda), so leader-only killing is the failure mode worth
#           pinning here.
#
# Design note
#   Modes are arguments rather than environment variables (the protocol
#   fake-slow-agda.sh uses) because check_project's configured gate IS an
#   argument vector: the test passes [script, mode] as --check-command and the
#   fixture needs no ambient state, which keeps one test from leaking into the
#   next.
# =============================================================================

mode="${1:-pass}"
secs="${2:-0}"
marker="${3:-}"

progress_ok() {
  echo "Checking Gate.Ok (/fixture/Gate/Ok.agda)."
}

progress_broken() {
  echo "Checking Gate.Broken (/fixture/Gate/Broken.agda)."
}

# An error block in Agda 2.8.0's own shape: a LINE.COL-COL position, a
# bracketed code, and the indented detail lines the structured parser mines.
error_block() {
  echo "/fixture/Gate/Broken.agda:16.9-14: error: [NotInScope]"
  echo "Not in scope:"
  echo "  zeroo"
  echo "  at /fixture/Gate/Broken.agda:16.9-14"
  echo "    (did you mean 'zero'?)"
  echo "when scope checking zeroo"
}

case "$mode" in
  pass)
    progress_ok
    progress_broken
    if [ "$secs" != "0" ]; then sleep "$secs"; fi
    exit 0
    ;;

  fail)
    progress_ok
    progress_broken
    error_block
    exit 1
    ;;

  slow)
    echo "Checking Gate.Slow (/fixture/Gate/Slow.agda)."
    if [ -n "$marker" ]; then
      ( sleep "${secs:-30}"; : > "$marker" ) &
    fi
    sleep "${secs:-30}"
    wait
    exit 0
    ;;

  masked)
    progress_ok
    progress_broken
    error_block
    # The build fails ...
    ( exit 1 )
    # ... and the wrapper's last command is an echo, so the shell exits 0.
    # Nothing may follow this line: that is the whole point of the fixture.
    echo "gate finished"
    ;;
esac

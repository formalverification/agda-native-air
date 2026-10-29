<!-- File: docs/field-reports/2026-10-27-private-section-proofs.md -->

# 2026-10-27, a private repository: three literate modules extended in batch

+  **Date**: 2026-10-27.
+  **Harness**: Claude Code 2.1.310.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: not recorded.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 7, normalize 1.

The session added about 450 lines of Agda to three existing literate modules
of a private library (two of about 500 and 700 lines, one example of about 170)
and changed the proof of one existing lemma without changing its type.  The
statements were short and their proofs known in advance, so the work was
written a whole section at a time and checked whole, not developed hole by
hole.  All of it checked; the project's own gate (`make check`, 158 modules)
was green at the end, run from the shell.

+  **Tools used**.  `normalize` once, before writing, to see the order in
   which a library function lists the parts of a small concrete term, which
   decided how six membership proofs had to be written (2.6 s, of which 2.55 s
   the lane's first load).  `check_file` seven times on the three modules,
   2.3 s to 4.3 s each: the first check of each module came back green with
   no diagnostic three times out of four; the fourth, on the largest edit
   (about 330 new lines), came back with one `UnsolvedConstraints` and one
   `UnsolvedMetaVariables` diagnostic, both at the same three-line range,
   which located the one defect at once (a standard-library function whose
   implicit argument could not be inferred through a `subst`).  The fix, an
   explicit implicit argument, was green on the next call.
+  **What worked**.  The verdicts were exact and quick enough to use after
   every edit: a module of 1 000 lines with its dependencies' interfaces in
   place checked in under 4 s.  The diagnostic's `involved.metaTypes` carried
   the full constraint, which named the unsolved function argument and the
   concrete list it was being matched against, enough to see the cause
   without opening the file.  `checkedFromSource: false` on one call, made
   after an edit script had failed and left the file unchanged, correctly told
   me nothing had been rechecked.
+  **What was awkward or missing**.  Nothing blocked.  The constraint dump in
   the diagnostic's `metaTypes` was split into one array element per printed
   line fragment, so it read as a list of fifty unrelated strings; the
   `message` field, which held the same text as prose, was easier to read.
   The project's per-module costs needed `--profile=modules` from the shell;
   no tool reports a module's own check time apart from its dependencies'.
+  **Command line comparison**.  For this work the server was the better
   loop for type-checking: each `check_file` cost 2 to 4 s, while every shell
   check paid for entering `nix develop` first (a profiling run that rechecked
   nine modules took 8.6 s of wall time for 6.0 s of checking), and the
   server's diagnostics came structured.  The command line remained the
   right tool for the whole-library gate, the release checks and the timing
   runs, which compare two checkouts.

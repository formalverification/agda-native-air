<!-- File: docs/field-reports/2026-10-23-private-name-probes-warning-exit-zero.md -->

# 2026-10-23, a private repository: release plumbing, with name probes on the command line

+  **Date**: 2026-10-23.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: none.

The session set up a new repository that receives byte-for-byte exports of Agda modules and depends on two pinned Agda libraries through a Nix dev shell, then checked that a table of names in its README matches the modules: every name in the table must be exported by the module the table gives.  It wrote no Agda module; the only Agda it ran was a set of throwaway probe files, one per module, each a single `open import M using (...)`, and the whole-repository check (`make check`, three cold runs of 27.5 to 30.4 s and three of 11.7 to 12.2 s).

+  **Tools used**.  None.  The repository is registered without agda-mcp (no Agda is written there), and the server registered for the source repository resolves its own checkout and library set, not the new repository's dev shell with its two pinned libraries; so the probes ran with the new repository's `agda` wrapper from the command line, about a second each with the interfaces built.
+  **What worked**.  The probe shape itself: one file per module, `open import M using (names)`, checked with `-i .` from a scratch directory, settles in seconds whether every name of a table exists in its module, and a second probe of the form `import M` then `open M.Sub using (name)` settles the names that live in a parameterized submodule.
+  **What was awkward or missing**.  A name that `M` does not export is a warning in Agda 2.9 (`-W[no]ModuleDoesntExport`), not an error, so the check exits 0.  The first loop over the probes tested the exit status and reported all of them clean while eight names were unexported (each in a submodule); only reading the output for "warning" found them.  `-W error` would make the status mean something, but it changes the options and so Agda tries to rewrite the standard library's interfaces in the read-only Nix store, which fails.  This bears on agda-mcp, whose verdicts are the exit code: a `check_file` on such a probe would report success.  A verdict mode that fails on chosen warning codes (this one, say), or a field listing the warnings beside the exit code, would make the server the better tool for this kind of check.
+  **Command line comparison**.  The command line was the only loop available here and was efficient for it: a shell loop over thirty-two probe files, then a second over seven.  The server would have needed a registration for this repository's dev shell, and its exit-code verdict would have hidden the warnings that were the whole finding.

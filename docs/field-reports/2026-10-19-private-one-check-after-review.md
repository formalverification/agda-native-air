<!-- File: docs/field-reports/2026-10-19-private-one-check-after-review.md -->

# 2026-10-19, a private repository: one whole-file check after a review, and the gate on the command line

+  **Date**: 2026-10-19.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 1.

The session reviewed an open pull request in a private Agda repository and
then fixed what the review found: two short lemmas added to an existing
literate module, and comment and prose fixes in three other modules.  The
review's execution half rebuilt the library from the command line, in the
background, in a disposable detached worktree.  The fix was checked through
the server once and then gated on the command line, and everything
typechecked at the first attempt.

+  **Tools used**.  One `check_file` on the edited module: `success: true`,
   exit code 0, no diagnostics, no holes, `checkedFromSource: true`, 21.0 s,
   with the project root resolved to the session's worktree (`rootSource:
   nearest-agda-lib`).  Then the repository's gate from the command line,
   inside the dev shell: the whole-library check (79 modules) and the plan's
   lint, both green.
+  **What worked**.  The verdict's structured fields answered the one
   question the fix raised (did the module check, with nothing left open)
   without reading Agda's output, and the resolved root named the worktree,
   so there was no doubt which tree had been checked.
+  **What was awkward or missing**.  Nothing, for a change this small.  The
   review's rebuild in the disposable worktree was a full-library build, the
   gate's job, and did not go through the server; whether the server would
   have resolved that second worktree was not tried.
+  **Command line comparison**.  Neither loop was more efficient here.  The
   lemmas were written whole and needed one check, which costs about the
   same through the server as with `agda` on the file in the dev shell; the
   server's gain was the structured verdict.  The whole-library gate and the
   lint belong on the command line, and ran there.

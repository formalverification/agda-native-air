<!-- File: docs/field-reports/2026-10-11-agda-algebras-590-opus.md -->
<!--
  Recovered under issue #252.  Written on 2026-10-11 as a section of
  docs/mcp-field-reports.md in the main checkout and never committed there;
  recovered from main's stash of 2026-10-11 23:17.  The title is the
  section's heading in this directory's form (the date, then the repository
  and the work, with "#N" written "issue N"), and the header was added from
  the section's own text, "not recorded" marking what it does not say.  The
  body is the section's, unchanged.
-->

# 2026-10-11, agda-algebras issue 590: canonical forms, finishing a partial session (Claude Opus 5.5)

+  **Date**: 2026-10-11.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: not recorded.
+  **Repository**: ualib/agda-algebras.
+  **Issue or pull request**: issue 590, pull request 600.
+  **Tools called**: check_file 8, normalize 7.

Continued the Kimi K3 session above in the same worktree, under Claude Code
2.1.282, with the agda-mcp server connected (Agda 2.8.0; the project is on
2.9.0).  Result: six new modules (about 2,300 lines: duality, canonical terms,
the algorithm, uniqueness, canonical joinands, a barrel), examples, and PR 600,
in about 50 minutes of wall time.

+  **Tools used**.  `check_file` 8 calls (one per module draft or repair, 5 to
   7.5 s each), `normalize` 7 calls, nothing else.  `get_goal`, `fill_hole`,
   `type_of`, `resolve_name`, `search_by_name`, `definition_of`, and
   `exports_of` were not used; standard-library signatures came from grep over
   the Nix store, which answered in one call each.
+  **What worked**.  The diagnostics of `check_file` named the root cause every
   time.  An `UnsolvedConstraints` list of the form `⌊ dualᴹ _b ⌋ᴶ = ⌊ dualᴹ x ⌋ᴶ
   (blocked on _b)` showed at once that a non-injective embedding was blocking
   inference of two implicit arguments; a `CoverageNoExactSplit` warning quoted
   the offending clause, which showed that the case tree split on the joinand
   before the location proof.  Four of the six modules checked on the first
   call; the other two took one and three repairs.
+  **`normalize` as a test harness**.  Before writing the examples, five calls
   evaluated `canonical` on closed terms over three generators (2 to 16 ms each
   once loaded) and confirmed the outputs by hand, including the case where
   condition 4 of Theorem 1.18 fires.  Two calls failed in band: the top-level
   scope drops a file-local `open`, so the scratch module needed `open ...
   public` (the tool description says so), and a tuple of four expressions
   failed because `_,_` was not in scope.
+  **No holes**.  The work was planned on paper and written a module at a time.
   The failures were about the shape of case trees (exact split, an index left
   neutral by `there`) and implicit-argument inference, not about what term
   fills a goal, so hole-driven development had nothing to offer here.
+  **2.8.0 against 2.9.0**.  Every server verdict agreed with the 2.9.0 command
   line.  The final gates ran on the command line: `make check` from source, 358
   modules, exit 0, 45 s wall.
+  **Command line comparison**.  Inside `nix develop`, a batch `agda` on one
   module with warm interfaces took 2.6 to 4 s, no slower than `check_file`.  The
   server's advantage was the structured diagnostic (code, range, expected and
   actual), not speed.  Kimi's report above measured about 20 s for the command
   line; the difference is probably the dev-shell entry and cold interfaces,
   neither of which I timed.

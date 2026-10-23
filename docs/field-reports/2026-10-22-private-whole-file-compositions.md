<!-- File: docs/field-reports/2026-10-22-private-whole-file-compositions.md -->

# 2026-10-22, a private repository: whole-file checks of short compositions

+  **Date**: 2026-10-22.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: xhigh.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 6, type_of 9.

The session added two new literate modules and small additions to two existing
ones in a private Agda library, about 600 lines, every proof a short
composition of lemmas the library already had.  It developed through
`check_file` on whole files rather than through holes, used `type_of` to read
back the exact statements it then quoted in a pull request and an issue
comment, and kept the project's `make check` on the command line as the final
gate, together with per-module profiles that no tool offers.  All four files
checked; one failed once and was fixed from the diagnostic in one edit.

+  **Tools used**.  `check_file` six times, on five files, each 2.4 to 2.8 s
   with the dependencies' interfaces warm; five verdicts were green, one red.
   `type_of` nine times: the first question on a file cost one load, 2.3 s;
   moving to another file cost a `switch` load of about 0.2 s; questions on the
   same unchanged file came back in 3 to 5 ms.
+  **What worked**.  Three things, as follows.
   +  The server answered from a git worktree whose `.agda/` directory (the
      Agda wrapper and library registry the server is configured with) was
      created after the session had started; the first call worked with no
      restart.
   +  The red verdict carried two diagnostics, `UnsolvedConstraints` and
      `UnsolvedMetaVariables`; the second gave the line and the column span of
      the unsolved implicit arguments, which was enough to fix it.  A pair
      written as `let (a , _ , b) = e in a , b` had left the implicit
      arguments of `b`'s type uninferred, and
      `λ {u} {v} p → proj₂ (proj₂ e) {u} {v} p` solved them.
   +  `type_of` in the default Simplified mode printed every statement in the
      form the module's readers see, with module parameters as leading
      binders, so the statements in the pull request body and the issue
      comment are Agda's own text rather than a transcription.
+  **What was awkward or missing**.  Three things, as follows.
   +  `type_of` with `rewrite: "Normalised"` on one theorem whose type
      mentions setoid and algebra records returned a single line of 161,884
      characters, which exceeded the client's limit on a tool result; the
      harness saved it to a file and the answer was of no use.  The same call
      in Simplified mode answered in four lines.  A cap on the printed size,
      with a flag saying the type was cut, or a warning in the tool's
      description that Normalised unfolds record types without limit, would
      have saved the call.
   +  The first of the two diagnostics, `UnsolvedConstraints`, came with no
      file or range, and the ordering put it ahead of the located
      `UnsolvedMetaVariables` that named the fix.  When both come from the
      same metavariables, the located one is the more likely root cause, or
      the constraint could carry the metavariable's range.
   +  No tool reports a per-module profile.  The session needed each new
      module's own check time for the module's prose and the pull request,
      and ran `agda --profile=modules` from the command line, twice per
      module, after deleting that module's interface file.  An option on
      `check_file` returning Agda's per-module times would have kept the loop
      in one place.
+  **Command line comparison**.  For checking, the two loops cost the same
   (about 2.5 s per file either way), and the server's structured diagnostics
   were easier to act on than Agda's text.  For measurement the command line
   was the only loop: wall time and peak memory of the whole-library gate under
   `/usr/bin/time`, and per-module profiles.  `get_goal` and `fill_hole` were
   not called, because no proof needed a hole: each was a composition written
   whole, and a whole-file check of a few seconds was the faster loop for that
   kind of work.

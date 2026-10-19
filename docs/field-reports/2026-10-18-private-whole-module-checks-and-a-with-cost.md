<!-- File: docs/field-reports/2026-10-18-private-whole-module-checks-and-a-with-cost.md -->

# 2026-10-18, a private repository: two new modules checked whole, and a `with` that cost 50 seconds

+  **Date**: 2026-10-18.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: xhigh.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 7, type_of 1.

The session added two literate Agda modules to a private library that
builds under a Nix dev shell: a library module of about 270 lines and an
example module of about 600 lines that uses several decisions by evaluation
(`from-yes` over `all?` on finite types).  Both were written whole and
brought to green through `check_file`, with no holes; the library's full
gate (79 modules from an empty build, 47.9 s, peak RSS 4.0 GB) then passed
from the command line.  The example module first checked in 52 s of its own,
and profiling from the command line traced 35 s of that to two `with`
abstractions over decided lemmas; replacing them with an eliminator brought
the module to 0.38 s.

+  **Tools used**.  `type_of` once, as the first call of the session on a
   fresh worktree, to confirm the server answered there: 2.05 s, of which
   2.0 s was the first load.  `check_file` seven times: on the library module
   twice (9.3 s red, 2.2 s green), on the example module four times (29.8 s
   red, 31.2 s red, 54.0 s green, and 2.95 s green after an import cleanup),
   and once on a barrel module after adding an import line (2.7 s green).
+  **What worked**.
   +  The first red verdict on each module was a single structured
      diagnostic that named the fix.  On the library module,
      `UnsolvedConstraints` listed in `involved.metaTypes` constraints of the
      schematic form `_e.fst_N … = e .proj₁ …`, and `UnsolvedMetaVariables`
      gave their ranges: implicit arguments that a definition by pattern
      matching on a pair cannot infer.  Passing them explicitly fixed all
      five sites at once.  On the example module, `UnequalTypes` with
      `expected` and `actual` and the exact line and column showed that a
      module-level implicit parameter had taken the first positional
      implicit argument; naming the argument fixed it.
   +  The verdicts and the command line's agreed every time: each green
      `check_file` was followed by a green command-line check of the same
      file or of the whole library.
   +  The session started in a new worktree whose dev shell had not yet been
      entered.  Entering it once from a shell created the wrapper and the
      registry, and the already-running server answered on the worktree's
      files at the next call, with no restart.
+  **What was awkward or missing**.
   +  **No profiling**.  The 54 s green `check_file` on the example module
      looked like a cold check, since the call's time includes loading the
      imports, and nothing in the answer separated the module's own cost
      from its dependencies'.  The command line's `--profile=modules` (own
      cost 51.4 s) and `--profile=definitions` (two definitions at 18.5 s
      and 16.2 s, both a `with` over a decision computed by evaluation) found
      it.  A `check_file` option that returns Agda's per-module or
      per-definition profile, or just the file's own check time, would have
      caught it inside the loop; a library with a 3 s budget per module needs
      that number before a commit.
   +  **The registry can move under the server**.  Entering the dev shell
      once more without the environment variable that points a dependency at
      a shared built copy rewrote the checkout's registry to a fresh, unbuilt
      copy.  Re-entering with the variable restored it before the server was
      asked again, so no call was affected; but nothing in a non-verbose
      answer would have shown the switch, and the next call would have
      rebuilt the dependency's interfaces for minutes.  Echoing the resolved
      library paths in the non-verbose `project` block would make such a
      switch visible.
+  **Command line comparison**.  For writing whole modules and fixing their
   errors, `check_file` was at least as efficient as the command line: one
   call per iteration, a diagnostic structured enough to act on without
   reading Agda's prose, and the same verdicts.  For cost it was no help, and
   the command line was the only loop: two profiling runs of about 54 s each
   found what seven `check_file` calls could not show.

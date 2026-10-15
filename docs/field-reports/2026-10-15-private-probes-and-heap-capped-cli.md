<!-- File: docs/field-reports/2026-10-15-private-probes-and-heap-capped-cli.md -->

# 2026-10-15, a private repository: small probe modules through check_file, and heap-bounded runs from the command line

+  **Date**: 2026-10-15.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 7.

The session wrote five small self-contained probe modules (13 to 80 lines,
no library imports, `--type-in-type`) to settle how a family of definitions
by pattern matching should be shaped, checked each through `check_file`,
and recorded each outcome in the module's first line.  The rest of its Agda
work was machine-generated modules of 0.2 to 1.3 MB, checked hundreds of
times by the repository's own harness, and a hunt for a declaration that
ran Agda out of memory; all of that ran from the command line.

+  **Tools used**.  `check_file` on the five probes, seven calls in all,
   each answered in 66 to 195 ms: two accepted modules, one expected
   rejection (`UnequalTerms`, with `involved.expected` and
   `involved.actual` filled), one `TerminationIssue`, one `ParseError` on
   a first draft, and two re-checks after edits.
+  **What worked**.  Every verdict came back structured and right, so a
   probe's outcome line could be written from the answer without reading
   prose: the `TerminationIssue` diagnostic carried its range, which
   showed at once that Agda reports a termination refusal at the
   definition's first line (the signature) rather than at the offending
   clause, a fact the session's own harness then had to handle.  The
   `ParseError` named the cause exactly (an underscore in a name read as a
   mixfix hole).
+  **What was awkward or missing**.  The tools offer no way to bound the
   heap of the Agda they run.  The session met a module whose checking
   grew Agda to 23 GB before the system's OOM killer stopped it, and every
   later run used GHC's `-M` bound (`+RTS -M6G -RTS`, or `GHCRTS=-M6G`) and
   `-v tc.decl:5`, whose `Checking X.` lines name the declaration Agda died
   in.  It kept those runs, and the normalization of suspect terms, on the
   command line (Agda's interaction mode under the same bound) rather than
   in `check_file` or in the live lane's `normalize`, since a lane that
   grows without bound is shared by the project's later questions and by
   the machine.  A `heapLimit` option, and a verdict that names the last
   declaration reached when Agda is killed, would have let the server do
   that part.
+  **Command line comparison**.  For the probes the two loops cost the
   same: each check took well under a second either way, and the server's
   structured diagnostic saved reading the message.  For the large
   generated modules the command line was the only reasonable loop, since
   the repository's harness drives Agda itself, and the memory hunt needed
   options the server does not pass.

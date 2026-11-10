<!-- File: docs/field-reports/2026-11-09-lean2agda-31-kickoff-probes.md -->

# 2026-11-09, lean2agda: probes behind a kickoff prompt and a pull request's review

+  **Date**: 2026-11-09.
+  **Harness**: Claude Code 2.1.316.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: max.
+  **Repository**: formalverification/lean2agda.
+  **Issue or pull request**: issue 31, pull request 82.
+  **Tools called**: none.

The session wrote a kickoff prompt for issue 31 (Lean's kernel-accelerated
`Nat` operations against Agda's builtins) and assessed pull request 82 for
merging.  For the prompt it wrote two scratch Agda files outside any checkout:
one bound its own `Nat` and `Bool` to the builtins and checked, by `refl` on
variables, that argument-swapped wrappers around `_+_`, `_*_` and `_<_`, and
the builtin `_==_`, satisfy Lean's defining equations for addition,
multiplication, `≤` and equality; the other showed that the builtin monus does
not satisfy Lean's `Nat.sub n (succ m) = pred (Nat.sub n m)` (`UnequalTerms`).
For the review it ran the pull request's checker on a 1.27 MB emitted
scaffold (33 Agda runs under an 8 GB heap bound, 546 s) and on probe files
from four reviewer subagents, which also ran Agda only from the command line.

+  **Tools used**.  None of agda-mcp's.  Each probe was one `agda <file>` in
   the project's dev shell: the first run stopped at once on a missing fixity
   declaration (`NoParseForApplication`, which named the application), and
   the fixed file checked in 0.07 s; the second gave the expected
   `UnequalTerms` with both sides printed.
+  **What worked**.  The command line, for files with no holes: the error
   named the line and the term, and each fix was one edit.  `+RTS -M` on the
   command line bounded Agda's heap through the dev shell's wrapper, and a
   heap exhaustion exits 251.
+  **What was awkward or missing**.  The session did not load agda-mcp before
   writing Agda, against the project's instruction.  The probes lived in a
   scratch directory outside any checkout, and whether `check_file` serves
   such a file was not tried.  One edit of a probe's options pragma missed
   its line (the pragma was the second line), and the "passing" check that
   followed proved nothing until the flag was found absent; a tool that
   echoes the options a file was checked under would have caught it.
+  **Command line comparison**.  For hole-free probes of under 100 lines, the
   command line was the cheaper loop: one call each, no project root to
   resolve.  The scaffold checks drive Agda from the project's own script,
   which is outside agda-mcp's reach in any case.

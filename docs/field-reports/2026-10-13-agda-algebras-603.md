<!-- File: docs/field-reports/2026-10-13-agda-algebras-603.md -->

# 2026-10-13, agda-algebras: keeping slow modules out of barrels

+  **Date**: 2026-10-13.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: xhigh, with workflow orchestration ("ultracode").
+  **Repository**: ualib/agda-algebras.
+  **Issue or pull request**: issue 603, pull request 615.
+  **Tools called**: check_file 2, exports_of 1, resolve_name 1.

The session wrote a policy and a pure-Python checker that keeps modules
marked `check-cost: heavy` out of the library's barrels (modules that only
import others), and marked the two slow `A₅` example modules.  Its Agda edits
were small: one import removed from the `Examples.Classical.Groups` barrel,
and front matter and prose in three literate modules.  Most of the Agda work
was whole-library measurement: `make check` from an empty build, five
`--profile=modules` runs (two pinned to one core with `taskset`), and
`--dependency-graph` over both aggregators as the checker's oracle.

+  **Tools used**.  `check_file` on the edited barrel (11.3 s) and on
   `Setoid.Homomorphisms.HomomorphicImages` (6.7 s), both with
   `checkedFromSource: false` after a fresh `make check`, so each figure is
   the load alone.  `exports_of` with `module: ""` on the barrel (8.1 s, of
   which 8.0 s the lane's first load) returned no exports, confirming that
   the barrel re-exports nothing.  `resolve_name` of a definition from the
   removed module's tables, asked from the barrel (11 ms on the reused
   lane), returned `inScope: false`, confirming the import was gone.
+  **What worked**.  The knowledge lane answered the question the edit
   raised (is anything of the removed module still in scope here?) in
   milliseconds once loaded, which no batch check can say; and
   `checkedFromSource` made plain that the two `check_file` calls were loads,
   not checks.
+  **What was awkward or missing**.  The checker needed each module's
   imports, and no tool returns them: `get_dependencies` answers about
   definitions, so the oracle came from `agda --dependency-graph` on the
   command line.  Its graph is transitively reduced (604 edges against 1,607
   direct imports), which is easy to misread as a disagreement; a tool
   returning a module's direct imports, or the graph with a flag saying it is
   reduced, would have served directly.  Nor can a tool profile: the
   per-module table of `--profile=modules`, run from an empty build and
   pinned to a performance core (on this hybrid processor an efficiency core
   doubled a module's CPU time), was the evidence for every marker, and the
   open `profile_file` issue asks only for `--profile=internal`.
+  **Command line comparison**.  The command line was the right loop for
   this work, which was whole-library and flag-heavy (`taskset`, RTS options,
   `--profile=modules`, `--dependency-graph`, an empty build directory);
   the batch tools take a file and none of those.  agda-mcp earned its place
   as the confirming step after the edits, where it was faster and more
   specific than a re-check.

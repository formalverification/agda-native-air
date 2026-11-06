<!-- File: docs/field-reports/2026-11-06-fls-stale-pin-and-proof-repairs.md -->

# 2026-11-06, formal-ledger-specifications: a stale pinned Agda, then mechanical proof repairs

+  **Date**: 2026-11-06.
+  **Harness**: Claude Code 2.1.316.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: xhigh (max for the session's first half).
+  **Repository**: IntersectMBO/formal-ledger-specifications.
+  **Issue or pull request**: not named.
+  **Tools called**: type_of 2.

The session rebased a stack of four proof branches onto a `master` that had
changed three shapes the proofs depend on: an environment record traded a
field for a larger one, a reflexive-transitive closure became a dedicated data
type with its own constructors, and a rule's premise tuple was reordered.  It
resolved two rebase conflicts, repaired the proofs, and checked every branch's
whole closure and the test library.  For most of the session the server could
not serve this repository at all: its registration runs one pinned Agda
environment, built by hand from the project's flake, and the project's
`flake.lock` had moved past it on 2026-10-22, so every load failed inside a
dependency (`NotInScope` in the set library, measured by earlier sessions).
William had the pin rebuilt mid-session; after that the server answered at
once.

+  **Tools used**.  After the rebuild, `type_of` on `Ledger.Prelude` (first
   load 10.6 s) and on the Dijkstra `Utxow` module, whose rule `master` had
   just changed (load 44 s, checked from source).  Both returned the expected
   types.  No other call: the repairs were done from the command line (below).
+  **What worked**.  Once the pin matched the flake, the lane loaded a heavily
   imported module in 11 s against a cache seeded from a sibling worktree, and
   a changed module in 44 s.  The rebuild itself was one `nix build` of the
   flake's environment, instant because the dev shell had already built it.
+  **What was awkward or missing**.  The stale pin is invisible from inside
   the server.  Its only symptom is a scope error deep in a dependency, which
   reads as broken code rather than as a configuration that no longer matches
   the project, and it went unnoticed for two weeks across sessions in two
   harnesses.  A startup check comparing the pinned environment with the one
   the project's flake names would have reported it in one line.  Separately,
   `check_file` runs agda in the session's own worktree, so it cannot check a
   file in a sibling worktree, and all four branches lived in siblings.  The
   lane tools can serve a sibling, but they write to that sibling's interface
   cache, which the session's batch checks were using at the same time.
+  **Command line comparison**.  For this work the command line was the more
   efficient loop.  The repairs were renames and reorderings: the first batch
   error named the first site exactly (`InstanceNoCandidate` for the vanished
   field's accessor), and a grep for the old constructor and field names found
   every other site at once.  No proof was written from a hole, so
   hole-driven development had nothing to offer, and three batch checks ran
   in parallel, one per worktree and cache, which one lane per project root does
   not allow.

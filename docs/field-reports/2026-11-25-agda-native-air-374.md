<!-- File: docs/field-reports/2026-11-25-agda-native-air-374.md -->

# 2026-11-25, agda-native-air: the move to the released Agda 2.9.0

+  **Date**: 2026-11-25.
+  **Harness**: Claude Code 2.1.332.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: formalverification/agda-native-air.
+  **Issue or pull request**: issue 374, pull request 380.
+  **Tools called**: none through the client (the server never connected);
   check_file 7, sent by hand over JSON-RPC to the built binary.

The session moved this repository from the 2.9.0 nightly (agda/agda
`da66a8c`) and the patched standard-library 2.3 to the released Agda 2.9.0
(`da046d69`) and standard-library 2.4.1, which meant moving agda-mcp's own
toolchain while proving that the server still reads every Agda it serves.
The server needed no change: the release prints every message class
`Diagnostics` parses, and every `--interaction-json` answer the lane reads,
byte for byte as the nightly does.  The work ran over two days, most of it
waiting on builds and suites at a load of 7 to 16 from other sessions.

+  **Tools used**.  The `agda` server registered by the tracked `.mcp.json`
   failed to connect at the start (`CONNECTION_CLOSED`): the session began
   in a fresh worktree, whose `dist-newstyle/` holds no build, as CLAUDE.md
   warns.  The session built it (77 s) but did not restart to pick it up,
   since the work was the server's toolchain, not proofs.  Instead it sent
   `check_file` to the built binary by hand.  Four of the seven calls were
   malformed (two named the argument `file`, two put a gold's and an
   obligation's directories on one include path, which Agda answered with
   `AmbiguousTopLevelModuleName`).  The other three checked one
   agda-algebras gold, `Homomorphism-epi-through-kernel` in the composition
   tier, at three stages.  Under the nightly (Agda `da66a8c`,
   standard-library 2.3 patched) the server answered success with 2
   diagnostics, agda-algebras' own `FixityDeclarationForNonOperator`
   warnings.  Under the release with agda-algebras' `depend:` line alone
   rewritten (Agda `da046d69`, standard-library 2.4.1), it answered success
   with 10, its cap, 8 of them `UserWarning` deprecations from another
   file.  Under the release with the five renames patched in, it answered
   the nightly's 2.  The test suite drove the server under each Agda as
   well: 704 of 704 under both, and the give-parity lane 106 of 106 under
   both.
+  **What worked**.  The cap and the per-diagnostic `file` field made the
   replayed warnings visible at once: the 8 extra diagnostics each named
   `Congruence.lagda.md`, not the checked file, which is what turned a
   "verdicts unchanged" result into a question for William about what an
   agent-bench subject would see.  The launcher's resolution messages and
   CLAUDE.md's note on a fresh worktree named the missing build correctly.
+  **What was awkward or missing**.  `check_file` passes on warnings from
   imported modules with nothing to tell them from the checked file's own
   but the `file` field, and they fill the default cap of 10 first, so a
   subject sees another library's deprecations ahead of its own file's
   diagnostics.  A per-file filter, or ranking the checked file's
   diagnostics first, would have kept the release's 8 from crowding the
   answer.  The argument is `filePath`, not `file`: a hand-written request
   meets "key \"filePath\" not found", which a client reading the schema
   avoids.  `cabal test` does not rebuild the server executable, so after a
   merge the wire tests drove the old binary and 2 of 704 failed until
   `cabal build exe:agda-mcp` ran.
+  **Command line comparison**.  For this work the command line was the
   loop: the evidence was the bare `agda` binaries of three builds on the
   same files, diffed after normalizing paths, and the server's own suites.
   The three server calls answered the one question the command line could
   not answer as directly, namely what a client is shown.

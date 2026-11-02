<!-- File: docs/field-reports/2026-11-01-private-cli-statements-first.md -->

# 2026-11-01, a private repository: statements first from the command line, with no agda-mcp server

+  **Date**: 2026-11-01.
+  **Harness**: Claude Code 2.1.316.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: none.

The session was launched from a checkout of another repository, so the agda-mcp
server registered for the library's checkouts was never connected: the
registration runs the wrapper at `${PWD}/.agda/bin/agda` of the launch
directory, and the session created the library's worktree only in its first
step, after launch.  All the Agda went through the command line instead,
`nix develop --command agda <file>` in the new worktree: about thirty
single-module checks, four `--profile=modules` runs and three whole-library
checks.  Four new modules, about 1,300 lines of literate Agda, were written
statements first: every statement a type with a `{!!}` proof, checked until the
only error was unsolved interaction metas, then proved.  All four check under
`--safe`, in 0.1 to 0.3 s each of their own.

+  **Tools used**.  None of the server's.  On the command line, a single-module
   check took about 2 s of wall time, of which about 1.5 s was the dev shell's
   startup, since every dependency's interface was already built.  A module's
   own cost came from `--profile=modules` after deleting its interface file,
   since otherwise Agda only loads it.
+  **What worked**.  The statements-first loop works in batch mode: with holes,
   Agda stops with `UnsolvedInteractionMetas` and the holes' locations (25 in
   one module) and no other error, which is the confirmation that every
   statement type-checks.  The other errors were precise and cheap to act on:
   `NoParseForApplication` for a postfix operator of lower precedence than the
   infix one beside it; `AmbiguousName` twice, when an opened module exported
   names that clashed with the file's own generalizable level variables, and
   once when an imported record type shared its name with a definition of an
   opened module (a renaming on import fixed it); `IllegalPatternInTelescope`
   for an `@`-pattern binder in a record's parameters, which a module's
   telescope accepts; `UnequalTerms` for a mixfix operator whose index argument
   came after the argument whose type depends on it (a `syntax` declaration
   fixed it); and `UnsolvedMetaVariables` from Σ inference in the equality of
   two tuples (stating them as vectors fixed it).  Two of the four modules
   checked on the first run after their proofs were written.
+  **What was awkward or missing**.  Batch mode prints a hole's location and
   not its goal or context.  The proofs here were planned by hand before they
   were written, so that cost nothing; a proof found by exploration would need
   the interaction protocol scripted by hand, or the server.  A session cannot
   attach the server to a worktree it creates after launch.  A filtered log can
   hide whether the target was checked at all, so each check's exit status and
   the interface file's timestamp were read.  Batch checks run in one worktree
   at once share its interface directory, so a whole-library timing run made
   while single-module checks ran beside it was repeated alone for clean
   figures.
+  **Command line comparison**.  For this work the command line was adequate,
   and probably no slower: small modules over built dependencies, about 2 s a
   check, and no goal needed.  The server would have shown each hole's goal and
   context during the statements-first stage, which matters for proofs not
   planned in advance; launching the session from the worktree it works in,
   created before launch, would have made that possible.

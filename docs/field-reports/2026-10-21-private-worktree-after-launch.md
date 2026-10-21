<!-- File: docs/field-reports/2026-10-21-private-worktree-after-launch.md -->

# 2026-10-21, a private repository: a worktree made after launch, so the server refused its files and the command line did the checking

+  **Date**: 2026-10-21.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 1.

The session filed an issue, made a new git worktree for its branch, and wrote
two new literate Agda modules there, of about 360 and 420 lines, under
`--without-K --exact-split --safe`: the first with a mutually recursive pair
of functions and a well-founded recursion, the second with decisions that run
by evaluation over finite tables.  It was launched from the repository's main
checkout, as it had to be, since its kickoff prompt creates the worktree as
the first step.  The server, bound at launch to the main checkout's library
registry, refused the worktree's files, as it is designed to; every check ran
from the command line, and both modules and the project's gate passed.

+  **Tools used**.  `check_file` once, on the first new module, refused at
   once with a `rootMismatch` naming the file's root, the registered root and
   the fix (restart the server against the worktree).  No knowledge tool was
   called: they share the same registry, and the work needed no query that
   reading the existing modules' source did not answer.
+  **What worked**.  The refusal was immediate and unambiguous, and it said
   why checking would mislead: the imports would resolve against the other
   checkout, and the answer would be about a tree the session did not ask
   about.  The command-line loop was enough for this work.  The first module
   failed once, on a missing import (`ConstructorPatternInWrongDatatype` at a
   line and column, naming the constructor and the datatype, which named the
   fix), and then checked; the second checked at its first run apart from one
   deprecation warning that named its replacement.  Eight single-module
   command-line checks took 2.2 to 5.1 s of wall time each, entering the dev
   shell included; the modules' own costs, from `--profile=modules`, were
   0.13 s and 0.85 s, and the whole-project gate from an empty build of the
   project's interfaces took 50.5 s.
+  **What was awkward or missing**.  Two things.  First, the launch order: a
   kickoff that creates a worktree cannot also be launched from it, and a
   session cannot restart its own server.  Once the dev shell had run in the
   worktree, the worktree had its own Agda wrapper and its own registry at its
   root, so the server had what it needed to check the file correctly; a way
   to rebind the server to such a checkout mid-session (a tool call, or an
   option that accepts a file whose own checkout carries a registry, and uses
   that registry rather than refusing) would have let the server serve this
   session.  Second, not the server's own: entering the dev shell from the
   command line without one environment variable rewrote the worktree's
   registry to point at a different copy of a dependency (twice this
   session), which the session caught by reading the file; a server bound to
   that registry would have followed the change without a sign.
+  **Command line comparison**.  The command line was the only loop here,
   and for this work it was not the less efficient one: the modules were
   written whole from a proof worked out beforehand, each needed one or two
   rounds, and no goal had to be opened.  With the server available,
   `check_file` would have replaced the same few command-line runs at about
   the same cost; the likely gain was the knowledge tools, for reading the
   exact types of the definitions the new code used, which the session did by
   reading source.  So this session is no test of the server's loop.

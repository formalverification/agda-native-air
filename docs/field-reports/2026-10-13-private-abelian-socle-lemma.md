<!-- File: docs/field-reports/2026-10-13-private-abelian-socle-lemma.md -->

# 2026-10-13, a private repository: one new module of group-theoretic lemmas, hole by hole (Claude Fable 5.1)

+  **Date**: 2026-10-13.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: max.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 4, get_goal 1, fill_hole 6, check_project 2.

Claude Code launched from a fresh worktree's root, before the dev shell had
been entered there; the shell was entered once from the harness (it writes
the per-checkout wrapper and registry the server is pointed at), and from
then on the server ran that worktree's Agda 2.9.0 against the sibling main
checkout's built dependency copy, with `project.root` naming the worktree on
every answer.  The task was one new literate module (about 550 lines, half
of it prose) formalizing a lemma and its corollary from a design note, over
an existing module's definitions and a library's group-theory toolkit, under
`--safe` with no postulates.  The module was designed on paper from the
sources and written whole, with six terms left as holes (one conjugation
chain and five applications of a modular-law lemma), then filled through
the server.  Result: the module green, the barrel listing it, the
whole-library gate green, in about ninety minutes of session time, with no
candidate rejected.

+  **Tools used**.  `check_file` on the module being extended first (5.0 s,
   from its interface) and then on the new module three times: the first
   run (5.4 s) reported exactly the six holes as `UnsolvedInteractionMetas`
   with their positions and nothing else, so every statement and every
   other proof in the file passed on the first check; the second (10.4 s)
   was green after the fills were written back; the third (67 s, for a
   reason found only afterward, below) was green after four long lines
   were rewrapped.  `get_goal` once
   on the first hole (5.5 s, the lane's first load at 5.4 s).  `fill_hole`
   six times (4.1, 6.5, 7.4, 8.1, 6.0, 6.6 s), each `status: ok` with the
   verdict's exit code 42 and `remainingHoles: 5`, the other holes still
   open; every candidate was written back by hand afterward in one batch.
   `check_project` twice: anchored at the module's file it failed in 14 ms
   (below); anchored at the worktree root it ran the configured gate (the
   repository's `make check`, about 4 min).  The baseline gate before any
   change was run from the shell: 3 min 45 s, 223 modules checked from
   source, most of them the dependency library's, whose interfaces that
   copy did not hold under the new Agda (and which, as it turned out,
   was a stale copy; below).
+  **What worked**.  The hole list is a usable work list: positions as
   written, the count, and a verdict that distinguishes "only holes remain"
   from a type error.  `fill_hole`'s restore-after-trial meant a candidate
   could be tried without editing, and single-line candidates left every
   other hole's position valid, so the six fills needed no re-listing.  The
   diagnostics on the first check were the whole story: no error other than
   the holes, in a file whose every signature was new.
+  **What was awkward or missing**.  `get_goal` from the interaction lane
   prints the goal and every context entry with the setoid-algebra
   machinery unfolded: the group operation appears as the interpretation of
   an operation symbol applied to a pair, so a goal that reads in the source
   as "the conjugate of `x` by `g` equals the conjugate of `x` by `b`" came
   back as twenty lines, and one hypothesis of the module (a minimality
   decision) as thirty.  The display was correct and unusable for reading;
   the proofs were derived from the library sources, not from the goals, and
   `get_goal` was not called again.  `fill_hole` patches the file in place
   and restores it, so fills cannot run concurrently; a harness that offers
   parallel tool calls will corrupt a file if a client sends two fills in
   one turn, and nothing in the answer says so.  `check_project` anchored at
   a file inside `src/` ran the configured check command in that file's
   directory rather than at the project root, and reported `make: *** No
   rule to make target 'check'` with `gate.source: server-config`; anchoring
   at the root worked.  The server reads the project's library registry at
   every call, and between the second and third `check_file` a dev shell
   entered from the harness for an unrelated Python gate, without the
   variable that points the registry at the sibling checkout's built
   dependency copy, had rewritten the registry to name a fresh copy under
   the worktree with no interfaces.  The third check therefore rebuilt the
   module's dependency closure from source (67 s instead of 10 s), and the
   gate that followed checked 43 modules against that copy.  Nothing in
   either answer said which copy was used: `project.root` names the
   worktree, and the registry's content is in the `verbose` echo only.  The
   paths in `check_project`'s output tail were the first sign, and the
   registry was repointed by hand afterward, and then back: the two copies
   turned out to be different pins (the sibling checkout's copy had not
   been refreshed since the project's lock moved, two weeks earlier), so
   the first checks had run against a stale dependency and the gate at the
   worktree's copy, the lock's pin, is the one that counts.  A server
   answer that named the registry's dependency paths by default would
   have shown the drift at once.
+  **Command line comparison**.  For this task the two loops were close.
   The server's loop (one check, one goal, six fills) cost about 60 s of
   tool time and needed no splicing by hand; the command line would have
   been one batch run per candidate at the same cost each, with the splice
   and the restore done by the session.  The server's advantages were the
   structured hole list and verdicts, and trying a candidate without
   touching the file; its disadvantages were the goal display, which could
   not be read, and the serialization the client must impose on fills.  The
   whole-library gate was the real check either way, and the baseline gate
   was faster to run from the shell in the background than to block on
   `check_project`.  Writing the module whole and checking it once would
   have reached the same green file: the hole-driven loop added confidence
   per term, not speed.

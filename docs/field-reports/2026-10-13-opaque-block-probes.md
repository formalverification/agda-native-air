<!-- File: docs/field-reports/2026-10-13-opaque-block-probes.md -->

# 2026-10-13, a private repository: probing Agda's opaque blocks for a translator's emitter

+  **Date**: 2026-10-13.
+  **Harness**: Claude Code 2.1.282.
+  **Model**: Claude Fable 5.1 (Anthropic).
+  **Effort**: xhigh.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 3.

The session changed how a translator emits Agda for a class of declarations
(every one of a kind inside an `opaque` block of its own) and added a
harness-driven fallback that re-emits one such declaration transparently when
Agda's error names it.  Before writing the emitter it probed Agda 2.8.0 with
three hand-written files of about twenty lines each, to see what Agda prints
when an opaque definition must unfold, and whether the two candidate fallback
forms check.  The emitter and the harness then produced and type-checked
modules of 41 to 2,128 declarations through the command line.

+  **Tools used**.  `check_file` on the three probe files, called in one
   batch: 200 ms, 171 ms and 184 ms, each `checkedFromSource`.  The failing
   probe answered `UnequalTerms` with `involved.expected` and
   `involved.actual` holding the two sides (`base` and `alias`, schematic
   names) and the message `alias != base of type True` followed by the
   `when checking that the expression q has type Q base` context; the two
   passing probes answered `success: true` with no diagnostics.
+  **What worked**.  The structured diagnostic settled the design in one
   call: the fallback's trigger is an error whose message proper names a
   declaration from an opaque block, and the harness tokenizes exactly the
   text `check_file` showed, before the `when checking` lines.  Three files
   in one batch, with the verdicts side by side, was the right shape for a
   "does Agda accept this form" question; nothing had to be read back from
   a log.  The files lived outside any registered library, under the
   session's scratch directory, and the server checked them without a
   library file, naming the scratch directory as the project root.
+  **What was awkward or missing**.  Nothing for the probes.  The server
   was of no use for the main work, which type-checks generated modules of
   hundreds of declarations dozens of times, rewriting one declaration
   between runs: that loop needs a batch Agda driven by a script with the
   error's line number and name parsed from the output, which the project's
   own checker does.  A `check_file` per run would have added a round trip
   and a JSON answer the script would have to parse all the same.
+  **Command line comparison**.  The command line was the more efficient
   loop for everything but the three probes: the harness ran Agda about 250
   times in all, on modules the tool would have returned as ten-diagnostic
   JSON documents.  For the probes, `check_file` was faster than the
   command line would have been, since the diagnostic's `expected` and
   `actual` fields answered the question without a second look at the file.

<!-- File: docs/field-reports/2026-11-01-private-review-checks.md -->

# 2026-11-01, pinned dependencies during review checks

+  **Date**: 2026-11-01.
+  **Harness**: Codex CLI, version not recorded.
+  **Model**: GPT-6 (OpenAI).
+  **Effort**: not recorded.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: normalize 1.

The session reviewed existing Agda changes using independent readers and
isolated source copies.  It attempted a semantic query through agda-mcp,
then used the command line with the dependency set selected by each
reviewed branch.  This report records tool behavior only.

+  **Tools used**.  One reader called `normalize` once.  The server reported
   25,591 ms and failed before evaluating the expression, with `NotInScope`
   in a dependency extension.  Tool discovery found the interaction tools;
   discovery is not counted as a call to them.
+  **What worked**.  The response identified the intended source copy as the
   project root.  The diagnostic located the dependency failure rather than
   pretending the semantic query had succeeded.
+  **What was awkward or missing**.  The session's pinned server wrapper
   still selected an older dependency set after the branch's flake lock had
   changed.  Resolving the branch's toolchain produced a different wrapper.
   The failed load therefore supplied no answer about the expression.
+  **Command line comparison**.  The command line was more efficient for
   this review because it could immediately use the matching wrapper and
   isolated caches.  A batch run checked eight closed boundary assertions;
   another checked a direct logical assertion after concrete normalization
   was blocked by an abstract equality instance.  These were review probes
   over existing definitions, so hole-driven editing offered little here.
   The result does not compare interaction latency under matching pins.

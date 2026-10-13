<!-- File: docs/field-reports/2026-10-11-codex-tool-discovery-project-check.md -->
<!--
  Recovered under issue #252.  Written on 2026-10-11 as a section of
  docs/mcp-field-reports.md in the main checkout and never committed there;
  recovered from main's stash of 2026-10-11 23:17.  The title is the
  section's heading in this directory's form (the date, then the repository
  and the work, with "#N" written "issue N"), and the header was added from
  the section's own text, "not recorded" marking what it does not say.  The
  body is the section's, unchanged.
-->

# 2026-10-11, a private repository: Codex tool discovery and the project check environment

+  **Date**: 2026-10-11.
+  **Harness**: Codex CLI 0.162.1.
+  **Model**: GPT-6.1 Sol (OpenAI).
+  **Effort**: xhigh.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: check_file 2, check_project 1.

+  **Setup**.  Codex CLI 0.162.1, GPT-6.1 Sol with `xhigh` reasoning.
   The first `ALL_TOOLS` scan contained no Agda tools.  A later scan
   exposed all 13 tools, and the session then used them.  The tool
   catalog needs another check after startup; its first snapshot is
   insufficient evidence that the server is unavailable.
+  **File checks**.  `check_file` on a valid scratch module returned
   `success:true`, exit 0, no diagnostics, and 64 ms elapsed.  It reused
   the interface (`checkedFromSource:false`).  On a separate invalid
   scratch module, it returned `success:false`, exit 42, a `NotInScope`
   diagnostic with the correct line and columns, and 54 ms elapsed.
   That call checked from source.  Both verdicts agreed with the expected
   batch Agda behavior.
+  **Project check**.  `check_project` selected the intended Makefile
   target but failed in 219 ms with exit 2 and library diagnostics.
   Its child commands found an inherited Agda 2.9.0 and a different
   registry, while `check_file` used the explicitly configured Agda
   2.8.0 wrapper.  Selecting the right Makefile did not ensure the gate
   used the same toolchain as the file checker.
+  **CLI comparison**.  The same project gate passed in 23 seconds through
   the pinned Nix shell with Agda 2.8.0.  The CLI loop was more efficient
   for this session's batch syntax checks because it kept the toolchain
   correct and ran the generated fixtures together.  The server's file
   diagnostics were useful once discovered; its project environment
   needs correction before it can replace the CLI gate here.

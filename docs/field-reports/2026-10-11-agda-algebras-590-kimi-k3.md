<!-- File: docs/field-reports/2026-10-11-agda-algebras-590-kimi-k3.md -->
<!--
  Recovered under issue #252.  Written on 2026-10-11 as a section of
  docs/mcp-field-reports.md in the main checkout and never committed there;
  recovered from main's stash of 2026-10-11 23:17.  The title is the
  section's heading in this directory's form (the date, then the repository
  and the work, with "#N" written "issue N"), and the header was added from
  the section's own text, "not recorded" marking what it does not say.  The
  body is the section's, except that two em-dashes became a colon and a
  semicolon.
-->

# 2026-10-11, agda-algebras issue 590: canonical forms (Kimi K3, partial session)

+  **Date**: 2026-10-11.
+  **Harness**: GitHub Copilot CLI (version not recorded).
+  **Model**: Kimi K3 (Moonshot AI).
+  **Effort**: not recorded.
+  **Repository**: ualib/agda-algebras.
+  **Issue or pull request**: issue 590.
+  **Tools called**: check_file about 35.

Session: formalizing canonical forms in free lattices (ualib/agda-algebras #590)
in worktree `590-m3-11-free-lattices-canonical-form`.  agda-mcp at Agda 2.8.0,
project at 2.9.0.

**Used**: `check_file` (~35 calls, 2-8 s each, all against
`src/Classical/Structures/Lattice/Free/Canonical.lagda.md` and a scratch file).
**Not used**: `fill_hole`, `get_goal`, `type_of`, `resolve_name`,
`search_by_name` (lookups were done with grep/Read against the nix-store stdlib
instead, which was fast enough that the corpus tools never became the path of
least resistance).

What worked well: (1) the scratch-file loop: validating the representation
(three-way mutual data with head+tail constructors), the mutual-data `≈ᶜ`
family, and WF-recursion evaluation on closed terms in ~2 s per check before
writing 900 lines against those decisions; (2) `check_file` as a whole-section
gate, with diagnostics precise enough to fix one issue per cycle.

What was awkward: (1) errors from `with`-defined functions (`stepJ`, stdlib
`filter`) arrive as giant `UnsolvedConstraints`/`UnsolvedMetaVariables` dumps
whose root cause ("the scrutinee is hidden inside another definition, so the
goal never reduces", or "a meta predicate cannot unify against a concrete
lambda inside a stuck with-application") is nowhere in the message; each cost
several cycles.  (2) `fill_hole` was not attempted because the development is
heavy on nested pattern matches where a whole clause is the natural unit; the
failures were structural, not goal-shaped.  (3) No way to ask the server for a
stdlib name's exact signature (`definition_of` might have served; I only
noticed it existed late).

CLI comparison: for single-module checks the MCP (2-8 s, source-fresh) beat
`nix develop --command agda` (~20 s startup) every time, so the CLI was never
tempting mid-development; the 2.9.0 `make check` remains the final gate and
was not run in this partial session.

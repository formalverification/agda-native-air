<!-- File: docs/field-reports/2026-11-22-private-barrel-layout-batch-agda.md -->

# 2026-11-22, a private library's module layout: name clashes measured in batch

+  **Date**: 2026-11-22.
+  **Harness**: Claude Code 2.1.330.
+  **Model**: Claude Opus 5.5 (Anthropic).
+  **Effort**: high.
+  **Repository**: a private repository.
+  **Issue or pull request**: not named.
+  **Tools called**: none.

The session reorganized a library of about two hundred literate Agda modules
into re-exporting "barrel" modules, and first had to measure, with Agda, every
name that two modules export with different definitions, since a barrel that
re-exports both is rejected.  It called no agda-mcp tool.  The session was
launched from the repository's main checkout and created the working tree it
edited in its own first step, so the server, bound to the main checkout's
library registry, would have refused every file of that tree with a
`rootMismatch` (a known limit, recorded in earlier reports).  The work went
through batch `agda` and through `agda --interaction-json` driven by a script.

+  **Tools used**.  None of the server's.  In their place, four scripted
   `--interaction-json` sessions over built interfaces, each one load and then
   a list of commands: 71 `Cmd_show_module_contents_toplevel` (5.1 s of user
   time in all, 1,454 names and 96 module names); 58
   `Cmd_why_in_scope_toplevel` on qualified names (4.0 s); and, from a client
   of each new barrel, one `Cmd_infer_toplevel` per exported name and one
   `Cmd_why_in_scope_toplevel` per exported module (1,432 commands in 23 s for
   the largest).  Batch `agda --no-libraries` on a dozen two-line scratch
   modules settled the semantics first, and about thirty-five batch checks of
   scratch barrels confirmed the table.
+  **What worked**.  The protocol answers every command in band, so one
   process answered a thousand questions after a single load, and an error
   (an ambiguous name, an unsolved constraint) came back as an answer to that
   command without ending the stream.  `why_in_scope` names each candidate's
   definition site, which is what decides "two definitions" against "one
   definition reached by two paths"; reading the site is more robust than
   reading the qualified name, since a record type is listed twice, as a name
   and as a module, at one site.  The batch probes found three facts worth
   stating for anyone designing re-exports under Agda 2.9.0: a module that
   publicly re-exports two definitions of one name is rejected at the second
   `open` (`ClashingDefinition`; `ClashingModule` for two modules); a client
   that opens a module wholesale and then declares one of its names is
   rejected at the declaration, even in a `where` block or a nested module,
   while bound variables shadow freely; and overloaded constructors are
   accepted, a bare use with no expected type leaving an unsolved constraint.
+  **What was awkward or missing**.  The server's `exports_of` and
   `resolve_name` answer the same questions one name at a time, and this work
   needed about 1,500 of them; a batch form, or `exports_of` returning each
   member's definition site, would have let the server do it in one call per
   module.  The launch-location limit decided the matter before any of that:
   a session whose first step creates its working tree cannot reach that tree
   through a server started earlier.  A `why_in_scope` message wraps its
   lines at a fixed width, so a parser must normalize whitespace before
   matching `its definition at <path>`.
+  **Command line comparison**.  For this work the scripted protocol was the
   more efficient loop, by far: the clash table is a cross product of module
   contents, which a per-name tool interface would have turned into thousands
   of round trips, and the batch checks of scratch modules needed nothing the
   server adds.  The server would have helped for the few interactive
   questions (what a given name resolves to in a given file), had it been
   bound to the right tree.

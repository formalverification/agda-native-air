<!-- File: docs/README.md -->

# docs/: what lives where

An index of this directory and a reading order for a new collaborator.  The repository's top-level [`README.md`](../README.md) is the front door; this file is the map of the documentation behind it.

## Subdirectories

+  [`adr/`](adr/): architecture decision records, numbered in order of adoption.  Each states a design's context, its decisions with status and evidence, a decision-log table, and references; the deep notes a record distills stay where they are and are linked per decision.  [`0001`](adr/0001-proof-search-on-agda-mcp.md) is proof search on agda-mcp; [`0002`](adr/0002-agda-mcp.md) is the agda-mcp server itself.
+  [`agda-mcp/`](agda-mcp/): the agda-mcp server's deep design notes: the interaction lane (the two-lane policy, the wire protocol as probed, lifecycle, and economics), the ask-Agda audit, the environment forensics (what the server and its shell hook write where, and which tree a call checks), and the executive summary of the [#68] hardening wave.  The tool contracts themselves live beside the code in [`agda-mcp/README.md`](../agda-mcp/README.md).
+  [`proof-search/`](proof-search/): the proof-search component's explanatory note: what the search is, how it works on a real obligation, how to run it, and how to read a run.  Its decisions and its measured record are in [`adr/0001`](adr/0001-proof-search-on-agda-mcp.md).
+  [`benchmarks/`](benchmarks/): the M1-5 baseline benchmark's difficulty taxonomy and its obligations document; the suite itself, its index, and its README are under [`data/benchmarks/`](../data/benchmarks/).
+  [`corpora/`](corpora/): one dataset card per published corpus cut, and the procedure for publishing a corpus release.
+  [`feedback/`](feedback/): documents imported from consumer projects (sessions in `ualib/agda-algebras`), kept verbatim apart from their header comments: the field report that motivated the [#68] wave, and the consumer-side case for corpus proof search.
+  [`notes/`](notes/): working notes and background reading (currently a prior-art report on AI for theorem proving).

## Top-level documents

The vision and plan documents are as follows:

+  [`MANIFESTO.md`](MANIFESTO.md): motivation and vision.
+  [`PLAN.md`](PLAN.md): the project plan by phase (v2.2, a living document).
+  [`GITHUB_PROJECT.md`](GITHUB_PROJECT.md): the living roadmap by milestone and issue, synced with GitHub; its marked regions are engine-generated, so edit only outside them.
+  [`roadmap.md`](roadmap.md): the frozen bootstrap plan the repository's issues were populated from (dated 2026-03-13).
+  [`architecture.md`](architecture.md): the system architecture, layer by layer, with per-layer status.

The contract documents are as follows:

+  [`representation.md`](representation.md): the data contract for what `agda-strux` emits (JSONL) and the views derived from it; referenced from code and dataset cards.
+  [`policy_contract.md`](policy_contract.md): the policy-backend request and response JSON contract (v0).
+  [`GLOSSARY.md`](GLOSSARY.md): the ML and search terms used here.

The operating guides are as follows:

+  [`HowToRun.md`](HowToRun.md): the copy-and-paste developer guide, end to end; § 13 configures agda-mcp against an external Agda project.
+  [`WORKFLOW.md`](WORKFLOW.md) and [`WORKFLOW-Cheatsheet.md`](WORKFLOW-Cheatsheet.md): the issue, branch, and worktree workflow, in full and condensed.
+  [`branch-protection-setup.md`](branch-protection-setup.md): the admin runbook for the repository's merge settings.
+  [`public-history.md`](public-history.md): notes on the migration that made the repository public.

The evidence record is as follows:

+  [`mcp-field-reports.md`](mcp-field-reports.md): the session-by-session record of agda-mcp in real use, appended newest last.  It stays at this path deliberately: the agda-algebras and fls standing instructions (in the claude-tooling repository) tell sessions in those projects to append to it by path.

## Reading order for a new collaborator

1.  [`MANIFESTO.md`](MANIFESTO.md) for why, then [`architecture.md`](architecture.md) for what.
2.  [`HowToRun.md`](HowToRun.md) §§ 1–3 to get a shell, a build, and the tests running; the rest as needed.
3.  [`GITHUB_PROJECT.md`](GITHUB_PROJECT.md) for where the work stands.
4.  [`adr/0002-agda-mcp.md`](adr/0002-agda-mcp.md) for the server's design and the evidence behind it, with [`agda-mcp/README.md`](../agda-mcp/README.md) open beside it for the tool contracts; the notes under [`agda-mcp/`](agda-mcp/) when a decision's detail matters.
5.  [`proof-search/overview.md`](proof-search/overview.md) for how the search built on top of the server works, then [`adr/0001-proof-search-on-agda-mcp.md`](adr/0001-proof-search-on-agda-mcp.md) for its decisions and numbers, and [`benchmarks/taxonomy.md`](benchmarks/taxonomy.md) for how it is scored.
6.  [`feedback/`](feedback/) and [`mcp-field-reports.md`](mcp-field-reports.md) for what agents actually do with the tools, which is what the next design decisions will be argued from.

<!-- GitHub references -->
[#68]: https://github.com/formalverification/agda-native-air/issues/68

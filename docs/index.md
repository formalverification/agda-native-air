---
# File: docs/index.md
#
# The project site's landing page (issue #169).  It is the one file in docs/
# written for a reader of the site rather than for a contributor;
# docs/README.md is the contributors' index of this directory and is not
# published.  [M6-3] (#171) writes the landing page proper in its place; this
# one exists so the skeleton has a page to build, and so the demo stays one
# click from the site's root while it does.  Every figure below is quoted from
# the README as of 2026-09-21; #171 replaces them with figures read from the
# generated data, so they cannot drift.
title: agda-native-air
description: >-
  Agda-native AI reasoning: the interaction, retrieval, and evaluation
  infrastructure that lets AI agents work with the Agda proof assistant.
---

# Agda-native AI reasoning

`agda-native-air` builds the infrastructure that lets AI agents work with the
[Agda](https://wiki.portal.chalmers.se/agda) proof assistant: a server that
exposes Agda's proof state and type-checking verdicts to any agent over the
Model Context Protocol, corpora extracted from real libraries, a benchmark of
proof obligations with gold solutions, and the measurements of frontier models
and of a native proof search on all of it.  Agda remains the final arbiter of
correctness.

## Watch a real session

[The demo](demo/index.html) replays five sessions from the committed archive:
a frontier model, the `agda-mcp` server, and one proof obligation each, with
every tool call and every answer on the page in full, beside the 55-row
measurement they belong to.  Nothing on that page is typed by hand.  It is
generated from the archive under `reports/agent-bench/`, and the build refuses
to publish it when a number disagrees with the decision record it was checked
against.

## Read the record

+  The source, the benchmark, the corpora, and the archives are on
   [GitHub](https://github.com/formalverification/agda-native-air).  Cite them
   by their GitHub URL or a Zenodo DOI, not by this site's address: the site is
   the front door, not the archive.
+  [ADR 0002](https://github.com/formalverification/agda-native-air/blob/main/docs/adr/0002-agda-mcp.md)
   is the server's design record, and
   [ADR 0001](https://github.com/formalverification/agda-native-air/blob/main/docs/adr/0001-proof-search-on-agda-mcp.md)
   is proof search on top of it, with the numbers.
+  The documentation for contributors starts at the repository's
   [README](https://github.com/formalverification/agda-native-air#readme).

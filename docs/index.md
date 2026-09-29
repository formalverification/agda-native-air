---
# File: docs/index.md
#
# The project site's landing page (issue #171): what agda-native-air is, what
# has been measured and what it showed, and where to go next, in about one
# screen.  It is the one file in docs/ written for a reader of the site rather
# than for a contributor; docs/README.md is the contributors' index of this
# directory and is not published.
#
# No figure below is typed.  Each `@fig(<run-id> <selector>)` is replaced at
# build time by scripts/python/site/figures_hook.py with the value it names in
# reports/agent-bench/<run-id>/report.json, either a JSON pointer into that
# report or a figure the hook derives from it by a named, tested function, and
# the build fails on a marker it cannot resolve.  So the source cites every
# figure, and the page cannot drift from the archive.  The story is
# docs/reading-the-results.md's; when that guide's reading changes, this page
# changes with it.
title: agda-native-air
description: >-
  Tools that let AI agents prove theorems in Agda, a benchmark that measures
  what they do with them, and what the measurements have shown so far.
figures: true
---

# Agda-native AI reasoning

`agda-native-air` builds tools that let AI agents prove theorems in the
[Agda](https://wiki.portal.chalmers.se/agda) proof assistant, and measures
what the agents do with them.  Its server, `agda-mcp`, gives any agent Agda's
own answers over the Model Context Protocol: does this file type-check, what
does this hole need, where is this name defined.  Its benchmark poses proof
obligations with gold solutions, mined from Agda's standard library and from
agda-algebras or posed for the purpose, and Agda itself decides whether each
attempt type-checks and still proves the statement it was given.

[Watch a real session](demo/index.html){ .md-button .md-button--primary }

## What the measurements say

+  **With the server, frontier models solve most of the benchmark, or all of
   it**: Opus 5
   solves @fig(suite219-opus5-mcp-1 /totals/solved) of the
   @fig(suite219-opus5-mcp-1 /totals/total) mined obligations, and Sonnet 5
   solves @fig(suite219-sonnet5-mcp-1 /totals/solved).
+  **Without the server, a shell does as well**: Sonnet 5 solves
   @fig(suite219-sonnet5-shell-1 /totals/solved), running `agda` itself.
   Given both, it took every final verdict from the server's `check_file`
   (@fig(suite219-sonnet5-both-1 /perVerdictVia/mcp) of
   @fig(suite219-sonnet5-both-1 /totals/total)) and called its knowledge
   tools @fig(suite219-sonnet5-both-1 knowledge-tool-calls) times, against
   @fig(suite219-sonnet5-mcp-1 knowledge-tool-calls) with no shell.
+  **The mined rows cannot tell the two apart**.  On the
   @fig(suite219-sonnet5-shell-1 rows-with-original) rows that restate a
   library lemma, the library's source was readable, and
   @fig(suite219-sonnet5-shell-1 /totals/solvedOriginalInView) of the
   shell's @fig(suite219-sonnet5-shell-1 solved-with-original) solves there
   came with the original proof in view; on the other
   @fig(suite219-sonnet5-shell-1 rows-without-original) rows, every
   configuration solves nearly all.
+  **Neither can the first hard rows, so far**.  On
   @fig(hard-opus5-mcp-1 /totals/total) statements posed with no proof on
   disk, Opus 5's final file type-checks with its statement intact on
   @fig(hard-opus5-shell-1 final-checks-statement-kept) with a shell,
   @fig(hard-opus5-mcp-1 final-checks-statement-kept) with the server, and
   @fig(hard-opus5-both-1 final-checks-statement-kept) with both.  Those
   runs had each fixture's proof sketched in its header, and their re-run
   without the sketch is still to come.
+  **A fixture's header used to name the answer**.  Until 2026-09-29 each
   haystack fixture's header named the one lemma its proof needs.  With that
   line in view, Sonnet 5 solved
   @fig(agent-sonnet5-1 haystack-unqueried) of those
   @fig(agent-sonnet5-1 /perStratum/agda-stdlib~1haystack/total) rows
   asking Agda nothing before its final check; without it,
   @fig(suite219-sonnet5-mcp-1 haystack-unqueried), and on the rest it
   asked first, mostly through the server's search.  Every figure above but the hard rows' is from runs whose
   headers carry no hints.

So a model wants the server's verdict, and beside a shell it wants little
else.  Whether the tools help a model prove what it could not prove without
them is still open: that takes statements harder for the model than these,
and those are the next instruments.

[Reading the results](reading-the-results.md) gives every number with the run
that produced it; its
[§ 4.5](reading-the-results.md#45-the-hard-tier) says why the hard tier's
solved column reads lower than the counts above, and its
[§ 4.6](reading-the-results.md#46-what-the-fixture-headers-were-worth) what
the fixture headers' hints were worth.
[ADR 0002](adr/0002-agda-mcp.md) records the server's design, and
[ADR 0001](adr/0001-proof-search-on-agda-mcp.md) a proof search built on it
with no model in the loop.  The source, the benchmark, and the run archive
are on [GitHub](https://github.com/formalverification/agda-native-air); cite
them by their GitHub URL, not by this site's address, since the site is the
front door and not the archive.

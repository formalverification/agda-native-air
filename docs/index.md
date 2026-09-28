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

+  **With the server, frontier models solve most of the benchmark**: Opus 5
   solves @fig(agent-opus5-1 /totals/solved) of the
   @fig(agent-opus5-1 /totals/total) mined obligations, and Sonnet 5 solves
   @fig(agent-sonnet5-1 /totals/solved).
+  **Without the server, a shell does as well**: Sonnet 5 solves
   @fig(arm162-shell-1 /totals/solved), running `agda` itself.  Given both, it
   took every final verdict from the server's `check_file`
   (@fig(arm162-both-1 /perVerdictVia/mcp) of
   @fig(arm162-both-1 /totals/total)) and called its knowledge tools
   @fig(arm162-both-1 knowledge-tool-calls) times, against
   @fig(arm162-mcp-1 knowledge-tool-calls) with no shell.
+  **The mined rows cannot tell the two apart**.  On the
   @fig(arm162-shell-1 rows-with-original) rows that restate a library lemma,
   the library's source was readable, and
   @fig(arm162-shell-1 /totals/solvedOriginalInView) of the shell's
   @fig(arm162-shell-1 solved-with-original) solves there came with the
   original proof in view; on the other
   @fig(arm162-shell-1 rows-without-original) rows, every configuration solves
   nearly all.
+  **Neither can the first hard rows**.  On
   @fig(hard-opus5-mcp-1 /totals/total) statements posed with no proof on
   disk, Opus 5's final file type-checks with its statement intact on
   @fig(hard-opus5-shell-1 final-checks-statement-kept) with a shell,
   @fig(hard-opus5-mcp-1 final-checks-statement-kept) with the server, and
   @fig(hard-opus5-both-1 final-checks-statement-kept) with both.

So a model wants the server's verdict, and beside a shell it wants little
else.  Whether the tools help a model prove what it could not prove without
them is still open: that takes statements harder for the model than these,
and those are the next instruments.

[Reading the results](reading-the-results.md) gives every number with the run
that produced it, and its
[§ 4.5](reading-the-results.md#45-the-hard-tier) says why the hard tier's
solved column reads lower than the counts above.
[ADR 0002](adr/0002-agda-mcp.md) records the server's design, and
[ADR 0001](adr/0001-proof-search-on-agda-mcp.md) a proof search built on it
with no model in the loop.  The source, the benchmark, and the run archive
are on [GitHub](https://github.com/formalverification/agda-native-air); cite
them by their GitHub URL, not by this site's address, since the site is the
front door and not the archive.

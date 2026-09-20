<!-- File: web/README.md -->

# `web/` : the demo site's assets

This directory holds the committed assets of the demo site (Issue [#85]): the
stylesheet, the replay script, and the favicon.  It holds no HTML.  The page
is generated, never committed, and the generator lives in
[`scripts/python/demo/`](../scripts/python/demo).

## Building it

```sh
make demo          # demo-data, then demo-site
```

+  `make demo-data` reads the committed archive under
   [`reports/agent-bench/`](../reports/agent-bench) and writes one small JSON
   per replay, plus the benchmark table, to `data/demo/`.
+  `make demo-site` renders `site/index.html` from those and copies this
   directory's files to `site/assets/`.
+  `make demo-clean` removes both output directories.

Both outputs are gitignored.  The build reads only files of this repository,
makes no network request, and needs nothing but Python 3: no Agda, no server,
no model call.  It refuses to write a page whose benchmark table disagrees
with [ADR 0001](../docs/adr/0001-proof-search-on-agda-mcp.md) § 9, or one
carrying an absolute path from the machine the sweep ran on.

`.github/workflows/pages.yml` runs the same two targets and deploys the
result to GitHub Pages.

## The two files, and the line between them

+  **`demo.css`** decides the page's appearance and, in its `--motion-*`
   custom properties, the replay's timing.  `replay.js` reads every duration
   off computed style, so this is the one place the rhythm is set.
+  **`replay.js`** replays a session that is *already on the page*.  The
   generator renders every session finished, so a crawler, a reader with
   JavaScript off, and a reader with `prefers-reduced-motion` on all see
   complete sessions with the script doing nothing; the script rewinds that
   state and types it back in.  It invents no content and marks up nothing:
   every character it types was in the element it types it back into, and the
   generator's own markup is restored as each line finishes.

The markup contract between them is stated in
[`scripts/python/demo/render.py`](../scripts/python/demo/render.py)'s header
and asserted by
[`scripts/python/tests/test_demo_render.py`](../scripts/python/tests/test_demo_render.py),
which builds the page and checks it: the selectors the script depends on, that
every tool answer is on the page in full, and that nothing is fetched from off
the origin at page load.

## What the page may not do

+  Fetch anything from another origin at load.  No web font, no CDN, no
   analytics; the typefaces are the reader's own system stacks, and the
   workflow greps the built page for an off-origin `src` or `href` before it
   deploys.
+  Present anything as a quotation that is not one.  The archived transcripts
   carry each thinking block's signature and an empty string in place of its
   text, so the page marks where the model thought and says the text is not
   there.
+  Abbreviate an answer without an affordance to see the whole one.  Every
   tool answer is on the page in full, behind a control that says how long it
   is; the summary beside it quotes named fields of the answer body rather
   than describing them, so no abbreviation can hide a `type_error` or a
   failed verdict.

[#85]: https://github.com/formalverification/agda-native-air/issues/85

"""
File: scripts/python/demo/__init__.py

Description: Generators for the agda-native-air demo site (Issue #85).

  The site is built in two steps, each a Makefile target:

    +  `make demo-data` reads the committed agent-bench archive under
       `reports/agent-bench/` and writes one small JSON per replay, plus the
       benchmark table, under `data/demo/`.
    +  `make demo-site` renders those into a static page under `site/`.

  Nothing here talks to Agda, to a model, or to the network; every fact on the
  page is read out of a file that is already in the repository.
"""

<!-- File: scripts/README.md -->

# scripts

Repository-level utility scripts that support the build, the MCP server, and the
project's Python tooling.  They are wrappers and helpers around the extraction,
ETL, and evaluation pipelines — sbt invocation, the MCP server launch, metadata and
report generation — rather than pipeline stages themselves, and are wired into
`Makefile` targets and `.mcp.json`.

## Shell wrappers

+  `run-sbt.sh` runs sbt in a reproducible, pinned-JDK environment (`JAVA_HOME`
   pinning, Spark/Java 17+ `--add-opens` flags, optional `AGDA_JSON_BIN` injection).
   It is the Makefile's `SBT_RUNNER`, so every sbt-driven target goes through it.

+  `run-server.sh` launches the `agda-mcp` server inside the `nix develop .#backend`
   shell, routing the Nix banner to stderr so it does not corrupt the MCP JSON-RPC
   framing on stdout.  It is the command configured in `.mcp.json`.

## Python tooling

These live under `scripts/python/` and are invoked by Makefile targets or run
directly during development.

+  `agda_lib_metadata.py` generates library metadata; it backs `make metadata`.

+  `normalize_bench_report.py` strips non-deterministic fields from a benchmark
   report so two runs can be compared byte-for-byte; it backs the determinism
   check in `make eval-benchmark-smoke`.

+  `doc_check.py` lints documentation; see `doc_check_guide.md` for the rules.

+  `gh_project_populate.py` is roadmap tooling that populates the GitHub project
   board and labels.

+  `utils/` holds shared helpers (config, command running, file operations, text
   processing) plus fixture and dataset tooling for the proof-completion work.

+  `tests/` holds the pytest suite for the Python tooling above.

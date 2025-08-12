# Where Scala/Spark fits

We have two separable loops.

1.  **Prover loop (tight, I/O-light)** Propose term → check in Agda → keep successes.

    + Best in **Python** (PyTorch/JAX/TF) talking to Agda via the JSON interaction.

    + FP style: *pure transforms* for data; IO/Agda calls at the edges; use immutable
      dataclasses (frozen), typed function signatures, and explicit dependency
      injection.

2.  **Data plumbing (heavy, parallel)**  Mining large Agda corpora, deduping,
    generating synthetic goals, statistics, sharding to Parquet, etc.

    + This is where **Scala/Spark** shines (distributed ETL, joins over symbol
      tables, scalable sampling).

    + Keep it optional: if size(dataset) < a few million examples, Python + Polars/Arrow
      may suffice. If it grows, plug Spark back in with minimal friction.

**A pragmatic compromise**

+  Start with **Python-only** ETL (Polars/pyarrow) and a clean FP-ish architecture:

   +  `domain/` pure transforms (no IO), `adapters/agda/` for JSON interaction,
      `adapters/fs/` for IO, `pipeline/` for orchestration.

   +  Use immutable configs (pydantic/attrs), small pure functions, and
      property-based tests (Hypothesis).

+  If/when scale demands, we mirror the same transforms in **Spark** (Scala),
   reading/writing the same Arrow/Parquet schemas. Our previous Scala work won't be
   wasted; we'll lift the hotspots only.



## Glossary (ML/LLM terms used here)

+  **Beam search**: like BFS, but at each depth you keep only the "best K" nodes (the
   *beam*) instead of all nodes. "Best" is decided by a **scoring** function.

+  **Scoring** (here): a hand-written function that prefers partial proofs that look
   closer to done; e.g., fewer visible binders remaining, constructor-headed goals,
   or simpler goal types. No probability model is required.




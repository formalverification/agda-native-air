<!-- File: docs/field-reports/2026-10-22-fls-leios-pr-review.md -->

# 2026-10-22, fls: checking a quorum predicate without editing Agda

+  **Date**: 2026-10-22.
+  **Harness**: Codex (version not recorded).
+  **Model**: GPT-6 (OpenAI).
+  **Effort**: not recorded.
+  **Repository**: IntersectMBO/formal-ledger-specifications.
+  **Issue or pull request**: pull request 1346, pull request 1355.
+  **Tools called**: type_of 1, normalize 8.

This session reviewed two public Leios pull requests, one extending the chain
rule and one naming whether the keyed committee seats have enough weight for
a quorum.  The server checked the latter's decision procedure on concrete
weights without a scratch Agda module.  Separate CLI checks covered both
complete import closures, and temporary Haskell probes exercised the extracted
chain entry point.  No Agda source was edited.

+  **Tools used**.  `type_of` loaded the predicate's defining file in a
   detached review worktree and reported its parameterized type.  `normalize`
   then evaluated six variants in the same file's scope; two earlier calls
   returned expression errors while constructing rational constants.  At a
   threshold of 75 percent of total active stake, keyed seats holding 74, 75,
   and 76 percent of that stake produced bodies reducing to false, true, and
   true.  An empty committee, an entirely keyless committee, and a committee
   split equally between keyed and keyless seats produced false bodies.  Each
   result retained the abstraction over unused inputs.
+  **What worked**.  Each expression quantified over the governance structure,
   parameters, pool hash, and key it did not need to inspect.  Updating only
   the threshold in the quantified parameter record avoided constructing the
   whole record.  Taking the Boolean projection of the decision let
   `normalize` answer directly, without assembling or printing a proof.  The
   project root in the response named the detached review worktree.

   The successful equality-boundary request was the following (line breaks
   added):

   ```agda
   λ gs pp kh vk → does (¿ certifiable gs
     (record pp { leiosQuorumStakeThreshold = clamp (ℚ.normalize 3 4) })
     (record { pool = kh ; weight = clamp (ℚ.normalize 3 4)
             ; key = just vk } ∷ []) ¿)
   ```

   Its `normalForm` field was exactly the following:

   ```agda
   λ gs pp kh vk → Agda.Builtin.Bool.Bool.true
   ```

+  **What was awkward or missing**.  My first rational expression supplied a
   natural where an integer was required; the next tried a constructor name
   unavailable in that scope.  Both errors were returned with Agda diagnostic
   codes.  Using `Data.Rational.normalize` on two naturals resolved this.
   These were mistakes in the queries, with useful diagnostics from the
   server.  No hole-driven editing was needed for this review, so the session
   provides no evidence about `get_goal` or `fill_hole`.
+  **Command line comparison**.  The persistent server was the simpler loop
   for these predicate questions: it reused the loaded file and required no
   source edits.  The pinned CLI remained appropriate for build verdicts.
   Compiling and running temporary Haskell probes exercised the exported
   chain entry point and its conversions.

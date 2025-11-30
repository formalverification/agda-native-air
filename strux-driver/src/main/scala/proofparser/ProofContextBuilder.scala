/** ============================================================================
 *  ProofContextBuilder.scala
 *  ---------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/ProofContextBuilder.scala
 *  Package: proofparser
 *  Copyright: (c) 2024 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  Pure functions to build `ProofContext` rows from canonical `AgdaData` rows.
 *
 *  Design (Phase 0)
 *  ----------------
 *  We intentionally keep the first version simple:
 *
 *    - group by (file, module) to approximate a local scope;
 *    - treat each `AgdaData` row with a non-empty type as a goal;
 *    - define context as "other declarations in same group rendered as
 *      `name : type` when `agdaType` is present";
 *    - reuse normalized `premises` from `AgdaData` (usually Nil for now);
 *    - preserve the original `proof` (if any) for supervised training.
 *
 *  This is sufficient to:
 *
 *    - produce high-level proof-from-context examples;
 *    - feed instruction-tuning JSONL builders;
 *    - revise internals later (richer context/premises) without breaking
 *      downstream consumers, as long as the public schema remains stable.
 *
 *  Later phases can refine:
 *
 *    - the notion of "context" (Agda reflection, dependency graphs);
 *    - premise selection (semantic filters, dependency-based premises);
 *    - goal selection and curriculum (difficulty, domain, etc.).
 *
 *  Pure, total, referentially transparent: no IO, no global state.
 *
 ** ============================================================================ */

package proofparser

import proofparser.schema.{AgdaData, ProofContext}

object ProofContextBuilder {

  /** Build `ProofContext` rows from a collection of `AgdaData` rows.
    *
    * Grouping strategy
    * -----------------
    * We group by `(file, module)` because:
    *
    *   - file: avoids accidentally mixing unrelated modules with the same
    *     name that live in different directories;
    *   - module: reflects the Agda logical namespace and is stable under
    *     minor refactorings of file layout.
    *
    * Within each group, each row with a non-empty `agdaType` yields a
    * `ProofContext`. Its context is all other rows in the same group.
    */
  def fromAgdaData(rows: Vector[AgdaData]): Vector[ProofContext] = {
    // Group rows by (file, module) to approximate a "local theory".
    val grouped: Map[(String, Option[String]), Vector[AgdaData]] =
      rows.groupBy(r => (r.file, r.module))

    // For each group, produce examples for each goal row with a type.
    val examplesPerGroup: Iterable[Vector[ProofContext]] =
      grouped.values.map(buildGroupExamples)

    // Flatten in a predictable order (not strictly required, but nicer).
    examplesPerGroup.toVector.flatten
  }

  /** Build examples within a single (file, module) group. */
  private def buildGroupExamples(group: Vector[AgdaData]): Vector[ProofContext] = {
    // In a purely functional style, we avoid mutable builders.
    group.flatMap { goalRow =>
      goalRow.agdaType match {
        case None =>
          // Rows without a type are not useful as "goals" for now.
          Vector.empty

        case Some(goalType) =>
          val idPrefix: String = goalRow.module.getOrElse("<none>")
          val id: String       = s"$idPrefix.${goalRow.name}"

          val contextLines: Vector[String] =
            group
              .filterNot(_.name == goalRow.name)
              .flatMap { ctx =>
                ctx.agdaType.map { tpe =>
                  s"${ctx.name} : $tpe"
                }
              }

          Vector(
            ProofContext(
              id            = id,
              file          = goalRow.file,
              module        = goalRow.module,
              goalName      = goalRow.name,
              goalType      = goalType,
              contextLines  = contextLines,
              premises      = goalRow.premises.toVector,
              proof         = goalRow.proof
            )
          )
      }
    }
  }
}

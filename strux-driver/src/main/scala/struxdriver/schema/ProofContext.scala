/** ============================================================================
 *  ProofContext.scala
 *  ---------------------------------------------------------------------------
 *
 *  File: strux-driver/src/main/scala/struxdriver/schema/ProofContext.scala
 *  Package: struxdriver.schema
 *
 *  Description
 *  -----------
 *  Canonical training row for "proof-from-context" models.
 *
 *  This is the unit of data we want to hand to the ML pipeline, in contrast
 *  to `AgdaData` which is closer to a raw extraction from Agda/regex.
 *
 *  Intuition
 *  ---------
 *  Each row encapsulates
 *
 *    - a *goal* we would like the model to prove;
 *    - the *type* of that goal;
 *    - a textual approximation to its *context* (other relevant declarations);
 *    - an (optional) list of *premises* (names of lemmas to use);
 *    - an (optional) *proof* term (for supervised training).
 *
 *  This is intentionally simple and text-oriented so that:
 *
 *    - we can serialize it as JSONL / Parquet easily;
 *    - it maps cleanly to instruction-tuning formats;
 *    - we can refine "context" and "premises" semantics later without
 *      breaking the surrounding infrastructure.
 *
 *  Suggested interpretation for ML:
 *
 *    - "input"  := (goalType, contextLines, premises)
 *    - "target" := proof.getOrElse("")  // or omitted for pure ranking tasks
 *
 *  Schema → PyArrow / Spark
 *  ------------------------
 *  A natural columnar schema for this case class is:
 *
 *    - id            : string           // stable identifier
 *    - file          : string
 *    - module        : string?          // nullable
 *    - goal_name     : string
 *    - goal_type     : string
 *    - context_lines : list<string>     // textified context
 *    - premises      : list<string>     // lemma names
 *    - proof         : string?          // nullable
 *
 *  This can be reflected as
 *
 *    - a PyArrow schema (for the Python side), or
 *    - a Spark StructType (for Scala/Spark ETL).
 *
 ** ============================================================================ */

package struxdriver.schema

import upickle.default.{ReadWriter, macroRW}

final case class ProofContext(
  id:            String,
  file:          String,
  module:        Option[String],
  goalName:      String,
  goalType:      String,
  contextLines:  Vector[String],
  premises:      Vector[String],
  proof:         Option[String]
)

object ProofContext {
  implicit val rw: ReadWriter[ProofContext] = macroRW
}

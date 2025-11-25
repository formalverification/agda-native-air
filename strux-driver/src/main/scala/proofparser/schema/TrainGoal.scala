/** ============================================================================
 *  TrainGoal.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/schema/TrainGoal.scala
 *  Package: proofparser.schema
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  Utility to construct the training goal string for ML models.
 *  This is the goal-centric representation used in premise selection / evaluation
 *  (e.g. “given a goal type, which premises should the model pick?”).
 *
 *  Usage
 *  -----
 *      import proofparser.schema.TrainGoal
 *      val goal = TrainGoal(...)
 *
 *  ============================================================================
 */

package proofparser.schema
import upickle.default._
/**
  * A single “training goal” for premise selection.
  *
  * Rough sketch of semantics:
  *
  *   - `module`:
  *       optional module name where the goal lives.
  *
  *   - `goalType`:
  *       the type we are trying to prove / complete.
  *
  *   - `imports`:
  *       names of declarations considered “available” as premises
  *       when attempting this goal (e.g. per-module imports).
  *
  * This is meant to be a small JSON-friendly and Spark-friendly
  * record that can be fed to ranking models.
  */
final case class TrainGoal(
  module: Option[String],
  goalType: String,
  imports: List[String]
)

object TrainGoal {
  implicit val rw: ReadWriter[TrainGoal] = macroRW
}

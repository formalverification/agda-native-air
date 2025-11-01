/**
 * SimpleSchema.scala
 *
 * FILE
 *   proof-parser/src/main/scala/proofparser/SimpleSchema.scala
 *
 * DESCRIPTION
 *   Minimal schema for training examples: Pos/Range, CtxVar, TrainRecord,
 *   with upickle codecs. Designed for JSONL emission and quick eyeballing.
 *
 * USAGE
 *   import proofparser.{TrainRecord, CtxVar, Range, Pos}
 *   val json = upickle.default.write(TrainRecord(...))
 *
 * EXAMPLES
 *   // See Agda2TrainReducer and AgdaExtractorMain for writers.
 *
 * NOTES
 *   - Keep types stable; only append optional fields to avoid breaking old corpora.
 *   - goalType/solution are pretty-printed Agda strings by design.
 *
 * (c) 2025 Thmpr Lab, LLC.
 */

package proofparser

import upickle.default._

/**
 * SimpleSchema (goal-centric training rows)
 *
 * PURPOSE
 *   `TrainRecord` represents individual goal/context snapshots (e.g., from
 *   AllGoalsWarnings), which is intentionally distinct from `AgdaData`
 *   (declaration/proof rows). Keep them separate to avoid field drift.
 *
 * INVARIANTS
 *   - file:    base filename (keep extension here; this is used by live extractor)
 *   - module:  fully-qualified module string, or "" if unknown.
 *   - decl:    local identifier (no module prefix).
 *   - goalType/solution/context/imports: pretty-printed strings as surfaced by Agda.
 *
 * SERIALIZATION
 *   upickle (see companion implicits).
 */
final case class Pos(line: Int, col: Int)
object Pos { implicit val rw: ReadWriter[Pos] = macroRW }

final case class Range(start: Pos, end: Pos)
object Range { implicit val rw: ReadWriter[Range] = macroRW }

final case class CtxVar(name: String, `type`: String)
object CtxVar { implicit val rw: ReadWriter[CtxVar] = macroRW }

final case class TrainRecord(
  file: String,
  module: String,
  decl: String,
  context: List[CtxVar],
  goalType: String,
  solution: Option[String] = None,
  range: Option[Range] = None,
  imports: List[String] = Nil
)
object TrainRecord { implicit val rw: ReadWriter[TrainRecord] = macroRW }


/** Minimal normalization helpers for TrainRecord. Mirrors AgdaDataOps ideas. */
object TrainRecordOps {
  import proofparser.AgdaDataOps._

  /** Normalize module/decl to documented invariants. */
  def normalize(r: TrainRecord): TrainRecord = {
    val m = normalizePremise(r.module)          // collapse hidden, strip .agda variants
    val d = stripAngle(r.decl)
    r.copy(module = m, decl = d)
  }
}

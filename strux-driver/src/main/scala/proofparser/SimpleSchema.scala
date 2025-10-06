/**
 * SimpleSchema.scala
 *
 * File: proof-parser/src/main/scala/proofparser/SimpleSchema.scala
 *
 * Description:
 *   Minimal schema for training examples: Pos/Range, CtxVar, TrainRecord,
 *   with upickle codecs. Designed for JSONL emission and quick eyeballing.
 *
 * Usage:
 *   import proofparser.{TrainRecord, CtxVar, Range, Pos}
 *   val json = upickle.default.write(TrainRecord(...))
 *
 * Examples:
 *   // See Agda2TrainReducer and AgdaExtractorMain for writers.
 *
 * Notes:
 *   - Keep types stable; only append optional fields to avoid breaking old corpora.
 *   - goalType/solution are pretty-printed Agda strings by design.
 *
 * (c) 2025 Thmpr Lab, LLC.
 */

package proofparser

import upickle.default._

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

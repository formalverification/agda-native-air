/**
 * Model.scala
 *
 * File: proof-parser/src/main/scala/proofparser/Model.scala
 *
 * Description:
 *   Defines the `AgdaData` case class used to represent theorems extracted from Agda
 *   files, including their names, types, proofs, and associated metadata;
 *   provides a canonical data model for simplified training rows
 *   (AgdaData/TrainRecord/etc).  Kept small and human-readable to aid iteration,
 *   inspection and inference.
 *
 * Usage:
 *   import proofparser.{AgdaData, TrainRecord, CtxVar, Range}
 *
 * Examples:
 *   val rec = TrainRecord(file="Foo.agda", module="Foo", decl="Foo.bar",
 *                         context=Nil, goalType="A → B", solution=None)
 *
 * Notes:
 *   - Please add new fields conservatively; prefer Option[...] for backwards compatibility.
 *   - Serialization uses upickle; keep RW codecs in companion objects.
 *
 * (c) 2025 Thmpr Lab, LLC.
 */
package proofparser

import upickle.default._

/** Canonical row for v1 datasets. */
final case class AgdaData(
  file: String,
  module: Option[String],
  name: String,
  agdaType: String,
  proof: String,
  premises: List[String] = Nil
)
object AgdaData { implicit val rw: ReadWriter[AgdaData] = macroRW }

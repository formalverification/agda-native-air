/**
 * Model.scala
 *
 * Description: Data model for Agda theorem extraction.
 *
 * This file defines the `AgdaData` case class used to represent
 * theorems extracted from Agda files, including their names,
 * types, proofs, and associated metadata.
 *
 * File: agda-ai-prover/proof-parser/src/main/scala/proofparser/Model.scala
 *
 * Copyright (c) 2024 Thmpr.
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

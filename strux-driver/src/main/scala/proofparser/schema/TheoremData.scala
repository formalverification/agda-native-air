/** ============================================================================
 *  TheoremData.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/schema/TheoremData.scala
 *  Package: proofparser.schema
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  Low-level representation of an Agda declaration extracted via
 *  reflection.  This is the “early extractor” shape—direct reflection output before
 *  we split declarations into type/proof/etc. It stays extremely simple and
 *  JSONL-friendly.
 *
 *  Usage
 *  -----
 *     import proofparser.schema.TheoremData
 *     val data = TheoremData(...)
 *
 *  ============================================================================
 */
package proofparser.schema
import upickle.default._

/**
  * Low-level representation of an Agda declaration extracted via
  * reflection, before we split it into type/proof/premises.
  *
  *   - `file`:
  *       path to the source file containing the declaration.
  *
  *   - `module`:
  *       optional module name where this declaration lives.
  *
  *   - `name`:
  *       simple declaration name (no module prefix).
  *
  *   - `body`:
  *       textual representation of the declaration body, as dumped
  *       by the current extractor (e.g. a pretty-printed AST or
  *       a raw snippet).
  *
  * This type is intentionally “dumb”; the logic that turns it
  * into [[AgdaData]] lives in transformer modules such as
  * `Agda2TrainTransformer`.
  */
final case class TheoremData(
  file: String,
  module: Option[String],
  name: String,
  body: String
)

object TheoremData {
  implicit val rw: ReadWriter[TheoremData] = macroRW
}

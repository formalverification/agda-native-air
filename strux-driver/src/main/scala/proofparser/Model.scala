/**
  * MODEL — canonical training row types for agda-ai-prover.
  *
  * File: proof-parser/src/main/scala/proofparser/Model.scala
  *
  * PURPOSE
  *   `AgdaData` is the single contract our downstream ETL/training expects.
  *
  * FIELDS & INVARIANTS
  *   - file:      base module file name WITHOUT extension when possible (e.g., "agda-example")
  *                Rationale: stable ID stems shouldn’t depend on extensions.
  *   - module:    optional fully-qualified module string or segments (decide here; see TODO).
  *   - name:      local identifier; may include a disambiguator suffix like `<40>`.
  *   - agdaType:  pretty-printed type.
  *   - proof:     pretty-printed definition body.
  *   - premises:  fully-qualified references used in proof; must be normalized (see Normalization).
  *
  * NORMALIZATION
  *   We centralize:
  *     - stripAngle("<n>")              // remove trailing disambiguators
  *     - stripAgdaDot("x.agda.y")       // collapse ".agda." and suffix ".agda"
  *     - collapseHidden("._.")          // collapse hidden module segments
  *     - isSelfPremise(record, premise) // membership test after normalization
  *
  * USAGE
  *   All producers should call `AgdaData.normalize(record)` to cleanse fields & premises.
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

object AgdaDataOps {
  def baseFile(file: String): String =
    if (file.endsWith(".agda")) file.stripSuffix(".agda") else file

  def stripAngle(s: String): String =
    s.replaceAll("<\\d+>$", "")

  def stripAgdaDot(path: String): String =
    path.replace(".agda.", ".").stripSuffix(".agda")

  def collapseHidden(path: String): String =
    path.replace("._.", ".")

  def normalizePremise(p: String): String =
    stripAgdaDot(collapseHidden(stripAngle(p)))

  def selfIdVariants(file: String, module: Option[String], name: String): List[String] = {
    val f  = baseFile(file)
    val nm = stripAngle(name)
    val v0 = s"$f.$nm"
    val v1 = module.filter(_.nonEmpty).map(m => s"$f.$m.$nm").getOrElse(v0)
    val v2 = s"$f.agda.$nm"
    val v3 = module.filter(_.nonEmpty).map(m => s"$f.agda.$m.$nm")
    (List(v1, v0, v2) ++ v3).map(normalizePremise)
  }

  def isSelfPremise(r: AgdaData, p: String): Boolean =
    selfIdVariants(r.file, r.module, r.name).contains(normalizePremise(p))

  def normalize(r: AgdaData): AgdaData = {
    val cleanedPremises = r.premises.distinct.filterNot(isSelfPremise(r, _))
    r.copy(
      file     = baseFile(r.file),
      name     = r.name,                  // could stripAngle here for canonical name
      premises = cleanedPremises
    )
  }
}

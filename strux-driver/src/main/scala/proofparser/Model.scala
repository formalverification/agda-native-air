/**
 * Model.scala -- Canonical declaration/proof row types for agda-ai-prover.
 *
 * FILE
 *   proof-parser/src/main/scala/proofparser/Model.scala
 *
 * PURPOSE
 *   `AgdaData` is the single contract downstream ETL/training expects for
 *   declaration/proof rows (not goal snapshots).
 *
 * FIELDS & INVARIANTS
 *   - file:      base module file name WITHOUT extension when possible (e.g., "agda-example").
 *                Rationale: stable ID stems shouldn’t depend on extensions.
 *   - module:    Option[String] — fully-qualified, dot-separated module name (e.g., "Data.Nat.Properties"),
 *                or None if unknown.
 *   - name:      local identifier; may include an Agda disambiguator suffix like "<40>" in raw inputs.
 *   - agdaType:  pretty-printed type.
 *   - proof:     pretty-printed definition body.
 *   - premises:  fully-qualified references used in the proof; normalized (see NORMALIZATION).
 *
 * NORMALIZATION
 *   Centralized here to keep producers/consumers consistent:
 *     - baseFile("Foo.agda")           => "Foo"
 *     - stripAngle("+-suc<40>")        => "+-suc"
 *     - stripAgdaDot("x.agda.y")       => "x.y" and strip suffix ".agda"
 *     - collapseHidden("Foo._.Bar")    => "Foo.Bar"
 *     - normalizePremise(s)            => collapseHidden(stripAgdaDot(stripAngle(s)))
 *     - isSelfPremise(record, prem)    => membership test after normalization
 *
 * USAGE
 *   All producers should call `AgdaDataOps.normalize(record)` to:
 *     - drop self-premises,
 *     - enforce baseFile(file),
 *     - (optionally) stripAngle from names to choose a canonical name policy.
 *
 * NOTES
 *   -  `name` is *kept as parsed* (may include `<n>`); producers may choose to strip
 *      via a policy toggle.
 *   -  `premises` should be stored **post-normalization** (callers can pass raw
 *      inputs; `normalize` will cleanse and drop self-premises).
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

object AgdaDataOps {
  def baseFile(file: String): String =
    if (file.endsWith(".agda")) file.stripSuffix(".agda") else file

  def stripAngle(s: String): String =
    s.replaceAll("<\\d+>$", "")

  def stripAgdaDot(path: String): String =
    path.replace(".agda.", ".").stripSuffix(".agda")

  def collapseHidden(path: String): String =
    path.replace("._.", ".")

  /** Remove any trailing '.' (one or more). */
  def stripTrailingDots(s: String): String =
    s.replaceAll("\\.+$", "")

  def normalizePremise(p: String): String =
    stripTrailingDots(stripAgdaDot(collapseHidden(stripAngle(p))))

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

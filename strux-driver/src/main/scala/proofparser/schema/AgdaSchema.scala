/** ============================================================================
 *  AgdaSchema.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/schema/AgdaSchema.scala
 *  Package: proofparser.schema
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  Canonical schema for Agda “theorem-like” declarations
 *  (definitions, postulates, theorems, lemmas, etc.).
 *
 *  Usage
 *  -----
 *     import proofparser.schema.{AgdaData, AgdaDataOps}
 *     val record = AgdaDataOps.normalize(AgdaData(...))
 *
 *  Notes
 *  -----
 *  -  Clean separation:
 *     -  `AgdaData` = “raw extracted semantics”
 *     -  `TheoremData` = “intermediate summarised theorem statement”
 *     -  `TrainRecord` = “final ML input format”
 *  -  Semantic enrichment: we will add `declKind`, `astShape`, etc. to `AgdaData`
 *  -  Keeps DatasetStats stable; we now simply do: `type Row = AgdaData`
 *  -  Proof-parser tools become easier to maintain; with fewer mismatched case class
 *     versions → fewer bugs.
 *  -  Serialization derivations `implicit val rw = macroRW` can be added once.
 *  -  Centralize normalization logic in AgdaDataOps.
 *
 * ============================================================================
 */

package proofparser.schema

// import upickle.default._
import upickle.default.{ReadWriter, macroRW}

/** AgdaData
 *  ---------
 *  Canonical representation of one “theorem-like” Agda declaration
 *  as seen by the ML pipeline.
 *
 *  Intended invariants (after [[AgdaDataOps.normalize]]):
 *
 *    - `file`:
 *        non-empty, trimmed absolute (or repo-relative) path.
 *
 *    - `module`:
 *        Some(trimmedName) for normal modules;
 *        None only when the extractor genuinely has no module.
 *
 *    - `name`:
 *        bare declaration name, trimmed. No module prefix.
 *
 *    - `agdaType`, `proof`:
 *        whitespace-normalized (collapsed to single spaces),
 *        no leading/trailing whitespace.
 *
 *    - `premises`:
 *        unique, sorted, whitespace-normalized names of
 *        other declarations this one depends on.
 *
 *  This shape is meant to be:
 *    - friendly to git/JSONL (no huge nested structures),
 *    - easy to map to Spark Datasets/DataFrames,
 *    - a stable contract between “extractor” and “trainer”.
 */
/**
 * AgdaData
 * --------
 * One logical training row:
 *   - a single Agda declaration (definition/lemma/etc.)
 *   - plus derived semantic features.
 *
 * JSON fields must stay stable; we control them here.
 */
final case class AgdaData(
  file: String,                   // absolute or project-relative path
  module: Option[String],         // Agda module name, if known
  name: String,                   // declaration name
  agdaType: Option[String],       // rendered type (maybe empty)
  proof: Option[String],          // rendered body/proof (maybe empty)
  premises: List[String],         // dependency names (maybe empty)
  declKind: DeclKind,             // coarse semantic kind
  astSize: Int                    // cheap complexity estimate
) {

  /** Helper: true if both type and proof are effectively empty. */
  def isEmpty: Boolean =
    agdaType.forall(_.trim.isEmpty) &&
      proof.forall(_.trim.isEmpty)
}

object AgdaData {
  /** upickle JSON (de)serialization */
  implicit val rw: ReadWriter[AgdaData] = macroRW
}

/** AgdaDataOps
 *  -----------
 *  Pure helper operations on [[AgdaData]].
 *
 *  Kept separate from the case class so they feel more like
 *  “library utilities” than methods with hidden side effects.
 */
object AgdaDataOps {

  /** Collapse all whitespace to single spaces and trim. */
  private def stripWhitespace(s: String): String =
    s.replaceAll("\\s+", " ").trim

  private def stripWhitespaceOpt(os: Option[String]): Option[String] =
    os.map(stripWhitespace).filter(_.nonEmpty)

  /**
    * Normalize premise list:
    *   - strip whitespace from each name,
    *   - drop empties,
    *   - deduplicate,
    *   - sort for a stable order.
    */
  private def canonicalPremises(ps: List[String]): List[String] =
    ps.map(stripWhitespace)
      .filter(_.nonEmpty)
      .distinct
      .sorted

  /**
    * Return a normalized copy of the record satisfying the invariants
    * documented on [[AgdaData]].
    */
  def normalize(r: AgdaData): AgdaData =
    r.copy(
      file     = r.file.trim,
      module   = r.module.map(_.trim).filter(_.nonEmpty),
      name     = r.name.trim,
      agdaType = stripWhitespaceOpt(r.agdaType),
      proof    = stripWhitespaceOpt(r.proof),
      premises = canonicalPremises(r.premises)
    )
}

// Row type alias (used by tools like DatasetStats and SampleGen)
type Row = AgdaData

// Previously, `Row` was implemented as a case class, which is now renamed `OldRow`:
/** OldRow **
 *  The core `OldRow` type that we use in evaluation / small analyses: a denormalised
 *  view of one declaration with its premises expanded as a sequence.
 *
 *  Denormalised representation of a declaration used in evaluation
 *  and small-scale analysis tools.
 *
 *  Compared to [[AgdaData]]:
 *  -  `module` is a plain String (for convenience when tabulating),
 *  -  `premises` is a Vector instead of List (nice for indexing),
 *  -  everything is fully materialised, ready for JSON lines or
 *     Spark Datasets.
 *
 *  This type deliberately stays “minimal”; if you need additional
 *  derived metrics (lengths, counts, etc.), prefer defining a
 *  separate StatsRow or similar in the analysis module.
 */
final case class OldRow(
  name: String,
  module: String,
  agdaType: String,
  proof: String,
  premises: Vector[String]
)
object OldRow {
  implicit val rw: ReadWriter[OldRow] = macroRW
  /**
    * Convert from the canonical [[AgdaData]].
    *
    * Missing module is rendered as "<none>" to keep the field total.
    */
  def fromAgdaData(d: AgdaData): OldRow =
    OldRow(
      name      = d.name,
      module    = d.module.getOrElse("<none>"),
      agdaType  = d.agdaType.getOrElse(""),
      proof     = d.proof.getOrElse(""),
      premises  = d.premises.toVector
    )
}


/** TheoremData
 *  -----------
 *  Low-level representation of an Agda declaration extracted via
 *  reflection, before we split it into type/proof/premises.
 *
 *  -  `file`: path to the source file containing the declaration.
 *  -  `module`: optional module name where this declaration lives.
 *  -  `name`: simple declaration name (no module prefix).
 *  -  `body`: textual representation of the declaration body, as dumped
 *     by the current extractor (e.g. a pretty-printed AST or
 *     a raw snippet).
 *
 *  This type is intentionally “dumb”; the logic that turns it
 *  into [[AgdaData]] lives in transformer modules such as
 *  `Agda2TrainTransformer`.
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


/** TrainGoal
 *  ---------
 *  Utility to construct the training goal string for ML models.
 *  This is the goal-centric representation used in premise selection / evaluation
 *  (e.g. “given a goal type, which premises should the model pick?”).
 *
 *  A single “training goal” for premise selection.
 *
 *  Rough sketch of semantics:
 *
 *    - `module`:
 *        optional module name where the goal lives.
 *
 *    - `goalType`:
 *        the type we are trying to prove / complete.
 *
 *    - `imports`:
 *        names of declarations considered “available” as premises
 *        when attempting this goal (e.g. per-module imports).
 *
 *  This is meant to be a small JSON-friendly and Spark-friendly
 *  record that can be fed to ranking models.
 */
final case class TrainGoal(
  module: Option[String],
  goalType: String,
  imports: List[String]
)

object TrainGoal {
  implicit val rw: ReadWriter[TrainGoal] = macroRW
}


/** TrainRecord.scala
 *  -----------------
 *  Flat, string-only representation used by downstream ETL/ML code
 *  (JSONL → CSV → Parquet) where premises are squashed into a single string column.
 *
 * This is intentionally simpler than [[AgdaData]]:
 *    - `module` is always a String (no Option) so it can be a single column.
 *    - `premises` are concatenated into one string, which plays nicer with
 *      basic feature extractors or simple text models.
 *
 *  Higher-level code (Spark, Python trainers) can decide whether to:
 *    - treat these as raw text fields; or
 *    - explode the `premises` string back into a sequence.
 */
final case class TrainRecord(
  module: String,
  name: String,
  agdaType: String,
  proof: String,
  premises: String
)

object TrainRecord {
  /**
    * Lossy but convenient projection from [[AgdaData]] to [[TrainRecord]].
    *
    * Design choices:
    *   - missing module → "<none>" (so it remains a single string column),
    *   - premises joined by spaces (simple and token-friendly).
    */
  def fromAgdaData(d: AgdaData): TrainRecord = {
    val moduleString = d.module.getOrElse("<none>")
    val premisesStr  = d.premises.mkString(" ")
    TrainRecord(
      module   = moduleString,
      name     = d.name,
      agdaType = d.agdaType.getOrElse(""),
      proof    = d.proof.getOrElse(""),
      premises = premisesStr
    )
  }
}

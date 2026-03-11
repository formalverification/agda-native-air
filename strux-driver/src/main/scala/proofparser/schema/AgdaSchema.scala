package proofparser.schema

/** ===========================================================================
 *  AgdaSchema.scala
 *  ---------------------------------------------------------------------------
 *
 *  File: strux-driver/src/main/scala/proofparser/schema/AgdaSchema.scala
 *  Package: proofparser.schema
 *
 *  Description
 *  -----------
 *  Canonical definitions of all core datatypes used throughout the
 *  strux-driver module. This file replaces older, duplicated schema
 *  definitions and serves as the single source of truth for:
 *
 *   • AgdaData        – a single extracted declaration
 *   • TrainRecord     – ML-ready training row
 *   • TrainGoal       – goal/query for premise selection evaluation
 *   • TheoremData     – intermediate summary representation
 *
 *  This module enforces:
 *
 *   • consistent JSON serialization (uPickle)
 *   • consistent normalization and cleaning of names, modules, premises
 *   • referentially transparent, functional helpers
 *
 * ===========================================================================
 */

import upickle.default.{ ReadWriter, macroRW }

/** ------------------------------------------
  *  Declaration Kind (syntactic, upgraded later)
  *  ------------------------------------------ */
/**
 * DeclKind
 * --------
 * A lightweight classification of the *kind* of declaration.
 *
 * This starts syntactic (based on name/module/type) but is meant
 * to be refined using Agda reflection/elaboration in AgdaExtractor.
 */
sealed trait DeclKind {
  def asString: String
}

object DeclKind {
  case object Definition  extends DeclKind { val asString = "definition"  }
  case object Postulate   extends DeclKind { val asString = "postulate"   }
  case object Data        extends DeclKind { val asString = "data"        }
  case object Record      extends DeclKind { val asString = "record"      }
  case object Module      extends DeclKind { val asString = "module"      }
  case object Constructor extends DeclKind { val asString = "constructor" }
  case object Projection  extends DeclKind { val asString = "projection"  }
  case object Lemma       extends DeclKind { val asString = "lemma"       }
  case object Theorem     extends DeclKind { val asString = "theorem"     }
  case object Axiom       extends DeclKind { val asString = "axiom"       }
  case object Unknown     extends DeclKind { val asString = "unknown"     }

  val all: List[DeclKind] =
    List(Definition, Postulate, Data, Record, Module,
      Constructor, Projection, Lemma, Theorem, Axiom, Unknown)

  def fromString(s: String): DeclKind =
    all.find(_.asString == s).getOrElse(Unknown)

  implicit val rw: ReadWriter[DeclKind] = upickle.default.readwriter[ujson.Value].bimap[DeclKind](
    dk => dk.asString,
    js => fromString(js.str)
  )
}


/** ------------------------------------------------------
 *  Semantic info produced by the semantic-light extractor
 *  ------------------------------------------------------
 * Bundle of lightweight semantic signals per declaration.
 *
 * For now we only track:
 *   - kind       : coarse declaration kind (Definition / Lemma / Data / ...)
 *   - astSize    : cheap "complexity" estimate based on type+proof text
 *
 * In future we can add:
 *   - scope, visibility, universe level, etc.
 *   - fully elaborated core size
 */
final case class SemanticInfo(
  kind: DeclKind,
  astSize: Int
)

object SemanticInfo {
  implicit val rw: ReadWriter[SemanticInfo] = macroRW
}


/** ------------------------------------------------------
  *  Primary dataset row: canonical representation of a
  *  single Agda declaration (type + proof + metadata).
  * ------------------------------------------------------ */
final case class AgdaData(
  file: String,                    // absolute or project-relative
  module: Option[String],          // Agda module path if known
  name: String,                    // declaration name
  agdaType: Option[String],        // type signature text
  proof: Option[String],           // proof body / definition
  premises: List[String],          // dependencies (raw or normalized)
  declKind: DeclKind,              // syntactic/semantic declaration kind
  astSize: Int                     // approximate AST size
)
object AgdaData { implicit val rw: ReadWriter[AgdaData] = macroRW }


/** ------------------------------------------------------
  *  TrainRecord – final ML-ready training item
  * ------------------------------------------------------ */
final case class TrainRecord(
  module: String,
  name: String,
  agdaType: String,
  proof: String,
  premises: String
)
object TrainRecord { implicit val rw: ReadWriter[TrainRecord] = macroRW }

/** ------------------------------------------------------
  *  TrainGoal – premise-selection evaluation item
  * ------------------------------------------------------ */
final case class TrainGoal(
  module: String,
  name: String,
  goalType: String,
  premises: List[String]
)
object TrainGoal { implicit val rw: ReadWriter[TrainGoal] = macroRW }

/** ------------------------------------------------------
  *  TheoremData – used by Agda2TrainTransformer
  * ------------------------------------------------------ */
final case class TheoremData(
  module: Option[String],
  name: String,
  tpe: Option[String],
  body: Option[String],
  premises: List[String]
)
object TheoremData { implicit val rw: ReadWriter[TheoremData] = macroRW }

/** ===========================================================================
  * Normalization utilities for AgdaData
  * ===========================================================================
  *
  * This is a cleaned and improved version of the logic originally found in
  * Model.scala + Agda2TrainTransformer. It implements:
  *
  *   • whitespace normalization
  *   • premise canonicalization
  *   • self-premise elimination
  *   • removal of Agda's <hiddens>, .agda., trailing dots
  *
  * Everything is referentially transparent and functional.
  */
object AgdaDataOps {

  /** Trim + collapse whitespace. */
  private def stripWhitespace(s: String): String =
    s.replaceAll("\\s+", " ").trim

  private def stripWhitespaceOpt(s: Option[String]): Option[String] =
    s.map(stripWhitespace).filter(_.nonEmpty)

  /** Remove <hidden> markup from identifiers. */
  private def collapseHidden(s: String): String =
    s.replaceAll("<[0-9]+>", "")

  /** Remove redundant ".agda." segments. */
  private def stripAgdaDot(s: String): String =
    s.replace(".agda.", ".")

  /** Remove angle brackets around generated names. */
  private def stripAngle(s: String): String =
    s.replace("<", "").replace(">", "")

  /** Remove trailing dots from generated names. */
  private def stripTrailingDots(s: String): String =
    s.replaceAll("\\.+$", "")

  /** Normalize a premise string. */
  private def normalizePremise(p: String): String = {
    val steps = List(stripAngle _, collapseHidden _, stripAgdaDot _, stripTrailingDots _, stripWhitespace _)
    steps.foldLeft(p){ case (acc, f) => f(acc) }
  }

  /** All self-identifier variants that should be dropped from premises. */
  private def selfIdVariants(file: String, module: Option[String], name: String): List[String] = {
    val shortFile = file.split("/").lastOption.getOrElse(file).replace(".agda", "")
    val mod       = module.getOrElse("")
    val variants  = List(
      s"$shortFile.$name",
      s"$mod.$name",
      name
    )
    variants.map(normalizePremise).distinct
  }

  /** Should we drop this premise because it refers to the same declaration? */
  private def isSelfPremise(r: AgdaData, p: String): Boolean =
    selfIdVariants(r.file, r.module, r.name).contains(normalizePremise(p))

  /** Canonicalize and deduplicate premises. */
  private def canonicalPremises(ps: List[String], self: AgdaData): List[String] =
    ps.map(normalizePremise)
      .filter(_.nonEmpty)
      .filterNot(isSelfPremise(self, _))
      .distinct
      .sorted

  /** Main entry: normalize whitespace, names, premises, drop self-premises. */
  def normalize(r: AgdaData): AgdaData = {
    val base = r.copy(
      file     = stripWhitespace(r.file),
      module   = r.module.map(stripWhitespace).filter(_.nonEmpty),
      name     = stripWhitespace(r.name),
      agdaType = stripWhitespaceOpt(r.agdaType),
      proof    = stripWhitespaceOpt(r.proof)
    )
    base.copy(
      premises = canonicalPremises(base.premises, base)
    )
  }

  /** Convert AgdaData → ML TrainRecord. */
  def asTrainRecord(r: AgdaData): TrainRecord =
    TrainRecord(
      module   = r.module.getOrElse("<none>"),
      name     = r.name,
      agdaType = r.agdaType.getOrElse(""),
      proof    = r.proof.getOrElse(""),
      premises = r.premises.mkString(" ")
    )

  /** Convert AgdaData → legacy “OldRow” structure. */
  def asLegacyRow(r: AgdaData): OldRow =
    OldRow(
      name     = r.name,
      module   = r.module.getOrElse("<none>"),
      agdaType = r.agdaType.getOrElse(""),
      proof    = r.proof.getOrElse(""),
      premises = r.premises.toVector
    )
}

/** ------------------------------------------
  * Legacy Row type (for DatasetStats / SampleGen)
  * ------------------------------------------ */
final case class OldRow(
  name: String,
  module: String,
  agdaType: String,
  proof: String,
  premises: Vector[String]
)
object OldRow { implicit val rw: ReadWriter[OldRow] = macroRW }

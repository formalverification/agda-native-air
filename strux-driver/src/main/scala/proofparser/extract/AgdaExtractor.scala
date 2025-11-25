/** ============================================================================
 *  AgdaExtractor.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/extract/AgdaExtractor.scala
 *  Package: proofparser.extract
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  Lightweight, regex-based extractor for Agda files (no Agda process).
 *
 *  This module scans `.agda` source files heuristically to recover
 *  simple declaration candidates (typically theorem/lemma-like bindings)
 *  and emits them as canonical `AgdaData` rows:
 *
 *      - file      : base file name
 *      - module    : optional Agda module name
 *      - name      : declaration name
 *      - agdaType  : optional rendered type string
 *      - proof     : optional rendered right-hand side
 *      - premises  : empty (heuristics for this will come later)
 *      - declKind  : coarse kind inferred via `Semantic.from`
 *      - astSize   : cheap complexity score (type+proof token count)
 *
 *  This extractor is:
 *
 *    • fast and local (does not invoke Agda);
 *    • heuristic (good for smoke tests / CI);
 *    • schema-consistent with the rest of the project.
 *
 *  For authoritative data (elaboration, reflection, full context),
 *  prefer Agda2Train-based pipelines or a future reflection-based extractor
 *  that uses `AgdaBridge`.
 *
 *  Usage
 *  -----
 *    import java.nio.file.Paths
 *    import proofparser.extract.AgdaExtractor
 *
 *    val rows: Vector[AgdaData] =
 *      AgdaExtractor.parseAgdaFile(Paths.get("path/to/Foo.agda"))
 *
 *  See `AgdaExtractorMain` for CLI usage that writes JSONL.
 *
 *  ============================================================================
 */

package proofparser.extract

import java.nio.file.{Files, Path, Paths}

import scala.annotation.tailrec
import scala.jdk.CollectionConverters._
import scala.util.Using
import scala.util.matching.Regex

import upickle.default._

import proofparser.schema.{AgdaData, AgdaDataOps}
import proofparser.schema.{Semantic, DeclKind, SemanticInfo}

object AgdaExtractor {

  // ===========================================================================
  //  File discovery
  // ===========================================================================

  /** Collect all `.agda` files under a directory, or return a singleton list if
    * the given path itself is a `.agda` file.
    */
  def getAgdaFiles(root: Path): List[Path] =
    if (Files.isDirectory(root))
      Files.walk(root).iterator.asScala.filter(_.toString.endsWith(".agda")).toList
    else if (Files.isRegularFile(root) && root.toString.endsWith(".agda"))
      List(root)
    else
      Nil

  // ===========================================================================
  //  Module/header parsing
  // ===========================================================================

  /** Extract `module Foo.Bar where` → Some("Foo.Bar"), else None. */
  def extractModuleName(lines: List[String]): Option[String] = {
    val ModuleDecl: Regex = """^\s*module\s+([A-Za-z_][A-Za-z0-9_\.]*)\s+where\s*$""".r
    lines.collectFirst { case ModuleDecl(name) => name }
  }

  // ===========================================================================
  //  “Theorem-like” declarations
  // ===========================================================================

  // A small token list we do NOT consider “theorem-like” (e.g. `postulate`, `data`…).
  private val ForbiddenFirstToken: Set[String] = Set(
    "postulate", "open", "import", "module",
    "data", "record", "mutual", "where",
    "infix", "infixl", "infixr", "syntax", "pragma", "private"
  )

  // Greedy but useful: a name, a colon, then the rest is the type string.
  private val Decl: Regex = """^\s*([^\s:]+)\s*:\s*(.+)$""".r

  private def isLineComment(s: String): Boolean   = s.trim.startsWith("--")
  private def isBlockCommentStart(s: String): Boolean = s.trim.startsWith("{-")
  private def isEmpty(s: String): Boolean         = s.trim.isEmpty

  /** Returns true iff the line looks like an Agda theorem/lemma type declaration. */
  def isTheoremLike(line: String): Boolean = {
    if (isEmpty(line) || isLineComment(line) || isBlockCommentStart(line)) false
    else
      line match {
        case Decl(name, _) =>
          val firstTok = line.trim.takeWhile(!_.isWhitespace)
          !ForbiddenFirstToken.contains(firstTok)
        case _ => false
      }
  }

  /** Returns true iff the line looks like a simple proof equation `name = ...`. */
  def isProofLike(line: String): Boolean =
    line.trim.nonEmpty &&
      !line.trim.startsWith("--") &&
      line.contains(" = ")

  /** Remove line comments and block-commented regions (very coarse). */
  def removeComments(lines: List[String]): List[String] = {
    val blockStart = "{-"
    val blockEnd   = "-}"

    @tailrec
    def loop(
      rem: List[String],
      inBlock: Boolean,
      acc: List[String]
    ): List[String] = rem match {
      case Nil => acc.reverse
      case line :: rest =>
        val trimmed = line.trim
        if (inBlock) {
          val newInBlock = !trimmed.contains(blockEnd)
          loop(rest, newInBlock, acc)
        } else if (trimmed.startsWith("--")) {
          loop(rest, inBlock = false, acc)
        } else if (trimmed.contains(blockStart)) {
          val newInBlock = !trimmed.contains(blockEnd)
          loop(rest, newInBlock, acc)
        } else {
          loop(rest, inBlock = false, line :: acc)
        }
    }

    loop(lines, inBlock = false, acc = Nil)
  }

  // ===========================================================================
  //  Functional theorem extraction → canonical AgdaData
  // ===========================================================================

  private final case class DeclState(
    decls: Map[String, (String, Option[String])],  // name → (type, proofOpt)
    rows:  Vector[AgdaData]                        // accumulated canonical rows
  )

  /** Pure, functional extraction of (type, proof) pairs and conversion to
    * canonical `AgdaData` using Semantic.from + AgdaDataOps.normalize.
    *
    * This mirrors the previous mutable Map/ListBuffer version but is easier
    * to reason about and keeps all logic inside a single fold.
    */
  def extractTheorems(
    lines: Seq[String],
    fileName: String,
    moduleName: Option[String]
  ): Vector[AgdaData] = {

    val cleaned = removeComments(lines.toList)

    val folded = cleaned.foldLeft(DeclState(Map.empty, Vector.empty)) {
      case (state, rawLine) =>
        val trimmed = rawLine.trim
        if (isTheoremLike(trimmed)) {
          trimmed match {
            case Decl(name, tpe) =>
              val nextDecls = state.decls.updated(name, (tpe.trim, None))
              state.copy(decls = nextDecls)
            case _ =>
              state
          }
        } else if (isProofLike(trimmed)) {
          val parts = trimmed.split("=", 2)
          if (parts.length == 2) {
            val name  = parts(0).trim
            val proof = parts(1).trim
            state.decls.get(name) match {
              case Some((tpe, _)) =>
                val row = mkAgdaData(
                  file       = fileName,
                  moduleName = moduleName,
                  name       = name,
                  tpe        = Option(tpe).filter(_.nonEmpty),
                  proof      = Option(proof).filter(_.nonEmpty)
                )
                state.copy(
                  decls = state.decls - name,
                  rows  = state.rows :+ row
                )
              case None =>
                // We saw a proof before the type; remember the proof alone for now.
                val nextDecls = state.decls.updated(name, ("", Some(proof)))
                state.copy(decls = nextDecls)
            }
          } else state
        } else {
          state
        }
    }

    // Any leftover decls: emit rows even if type or proof is missing.
    val leftovers: Vector[AgdaData] =
      folded.decls.iterator.map {
        case (name, (tpe, proofOpt)) =>
          mkAgdaData(
            file       = fileName,
            moduleName = moduleName,
            name       = name,
            tpe        = Option(tpe).filter(_.nonEmpty),
            proof      = proofOpt.filter(_.nonEmpty)
          )
      }.toVector

    folded.rows ++ leftovers
  }

  /** Construct a canonical, normalized AgdaData row from raw strings. */
  private def mkAgdaData(
    file: String,
    moduleName: Option[String],
    name: String,
    tpe: Option[String],
    proof: Option[String]
  ): AgdaData = {
    val sem: SemanticInfo =
      Semantic.from(
        name     = name,
        agdaType = tpe,
        module   = moduleName,
        proof    = proof
      )

    val raw = AgdaData(
      file     = file,
      module   = moduleName,
      name     = name,
      agdaType = tpe,
      proof    = proof,
      premises = Nil,
      declKind = sem.kind,
      astSize  = sem.astSize
    )

    AgdaDataOps.normalize(raw)
  }

  // ===========================================================================
  //  Block-based parsing helpers (kept for possible future use)
  // ===========================================================================

  def isBlockStart(line: String): Boolean =
    line.matches("""^\s*\S+\s*[:=].*""")

  def getBlockName(line: String): String =
    line.trim.takeWhile(c => !c.isWhitespace && c != ':' && c != '=')

  def isIndented(line: String): Boolean =
    line.startsWith(" ") || line.startsWith("\t")

  /** Group contiguous blocks starting with a declaration line and followed by
    * indented/blank lines. Currently not used by the extractor core, but kept
    * as a building block for more structured block-based heuristics.
    */
  def extractBlocks(lines: List[String]): List[(String, List[String])] = {
    @tailrec
    def loop(
      remaining: List[String],
      current:   Option[(String, List[String])],
      acc:       List[(String, List[String])]
    ): List[(String, List[String])] =
      remaining match {
        case Nil =>
          current.map(acc :+ _).getOrElse(acc)
        case line :: rest =>
          if (isBlockStart(line)) {
            current match {
              case Some(block) =>
                loop(rest, Some((getBlockName(line), List(line))), acc :+ block)
              case None =>
                loop(rest, Some((getBlockName(line), List(line))), acc)
            }
          } else if (isIndented(line) || line.trim.isEmpty) {
            current match {
              case Some((name, body)) =>
                loop(rest, Some((name, body :+ line)), acc)
              case None =>
                loop(rest, None, acc)
            }
          } else {
            current match {
              case Some(block) =>
                loop(rest, None, acc :+ block)
              case None =>
                loop(rest, None, acc)
            }
          }
      }

    loop(lines, current = None, acc = Nil)
  }

  // ===========================================================================
  //  Public API: parse a single file into canonical rows
  // ===========================================================================

  /** Parse one `.agda` file into canonical `AgdaData` rows. */
  def parseAgdaFile(path: Path): Vector[AgdaData] = {
    val lines: List[String] =
      Files.readAllLines(path).asScala.toList
    val module = extractModuleName(lines)
    extractTheorems(lines, path.getFileName.toString, module)
  }

  // ===========================================================================
  //  Legacy tooling (JSONL output, kept for completeness)
  // ===========================================================================

  /** Write arbitrary entries as JSONL (generic, not specific to AgdaData). */
  def writeAsJsonl[T: upickle.default.Writer](entries: Seq[T], out: Path): Unit = {
    Using(Files.newBufferedWriter(out)) { writer =>
      entries.foreach { thm =>
        writer.write(upickle.default.write(thm))
        writer.newLine()
      }
    }.get
  }

}

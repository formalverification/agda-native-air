/** ============================================================================
  *  Judge.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Judge.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  The judge of the agent-in-the-loop evaluation (issue #154): decides, for
  *  the file a subject leaves behind, whether the obligation was solved, and
  *  if not, which gate it failed.  The gates, in the order they are named:
  *
  *    1. preservation — the module header line, every original import line,
  *       and the type signature of the definition with the hole are present
  *       byte-for-byte (comment-only and blank lines aside); added import
  *       lines are allowed and reported.
  *    2. escape       — no postulate, no trustMe / primTrustMe, and no pragma
  *       of any kind (TERMINATING, NON_TERMINATING, NO_POSITIVITY_CHECK,
  *       NON_COVERING, OPTIONS, ... — the fixtures carry none, so any pragma
  *       is an addition).
  *    3. holes        — no hole token left: `{!`, or a lexically separate `?`.
  *    4. typecheck    — the gold verifier's own `agda` invocation
  *       (GoldVerifier.agdaCommand) on the final file, with `--safe` added
  *       because every committed gold passes under it, exit-code verdict.
  *
  *  A file that passes every gate but names the library's own lemma for the
  *  statement it was asked to prove is *restated*, never solved: on stdlib
  *  rows the original is the index `module` and `hole`; on agda-algebras rows
  *  the fixture's definition carries a prime (`lift∼lower′`) and the original
  *  is the unprimed name.  Evidence is any qualified token ending in the
  *  original's bare name, any import or open line that names it in a `using`
  *  or `renaming` list, or (on primed rows only, where the bare name cannot
  *  be a recursive call) the bare name itself, all read over the parts of the
  *  final file that are not the frozen statement.  The haystack tier has no
  *  original by construction (its statements are specializations the library
  *  does not state), so the gate never fires there.
  *
  *  Design notes
  *  ------------
  *  - The syntactic gates are pure functions over source text, pinned by
  *    JudgeSpec on fixture texts and over every committed obligation/gold
  *    pair; only the typecheck gate spawns Agda.
  *  - Comments are stripped before any scan (line comments, nested block
  *    comments), pragmas are kept, so a `postulate` in a comment is nothing
  *    and a `{-# TERMINATING #-}` is caught.  The scans name the gate; Agda
  *    under `--safe` is the authority that would refuse the same file anyway.
  *  - A statement is read as top-level declaration blocks (a column-0 line
  *    plus its indented continuation lines): the frozen blocks are every
  *    block of the obligation except the clauses of the hole's definition.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.IO
import java.nio.file.Path
import scala.concurrent.duration._

import struxdriver.benchmark.{GoldVerifier, Obligation => IndexEntry}

/** Lexical helpers shared by the gates: comment stripping and tokenizing on
  * Agda's own delimiters (whitespace, parentheses, braces, semicolons, `@`,
  * and string quotes; a dot stays inside a token so a qualified name is one
  * token).
  */
object Code {
  private def isDelim(c: Char): Boolean =
    c.isWhitespace || c == '(' || c == ')' || c == '{' || c == '}' || c == ';'

  /** Drop `-- ...` line comments and nested `{- ... -}` block comments; keep
    * `{-# ... #-}` pragmas and the line structure (newlines inside a block
    * comment survive, so line numbers are stable).
    */
  def stripComments(s: String): String = {
    val sb = new StringBuilder
    var i  = 0
    val n  = s.length
    while (i < n) {
      if (s.startsWith("{-#", i)) {
        val j   = s.indexOf("#-}", i)
        val end = if (j < 0) n else j + 3
        sb.append(s, i, end); i = end
      } else if (s.startsWith("{-", i)) {
        var depth = 1
        i += 2
        while (i < n && depth > 0) {
          if (s.startsWith("{-", i)) { depth += 1; i += 2 }
          else if (s.startsWith("-}", i)) { depth -= 1; i += 2 }
          else { if (s.charAt(i) == '\n') sb.append('\n'); i += 1 }
        }
      } else if (s.startsWith("--", i) && (i == 0 || isDelim(s.charAt(i - 1)))) {
        val j = s.indexOf('\n', i)
        i = if (j < 0) n else j
      } else {
        sb.append(s.charAt(i)); i += 1
      }
    }
    sb.toString
  }

  def tokens(code: String): Vector[String] =
    code.split("[\\s(){};@\"]+").toVector.filter(_.nonEmpty)

  /** The lines that carry code, as the preservation gate compares them: every
    * comment stripped first (a line inside a `{- -}` block is not code, so a
    * frozen line hidden there does not count as present: Copilot on PR #158),
    * trailing whitespace dropped, blank lines removed.  Both sides of every
    * comparison go through this, so a trailing comment on an original line is
    * tolerated and a commented-out one is not.
    */
  def keptLines(source: String): Vector[String] =
    stripComments(source).split("\n", -1).toVector.map(_.replaceAll("\\s+$", "")).filterNot(_.isEmpty)
}

/** The frozen statement of an obligation: what the subject may not change. */
final case class Statement(
  hole:         String,
  moduleLine:   String,
  importLines:  Vector[String],
  signature:    Vector[String],
  frozenBlocks: Vector[Vector[String]]
)

object Statement {
  /** Top-level declaration blocks: a column-0 line plus the indented lines
    * after it, over the kept lines (comments and blank lines dropped).
    */
  def blocks(source: String): Vector[Vector[String]] =
    Code.keptLines(source).foldLeft(Vector.empty[Vector[String]]) { (acc, l) =>
      if (acc.isEmpty || !l.head.isWhitespace) acc :+ Vector(l)
      else acc.init :+ (acc.last :+ l)
    }

  private def afterHole(line: String, hole: String): Option[String] =
    if (line.startsWith(hole) && line.length > hole.length && line.charAt(hole.length).isWhitespace)
      Some(line.drop(hole.length).trim)
    else None

  /** `hole : ...` at column 0. */
  def isSignature(block: Vector[String], hole: String): Boolean =
    afterHole(block.head, hole).exists(rest => rest.startsWith(":") && (rest.length == 1 || rest.charAt(1).isWhitespace))

  /** `hole pats = ...` (or `hole = ...`) at column 0: a clause of the definition. */
  def isClause(block: Vector[String], hole: String): Boolean =
    afterHole(block.head, hole).exists(rest => !rest.startsWith(":")) || block.head == hole

  private val WherePrefix = """^where\s+""".r

  /** The `open` or `import` statement a line carries, with a leading `where`
    * removed (`  where open import M using (x)`), or None.
    */
  def openText(line: String): Option[String] = {
    val t = WherePrefix.replaceFirstIn(line.trim, "")
    if (t.startsWith("open ") || t.startsWith("import ")) Some(t) else None
  }

  /** The import statement a line carries (`open import M ...` or `import M ...`), or None. */
  def importText(line: String): Option[String] =
    openText(line).filter(t => t.startsWith("open import ") || t.startsWith("import "))

  def isImport(line: String): Boolean = importText(line).isDefined

  /** Read the statement of an obligation; Left when it has no module line, no
    * signature for the hole, or no clause for it.
    */
  def of(obligation: String, hole: String): Either[String, Statement] = {
    val bs = blocks(obligation)
    for {
      moduleLine <- bs.map(_.head).find(l => l.startsWith("module ") && l.trim.endsWith(" where"))
                      .toRight("obligation has no top-level module line")
      signature  <- bs.find(isSignature(_, hole)).toRight(s"obligation has no type signature for `$hole`")
      _          <- if (bs.exists(isClause(_, hole))) Right(()) else Left(s"obligation has no clause for `$hole`")
    } yield Statement(
      hole         = hole,
      moduleLine   = moduleLine,
      importLines  = bs.map(_.head).filter(isImport),
      signature    = signature,
      frozenBlocks = bs.filterNot(isClause(_, hole))
    )
  }
}

/** The first gate a file failed, by name, with what was seen. */
final case class GateFailure(gate: String, detail: String)

object Gates {

  private def containsRun(haystack: Vector[String], run: Vector[String]): Boolean =
    run.nonEmpty && haystack.indices.exists(i => haystack.slice(i, i + run.size) == run)

  /** Gate 1.  Every frozen block of the obligation appears in the final file
    * as a consecutive run of kept lines (comments stripped on both sides),
    * byte-identical.  Right carries the import lines the final file has that
    * the obligation did not (indented `where`-block imports included), for
    * the ledger.
    */
  def preservation(st: Statement, finalText: String): Either[GateFailure, Vector[String]] = {
    val kept = Code.keptLines(finalText)
    st.frozenBlocks.find(b => !containsRun(kept, b)) match {
      case Some(missing) =>
        val what =
          if (missing == st.signature) "type signature"
          else if (missing.head == st.moduleLine) "module line"
          else if (Statement.isImport(missing.head)) "import line"
          else "declaration"
        Left(GateFailure("preservation", s"$what changed or missing: ${missing.mkString(" ⏎ ")}"))
      case None =>
        val originals = st.importLines.map(_.trim).toSet
        Right(kept.flatMap(Statement.importText).filterNot(originals).distinct)
    }
  }

  private val Pragma   = """\{-#\s*(\S+)""".r
  private val keywords = Set("postulate", "primTrustMe", "trustMe")

  /** Gate 2.  No pragma, no postulate, no trustMe, over the comment-stripped code. */
  def escape(finalText: String): Either[GateFailure, Unit] = {
    val code = Code.stripComments(finalText)
    Pragma.findFirstMatchIn(code).map(m => s"pragma ${m.group(1)}")
      .orElse(Code.tokens(code).find(keywords).map(k => s"keyword $k"))
      .toLeft(()).left.map(GateFailure("escape", _))
  }

  private val LoneQuestion = """(?<![^\s(){};])\?(?![^\s(){};])""".r

  /** Gate 3.  No `{!` and no lexically separate `?` in the code. */
  def holes(finalText: String): Either[GateFailure, Unit] = {
    val code   = Code.stripComments(finalText)
    val braces = code.sliding(2).count(_ == "{!")
    val lone   = LoneQuestion.findAllIn(code).size
    if (braces + lone == 0) Right(())
    else Left(GateFailure("holes", s"${braces + lone} hole(s) remain"))
  }

  /** The original a row restates: its bare name (the hole with a trailing
    * prime stripped) and whether the bare name is itself evidence (only when
    * it differs from the hole, since the hole's own name in its body is a
    * recursive call).
    */
  def originalOf(hole: String): (String, Boolean) = {
    val bare = hole.stripSuffix("′")
    (bare, bare != hole)
  }

  private val ListClause = """(?:using|renaming)\s*\(([^)]*)\)""".r

  /** Restatement evidence over the final file minus the frozen statement:
    * qualified tokens ending in `.<original>`, import or open lines that name
    * the original in a `using` or `renaming` list, and, on primed rows, the
    * bare original.  Each hit is reported as text a reader can check.
    */
  def restatement(st: Statement, finalText: String): Vector[String] = {
    val (orig, bareCounts) = originalOf(st.hole)
    val frozen = st.frozenBlocks.flatten.toSet
    val own    = Code.keptLines(finalText).filterNot(frozen)
    val code   = Code.stripComments(own.mkString("\n"))
    val toks   = Code.tokens(code)
    val qualified = toks.filter(t => t.endsWith("." + orig) && t.length > orig.length + 1).distinct
      .map(t => s"qualified $t")
    val imports = own.flatMap(Statement.openText)
      .filter { l =>
        ListClause.findAllMatchIn(l).exists { m =>
          m.group(1).split(";").map(_.trim).exists { entry =>
            val name = entry.split("\\s+").headOption.getOrElse("")
            name == orig
          }
        }
      }.map(l => s"import $l")
    val bare = if (bareCounts && toks.contains(orig)) Vector(s"bare $orig") else Vector.empty
    qualified ++ imports ++ bare
  }
}

/** What the judge concluded about one final file. */
final case class Verdict(
  gate:         Option[GateFailure],
  addedImports: Vector[String],
  evidence:     Vector[String],
  agdaExit:     Option[Int],
  agdaMs:       Option[Long],
  agdaTail:     Option[String]
) {
  def passed:   Boolean = gate.isEmpty
  def restated: Boolean = passed && evidence.nonEmpty
  def solved:   Boolean = passed && evidence.isEmpty
}

object Judge {

  /** The syntactic gates only (no Agda): the statement, then preservation,
    * escape, holes; restatement evidence is collected whatever the gates say.
    */
  def syntactic(st: Statement, finalText: String): (Option[GateFailure], Vector[String], Vector[String]) = {
    val evidence = Gates.restatement(st, finalText)
    Gates.preservation(st, finalText) match {
      case Left(f) => (Some(f), Vector.empty, evidence)
      case Right(added) =>
        val rest = Gates.escape(finalText).left.toOption.orElse(Gates.holes(finalText).left.toOption)
        (rest, added, evidence)
    }
  }

  /** Gate 4: the gold verifier's invocation on the final file, `--safe` added
    * when `safe`, bounded by `timeout`.
    */
  def typecheck(entry: IndexEntry, file: Path, projectRoot: Path, safe: Boolean, timeout: FiniteDuration): IO[(Int, Long, String)] = {
    val agdaDir = GoldVerifier.agdaDirOf(projectRoot)
    val libs    = java.nio.file.Paths.get(agdaDir).resolve("libraries").toString
    val cmd     = GoldVerifier.agdaCommand(entry.source, file, libs, if (safe) Vector("--safe") else Vector.empty)
    for {
      t0  <- IO.monotonic
      res <- GoldVerifier.runAgda(cmd, agdaDir, timeout)
      t1  <- IO.monotonic
    } yield (res._1, (t1 - t0).toMillis, res._2)
  }

  /** All four gates on a final file, first failure named.  Agda runs whatever
    * the syntactic gates said, so a file that broke a rule of the protocol
    * (an original import line edited, say) is reported with its verdict too:
    * "failed preservation, and would have type-checked" is a finding a reader
    * needs, and the run costs one batch check per row either way.
    */
  def judge(entry: IndexEntry, obligationText: String, finalText: String, finalFile: Path, projectRoot: Path, safe: Boolean, timeout: FiniteDuration): IO[Verdict] =
    Statement.of(obligationText, entry.hole) match {
      case Left(msg) =>
        IO.pure(Verdict(Some(GateFailure("statement", msg)), Vector.empty, Vector.empty, None, None, None))
      case Right(st) =>
        val (syn, added, evidence) = syntactic(st, finalText)
        typecheck(entry, finalFile, projectRoot, safe, timeout).map { case (rc, ms, out) =>
          val tail = out.linesIterator.toVector.takeRight(12).mkString("\n")
          val gate = syn.orElse(if (rc == 0) None else Some(GateFailure("typecheck", s"agda exit $rc")))
          Verdict(gate, added, evidence, Some(rc), Some(ms), Some(tail))
        }
    }
}

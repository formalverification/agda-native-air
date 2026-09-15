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
  *    1. preservation — every frozen block of the obligation (Statement.scala)
  *       is present byte-for-byte, comments aside; added import lines are
  *       allowed and reported.
  *    2. escape       — no postulate, no trustMe / primTrustMe, and no pragma
  *       of any kind (the fixtures carry none, so any pragma is an addition).
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
  *  original by construction, so the gate never fires there.
  *
  *  Design notes
  *  ------------
  *  - Agda runs whatever the syntactic gates said, so a file that broke a
  *    rule of the protocol is reported with its verdict too.
  *  - Agda itself names the escapes and the holes under `--safe`
  *    (`SafeFlagPostulate`, `SafeFlagTerminating`, `CoInfectiveImport`,
  *    `UnsolvedInteractionMetas`), and `check_file` exposes those codes; the
  *    syntactic scans here name the gate before Agda runs and are the part
  *    of this judge that should give way to Agda's own classification.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.IO
import java.nio.file.Path
import scala.concurrent.duration._

import struxdriver.benchmark.{GoldVerifier, Obligation => IndexEntry}

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

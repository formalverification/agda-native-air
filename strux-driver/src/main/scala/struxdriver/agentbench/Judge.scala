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
  *  if not, which gate it failed.  Every fact about Agda code is Agda's own
  *  answer (Ask.scala); the judge combines them.  The gates, in the order a
  *  failure is named:
  *
  *    1. preservation: the module line and every original import line are
  *       present (a line diff, comments aside; added import lines allowed and
  *       reported).
  *    2. escape: `check_file` under `--safe` reports none of Agda's
  *       safe-flag refusals (`SafeFlagPostulate`, `SafeFlagTerminating`,
  *       `SafeFlagPragma`, `SafeFlagNoPositivityCheck`, ..., and
  *       `CoInfectiveImport` for an unsafe module such as `TrustMe`).
  *    3. holes: `check_file`'s hole list is empty.
  *    4. preservation: the definition in the final file has the statement
  *       it was given: its elaborated type, as Agda holds it internally and
  *       agda-strux extracts it (`typeAst`), equals the committed gold's, the
  *       gold being the obligation with the hole filled and therefore the
  *       statement by construction.  Binder-name hints are dropped before the
  *       comparison, so a renamed binder is not a changed statement; nothing
  *       is printed or parsed.  Asked only of a file Agda could check (an
  *       unchecked file has no elaborated type), so the verdict speaks for a
  *       file that does not type-check.  A file Agda checked that the
  *       extractor cannot read fails this gate too: the statement is
  *       unverified, so the row is not a solve.
  *    5. typecheck: the gold verifier's own `agda` invocation
  *       (GoldVerifier.agdaCommand) on the final file, with `--safe` added
  *       because every committed gold passes under it, exit-code verdict;
  *       `check_file`'s exit code is recorded beside it and a disagreement
  *       is reported.
  *
  *  A file that passes every gate but whose definition refers to the library's
  *  own lemma for the statement it was asked to prove is *restated*, never
  *  solved.  The original is the index row's `restates:` tag (PR #152, the
  *  qualified corpus name) where the row has one, else the index's module and
  *  the fixture's name with its prime stripped; the references are the
  *  extractor's `bodyRefs`, read off Agda's internal terms, closed over the
  *  file's own helper definitions (a `where` block is its own definition).
  *  Evidence is a reference equal to the original's qualified name, or a
  *  reference outside the file whose bare name is the original's.  The
  *  haystack tier has no original by construction, so the gate never fires
  *  there.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.IO
import java.nio.file.Path
import scala.concurrent.duration._

import struxdriver.benchmark.{GoldVerifier, Obligation => IndexEntry}
import struxdriver.search.Scaffold

/** The first gate a file failed, by name, with what was seen. */
final case class GateFailure(gate: String, detail: String)

/** The library original a row restates: its qualified name when the index
  * says (the `restates:` tag), its bare name, and whether the bare name alone
  * is evidence.  It is when the row is untagged, where the qualified name is
  * a guess (the index's module and the hole's name, and the two disagree for
  * a lemma the index files elsewhere), and when a tag's bare name differs
  * from the hole's, where it widens the exact name to a re-export.  It is not
  * when a tag names the hole's own name, where any same-named lemma anywhere
  * would match an exactly known original.
  */
final case class Original(qualified: Option[String], bare: String, bareIsEvidence: Boolean)

/** The statement in both files, as Agda printed the elaborated types (for the
  * ledger), and whether the two type ASTs are equal.
  */
final case class StatementCheck(gold: String, finalFile: String, equal: Boolean)

object Gates {

  private def containsRun(haystack: Vector[String], run: Vector[String]): Boolean =
    run.nonEmpty && haystack.indices.exists(i => haystack.slice(i, i + run.size) == run)

  /** Gate 1a.  The module line and every original import line appear in the
    * final file (comments stripped on both sides).  Right carries the import
    * lines the final file has that the obligation did not, for the ledger.
    */
  def imports(st: Statement, finalText: String): Either[GateFailure, Vector[String]] = {
    val kept = Code.keptLines(finalText)
    if (!containsRun(kept, Vector(st.moduleLine)))
      Left(GateFailure("preservation", s"module line changed or missing: ${st.moduleLine}"))
    else st.importLines.find(l => !containsRun(kept, Vector(l))) match {
      case Some(missing) => Left(GateFailure("preservation", s"import line changed or missing: $missing"))
      case None =>
        val originals = st.importLines.toSet
        Right(kept.flatMap(Statement.importText).filterNot(originals).distinct)
    }
  }

  /** Binder names are hints, not statement: drop them before comparing. */
  def withoutNameHints(ast: io.circe.Json): io.circe.Json =
    ast.arrayOrObject(ast,
      arr => io.circe.Json.arr(arr.map(withoutNameHints): _*),
      obj => io.circe.Json.fromJsonObject(obj.remove("nameHint").mapValues(withoutNameHints)))

  /** Gate 1b.  The definition's elaborated type in the final file equals the
    * gold's, structurally.  `finalRows` and `goldRows` are the extractor's
    * rows for the two files; the definition is looked up by its qualified
    * name in the file's module.
    */
  def statement(stem: String, hole: String, goldRows: Vector[DefRow], finalRows: Vector[DefRow]): Either[GateFailure, StatementCheck] = {
    val q = s"$stem.$hole"
    (goldRows.find(_.prettyQname == q), finalRows.find(_.prettyQname == q)) match {
      case (None, _) =>
        Left(GateFailure("statement", s"the gold has no definition `$q` to read the statement from"))
      case (Some(_), None) =>
        Left(GateFailure("preservation", s"`$q` is not a definition of the final file"))
      case (Some(g), Some(f)) =>
        val equal = withoutNameHints(g.typeAst) == withoutNameHints(f.typeAst)
        if (equal) Right(StatementCheck(g.printedType, f.printedType, equal = true))
        else Left(GateFailure("preservation", s"statement changed: Agda's elaborated type of `$q` differs from the gold's: gold `${g.printedType}`, final `${f.printedType}`"))
    }
  }

  /** Agda's own names for what `--safe` refuses. */
  def isEscapeCode(code: String): Boolean = code.startsWith("SafeFlag") || code == "CoInfectiveImport"

  /** Gate 2.  No safe-flag refusal among the diagnostics. */
  def escape(checked: Checked): Either[GateFailure, Unit] =
    checked.codes.find(isEscapeCode) match {
      case Some(code) => Left(GateFailure("escape", s"$code: ${checked.messages.getOrElse(code, "")}".trim))
      case None       => Right(())
    }

  /** Gate 3.  No hole left, by the server's count. */
  def holes(checked: Checked): Either[GateFailure, Unit] =
    if (checked.holesCount == 0 && !checked.codes.contains("UnsolvedInteractionMetas")) Right(())
    else Left(GateFailure("holes", s"${checked.holesCount} hole(s) remain"))

  def originalOf(module: String, hole: String, tags: Vector[String]): Original = {
    val tagged = tags.collectFirst { case t if t.startsWith("restates:") => t.stripPrefix("restates:") }
    val bare   = tagged.map(_.split('.').last).getOrElse(hole.stripSuffix("′"))
    Original(tagged.orElse(Some(s"$module.$bare")), bare, tagged.isEmpty || bare != hole)
  }

  /** The names the definition's body refers to, closed over the file's own
    * definitions (helpers, where-blocks, extended lambdas), then the evidence:
    * the original by its qualified name, or (when the original's bare name is
    * evidence in itself, `Original.bareIsEvidence`) a name outside the file
    * whose bare name is the original's.  The second is the fallback for an
    * original whose module the index states differently from the corpus, and
    * for a re-export under another path; it is off when the index names the
    * original exactly and its bare name is the hole's own, where any
    * same-named lemma anywhere would match.
    */
  def restatement(stem: String, hole: String, original: Original, rows: Vector[DefRow]): Vector[String] = {
    val byName = rows.map(r => r.prettyQname -> r.bodyRefs).toMap
    val own    = (q: String) => q.startsWith(stem + ".")
    def close(seen: Set[String], todo: List[String]): Set[String] = todo match {
      case Nil => seen
      case q :: rest =>
        val refs = byName.getOrElse(q, Vector.empty).filterNot(seen)
        close(seen ++ refs, rest ++ refs.filter(own))
    }
    val refs = close(Set.empty, List(s"$stem.$hole")).toVector.sorted
    refs.filter { r =>
      original.qualified.contains(r) ||
        (original.bareIsEvidence && !own(r) && r.split('.').last == original.bare)
    }.map(r => s"ref $r")
  }
}

/** What the judge concluded about one final file. */
final case class Verdict(
  gate:           Option[GateFailure],
  addedImports:   Vector[String],
  evidence:       Vector[String],
  evidenceSource: String,
  statement:      Option[StatementCheck],
  checkCodes:     Vector[String],
  checkExit:      Option[Int],
  agdaExit:       Option[Int],
  agdaMs:         Option[Long],
  agdaTail:       Option[String]
) {
  def passed:   Boolean = gate.isEmpty
  def restated: Boolean = passed && evidence.nonEmpty
  def solved:   Boolean = passed && evidence.isEmpty
  /** The two batch verdicts on the same file disagree: a configuration fact worth an anomaly. */
  def verdictsDisagree: Boolean = (checkExit, agdaExit) match {
    case (Some(a), Some(b)) => (a == 0) != (b == 0)
    case _                  => false
  }
}

object Judge {

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

  /** All four gates on a final file, first failure named; Agda runs whatever
    * the earlier gates said, so a rule violation that still type-checks is
    * reported with its verdict.
    */
  def judge(entry: IndexEntry, obligationText: String, finalText: String, goldFile: Path, finalFile: Path,
            agda: Agda, projectRoot: Path, safe: Boolean, timeout: FiniteDuration): IO[Verdict] = {
    val hole = entry.hole
    val stem = Scaffold.fixtureStem(entry)
    Statement.of(obligationText, hole) match {
      case Left(msg) =>
        IO.pure(Verdict(Some(GateFailure("statement", msg)), Vector.empty, Vector.empty, "unavailable: statement unreadable",
          None, Vector.empty, None, None, None, None))
      case Right(st) =>
        val importsGate = Gates.imports(st, finalText)
        for {
          checked   <- agda.check(finalFile)
          verdict   <- typecheck(entry, finalFile, projectRoot, safe, timeout)
          (rc, ms, out) = verdict
          typeGate  = if (rc == 0) Right(()) else Left(GateFailure("typecheck", s"agda exit $rc"))
          // The elaborated types and the body references exist only for a
          // file Agda could check; for one it could not, the verdict speaks.
          finalRows <- if (rc == 0) agda.rows(finalFile)
                       else IO.pure(Left("the file does not type-check, so it has no elaborated types to extract"): Either[String, Vector[DefRow]])
          goldRows  <- if (rc == 0) agda.rows(goldFile) else IO.pure(Left("not needed"): Either[String, Vector[DefRow]])
          // A file Agda checked has an elaborated type; if the extractor
          // cannot read it, the statement is unverified and the row is not a
          // solve (and Outcomes makes it an anomaly).  A file Agda could not
          // check is named by the verdict instead.
          statementGate = (rc == 0, goldRows, finalRows) match {
                            case (true, Right(g), Right(f)) => Some(Gates.statement(stem, hole, g, f))
                            case (true, _, Left(e))         => Some(Left(GateFailure("statement", s"the final file type-checks but could not be extracted: $e")))
                            case (true, Left(e), Right(_))  => Some(Left(GateFailure("statement", s"the gold could not be extracted: $e")))
                            case _                          => None
                          }
          gate      = importsGate.left.toOption
                        .orElse(Gates.escape(checked).left.toOption)
                        .orElse(Gates.holes(checked).left.toOption)
                        .orElse(statementGate.flatMap(_.left.toOption))
                        .orElse(typeGate.left.toOption)
          original   = Gates.originalOf(entry.module, hole, entry.tags)
        } yield Verdict(
          gate           = gate,
          addedImports   = importsGate.getOrElse(Vector.empty),
          evidence       = finalRows.map(rows => Gates.restatement(stem, hole, original, rows)).getOrElse(Vector.empty),
          evidenceSource = finalRows.fold(e => s"unavailable: $e", _ => "bodyRefs"),
          statement      = statementGate.flatMap(_.toOption),
          checkCodes     = checked.codes,
          checkExit      = checked.exitCode,
          agdaExit       = Some(rc),
          agdaMs         = Some(ms),
          agdaTail       = Some(out.linesIterator.toVector.takeRight(12).mkString("\n"))
        )
    }
  }
}

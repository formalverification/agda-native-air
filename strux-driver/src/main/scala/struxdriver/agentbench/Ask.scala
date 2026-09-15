/** ============================================================================
  *  Ask.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Ask.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  What the judge asks Agda (issue #154), behind one small interface, so the
  *  gates in Judge.scala are pure functions over Agda's answers and never
  *  read Agda code themselves:
  *
  *    + `check`: agda-mcp's `check_file` on a server started with `--safe`
  *                in its flags: the verdict's exit code, the hole list the
  *                server's own hole model counted, and every structured
  *                diagnostic's code (`SafeFlagPostulate`,
  *                `UnsolvedInteractionMetas`, ...).
  *    + `rows`: agda-strux's `agda-json` on a file (Agda as a library): for
  *                every definition the file holds, its elaborated type as a
  *                structural AST (`typeAst`: de Bruijn indices, fully
  *                qualified names, hiding; binder names only as hints), the
  *                type as printed, and the fully qualified names its clause
  *                bodies refer to (`bodyRefs`, read off the internal terms).
  *                The statement gate compares the final file's type AST with
  *                the gold's; the restatement gate reads the references.
  *
  *  Design notes
  *  ------------
  *  - The server client is the search loop's own (`struxdriver.search.Oracle`
  *    over `McpClient`), so the judge sees the same wire contract the loop
  *    and every agent see.  A server-level failure of `check_file` raises,
  *    which the harness records as that row's anomaly.
  *  - Nothing is asked of the interaction lane: a printed type is not a
  *    statement (a module loaded twice in one lane prints qualified names,
  *    and a printed type need not read back in the file's scope), where the
  *    elaborated type Agda holds internally is.
  *  - The extractor needs every registered library's source root on its
  *    include path, because an explicit include path switches Agda's default
  *    libraries off; the roots are read from the same `libraries` registry
  *    the gold verifier consults (each `.agda-lib`'s `include:` line).
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.IO
import io.circe.Json
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths}
import scala.concurrent.duration._
import scala.jdk.CollectionConverters._

import struxdriver.search.{CallCtx, Oracle}

/** What `check_file` established about a file. */
final case class Checked(
  success:    Boolean,
  exitCode:   Option[Int],
  holesCount: Int,
  codes:      Vector[String],
  messages:   Map[String, String], // first message per code
  elapsedMs:  Long
)

/** One definition of a file: its elaborated type as Agda's structural AST,
  * the type as printed, and the names its clause bodies refer to.
  */
final case class DefRow(prettyQname: String, typeAst: Json, printedType: String, bodyRefs: Vector[String])

/** The two questions, answered by Agda. */
trait Agda {
  def check(file: Path): IO[Checked]
  def rows(file: Path): IO[Either[String, Vector[DefRow]]]
}

/** The agda-strux extractor, driven on one file. */
final case class Extractor(bin: Path, includes: Vector[Path], agdaDir: String, timeout: FiniteDuration) {

  def rows(file: Path): IO[Either[String, Vector[DefRow]]] =
    IO.blocking {
      val out = Files.createTempFile("agent-bench-refs-", ".jsonl")
      try {
        val cmd = Vector(bin.toString, "--input", file.toString, "--output", out.toString) ++
          includes.flatMap(p => Vector("--include", p.toString))
        val pb = new ProcessBuilder(cmd.asJava)
        pb.environment().put("AGDA_DIR", agdaDir)
        pb.redirectErrorStream(true)
        val proc = pb.start()
        val log  = new String(proc.getInputStream.readAllBytes(), StandardCharsets.UTF_8)
        val rc   = proc.waitFor()
        if (rc != 0) Left(s"agda-json exit $rc: ${log.linesIterator.toVector.takeRight(6).mkString(" | ")}")
        else Right(Files.readAllLines(out, StandardCharsets.UTF_8).asScala.toVector.filter(_.trim.nonEmpty).flatMap { line =>
          io.circe.parser.parse(line).toOption.flatMap { j =>
            for {
              q    <- j.hcursor.get[String]("prettyQname").toOption
              ast  <- j.hcursor.downField("typeAst").focus
              tpe  <- j.hcursor.get[String]("type").toOption
              refs <- j.hcursor.get[Vector[String]]("bodyRefs").toOption
            } yield DefRow(q, ast, tpe, refs)
          }
        })
      } finally Files.deleteIfExists(out)
    }.timeout(timeout).handleError(e => Left(s"agda-json: ${e.getMessage}"))
}

object Extractor {
  /** Every registered library's source roots: each line of the registry names
    * a `.agda-lib`, whose `include:` line lists roots relative to it.
    */
  def includesFromRegistry(librariesFile: Path): IO[Vector[Path]] =
    IO.blocking {
      Files.readAllLines(librariesFile, StandardCharsets.UTF_8).asScala.toVector.map(_.trim).filter(_.nonEmpty).flatMap { libLine =>
        val lib = Paths.get(libLine)
        if (!Files.isRegularFile(lib)) Vector.empty
        else Files.readAllLines(lib, StandardCharsets.UTF_8).asScala.toVector
          .map(_.trim).filter(_.toLowerCase.startsWith("include:"))
          .flatMap(_.drop("include:".length).trim.split("\\s+").toVector.filter(_.nonEmpty))
          .map(d => lib.getParent.resolve(d).normalize)
      }
    }
}

/** Agda through the server and the extractor. */
final class ServerAgda(oracle: Oracle, extractor: Extractor, fixtureId: String) extends Agda {
  private def ctx(phase: String) = CallCtx(1, fixtureId, phase, None)

  def check(file: Path): IO[Checked] =
    oracle.checkFile(ctx("judge_check"), file).map { a =>
      val b = a.body
      Checked(
        success    = b.success,
        exitCode   = b.exitCode,
        holesCount = b.holesCount,
        codes      = b.diagnostics.flatMap(_.code),
        messages   = b.diagnostics.flatMap(d => d.code.map(_ -> d.message.linesIterator.toVector.headOption.getOrElse(""))).toMap,
        elapsedMs  = b.elapsedMs
      )
    }

  def rows(file: Path): IO[Either[String, Vector[DefRow]]] = extractor.rows(file)
}

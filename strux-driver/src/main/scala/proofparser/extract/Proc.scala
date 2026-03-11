/** ============================================================================
  *  Proc.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/proofparser/extract/Proc.scala
  *  Package: proofparser.extract
  *  Copyright: (c) 2025--2026 Thmpr Lab, LLC.
  *
  *  Purpose
  *  -------
  *  A small, FP-friendly process runner for invoking external tools (e.g. the
  *  Haskell `agda-json` backend), capturing stdout+stderr into a log file, and
  *  returning structured results.
  *
  *  Design
  *  ------
  *  - Effects are explicit (cats-effect IO).
  *  - Lifecycle is managed with Resource (process + log writer).
  *  - Output capture uses fs2 streaming (no manual loops).
  *  - Errors are data (EitherT in the caller).
  *
  *  Fits into project
  *  -----------------
  *  Used by AgdaJsonlDriver to:
  *    - run agda-json per module
  *    - write per-module logs
  *    - measure timing + exit code for the manifest
  *
  *  ============================================================================
  */

package proofparser.extract

import cats.effect.{IO, Resource}
import cats.syntax.all._
import cats.syntax.parallel._
import fs2.Stream
import fs2.io.file.{Files => Fs2Files, Path => Fs2Path}

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path}
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

object Proc {

  final case class ExecResult(exitCode: Int, seconds: Double)

  // --- helpers ---------------------------------------------------------------

  private val tsFmt: DateTimeFormatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ssXXX")

  private def nowTs: String =
    ZonedDateTime.now().format(tsFmt)

  // Minimal shell-ish quoting so the command is copy/pasteable
  private def shQuote(s: String): String =
    if (s.isEmpty) "''"
    else if (s.forall(ch => ch.isLetterOrDigit || "-._/:=@".contains(ch))) s
    else "'" + s.replace("'", "'\"'\"'") + "'"

  private def renderRepro(cmd: Seq[String], env: Map[String, String], cwd: Path): String = {
    val envPart =
      if (env.isEmpty) ""
      else env.toVector.sortBy(_._1).map { case (k, v) => s"$k=${shQuote(v)}" }.mkString("", " ", " ")

    val cmdPart = cmd.map(shQuote).mkString(" ")

    // One-liner repro + extra context lines
    s"""|=== PROC RUN ===
        |time: ${nowTs}
        |cwd:  ${cwd.toAbsolutePath.normalize()}
        |env:  ${env.toVector.sortBy(_._1).map { case (k, v) => s"$k=$v" }.mkString(", ")}
        |REPRO:
        |${envPart}${cmdPart}
        |----------------
        |""".stripMargin
  }

  /** Run a command, merging stderr into stdout, and teeing output to a log file. */
  def runLogged(
    cmd: Seq[String],
    cwd: Path,
    env: Map[String, String],
    logFile: Path
  ): IO[ExecResult] = {

    val procR: Resource[IO, Process] =
      Resource.make {
        IO.blocking {
          Files.createDirectories(logFile.getParent)
          val pb = new ProcessBuilder(cmd: _*)
          pb.directory(cwd.toFile)
          pb.redirectErrorStream(true) // merge stderr into stdout

          val penv = pb.environment()
          env.foreach { case (k, v) => penv.put(k, v) }

          pb.start()
        }
      } { p =>
        IO.blocking {
          // best-effort cleanup
          if (p.isAlive) p.destroy()
        }.handleError(_ => ())
      }

    val logR: Resource[IO, java.io.OutputStream] =
      Resource.make(IO.blocking(Files.newOutputStream(logFile)))(os =>
        IO.blocking(os.close()).handleError(_ => ())
      )

    Resource.both(procR, logR).use { case (p, out) =>
      val headerBytes = renderRepro(cmd, env, cwd).getBytes(StandardCharsets.UTF_8)

      val in: Stream[IO, Byte] =
        fs2.io.readInputStream(IO.blocking(p.getInputStream), chunkSize = 64 * 1024, closeAfterUse = true)

      val writeLog: Stream[IO, Unit] =
        in.through(fs2.io.writeOutputStream(IO.pure(out), closeAfterUse = false))

      for {
        _    <- IO.blocking(out.write(headerBytes))
        t0   <- IO.monotonic
        _    <- writeLog.compile.drain
        code <- IO.blocking(p.waitFor())
        t1   <- IO.monotonic
        secs  = (t1 - t0).toNanos.toDouble / 1e9
        _    <- IO.blocking {
                  val trailer =
                    s"\n----------------\nexitCode: $code\nseconds:  $secs\n=== END PROC RUN ===\n"
                  out.write(trailer.getBytes(StandardCharsets.UTF_8))
                }
      } yield ExecResult(exitCode = code, seconds = secs)
    }
  }

  /** NOTE:
    * We time using IO.monotonic so it's unaffected by wall-clock changes.
    */
}

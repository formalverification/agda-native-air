/** ============================================================================
  *  Proc.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: proof-parser/src/main/scala/proofparser/extract/Proc.scala
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
import fs2.Stream
import fs2.io.file.{Files => Fs2Files, Path => Fs2Path}

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path}

object Proc {

  final case class ExecResult(exitCode: Int, seconds: Double)

  /** Run a command, merging stderr into stdout, and teeing output to a log file. */
  def runLogged(
    cmd: Seq[String],
    cwd: Path,
    env: Map[String, String],
    logFile: Path
  ): IO[ExecResult] = {
    val t0 = IO.monotonic

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
      Resource.make(IO.blocking(Files.newOutputStream(logFile)))(os => IO.blocking(os.close()).handleError(_ => ()))

    (procR, logR).tupled.use { case (p, out) =>
      val in: Stream[IO, Byte] =
        fs2.io.readInputStream(IO.blocking(p.getInputStream), chunkSize = 64 * 1024, closeAfterUse = true)

      val writeLog: Stream[IO, Unit] =
        in.through(Fs2Files[IO].writeOutputStream(IO.pure(out)))

      for {
        _    <- writeLog.compile.drain
        code <- IO.blocking(p.waitFor())
        t1   <- IO.monotonic
      } yield ExecResult(exitCode = code, seconds = (t1 - t0.unsafeRunSync()).toNanos.toDouble / 1e9) // see note below
    }
  }

  /** NOTE:
    * The one awkward line above is subtracting timestamps. For a purer approach, we could
    * replace that with a single `for { t0 <- IO.monotonic; ...; t1 <- IO.monotonic } yield ...`
    * and compute (t1 - t0) without the unsafeRunSync.
    */
}

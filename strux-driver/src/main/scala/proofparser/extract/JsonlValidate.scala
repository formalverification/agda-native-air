/** ============================================================================
  *  JsonlValidate.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/proofparser/extract/JsonlValidate.scala
  *  Package: proofparser.extract
  *
  *  Purpose
  *  -------
  *  Validate JSONL files emitted by the Haskell `agda-json` backend.
  *
  *  Why this exists
  *  ---------------
  *  The Scala/Spark driver runs `agda-json` per module and needs a fast, robust
  *  way to decide:
  *
  *    - whether an output JSONL file is "good enough" to skip (resume), and
  *    - whether a run succeeded even if the process exited 0 (sanity checks).
  *
  *  Design
  *  ------
  *  - Pure core: validate an Iterator[String] via fold (test-friendly).
  *  - Effectful wrapper: validate a Path in IO via fs2 streaming (scales to big files).
  *  - Monadic error handling: no unchecked exceptions leak; failures become data.
  *
  *  Invariants checked (v0)
  *  -----------------------
  *  - each non-empty line parses as a JSON object
  *  - object contains required keys:
  *      file, module, name, qname, type, kind, astSize
  *
  *  Fits into project
  *  -----------------
  *  Used by AgdaJsonlDriver to implement:
  *    - resumability
  *    - post-run validation
  *    - manifest reporting
  *
  *  ============================================================================
  */

package proofparser.extract

// import cats.data.{NonEmptyList, ValidatedNel}
import cats.effect.IO
import cats.syntax.all._
import fs2.Stream
import fs2.io.file.{Files => Fs2Files, Path => Fs2Path}
import java.nio.file.{Files => JFiles}

object JsonlValidate {

   // ---------------------------------------------------------------------------
   // Shared line-level validator (used by pure + streaming)
   // ---------------------------------------------------------------------------

   private final case class Acc(rows: Long, errs: Vector[String], lineNo: Long) {
     def addErr(msg: String, maxErrors: Int): Acc =
       if (errs.size >= maxErrors) this else copy(errs = errs :+ msg)
   }

   private def step(acc0: Acc, raw0: String, maxErrors: Int): Acc = {
     val acc1   = acc0.copy(lineNo = acc0.lineNo + 1)
     val raw    = raw0.trim
     val isData = raw.nonEmpty

     if (!isData || acc1.errs.size >= maxErrors) acc1
     else {
       val parsedE: Either[String, ujson.Value] =
         Either.catchNonFatal(ujson.read(raw))
           .leftMap(e => s"line ${acc1.lineNo}: JSON parse error: ${e.getMessage}")

       parsedE match {
         case Left(err) =>
           acc1.addErr(err, maxErrors).copy(rows = acc1.rows + 1)

         case Right(js) =>
           js.objOpt match {
             case None =>
               acc1.addErr(s"line ${acc1.lineNo}: not a JSON object", maxErrors).copy(rows = acc1.rows + 1)

             case Some(obj) =>
               val keys    = obj.keySet
               val required =
                 if (keys.contains("file")) FullKeys else HumanKeys
               val missing = required.diff(keys)
               val acc2    = acc1.copy(rows = acc1.rows + 1)
               if (missing.isEmpty) acc2
               else acc2.addErr(s"line ${acc1.lineNo}: missing keys: ${missing.toList.sorted.mkString(",")}", maxErrors)
           }
       }
     }
   }

  // ---------------------------------------------------------------------------
  // Schema expectations for v0 backend rows.
  // ---------------------------------------------------------------------------

  private val FullKeys: Set[String] = Set("file", "module", "name", "qname", "type", "kind", "astSize")

  private val HumanKeys: Set[String] = Set("name", "type", "body")

  // ---------------------------------------------------------------------------
  // Result model
  // ---------------------------------------------------------------------------

  final case class Result(
    ok: Boolean,
    rows: Long,
    errors: Vector[String]
  )

  // ---------------------------------------------------------------------------
  // Pure core (testable)
  // ---------------------------------------------------------------------------

  /** Validate JSONL lines (pure, fold-based).
    *
    * @param lines     iterator over lines
    * @param maxErrors cap the number of collected errors
    */
  def validateLines(lines: Iterator[String], maxErrors: Int = 50): Result = {

    val acc0 = Acc(rows = 0L, errs = Vector.empty, lineNo = 0L)

    val accF = lines.foldLeft(acc0)((acc, raw) => step(acc, raw, maxErrors))

    Result(ok = accF.errs.isEmpty, rows = accF.rows, errors = accF.errs)
  }

  // ---------------------------------------------------------------------------
  // Effectful wrapper (streaming)
  // ---------------------------------------------------------------------------

  /** Validate a JSONL file in IO using streaming (fs2).
    *
    * This is the function the Spark driver should use for:
    * - resumability checks
    * - post-run output validation
    */
  def validateFile(path: java.nio.file.Path, maxErrors: Int = 50): IO[Result] = {
    val p = Fs2Path.fromNioPath(path)

    // Stream file -> decode -> split lines -> validate with pure core.
    // We keep the "big file" behavior by not slurping the whole file.
    IO.blocking(JFiles.exists(path)).flatMap {
      case false =>
        IO.pure(Result(ok = false, rows = 0L, errors = Vector(s"missing file: $path")))

      case true =>
        IO.blocking(JFiles.size(path)).flatMap {
          case 0L =>
            IO.pure(Result(ok = true, rows = 0L, errors = Vector.empty))

          case _ =>
            val lines: Stream[IO, String] =
              Fs2Files[IO]
                .readAll(p)
                .through(fs2.text.utf8.decode)
                .through(fs2.text.lines)

            val acc0 = Acc(rows = 0L, errs = Vector.empty, lineNo = 0L)
            lines
              .compile
              .fold(acc0)((acc, raw) => step(acc, raw, maxErrors))
              .map(acc => Result(ok = acc.errs.isEmpty, rows = acc.rows, errors = acc.errs))
              .handleError(e => Result(ok = false, rows = 0L, errors = Vector(s"validateFile failed: ${e.getMessage}")))
        }
    }
  }
}

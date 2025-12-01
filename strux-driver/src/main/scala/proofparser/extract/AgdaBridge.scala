/** ============================================================================
 *  AgdaBridge.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/main/scala/proofparser/extract/AgdaBridge.scala
 *  Package: proofparser.extract
 *  Copyright: (c) 2025 Thmpr Lab, LLC.
 *
 *  Purpose
 *  -------
 *  A tiny process bridge to `agda --interaction-json` with:
 *
 *    +  lifecycle control (start/stop)
 *    +  line-based send/receive
 *    +  JSON helpers (send JSON values as a single line)
 *    +  explicit, typed errors (`Either[String, A]`) instead of exceptions
 *
 *  Design
 *  ------
 *  +  This class owns exactly one Agda child process.
 *  +  All I/O is UTF-8, line-oriented. We never block forever (callers implement timeouts).
 *  +  We DO NOT interpret Agda’s JSON protocol here; we just read/write lines.
 *     Higher layers (extractors) decide what to send and how to parse.
 *
 *  Typical Usage
 *  -------------
 *
 *    {{{
 *    val bridge = new AgdaBridge() // or new AgdaBridge(Seq("agda","--interaction-json","--library-file", "/path/to/libraries"))
 *    for {
 *      _ <- bridge.start()
 *      _ <- bridge.sendJson(ujson.Obj("command" -> "IOTCM", "payload" -> ...))
 *      ln <- bridge.readLine() // Option[String]
 *    } yield ()
 *    bridge.stop()
 *    }}}
 *
 *  ============================================================================
 */

package proofparser.extract

import java.io.{BufferedReader, InputStreamReader, OutputStreamWriter, PrintWriter}
import java.nio.charset.StandardCharsets
import scala.util.control.NonFatal
import scala.util.{Try, Success, Failure}

final class AgdaBridge(
  val command: Seq[String] = Seq("agda", "--interaction-json")
) {

  private var proc: Option[Process] = None
  private var inReader: Option[BufferedReader] = None
  private var outWriter: Option[PrintWriter] = None

  /** Start the Agda process. Idempotent if already started. */
  def start(): Either[String, Unit] =
    if (proc.isDefined) Right(())
    else {
      Try {
        val pb = new ProcessBuilder(command: _*)
        // Important: inherit error stream so we can see diagnostics immediately.
        pb.redirectError(ProcessBuilder.Redirect.INHERIT)
        val p = pb.start()
        proc = Some(p)
        inReader = Some(new BufferedReader(new InputStreamReader(p.getInputStream, StandardCharsets.UTF_8)))
        outWriter = Some(new PrintWriter(new OutputStreamWriter(p.getOutputStream, StandardCharsets.UTF_8), true))
      } match {
        case Success(_) => Right(())
        case Failure(e) => Left(s"Failed to start Agda process: ${e.getMessage}")
      }
    }

  /** Stop the Agda process gracefully. Safe to call multiple times. */
  def stop(): Unit = {
    try outWriter.foreach(_.flush()) catch { case _: Throwable => () }
    outWriter = None
    inReader.foreach(_.close()); inReader = None
    proc.foreach(_.destroy()); proc = None
  }

  /** Send a raw line (appends '\n'). */
  def send(line: String): Either[String, Unit] = synchronized {
    outWriter match {
      case None => Left("AgdaBridge not started; call start() first.")
      case Some(w) =>
        Try { w.println(line); w.flush() } match {
          case Success(_) => Right(())
          case Failure(e) => Left(s"Failed to write to Agda: ${e.getMessage}")
        }
    }
  }

  /** Convenience: write a ujson.Value as a single line. */
  def sendJson(js: ujson.Value): Either[String, Unit] =
    send(ujson.write(js))

  /** Read one line if available (blocking until a line or EOF). Return None on EOF. */
  def readLine(): Either[String, Option[String]] =
    inReader match {
      case None => Left("AgdaBridge not started; call start() first.")
      case Some(r) =>
        Try {
          val s = r.readLine()
          if (s == null) None else Some(s)
        } match {
          case Success(v) => Right(v)
          case Failure(e) => Left(s"Failed to read from Agda: ${e.getMessage}")
        }
    }
}

/**
 * ## Helpers to build Agda IOTCM commands.
 *
 * We keep these as *pure builders* returning `ujson.Value`.
 * Notes for Agda JSON protocol (varies by version/build):
 * - In many versions, a load looks like:
 *   {"command":"IOTCM","payload":["",[],"NonInteractive",{"command":"Cmd_load","file":"...","args":["-i", "...", "-l", "..."]}]}
 * - Some builds require minor shape tweaks; higher layers can adapt as needed.
 */
object AgdaIOTCM {
  def load(file: String, include: Seq[String], libs: Seq[String] = Nil): ujson.Value = {
    val incArgs = include.flatMap(inc => Seq("-i", inc))
    val libArgs = libs.flatMap(l => Seq("-l", l))
    val args    = incArgs ++ libArgs

    ujson.Obj(
      "kind"    -> "IOTCM",
      "payload" -> ujson.Arr(
        ujson.Str(""),    // interaction id
        ujson.Arr(),      // range/options
        ujson.Str("NonInteractive"),
        ujson.Obj(
          "kind"    -> "Cmd_load",
          "payload" -> ujson.Obj(
            "file" -> file,
            "args" -> ujson.Arr(args.map(ujson.Str): _*)
          )
        )
      )
    )
  }
}


/**
 * ## Minimal recognizers for a few Agda messages
 * Keep these tiny and purely pattern-based; avoid throwing.
 */
object AgdaMsgs {
  def isAllGoals(m: ujson.Value): Boolean =
    m("kind").strOpt.contains("DisplayInfo") &&
    m.obj.get("payload").exists(p => p("info").obj.get("kind").exists(_.str == "AllGoalsWarnings"))

  def isInteractionPoints(m: ujson.Value): Boolean =
    m("kind").strOpt.contains("InteractionPoints")

  def isStatus(m: ujson.Value): Boolean =
    m("kind").strOpt.contains("Status")
}

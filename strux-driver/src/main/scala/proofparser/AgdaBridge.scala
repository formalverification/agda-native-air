/**
 * AgdaBridge.scala
 *
 * Description: Minimal bridge for `agda --interaction-json`. Starts the process,
 *              sends IOTCM commands, and reads JSON messages line-by-line.
 *
 * File: proof-parser/src/main/scala/proofparser/AgdaBridge.scala
 *
 * Usage:
 *   val agda = new AgdaBridge() ; agda.start()
 *   agda.send(AgdaIOTCM.load(file = "Foo.agda", include = Seq("."), libs = Seq("standard-library")))
 *   var msg = agda.readLine()
 *   // ... handle messages ...
 *   agda.stop()
 *
 * Examples:
 *   // See AgdaSimplifiedExtractor for end-to-end usage that collects goal info.
 *
 * Notes:
 *   - Only a tiny subset of the protocol is implemented; add recognizers as needed.
 *   - Keep process lifecycle well-scoped to avoid zombie processes.
 *
 * (c) 2025 Thmpr Lab, LLC.
 */

package proofparser

import java.io._
import scala.sys.process._
import scala.util.control.NonFatal
import upickle.default._

/** Minimal bridge for `agda --interaction-json`.
  * We only handle enough of the protocol to:
  *  - load a file
  *  - observe metas/goals/constraints
  *  - observe "give/solve" messages if present
  */
final class AgdaBridge(
  agdaCmd: Seq[String] = Seq("agda", "--interaction-json")
) {
  private val pb = new ProcessBuilder(agdaCmd: _*)
  private var proc: Process = _
  private var in: BufferedWriter = _
  private var out: BufferedReader = _

  def start(): Unit = {
    proc = pb.start()
    in  = new BufferedWriter(new OutputStreamWriter(proc.getOutputStream, "UTF-8"))
    out = new BufferedReader(new InputStreamReader(proc.getInputStream, "UTF-8"))
  }

  def stop(): Unit = {
    try in.close() catch { case _: Throwable => () }
    try out.close() catch { case _: Throwable => () }
    if (proc != null) proc.destroy()
  }

  /** Send one JSON command line (no final newline required; we add it). */
  def send(obj: ujson.Value): Unit = {
    val s = obj.render()
    in.write(s)
    in.write("\n")
    in.flush()
  }

  /** Read next JSON line from Agda (blocking). Returns None on EOF. */
  def readLine(): Option[ujson.Value] = {
    val s = out.readLine()
    if (s == null) None else Some(ujson.read(s))
  }
}

/** Helpers to build Agda IOTCM commands.
  * Agda’s protocol is documented in the code & editor backends. We use a tiny subset:
 *   { "command": "IOTCM"
 *   , "payload": [""
 *                , []
 *                , "NonInteractive"
 *                , { "command" :"Cmd_load"
 *                  , "file"    : "..."
 *                  , "args"    : ["-i", "<inc1>", "-i", "<inc2>", "-l", "standard-library"]
 *                  }
 *                ]
 *   }
  */
object AgdaIOTCM {
  def load(file: String, include: Seq[String], libs: Seq[String] = Nil): ujson.Value = {
    val args = include.flatMap(inc => Seq("-i", inc)) ++ libs.flatMap(l => Seq("-l", l))
    ujson.Obj(
      "command" -> "IOTCM",
      "payload" -> ujson.Arr(
        "", ujson.Arr(), "NonInteractive",
        ujson.Obj(
          "command" -> "Cmd_load",
          "file"    -> file,
          "args"    -> ujson.Arr(args.map(ujson.Str): _*)
        )
      )
    )
  }
}

/** Minimal subset of messages we care about. We keep them as ujson and
  * pick just the fields we need in the extractor.
  */
object AgdaMsgs {
  def isAllGoals(m: ujson.Value): Boolean =
    m("kind").strOpt.contains("DisplayInfo") &&
    m.obj.get("payload").exists(p => p("info").obj.get("kind").exists(_.str == "AllGoalsWarnings"))

  def isInteractionPoints(m: ujson.Value): Boolean =
    m("kind").strOpt.contains("InteractionPoints")

  def isStatus(m: ujson.Value): Boolean =
    m("kind").strOpt.contains("Status")

  // Extend with other recognizers as needed (e.g. “Solved”, “GiveAction”, etc.).
}

/**
 * AgdaBridge.scala
 *
 * Description: Minimal bridge for `agda --interaction-json`. Starts the Agda process,
 *              writes interaction (IOTCM) commands, and reads JSON lines from stdout.
 *
  * File: proof-parser/src/main/scala/proofparser/AgdaBridge.scala
 *
 * Usages:
 *   1.  val agda = new AgdaBridge() ; agda.start()
 *       agda.send("""{"command":"SomeIOTCM"}""")
 *       val line: Option[String] = agda.readLine()
 *       agda.stop()
 *
 *   2.  val agda = new AgdaBridge() ; agda.start()
 *       agda.send(AgdaIOTCM.load(file = "Foo.agda", include = Seq("."), libs = Seq("standard-library")))
 *       var msg = agda.readLine()
 *       // ... handle messages ...
 *       agda.stop()
 *
  * Examples:
 *   // See AgdaSimplifiedExtractor for end-to-end usage that collects goal info.
 *
 * Notes:
 *   - Only a tiny subset of the protocol is implemented; add recognizers as needed.
 *   - Keep process lifecycle well-scoped to avoid zombie processes.
 *   - Uses java.lang.ProcessBuilder (avoid scala.sys.process.* here).
 *   - Redirects stderr → stdout so we only need one reader.
 *
 * (c) 2025 Thmpr Lab, LLC.
 */


package proofparser

import java.io._
import java.nio.charset.StandardCharsets
import java.lang.ProcessBuilder.Redirect

final class AgdaBridge(
  agdaCmd: Seq[String] = Seq("agda", "--interaction-json")
) {

  private var pb: java.lang.ProcessBuilder = _
  private var proc: java.lang.Process = _
  private var in: BufferedWriter = _
  private var out: BufferedReader = _

  def start(): Unit = {
    require(proc == null, "AgdaBridge already started")

    pb = new java.lang.ProcessBuilder(agdaCmd: _*)
    pb.redirectErrorStream(true) // merge stderr into stdout for simplicity
    proc = pb.start()

    in  = new BufferedWriter(new OutputStreamWriter(proc.getOutputStream, StandardCharsets.UTF_8))
    out = new BufferedReader(new InputStreamReader(proc.getInputStream, StandardCharsets.UTF_8))
  }

  /** Send a line to Agda (adds newline, flushes). */
  def send(line: String): Unit = {
    require(in != null, "AgdaBridge not started")
    in.write(line)
    in.write("\n")
    in.flush()
  }

  /** Read a single line from Agda (None on EOF). */
  def readLine(): Option[String] = {
    require(out != null, "AgdaBridge not started")
    val s = out.readLine()
    if (s == null) None else Some(s)
  }

  def stop(): Unit = {
    try if (in != null) in.close() catch { case _: Throwable => () }
    try if (out != null) out.close() catch { case _: Throwable => () }
    try if (proc != null) proc.destroy() catch { case _: Throwable => () }
    in = null; out = null; proc = null; pb = null
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

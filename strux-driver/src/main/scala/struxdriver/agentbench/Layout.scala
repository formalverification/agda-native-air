/** ============================================================================
  *  Layout.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Layout.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  Where a run keeps things (issue #154), in one place, so the runner that
  *  writes a subject's archive and the judge that reads it back cannot
  *  disagree about a path.  A run root holds the report, the two JSONL
  *  files, the prompts, the staging server's log, the solved files, one work
  *  directory per subject (its cwd: the staged file and nothing else), and
  *  one subject directory per obligation: the server config, the rendered
  *  prompt, the stream-json transcript, the client's stderr, how the process
  *  ended, the final file under its module stem, and the verdict.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import java.nio.file.Path

/** The run directory. */
final case class RunLayout(runRoot: Path) {
  def report:     Path = runRoot.resolve("report.json")
  def protocol:   Path = runRoot.resolve("protocol.json")
  def results:    Path = runRoot.resolve("results.jsonl")
  def fixtures:   Path = runRoot.resolve("fixtures.jsonl")
  def prompts:    Path = runRoot.resolve("prompts")
  def solved:     Path = runRoot.resolve("solved")
  def stagingLog: Path = runRoot.resolve("server-stderr.log")

  /** The subject's working directory: the staged copy of the one file. */
  def workDir(id: String): Path = runRoot.resolve(s"work/$id")

  def subject(id: String): SubjectLayout = SubjectLayout(runRoot.resolve(s"subjects/$id"), this)

  def relative(p: Path): String = runRoot.relativize(p).toString
}

/** One subject's archive. */
final case class SubjectLayout(dir: Path, run: RunLayout) {
  def mcpConfig:  Path = dir.resolve("mcp.json")
  def prompt:     Path = dir.resolve("prompt.txt")
  def transcript: Path = dir.resolve("transcript.jsonl")
  def stderr:     Path = dir.resolve("stderr.log")
  def runRecord:  Path = dir.resolve("run.json")
  def outcome:    Path = dir.resolve("outcome.json")

  /** The file as the subject left it, under its module stem so Agda can check it. */
  def finalFile(stem: String): Path = dir.resolve(s"final/$stem.agda")

  def transcriptRel: String = run.relative(transcript)
}

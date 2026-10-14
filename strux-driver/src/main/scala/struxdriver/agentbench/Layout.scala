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
  *  disagree about a path.  A run root holds the report, the two JSONL files,
  *  the protocol, the price table it was priced at (issue #237: a copy, so a
  *  re-judge and a resume price at the run's own), the prompts, the staging
  *  server's log, the solved files, one work directory per subject (its cwd:
  *  the staged file and nothing else), and one subject directory per
  *  obligation: the server config (an arm with the server), the arm and the
  *  roots the subject was given (`subject.json`, issue #162, so a re-judge
  *  audits the run's own arm and roots rather than the operator's current
  *  ones), the rendered prompt, the stream-json transcript, the client's
  *  stderr, how the process ended, the final file under its module stem, and
  *  the verdict.  Both prompts are archived as the subject saw them, rendered:
  *  the shell arms' carry the row's own `agda` command and corpus path (issue
  *  #162), which the templates under the run root do not.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import java.nio.file.Path

object Layout {
  /** The run's own copy of its price table, by its name in the run root. */
  val pricesFile: String = "prices.json"

  /** A Codex run's own copy of its pinned model catalog, in the run root (issue #239). */
  val codexModelsFile: String = "codex-models.json"

  /** A Codex run's configuration template, under the run's prompts (issue #239). */
  val codexConfigTemplate: String = "codex-config.toml"
}

/** The run directory. */
final case class RunLayout(runRoot: Path) {
  def report:     Path = runRoot.resolve("report.json")
  def protocol:   Path = runRoot.resolve("protocol.json")
  def prices:     Path = runRoot.resolve(Layout.pricesFile)
  def leaks:      Path = runRoot.resolve("credential-leaks.json")
  def results:    Path = runRoot.resolve("results.jsonl")
  def fixtures:   Path = runRoot.resolve("fixtures.jsonl")
  def prompts:    Path = runRoot.resolve("prompts")
  def solved:     Path = runRoot.resolve("solved")
  def stagingLog: Path = runRoot.resolve("server-stderr.log")

  /** The subject's working directory: the staged copy of the one file. */
  def workDir(id: String): Path = runRoot.resolve(s"work/$id")

  /** A Codex run's own copy of its pinned model catalog (issue #239). */
  def codexModels: Path = runRoot.resolve(Layout.codexModelsFile)

  /** Where Codex subjects keep their own CODEX_HOME (issue #239): beside the
    * run directory, never in it, since each holds a link to the operator's
    * login, so no run directory, and no copy of one, can carry a login.
    */
  def codexHomes: Path = runRoot.resolveSibling(s".codex-homes/${runRoot.getFileName}")

  /** A Codex subject's own CODEX_HOME. */
  def codexHome(id: String): CodexHome = CodexHome(codexHomes.resolve(id))

  def subject(id: String): SubjectLayout = SubjectLayout(runRoot.resolve(s"subjects/$id"), this)

  def relative(p: Path): String = runRoot.relativize(p).toString
}

/** One subject's archive. */
final case class SubjectLayout(dir: Path, run: RunLayout) {
  def mcpConfig:  Path = dir.resolve("mcp.json")
  def record:     Path = dir.resolve("subject.json")
  def prompt:     Path = dir.resolve("prompt.txt")
  def sysPrompt:  Path = dir.resolve("system-prompt.txt")
  def transcript: Path = dir.resolve("transcript.jsonl")
  def stderr:     Path = dir.resolve("stderr.log")
  def runRecord:  Path = dir.resolve("run.json")
  def outcome:    Path = dir.resolve("outcome.json")

  /** A Codex subject's own records (issue #239): its configuration, the
    * `--json` stream as Codex wrote it, the session's rollout (filtered for
    * the archive, CodexSubject.archivable), and the surface its first
    * request presented; `transcript` is the adapter's reading of them.
    */
  def codexConfig:  Path = dir.resolve("codex-config.toml")
  def codexEvents:  Path = dir.resolve("codex-events.jsonl")
  def codexRollout: Path = dir.resolve("codex-rollout.jsonl")
  def codexSurface: Path = dir.resolve("codex-surface.json")

  /** The file as the subject left it, under its module stem so Agda can check it. */
  def finalFile(stem: String): Path = dir.resolve(s"final/$stem.agda")

  def transcriptRel: String = run.relative(transcript)
}

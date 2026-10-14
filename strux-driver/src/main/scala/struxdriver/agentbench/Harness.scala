/** ============================================================================
  *  Harness.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Harness.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  Which agent harness a run's subjects are (issue #239): `claude`, a
  *  non-interactive `claude -p` session (Subject.scala), the instrument of
  *  every archived run; or `codex`, a `codex exec --json` session
  *  (CodexSubject.scala), the only way to put OpenAI's models in front of the
  *  benchmark, since they have no Anthropic-compatible endpoint.  A run id is
  *  one harness, recorded in `protocol.json` and in each Codex subject's own
  *  record (absent, the record is a Claude subject's), so a re-judge reads a
  *  subject's transcript the way its harness wrote it and a resume across
  *  harnesses is refused.
  *
  *  Design notes
  *  ------------
  *  - A Codex row measures the harness and the model together, never the
  *    model alone: Codex brings its own system prompt and its own way of
  *    calling tools (JavaScript cells beside the top-level tools), and the
  *    caps are enforced from outside it.  The harness is a protocol field
  *    for that reason, beside the model.
  *  - A Codex subject is given the `mcp` arm's instrument and nothing more:
  *    its shell is off, it reads through a confined read tool (Read), and it
  *    edits with apply_patch (Edit).  What Codex presents beyond that and
  *    cannot be switched off (its code-mode entry points, the MCP resource
  *    tools every configured server brings, the clock, and the asynchronous
  *    question the model catalog registers) is `fixedSurface`: admitted when
  *    presented, and its use recorded, never an extra instrument for Agda.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

sealed abstract class Harness(val name: String) {

  /** Tools this harness presents on every arm beyond the arm's own, which
    * the audit admits.
    */
  def fixedSurface: Set[String]

  /** The caps the harness enforces, and how: the client's own, or the
    * harness's from outside the client.
    */
  def capsEnforced: Vector[String]

  /** The price table a fresh run reads when `--prices` names none, from the
    * project root.
    */
  def defaultPrices: String
}

object Harness {

  case object Claude extends Harness("claude") {
    val fixedSurface: Set[String]    = Set.empty
    val capsEnforced: Vector[String] = Vector("turns:client", "budget:client", "wall:harness")
    val defaultPrices: String        = "data/benchmarks/prices-anthropic.json"
  }

  case object Codex extends Harness("codex") {
    val fixedSurface: Set[String] = Set(
      "exec", "wait", "request_user_input_async",
      "list_mcp_resources", "list_mcp_resource_templates", "read_mcp_resource", "clock__curr_time")
    val capsEnforced: Vector[String] = Vector("turns:harness", "budget:harness", "wall:harness")
    val defaultPrices: String        = "data/benchmarks/prices-openai.json"
  }

  val all: Vector[Harness] = Vector(Claude, Codex)

  /** The archived runs' harness, and so the default: a record that names
    * none was made by `claude -p`.
    */
  val default: Harness = Claude

  def parse(s: String): Either[String, Harness] =
    all.find(_.name == s).toRight(s"bad --harness: $s (${all.map(_.name).mkString("|")})")
}

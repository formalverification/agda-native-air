/** ============================================================================
  *  Arm.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Arm.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  Which instrument an arm puts in its subjects' hands (issue #162), so that
  *  the attribution measurement is one knob: `shell` gives the raw materials
  *  (Bash, and the pinned `agda` on PATH) and no server, `mcp` gives the
  *  server and no shell (the archived protocol), `both` gives both.  A run id
  *  is one arm, recorded in `protocol.json` and in every subject's own record,
  *  so a re-judge audits a run under the arm it was run with rather than
  *  under whatever the operator last typed.
  *
  *  Design notes
  *  ------------
  *  - The built-in tool set is the arm's: Read and Edit everywhere, Bash only
  *    where the arm has a shell.  A tool presented beyond the arm's set is an
  *    anomaly, so the set has to be exact.
  *  - An arm with the server admits ANY `mcp__agda__` tool rather than a fixed
  *    list, because the server's surface grows: it exposed thirteen tools when
  *    the archived arms ran and fourteen since `search_in_scope` landed (PR
  *    #161, issue #17).  `Subject.agdaToolsRequired` is the floor every such
  *    arm must have; what was actually presented is recorded per subject, so
  *    the report says which surface a run measured instead of assuming one.
  *  - A run with `--expose` (issue #191) presents a subset, and then the
  *    subset is the exact expectation both ways: every exposed tool must
  *    arrive, and an agda tool outside it is as foreign as Bash on the mcp
  *    arm.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

sealed abstract class Arm(val name: String, val hasServer: Boolean, val hasShell: Boolean) {

  /** The built-in client tools this arm presents (`--tools`). */
  def builtinTools: Set[String] = Subject.fileTools ++ (if (hasShell) Set(Arm.bash) else Set.empty[String])

  /** The tools this arm may pre-approve (`--allowedTools`): the server's
    * namespace when it has one, Bash when it has a shell.  Read and Edit are
    * carried by `--permission-mode acceptEdits`, as in the archived arms.
    */
  def allowedTools: Vector[String] =
    (if (hasServer) Vector("mcp__agda") else Vector.empty) ++ (if (hasShell) Vector(Arm.bash) else Vector.empty)

  /** May a subject of this arm be presented this tool?  Under `--expose`
    * only the exposed agda tools qualify (issue #191).
    */
  def presents(tool: String, expose: Option[Vector[String]] = None): Boolean =
    builtinTools(tool) ||
      (hasServer && tool.startsWith(Arm.agdaPrefix) && expose.forall(_.contains(tool.stripPrefix(Arm.agdaPrefix))))
}

object Arm {
  val bash: String       = "Bash"
  val agdaPrefix: String = "mcp__agda__"

  case object Shell extends Arm("shell", hasServer = false, hasShell = true)
  case object Mcp   extends Arm("mcp",   hasServer = true,  hasShell = false)
  case object Both  extends Arm("both",  hasServer = true,  hasShell = true)

  val all: Vector[Arm] = Vector(Shell, Mcp, Both)

  /** The archived protocol's arm, and so the default: a run id that names no
    * arm is the server-only arm the archive holds.
    */
  val default: Arm = Mcp

  def parse(s: String): Either[String, Arm] =
    all.find(_.name == s).toRight(s"bad --arm: $s (${all.map(_.name).mkString("|")})")
}

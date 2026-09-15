/** ============================================================================
  *  Statement.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Statement.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  The two lines of an obligation that the protocol freezes as TEXT (issue
  *  #154): the module line and every original import line.  These are the
  *  scope the statement was posed in, and whether they are still there is a
  *  diff, not a parse: the final file is compared line for line, with comments
  *  stripped on both sides so a commented-out copy cannot stand in for the
  *  real one (Copilot on PR #158).  Everything else the judge wants to know
  *  about the statement it asks Agda (Judge.scala): what the definition's
  *  type is, whether the file is safe, whether a hole remains, what the body
  *  refers to.  Nothing here classifies a signature or a clause.
  *
  *  `Propose.Imports` (search package) also reads import lines, for the fixed
  *  proposer's lemma pool (module and `using` names); this reader only asks
  *  which lines are imports, for the diff.  Two questions, two readers.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

/** Lexical helpers for the diff: a comment stripper that keeps pragmas and
  * line structure, and the code lines it leaves.
  */
object Code {
  private def isDelim(c: Char): Boolean =
    c.isWhitespace || c == '(' || c == ')' || c == '{' || c == '}' || c == ';'

  /** Drop `-- ...` line comments and nested `{- ... -}` block comments; keep
    * `{-# ... #-}` pragmas and the line structure (newlines inside a block
    * comment survive, so line numbers are stable).
    */
  def stripComments(s: String): String = {
    val sb = new StringBuilder
    var i  = 0
    val n  = s.length
    while (i < n) {
      if (s.startsWith("{-#", i)) {
        val j   = s.indexOf("#-}", i)
        val end = if (j < 0) n else j + 3
        sb.append(s, i, end); i = end
      } else if (s.startsWith("{-", i)) {
        var depth = 1
        i += 2
        while (i < n && depth > 0) {
          if (s.startsWith("{-", i)) { depth += 1; i += 2 }
          else if (s.startsWith("-}", i)) { depth -= 1; i += 2 }
          else { if (s.charAt(i) == '\n') sb.append('\n'); i += 1 }
        }
      } else if (s.startsWith("--", i) && (i == 0 || isDelim(s.charAt(i - 1)))) {
        val j = s.indexOf('\n', i)
        i = if (j < 0) n else j
      } else {
        sb.append(s.charAt(i)); i += 1
      }
    }
    sb.toString
  }

  /** The lines that carry code, as the diff compares them: comments stripped
    * first (so a line inside a `{- -}` block is not code), trailing
    * whitespace dropped, blank lines removed.  Both sides of every comparison
    * go through this, so a trailing comment on an original line is tolerated
    * and a commented-out one is not.
    */
  def keptLines(source: String): Vector[String] =
    stripComments(source).split("\n", -1).toVector.map(_.replaceAll("\\s+$", "")).filterNot(_.isEmpty)
}

/** The frozen text of an obligation: its module line and its import lines. */
final case class Statement(hole: String, moduleLine: String, importLines: Vector[String])

object Statement {
  private val WherePrefix = """^where\s+""".r

  /** The import statement a line carries (`open import M ...` or `import M
    * ...`), with a leading `where` removed (`  where open import M using (x)`),
    * or None.
    */
  def importText(line: String): Option[String] = {
    val t = WherePrefix.replaceFirstIn(line.trim, "")
    if (t.startsWith("open import ") || t.startsWith("import ")) Some(t) else None
  }

  def isImport(line: String): Boolean = importText(line).isDefined

  /** Read the frozen text of an obligation; Left when it has no module line or
    * never mentions the definition it is said to declare.
    */
  def of(obligation: String, hole: String): Either[String, Statement] = {
    val lines = Code.keptLines(obligation)
    for {
      moduleLine <- lines.find(l => l.startsWith("module ") && l.endsWith(" where"))
                      .toRight("obligation has no top-level module line")
      _          <- if (lines.exists(l => l.startsWith(hole) && l.length > hole.length && l.charAt(hole.length).isWhitespace)) Right(())
                    else Left(s"obligation never declares `$hole` at column 0")
    } yield Statement(hole, moduleLine, lines.filter(l => !l.head.isWhitespace && isImport(l)))
  }
}

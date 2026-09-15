/** ============================================================================
  *  Statement.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Statement.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  What an obligation *states*, read off its source for the preservation
  *  gate (issue #154): the module line, the original import lines, the type
  *  signature of the definition with the hole, and the frozen blocks (every
  *  top-level declaration except that definition's clauses).  Beneath it,
  *  the two lexical helpers the gates share: a comment stripper that keeps
  *  pragmas and line structure, and a tokenizer on Agda's own delimiters.
  *
  *  Design notes
  *  ------------
  *  - This is a textual reading, not a parse of Agda: a column-0 line and its
  *    indented continuation lines form a block, and a block is the signature
  *    or a clause by how it begins.  It is enough for the committed fixtures
  *    (JudgeSpec sweeps all 55 obligation/gold pairs) and it names what the
  *    subject may not change; the question "is the statement the same" is
  *    one Agda can also answer (`type_of` on the definition name), which is
  *    the direction the judge should grow in.
  *  - `Propose.Imports` (search package) also reads import lines, for the
  *    fixed proposer's lemma pool: module and `using` names.  The reader here
  *    classifies lines for a diff and tolerates a leading `where`; the two
  *    serve different questions and are kept apart deliberately.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

/** Lexical helpers shared by the gates: comment stripping and tokenizing on
  * Agda's own delimiters (whitespace, parentheses, braces, semicolons, `@`,
  * and string quotes; a dot stays inside a token so a qualified name is one
  * token).
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

  def tokens(code: String): Vector[String] =
    code.split("[\\s(){};@\"]+").toVector.filter(_.nonEmpty)

  /** The lines that carry code, as the preservation gate compares them: every
    * comment stripped first (a line inside a `{- -}` block is not code, so a
    * frozen line hidden there does not count as present: Copilot on PR #158),
    * trailing whitespace dropped, blank lines removed.  Both sides of every
    * comparison go through this, so a trailing comment on an original line is
    * tolerated and a commented-out one is not.
    */
  def keptLines(source: String): Vector[String] =
    stripComments(source).split("\n", -1).toVector.map(_.replaceAll("\\s+$", "")).filterNot(_.isEmpty)
}

/** The frozen statement of an obligation: what the subject may not change. */
final case class Statement(
  hole:         String,
  moduleLine:   String,
  importLines:  Vector[String],
  signature:    Vector[String],
  frozenBlocks: Vector[Vector[String]]
)

object Statement {
  /** Top-level declaration blocks: a column-0 line plus the indented lines
    * after it, over the kept lines (comments and blank lines dropped).
    */
  def blocks(source: String): Vector[Vector[String]] =
    Code.keptLines(source).foldLeft(Vector.empty[Vector[String]]) { (acc, l) =>
      if (acc.isEmpty || !l.head.isWhitespace) acc :+ Vector(l)
      else acc.init :+ (acc.last :+ l)
    }

  private def afterHole(line: String, hole: String): Option[String] =
    if (line.startsWith(hole) && line.length > hole.length && line.charAt(hole.length).isWhitespace)
      Some(line.drop(hole.length).trim)
    else None

  /** `hole : ...` at column 0. */
  def isSignature(block: Vector[String], hole: String): Boolean =
    afterHole(block.head, hole).exists(rest => rest.startsWith(":") && (rest.length == 1 || rest.charAt(1).isWhitespace))

  /** `hole pats = ...` (or `hole = ...`) at column 0: a clause of the definition. */
  def isClause(block: Vector[String], hole: String): Boolean =
    afterHole(block.head, hole).exists(rest => !rest.startsWith(":")) || block.head == hole

  private val WherePrefix = """^where\s+""".r

  /** The `open` or `import` statement a line carries, with a leading `where`
    * removed (`  where open import M using (x)`), or None.
    */
  def openText(line: String): Option[String] = {
    val t = WherePrefix.replaceFirstIn(line.trim, "")
    if (t.startsWith("open ") || t.startsWith("import ")) Some(t) else None
  }

  /** The import statement a line carries (`open import M ...` or `import M ...`), or None. */
  def importText(line: String): Option[String] =
    openText(line).filter(t => t.startsWith("open import ") || t.startsWith("import "))

  def isImport(line: String): Boolean = importText(line).isDefined

  /** Read the statement of an obligation; Left when it has no module line, no
    * signature for the hole, or no clause for it.
    */
  def of(obligation: String, hole: String): Either[String, Statement] = {
    val bs = blocks(obligation)
    for {
      moduleLine <- bs.map(_.head).find(l => l.startsWith("module ") && l.trim.endsWith(" where"))
                      .toRight("obligation has no top-level module line")
      signature  <- bs.find(isSignature(_, hole)).toRight(s"obligation has no type signature for `$hole`")
      _          <- if (bs.exists(isClause(_, hole))) Right(()) else Left(s"obligation has no clause for `$hole`")
    } yield Statement(
      hole         = hole,
      moduleLine   = moduleLine,
      importLines  = bs.map(_.head).filter(isImport),
      signature    = signature,
      frozenBlocks = bs.filterNot(isClause(_, hole))
    )
  }
}

/** ============================================================================
  *  ShellAudit.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/ShellAudit.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  Confine the shell arm by audit (issue #162).  The client can confine its
  *  file tools (`--restricted` keeps Read and Edit inside the working
  *  directories, `--add-dir` included) but it cannot confine Bash: a
  *  pre-approved Bash call runs whatever it is given.  So the shell arm's
  *  isolation is a reading of the paths each Bash command names, and this file
  *  is that reader: it lexes the command, splits it into simple commands,
  *  finds every path they name, and reports the ones that fall outside the
  *  roots the arm allows.  It also classes each call, which is what the
  *  report's shell-side `perTool` extension counts.
  *
  *  Conservative by construction
  *  ----------------------------
  *  A command this reader cannot account for is a VIOLATION, never a pass.
  *  Three kinds of unaccountable command, each reported with the command text:
  *
  *    1. A construct it cannot see through: command substitution (`$(...)`,
  *       backticks), parameter expansion (`$VAR`, `${...}`), or an
  *       unterminated quote.  A path could be hiding in the result, so the
  *       whole command fails and no path check is attempted.  A `$` inside
  *       single quotes is literal and is not an expansion, so an anchored
  *       grep pattern passes.  The special parameters that expand to a
  *       number or to the shell's option letters (`$?`, `$#`, `$$`, `$!`,
  *       `$-`) name no path, so they are read as literal text: `agda M.agda;
  *       echo "exit=$?"` is the ordinary way to see a batch verdict (issue
  *       #189's hard-tier cost pair).  `$@`, `$*`, `$_`, and the positional
  *       parameters can carry a path and stay violations.  A variable the
  *       call itself binds to a literal, in a simple command of its own
  *       (`G=<library>/src/Group; sed -n '1,90p' $G/Basic.lagda.md`), is read
  *       as that literal wherever the shell would expand it later in the call
  *       (`bindLiterals`), so its paths are checked like any others; a
  *       variable used before it is bound, bound in a pipeline stage or as a
  *       prefix of another command, or bound to a value that itself expands,
  *       is still unaccountable.
  *    2. A program it does not model (`allowedPrograms`): anything that runs
  *       another program (`bash`, `env`, `xargs`, `eval`, `timeout`), a shell
  *       keyword (`for`, `while`, `if`), an interpreter, or simply a tool that
  *       has not been considered.  The segment fails on the program alone and
  *       its arguments are not read: the program is the finding.  Widening
  *       this list is a change to the audit, and the rule is that every arm of
  *       a comparison is re-judged under one audit.
  *    3. A `cd` out of the arm's roots.  A `cd` INTO one of them is read
  *       faithfully: the reader carries the working directory across the simple
  *       commands of a call, so the paths after a `cd` resolve where the shell
  *       would resolve them.  A `cd` elsewhere is a shell leaving the roots,
  *       and this reader could not resolve what followed it either.
  *
  *  What the roots mean
  *  -------------------
  *  Reads are allowed under the work directory, the library source roots
  *  (`--add-dir`'s, from the Agda registry), and the row's corpus files; also
  *  the three standard sinks (`/dev/null`, `/dev/stdout`, `/dev/stderr`), which
  *  are writable too.  Writes are allowed only under the work directory: a
  *  redirection target, and the destination of a write-capable program
  *  (`cp`, `mv`, `rm`, `mkdir`, `touch`, `tee`, `sed -i`, ...), must lie there.
  *  A here-doc BODY is data on the program's standard input and names no path
  *  the shell opens, so it is stripped before lexing; the redirection that
  *  carries it is audited like any other.
  *
  *  Pinned by ShellAuditSpec, which was written before this file.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import java.nio.file.{Path, Paths}

/** Where a shell command of one subject may touch the filesystem: its work
  * directory (read and write), the library source roots and the row's corpus
  * files (read only).  Recorded per subject, so a re-judge audits against the
  * roots the run had rather than today's nix store paths.
  */
final case class ShellRoots(workDir: Path, readRoots: Vector[Path], corpora: Vector[Path]) {
  private val work: Path = workDir.toAbsolutePath.normalize

  /** Every root a read may lie under. */
  def readable: Vector[Path] = work +: (readRoots ++ corpora).map(_.toAbsolutePath.normalize)

  def canRead(p: Path): Boolean  = ShellAudit.sinks(p.toString) || readable.exists(p.startsWith)
  def canWrite(p: Path): Boolean = ShellAudit.sinks(p.toString) || p.startsWith(work)
  def isCorpus(p: Path): Boolean = corpora.map(_.toAbsolutePath.normalize).exists(p.startsWith)
  def isLibrary(p: Path): Boolean = readRoots.map(_.toAbsolutePath.normalize).exists(p.startsWith)
  def isWorkDir(p: Path): Boolean = p == work
}

/** What the audit made of one Bash call: what it may not do, and what it is. */
final case class ShellVerdict(violations: Vector[String], commandClass: String)

object ShellAudit {

  /** The standard sinks, readable and writable everywhere: a command that
    * throws output away is not leaving the protocol.
    */
  val sinks: Set[String] = Set("/dev/null", "/dev/stdout", "/dev/stderr", "/dev/fd/1", "/dev/fd/2", "/dev/tty")

  /** The classes a Bash call is counted under, in the order they are tried:
    * a call has exactly one, so the counts sum to the arm's Bash calls.
    */
  val classes: Vector[String] = Vector("agda-interaction", "agda-batch", "corpus-grep", "library-read", "other")

  /** The programs this reader models: `agda`, and the read-only text plumbing
    * plus the file movers a subject needs inside its own directory.  Nothing
    * here runs another program.
    */
  val allowedPrograms: Set[String] = Set(
    "agda",
    "cat", "head", "tail", "grep", "egrep", "fgrep", "rg", "sed", "awk", "cut", "tr", "sort", "uniq",
    "wc", "ls", "find", "jq", "echo", "printf", "pwd", "true", "false", "test", "diff", "cmp",
    "basename", "dirname", "realpath", "readlink", "nl", "stat", "file", "paste", "column",
    "expand", "fold", "rev", "comm", "join", "tac", "od", "md5sum", "sha256sum",
    "cp", "mv", "rm", "rmdir", "mkdir", "touch", "tee", "truncate", "ln", "chmod"
  )

  /** Programs whose path arguments are write targets: all of them, or (for the
    * copiers) the last one, which is the destination.  OriginalInView reads
    * `writesLast` too, so a copier the audit knows is also an edit of the
    * work file when it is the destination (issue #188).
    */
  private val writesAll:  Set[String] = Set("rm", "rmdir", "mkdir", "touch", "tee", "truncate", "chmod")
  private[agentbench] val writesLast: Set[String] = Set("cp", "mv", "ln")

  /** `find` actions that run a program or write a file: outside what this reader models. */
  private val findActions: Set[String] = Set("-exec", "-execdir", "-ok", "-okdir", "-delete", "-fprint", "-fprintf", "-fls")

  // ------------------------------------------------------------------ lexing

  private[agentbench] sealed trait Tok
  private[agentbench] final case class Word(text: String, singleQuoted: Boolean) extends Tok
  private[agentbench] final case class Op(text: String) extends Tok

  /** A lexed command: its tokens, and whether it hid something from the reader. */
  private[agentbench] final case class Lexed(toks: Vector[Tok], opaque: Option[String])

  private val separators: Set[String] = Set(";", "&&", "||", "|", "&", "\n")

  /** Strip every here-doc body: a body is standard input to the program, not a
    * path the shell opens, and reading it as tokens would invent findings.
    */
  private[agentbench] def stripHeredocs(cmd: String): String = {
    @annotation.tailrec
    def drop(delims: List[String], lines: List[String]): List[String] = delims match {
      case Nil          => lines
      case d :: moreD   => lines.dropWhile(_.trim != d) match {
        case Nil       => Nil                                      // unterminated body: all of it is data
        case _ :: rest => drop(moreD, rest)
      }
    }
    @annotation.tailrec
    def go(lines: List[String], out: Vector[String]): Vector[String] = lines match {
      case Nil            => out
      case line :: rest   => heredocDelims(line) match {
        case Nil  => go(rest, out :+ line)
        case ds   => go(drop(ds, rest), out :+ line)
      }
    }
    go(cmd.linesIterator.toList, Vector.empty).mkString("\n")
  }

  /** The here-doc delimiters a line opens, in order: each `<<` or `<<-` that
    * is not `<<<` and is not inside quotes, with the following word's quotes
    * stripped.
    */
  private[agentbench] def heredocDelims(line: String): List[String] = {
    @annotation.tailrec
    def go(i: Int, quote: Char, acc: List[String]): List[String] =
      if (i >= line.length) acc.reverse
      else {
        val c = line.charAt(i)
        if (quote != 0) go(i + 1, if (c == quote) 0.toChar else quote, acc)
        else if (c == '\'' || c == '"') go(i + 1, c, acc)
        else if (c == '\\') go(i + 2, quote, acc)
        else if (c == '<' && line.startsWith("<<", i) && !line.startsWith("<<<", i)) {
          val afterOp = i + 2 + (if (line.startsWith("<<-", i)) 1 else 0)
          val start   = line.indexWhere(!_.isWhitespace, afterOp.min(line.length))
          if (start < 0) go(line.length, quote, acc)
          else {
            val end   = line.indexWhere(ch => ch.isWhitespace || ch == ';' || ch == '|' || ch == '&', start) match {
              case -1 => line.length
              case k  => k
            }
            val delim = line.substring(start, end).filterNot(ch => ch == '\'' || ch == '"')
            go(end, quote, if (delim.isEmpty) acc else delim :: acc)
          }
        } else go(i + 1, quote, acc)
      }
    go(0, 0.toChar, Nil)
  }

  /** Lex one command into words and operators, reporting the first construct
    * that hides a path from the reader instead of guessing past it.
    */
  private[agentbench] def lex(raw: String): Lexed = lexText(stripHeredocs(raw))

  /** `lex` on a command whose here-doc bodies are already stripped. */
  private def lexText(s: String): Lexed = {
    @annotation.tailrec
    def go(i: Int, toks: Vector[Tok], cur: Option[String], sq: Boolean): Lexed = {
      val flush: Vector[Tok] = cur.fold(toks)(w => toks :+ Word(w, sq))
      if (i >= s.length) Lexed(flush, None)
      else s.charAt(i) match {
        case '\\' if i + 1 < s.length                    => go(i + 2, toks, Some(cur.getOrElse("") + s.charAt(i + 1)), sq)
        case '\'' =>
          s.indexOf('\'', i + 1) match {
            case -1 => Lexed(flush, Some("an unterminated quote"))
            case j  => go(j + 1, toks, Some(cur.getOrElse("") + s.substring(i + 1, j)), sq = true)
          }
        case '"' =>
          quoted(s, i + 1, '"') match {
            case Left(why)      => Lexed(flush, Some(why))
            case Right((t, j))  => go(j, toks, Some(cur.getOrElse("") + t), sq)
          }
        case '`'                                          => Lexed(flush, Some("a command substitution"))
        case '$' if i + 1 < s.length && numeric(s.charAt(i + 1)) => go(i + 2, toks, Some(cur.getOrElse("") + s.substring(i, i + 2)), sq)
        case '$' if i + 1 < s.length && expands(s.charAt(i + 1)) =>
          Lexed(flush, Some(if (s.charAt(i + 1) == '(') "a command substitution" else "a parameter expansion"))
        case c if c.isWhitespace && c != '\n'              => go(i + 1, flush, None, sq = false)
        case c if isOpStart(c) =>
          operatorAt(s, i, cur) match {
            case (op, j, dropDigit) =>
              val base = if (dropDigit) cur.map(_.dropRight(1)).filter(_.nonEmpty) else cur
              go(j, base.fold(toks)(w => toks :+ Word(w, sq)) :+ Op(op), None, sq = false)
          }
        case c                                             => go(i + 1, toks, Some(cur.getOrElse("") + c), sq)
      }
    }
    go(0, Vector.empty, None, sq = false)
  }

  private def expands(c: Char): Boolean = c == '(' || c == '{' || c.isLetterOrDigit || c == '_' || "?#*@!$-".contains(c)

  /** The special parameters whose value is a number or option letters, never a path. */
  private def numeric(c: Char): Boolean = "?#$!-".contains(c)

  /** A double-quoted run: expansion inside it is real, so it is reported. */
  private def quoted(s: String, from: Int, q: Char): Either[String, (String, Int)] = {
    @annotation.tailrec
    def go(i: Int, acc: String): Either[String, (String, Int)] =
      if (i >= s.length) Left("an unterminated quote")
      else s.charAt(i) match {
        case '\\' if i + 1 < s.length                      => go(i + 2, acc + s.charAt(i + 1))
        case '`'                                           => Left("a command substitution")
        case '$' if i + 1 < s.length && numeric(s.charAt(i + 1)) => go(i + 2, acc + s.substring(i, i + 2))
        case '$' if i + 1 < s.length && expands(s.charAt(i + 1)) =>
          Left(if (s.charAt(i + 1) == '(') "a command substitution" else "a parameter expansion")
        case c if c == q                                   => Right((acc, i + 1))
        case c                                             => go(i + 1, acc + c)
      }
    go(from, "")
  }

  private def isOpStart(c: Char): Boolean = c == ';' || c == '|' || c == '&' || c == '<' || c == '>' || c == '\n'

  /** The operator at `i`, the index after it, and whether a single leading
    * digit of the current word was its file descriptor (`2>`).
    */
  private def operatorAt(s: String, i: Int, cur: Option[String]): (String, Int, Boolean) = {
    val fd = cur.exists(w => w.length == 1 && w.charAt(0).isDigit) && s.charAt(i) == '>'
    val pre = if (fd) cur.get else ""
    val rest = s.substring(i)
    val op = Vector("<<<", "<<-", "<<", "&>>", "&>", ">>", ">", "<", "&&", "||", "|", ";", "&", "\n")
      .find(rest.startsWith).getOrElse(s.charAt(i).toString)
    // A duplication (`2>&1`, `>&2`) names a descriptor, never a path.
    val dup = if (rest.startsWith(op + "&")) {
      val tail = rest.drop(op.length + 1).takeWhile(c => c.isDigit || c == '-')
      Some("&" + tail)
    } else None
    (pre + op + dup.getOrElse(""), i + op.length + dup.fold(0)(_.length), fd)
  }

  // ---------------------------------------------------------- the bindings

  private val nameStart: Char => Boolean = c => c.isLetter && c < 128 || c == '_'
  private val nameChar: Char => Boolean  = c => c.isLetterOrDigit && c < 128 || c == '_'

  /** A word that assigns a shell variable, `NAME=value`: no program runs. */
  private[agentbench] def isAssignment(word: String): Boolean =
    word.indexOf('=') match {
      case k if k > 0 => nameStart(word.charAt(0)) && word.substring(0, k).forall(nameChar)
      case _          => false
    }

  /** Read the literal bindings a call makes and substitute them where the
    * shell would expand them (issue #189).  A simple command that is nothing
    * but `NAME=value`, at the start of the call or after `;`, `&&`, `||`, or a
    * newline, binds NAME when its value, unquoted, is plain path text: no
    * whitespace, quote, backslash, `$`, backtick, or control operator, so the
    * substitution can neither hide a path nor invent a command.  Every later
    * `$NAME` or `${NAME}` outside single quotes is then replaced by the value.
    * Anything else is left as written, so the lexer still reports it: a use
    * before the binding, `${NAME:-x}` and the other operator forms, a binding
    * in a pipeline stage or before `&` (a subshell's), and a prefix
    * assignment (`NAME=v cmd`, which the shell does not apply to its own
    * words), which also forgets any earlier binding of NAME.  It reads a
    * command whose here-doc bodies are already stripped, since a body is data
    * and its quotes would mislead the quote tracking.
    */
  private[agentbench] def bindLiterals(s: String): String = {
    def nameEnd(from: Int): Int = {
      @annotation.tailrec def go(j: Int): Int = if (j < s.length && nameChar(s.charAt(j))) go(j + 1) else j
      if (from < s.length && nameStart(s.charAt(from))) go(from + 1) else from
    }
    // An assignment's right-hand side from `from`: its unquoted text, when
    // that text is plain, and the index after it.
    def value(from: Int): (Option[String], Int) = {
      @annotation.tailrec
      def go(j: Int, acc: String, plain: Boolean): (Option[String], Int) =
        if (j >= s.length || s.charAt(j).isWhitespace || ";&|<>()".contains(s.charAt(j)))
          (Option.when(plain && acc.forall(ch => !"'\"\\`$".contains(ch)))(acc), j)
        else s.charAt(j) match {
          case q @ ('\'' | '"') => s.indexOf(q, j + 1) match {
            case -1 => (None, s.length)
            case k  => val inner = s.substring(j + 1, k); go(k + 1, acc + inner, plain && !inner.exists(_.isWhitespace))
          }
          case '\\' | '$' | '`' => go(j + 1, acc, plain = false)
          case c                 => go(j + 1, acc + c, plain)
        }
      go(from, "", plain = true)
    }
    // The binding counts only when the simple command ends at the value, at a
    // separator that keeps the current shell.
    def endsSimple(from: Int): Boolean = {
      val j = s.indexWhere(c => !(c.isWhitespace && c != '\n'), from)
      j < 0 || s.charAt(j) == ';' || s.charAt(j) == '\n' || s.startsWith("&&", j) || s.startsWith("||", j)
    }
    @annotation.tailrec
    def go(i: Int, quote: Char, atStart: Boolean, env: Map[String, String], out: String): String =
      if (i >= s.length) out
      else {
        val c = s.charAt(i)
        if (quote == '\'') go(i + 1, if (c == '\'') 0.toChar else quote, atStart = false, env, out + c)
        else if (c == '\\' && i + 1 < s.length) go(i + 2, quote, atStart = false, env, out + c + s.charAt(i + 1))
        else if (c == '$' && i + 1 < s.length) {
          val braced = s.charAt(i + 1) == '{'
          val from   = if (braced) i + 2 else i + 1
          val end    = nameEnd(from)
          val close  = if (!braced) end else if (end < s.length && s.charAt(end) == '}') end + 1 else -1
          env.get(s.substring(from, end)).filter(_ => end > from && close > 0) match {
            case Some(v) => go(close, quote, atStart = false, env, out + v)
            case None    => go(i + 1, quote, atStart = false, env, out + c)
          }
        }
        else if (quote == '"') go(i + 1, if (c == '"') 0.toChar else quote, atStart = false, env, out + c)
        else if (c == '\'' || c == '"') go(i + 1, c, atStart = false, env, out + c)
        else if (c == ';' || c == '\n') go(i + 1, quote, atStart = true, env, out + c)
        else if (s.startsWith("&&", i) || s.startsWith("||", i)) go(i + 2, quote, atStart = true, env, out + s.substring(i, i + 2))
        else if (c.isWhitespace) go(i + 1, quote, atStart, env, out + c)
        else if (atStart && nameStart(c) && nameEnd(i) < s.length && s.charAt(nameEnd(i)) == '=') {
          val name       = s.substring(i, nameEnd(i))
          val (v, after) = value(nameEnd(i) + 1)
          val env2       = v.filter(_ => endsSimple(after)).fold(env - name)(x => env + (name -> x))
          go(after, quote, atStart = false, env2, out + s.substring(i, after))
        }
        else go(i + 1, quote, atStart = false, env, out + c)
      }
    go(0, 0.toChar, atStart = true, Map.empty, "")
  }

  // --------------------------------------------------------------- the audit

  /** One simple command: its program, its words, and the paths its
    * redirections read and write.
    */
  private final case class Simple(words: Vector[Word], reads: Vector[String], writes: Vector[String], data: Set[Int])

  /** Split the token stream into simple commands, resolving each redirection's
    * target and marking here-doc delimiters and here-strings as data.
    */
  private def simples(toks: Vector[Tok]): Vector[Simple] = {
    def step(acc: Vector[Simple], cur: Simple, pending: Option[String], rest: List[Tok]): Vector[Simple] =
      rest match {
        case Nil => acc :+ cur
        case Op(o) :: tail if separators(o.trim) || separators(o) => step(acc :+ cur, Simple(Vector.empty, Vector.empty, Vector.empty, Set.empty), None, tail)
        case Op(o) :: tail =>
          val role =
            if (o.endsWith("&") || o.matches(""".*&[0-9-]*""")) None            // a descriptor duplication
            else if (o.contains(">")) Some("w")
            else if (o == "<<" || o == "<<-" || o == "<<<") Some("d")
            else Some("r")
          step(acc, cur, role, tail)
        case Word(w, q) :: tail =>
          pending match {
            case Some("w") => step(acc, cur.copy(writes = cur.writes :+ w), None, tail)
            case Some("r") => step(acc, cur.copy(reads = cur.reads :+ w), None, tail)
            case Some("d") => step(acc, cur, None, tail)                        // a delimiter or a here-string: data
            case _         => step(acc, cur.copy(words = cur.words :+ Word(w, q)), None, tail)
          }
      }
    step(Vector.empty, Simple(Vector.empty, Vector.empty, Vector.empty, Set.empty), None, toks.toList)
      .filter(s => s.words.nonEmpty || s.reads.nonEmpty || s.writes.nonEmpty)
  }

  /** The path a word names, when it names one: a word containing a separator,
    * or `.` and `..` themselves.  An option's prefix is stripped first, so
    * `-i/work` and `--library-file=/x` give up their paths.
    */
  private[agentbench] def pathOf(word: String): Option[String] = {
    val bare =
      if (!word.startsWith("-")) word
      else word.dropWhile(c => c == '-' || c.isLetterOrDigit || c == '_') match {
        case r if r.startsWith("=") => r.drop(1)
        case r                      => r
      }
    if (bare.isEmpty) None
    else if (bare.contains("/") || bare == "." || bare == "..") Some(bare)
    else None
  }

  /** Resolve a path a command named against the work directory; `None` when it
    * cannot be resolved into the allowed space at all (a `~` home reference).
    */
  private def resolve(workDir: Path, candidate: String): Option[Path] =
    if (candidate.startsWith("~")) None
    else {
      val p = Paths.get(candidate)
      Some((if (p.isAbsolute) p else workDir.toAbsolutePath.resolve(p)).normalize)
    }

  private def oneLine(cmd: String): String = {
    val flat = cmd.linesIterator.map(_.trim).filter(_.nonEmpty).mkString(" ; ")
    if (flat.length <= 200) flat else flat.take(197) + "..."
  }

  /** Read one Bash command: what it may not do, and what class it is.
    *
    * The simple commands are folded in order, carrying the working directory,
    * so a `cd` into one of the arm's roots is READ faithfully rather than
    * refused: the paths after it resolve where the shell would resolve them.
    * A `cd` to anywhere else is still a violation, because that is a shell
    * leaving the arm's roots, and because this reader could not resolve what
    * followed it.
    */
  def inspect(command: String, roots: ShellRoots): ShellVerdict = {
    val cmd    = oneLine(command)
    val lexed  = lexText(bindLiterals(stripHeredocs(command)))
    def fail(why: String): Vector[String] = Vector(s"Bash $why: $cmd")
    lexed.opaque match {
      // Unaccountable as a whole: no path check is attempted, because the
      // construct could carry any path at all.
      case Some(why) => ShellVerdict(fail(why), classOf(lexed.toks, roots))
      case None =>
        val vs = simples(lexed.toks).foldLeft((roots.workDir.toAbsolutePath.normalize, Vector.empty[String])) {
          case ((cwd, acc), simple) =>
            val (next, vs) = auditSimple(simple, roots, cmd, cwd)
            (next, acc ++ vs)
        }._2
        ShellVerdict(vs.distinct, classOf(lexed.toks, roots))
    }
  }

  /** One simple command, read from `cwd`: the working directory it leaves
    * behind, and what it may not do.
    */
  private def auditSimple(s: Simple, roots: ShellRoots, cmd: String, cwd: Path): (Path, Vector[String]) = {
    def fail(why: String): Vector[String] = Vector(s"Bash $why: $cmd")
    val prog = s.words.headOption.map(w => Paths.get(w.text).getFileName.toString).getOrElse("")
    val args = s.words.drop(1)
    if (prog.isEmpty || s.words.forall(w => isAssignment(w.text))) (cwd, Vector.empty)
    else if (prog == "cd") {
      args.map(_.text).find(!_.startsWith("-")).map(t => resolve(cwd, t)) match {
        case Some(Some(p)) if roots.canRead(p) => (p, Vector.empty)
        case Some(Some(p))                     => (cwd, fail(s"changes the working directory outside the arm's roots ($p)"))
        case _                                 => (cwd, fail("changes the working directory to a path this audit cannot resolve"))
      }
    }
    else (cwd, auditProgram(prog, args, s, roots, cmd, cwd))
  }

  /** Everything but `cd`: the program, then every path the command names. */
  private def auditProgram(prog: String, args: Vector[Word], s: Simple, roots: ShellRoots, cmd: String, cwd: Path): Vector[String] = {
    def fail(why: String): Vector[String] = Vector(s"Bash $why: $cmd")
    if (!allowedPrograms(prog)) fail(s"runs a program this audit does not model ($prog)")
    else if (prog == "find" && args.exists(a => findActions(a.text))) fail("uses a find action that runs a program or writes a file")
    else {
      val cands     = args.flatMap(a => pathOf(a.text))
      val inPlace   = prog == "sed" && args.exists(a => a.text == "-i" || a.text.startsWith("-i") && !a.text.contains("/") || a.text == "--in-place")
      val writeArgs =
        if (writesAll(prog) || inPlace) cands
        else if (writesLast(prog))      cands.lastOption.toVector
        else                            Vector.empty
      val readArgs  = cands.filterNot(writeArgs.contains) ++ s.reads
      val writes    = writeArgs ++ s.writes
      val badWrites = writes.flatMap { c =>
        resolve(cwd, c) match {
          case Some(p) if roots.canWrite(p) => None
          case Some(p)                      => Some(s"Bash writes outside the work directory ($p): $cmd")
          case None                         => Some(s"Bash names a path this audit cannot resolve ($c): $cmd")
        }
      }
      val badReads = readArgs.flatMap { c =>
        resolve(cwd, c) match {
          case Some(p) if roots.canRead(p) => None
          case Some(p)                     => Some(s"Bash reads outside the arm's roots ($p): $cmd")
          case None                        => Some(s"Bash names a path this audit cannot resolve ($c): $cmd")
        }
      }
      badWrites ++ badReads
    }
  }

  /** The call's class, the first that applies (`classes`), so the counts of a
    * run's Bash calls sum to the calls themselves.
    */
  private def classOf(toks: Vector[Tok], roots: ShellRoots): String = {
    val ss    = simples(toks)
    val progs = ss.map(_.words.headOption.map(w => Paths.get(w.text).getFileName.toString).getOrElse(""))
    val agdas = ss.zip(progs).collect { case (s, "agda") => s }
    val paths = ss.flatMap(s => (s.words.drop(1).flatMap(w => pathOf(w.text)) ++ s.reads ++ s.writes))
                  .flatMap(c => resolve(roots.workDir, c))
    if (agdas.exists(_.words.exists(w => w.text == "--interaction-json" || w.text == "--interaction"))) "agda-interaction"
    else if (agdas.nonEmpty)              "agda-batch"
    else if (paths.exists(roots.isCorpus)) "corpus-grep"
    else if (paths.exists(roots.isLibrary)) "library-read"
    else                                   "other"
  }

  /** Every Bash call of a transcript, audited and classed. */
  def auditCalls(t: Transcript, roots: ShellRoots): (Vector[String], Vector[(String, Int)]) = {
    val verdicts = t.usesOf(Arm.bash).map(u => inspect(u.str("command").getOrElse(""), roots))
    val counted  = classes.map(c => c -> verdicts.count(_.commandClass == c)).filter(_._2 > 0)
    (verdicts.flatMap(_.violations).distinct, counted)
  }
}

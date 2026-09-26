/** ============================================================================
  *  OriginalInView.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/OriginalInView.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  Whether the library's own proof of the lemma a row restates was in front
  *  of the subject before it wrote its answer (issue #188).  Every
  *  agda-algebras obligation restates a lemma the library already proves (the
  *  index row's `restates:` tag, `Original` in Judge.scala), and since issue
  *  #162 the libraries' sources are readable on every arm.  The restated rule
  *  reads the final body's references, so it catches a body that cites the
  *  original and not one that transcribes the original's proof; this reading
  *  is the column that says which solves could have been transcriptions.  It
  *  is reported, never gated: no verdict depends on it.
  *
  *  The reading
  *  -----------
  *  The original's FILE is its module's source (`Module/Path.agda`, or one of
  *  Agda's literate forms) under the first of the subject's read roots that
  *  holds it.  Its BODY is the definition's clauses: from the first line that
  *  begins with the name, carries an `=`, and is not the type signature, to
  *  the next blank line, code fence, or line indented no deeper that does not
  *  begin with the name.
  *
  *  The original was IN VIEW iff, before the subject composed its last
  *  successful edit of the work file (an Edit or Write naming it, or a Bash
  *  command that writes it), some call's successful result showed a line of
  *  that body longer than twelve characters, a line the subject had not itself
  *  written in an earlier call.  `how` says whether that call's input named
  *  the original's file (`read`: a Read of it, a `sed -n` or `cat` of it) or
  *  not (`result`: a recursive grep, say, whose answer carried the line), and
  *  `at` is the call's index among the subject's calls, from 0.
  *
  *  Edge cases, each pinned by OriginalInViewSpec
  *  ---------------------------------------------
  *  - A call that names the file without showing the proof is not the proof
  *    in view.  A `definition_of` answer names the file in its result (it
  *    answers where, not what); a Read of a range that stops short of the
  *    proof, or a grep for another name in the file, names it in its input.
  *    `reads` counts the successful calls whose input named the file, so the
  *    looser reading (any such call is enough) can still be made from the
  *    block: it is `inView || reads > 0`.
  *  - A refused read (the archived arms' "is outside the working directory")
  *    shows nothing; `refusedReads` counts it.
  *  - Order is by stream record, not by call (Transcript.scala): a result
  *    counts only if it came back before the last edit was composed, so a read
  *    made after the last edit, or in the same turn as it, did not shape the
  *    answer.  An edit the client refused changed nothing and is not an edit.
  *  - A line the subject wrote itself and then saw echoed (a Read of its own
  *    file) is not the original shown to it.  Three fixtures keep the
  *    original's name (`π`, `lift∼lower`, `lower∼lift`), so there the
  *    subject's own line and the library's are byte-identical.
  *  - Twelve characters: a shorter line (`refl`, `where`) matches text it did
  *    not come from.  A body with no longer line is looked for only in the
  *    answer of a call that named the file; a body not found at all (a mixfix
  *    name, whose clauses do not begin with it) makes any successful read of
  *    the file count, since nothing narrower can be checked.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.IO
import io.circe.Json
import io.circe.syntax._
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths}
import scala.util.Try

/** The original's defining file as the judge found it: its absolute path, its
  * path relative to the source root that holds it (which a command naming the
  * file contains, whatever directory it names it from), and the definition's
  * clause lines, stripped.
  */
final case class OriginalSource(file: Path, rel: String, body: Vector[String])

/** The `original` block of outcome.json, on a row whose index entry names an
  * original.  `inView` is None only when the reading could not be made: no
  * source file under the roots, or no transcript to read.
  */
final case class OriginalReading(
  file:         Option[String],
  inView:       Option[Boolean],
  how:          Option[String],
  at:           Option[Int],
  reads:        Int,
  refusedReads: Int
) {
  def seen: Boolean = inView.contains(true)

  def toJson: Json = Json.obj(
    "file"         -> file.asJson,
    "inView"       -> inView.asJson,
    "how"          -> how.asJson,
    "at"           -> at.asJson,
    "reads"        -> reads.asJson,
    "refusedReads" -> refusedReads.asJson
  )
}

object OriginalReading {
  /** A row with an original whose reading could not be made. */
  def unread(file: Option[String]): OriginalReading = OriginalReading(file, None, None, None, 0, 0)
}

object OriginalInView {

  /** Agda's source-file extensions, the plain one first. */
  val extensions: Vector[String] =
    Vector(".agda", ".lagda.md", ".lagda", ".lagda.tex", ".lagda.rst", ".lagda.org", ".lagda.typ", ".lagda.tree")

  /** A body line this short or shorter matches text it did not come from. */
  val minLine: Int = 12

  /** The tools whose input is the subject's own writing, never a request to see something. */
  val editTools: Set[String] = Set("Edit", "Write", "MultiEdit")

  /** Programs that run code of their own: a command running one on the work file is an edit of it. */
  val interpreters: Set[String] = Set("python", "python3", "perl", "ruby", "node", "sh", "bash", "zsh")

  private val separators: Set[String] = Set(";", "&&", "||", "|", "&", "\n")

  // ------------------------------------------------------------ the source

  /** The original's module and name, when the index names one. */
  def moduleOf(original: Original): Option[(String, String)] =
    original.qualified.filter(_ => original.tagged).flatMap { q =>
      val module = q.stripSuffix("." + original.bare)
      if (module.isEmpty || module == q) None else Some((module, original.bare))
    }

  /** The definition's clause lines, stripped: from the first line that begins
    * with `name`, carries an `=`, and is not the signature, to the next blank
    * line, code fence, or line indented no deeper that does not begin with
    * the name.  Empty when no line qualifies.
    */
  def body(text: String, name: String): Vector[String] = {
    val lines = text.linesIterator.toVector
    def begins(s: String): Boolean    = s == name || (s.startsWith(name) && s.charAt(name.length).isWhitespace)
    def signature(s: String): Boolean = s.drop(name.length).dropWhile(_.isWhitespace).startsWith(":")
    def fence(s: String): Boolean     = s.startsWith("```") || s.startsWith("\\end{code}") || s.startsWith("\\begin{code}")
    def indent(l: String): Int        = l.length - l.stripLeading.length
    lines.indexWhere { l => val s = l.strip; begins(s) && s.contains('=') && !signature(s) } match {
      case -1 => Vector.empty
      case i  =>
        val clause = lines(i)
        val more   = lines.drop(i + 1).takeWhile { l =>
          val s = l.strip
          s.nonEmpty && !fence(s) && (indent(l) > indent(clause) || begins(s))
        }
        (clause +: more).map(_.strip)
    }
  }

  /** The original's source under the first root that holds its module: the
    * file system is asked and the file read, hence IO.  None for a row whose
    * index entry names no original, or whose module no root holds.
    */
  def locate(original: Original, roots: Vector[Path]): IO[Option[OriginalSource]] =
    moduleOf(original) match {
      case None                 => IO.pure(None)
      case Some((module, name)) =>
        IO.blocking {
          val stem  = module.replace('.', '/')
          val found = roots.iterator.flatMap(root => extensions.iterator.map(ext => (root.resolve(stem + ext), stem + ext)))
                        .find { case (f, _) => Files.isRegularFile(f) }
          found.map { case (f, rel) =>
            OriginalSource(f.toAbsolutePath.normalize, rel, body(new String(Files.readAllBytes(f), StandardCharsets.UTF_8), name))
          }
        }
    }

  // ------------------------------------------------------------ the reading

  /** Longer than twelve characters, counted as Unicode code points: the
    * library's names are full of mathematical letters outside the BMP, which
    * a UTF-16 length would count twice.
    */
  private def long(line: String): Boolean = line.codePointCount(0, line.length) > minLine

  /** Every string in a call's arguments: its path, its command, its text. */
  private def strings(j: Json): Vector[String] =
    j.fold(Vector.empty, _ => Vector.empty, _ => Vector.empty, s => Vector(s),
      arr => arr.flatMap(strings), obj => obj.values.toVector.flatMap(strings))

  /** Does `s` name the file whose path under its source root is `rel`?  The
    * relative path must stand as a path of its own (after a separator, a
    * quote, whitespace, or nothing, and before no letter or digit), so an
    * absolute path, a path relative to the root, or a quoted one names the
    * file, and `Foo.agdai` does not name `Foo.agda`.
    */
  private[agentbench] def names(s: String, rel: String): Boolean = {
    @annotation.tailrec
    def from(i: Int): Boolean = s.indexOf(rel, i) match {
      case -1 => false
      case k  =>
        val end    = k + rel.length
        val before = k == 0 || { val c = s.charAt(k - 1); c == '/' || c.isWhitespace || "\"'`=:(<>|;&,".indexOf(c.toInt) >= 0 }
        val after  = end == s.length || !s.charAt(end).isLetterOrDigit
        (before && after) || from(k + 1)
    }
    from(0)
  }

  private def basename(w: String): String = w.split('/').lastOption.getOrElse(w)

  /** A descriptor duplication (`2>&1`, `>&2`) names no file. */
  private def duplication(op: String): Boolean = op.endsWith("&") || op.matches(""".*&[0-9-]*""")

  private def sedInPlace(args: Vector[String]): Boolean =
    args.exists(a => a.startsWith("-i") || a.startsWith("--in-place") || (a.matches("-[A-Za-z]+") && a.contains('i')))

  /** gawk's in-place extension, which rewrites every input file. */
  private def awkInPlace(args: Vector[String]): Boolean = {
    val inplace = (w: String) => w == "inplace" || w == "inplace.awk"
    args.zip(args.drop(1)).exists { case (a, b) => (a == "-i" || a == "--include") && inplace(b) } ||
      args.exists(a => (a.startsWith("-i") && inplace(a.drop(2))) || (a.startsWith("--include=") && inplace(a.stripPrefix("--include="))))
  }

  /** The file `sort` writes: its `-o` or `--output` argument, in any spelling. */
  private def sortOutput(args: Vector[String]): Option[String] =
    args.zip(args.drop(1).map(Option(_)) :+ None).collectFirst {
      case ("-o" | "--output", Some(f))                  => f
      case (a, _) if a.startsWith("--output=")           => a.stripPrefix("--output=")
      case (a, _) if a.startsWith("-o") && a.length > 2  => a.drop(2)
    }

  /** The file `uniq` writes: its second operand (`uniq [OPTION]... [INPUT
    * [OUTPUT]]`), past the options that take an argument of their own.
    */
  private def uniqOutput(args: Vector[String]): Option[String] = {
    val withArgument = Set("-f", "-s", "-w", "--skip-fields", "--skip-chars", "--check-chars")
    @annotation.tailrec
    def operands(rest: List[String], acc: Vector[String]): Vector[String] = rest match {
      case Nil                                        => acc
      case "--" :: tail                               => acc ++ tail
      case o :: _ :: tail if withArgument(o)          => operands(tail, acc)
      case o :: tail if o.startsWith("-") && o != "-" => operands(tail, acc)
      case w :: tail                                  => operands(tail, acc :+ w)
    }
    operands(args.toList, Vector.empty).lift(1)
  }

  /** Does a shell command write the work file?  Read with the audit's own
    * lexer (ShellAudit.lex): a redirection into it (`>`, `>>`, `&>`; not a
    * duplication such as `2>&1`, so a check whose output is redirected is not
    * an edit); a writer among the words, which is `tee` or `truncate` on it,
    * the destination of a copier the audit knows (ShellAudit.writesLast:
    * `cp`, `mv`, `ln`), or an allowed text tool told to write it (`sed -i`,
    * gawk's `-i inplace`, `sort -o`, `uniq`'s output operand); or an
    * interpreter run by a command that names the file's stem.  The audit's
    * other writers (`touch`, `chmod`, `rm`, `mkdir`, `rmdir`) change no
    * content, so they are not edits.  A command the lexer cannot see through
    * counts when it names the stem: the reading must not end the subject's
    * writing too early.
    */
  private[agentbench] def bashWrites(command: String, workFile: Path): Boolean = {
    val file = workFile.getFileName.toString
    val stem = file.stripSuffix(".agda")
    def isWork(w: String): Boolean = w == file || w.endsWith("/" + file)
    if (!command.contains(stem)) false
    else {
      val lexed = ShellAudit.lex(command)
      lexed.opaque.isDefined || {
        val toks       = lexed.toks
        val redirected = toks.zip(toks.drop(1)).exists {
          case (ShellAudit.Op(o), ShellAudit.Word(w, _)) => o.contains(">") && !duplication(o) && isWork(w)
          case _                                         => false
        }
        // The words of each simple command; a redirection's target is not an argument.
        val (simple, _) = toks.foldLeft((Vector(Vector.empty[String]), false)) {
          case ((acc, _), ShellAudit.Op(o)) if separators(o) => (acc :+ Vector.empty, false)
          case ((acc, _), ShellAudit.Op(o))                  => (acc, !duplication(o))
          case ((acc, true), ShellAudit.Word(_, _))          => (acc, false)
          case ((acc, false), ShellAudit.Word(w, _))         => (acc.init :+ (acc.last :+ w), false)
        }
        redirected || simple.exists { ws =>
          val args = ws.drop(1)
          ws.headOption.map(basename).getOrElse("") match {
            case p if interpreters(p)          => true
            case p if ShellAudit.writesLast(p) => args.lastOption.exists(isWork)
            case "tee" | "truncate"            => args.exists(isWork)
            case "sed"                         => sedInPlace(args) && args.exists(isWork)
            case "awk" | "gawk"                => awkInPlace(args) && args.exists(isWork)
            case "sort"                        => sortOutput(args).exists(isWork)
            case "uniq"                        => uniqOutput(args).exists(isWork)
            case _                             => false
          }
        }
      }
    }
  }

  private def resolved(workFile: Path, p: String): Option[Path] =
    Try(Paths.get(p)).toOption.map(q => (if (q.isAbsolute) q else workFile.getParent.resolve(q)).normalize)

  /** Does this call write the work file?  An Edit or Write naming it that the
    * client did not refuse, or a Bash command that writes it.
    */
  def edits(u: ToolUse, result: Option[ToolResult], workFile: Path): Boolean =
    if (editTools(u.name))
      !result.exists(_.isError) &&
        u.str("file_path").orElse(u.str("path")).orElse(u.str("filePath")).flatMap(resolved(workFile, _)).contains(workFile)
    else u.name == Arm.bash && bashWrites(u.str("command").getOrElse(""), workFile)

  /** The reading of one transcript against the original's source and the
    * subject's work file (the header's rules).  Pure.
    */
  def of(t: Transcript, source: OriginalSource, workFile: Path): OriginalReading = {
    val work     = workFile.toAbsolutePath.normalize
    val calls    = t.uses.zipWithIndex
    val lastEdit = t.uses.filter(u => edits(u, t.resultOf(u), work)).lastOption.map(_.record)
    // In the subject's context before it composed its last edit.
    def before(r: ToolResult): Boolean = lastEdit.exists(r.record < _)
    def named(u: ToolUse): Boolean     = !editTools(u.name) && strings(u.input).exists(names(_, source.rel))
    // Text the subject itself put in a call made before `record`.
    def wrote(line: String, record: Int): Boolean =
      t.uses.exists(u => u.record < record && strings(u.input).exists(_.contains(line)))
    val evidence = source.body.filter(long)
    def shows(u: ToolUse, r: ToolResult): Boolean =
      if (source.body.isEmpty) named(u)
      else {
        val lines = if (evidence.nonEmpty) evidence else source.body
        (evidence.nonEmpty || named(u)) && lines.exists(l => r.text.contains(l) && !wrote(l, r.record))
      }
    val answered = calls.flatMap { case (u, i) => t.resultOf(u).map(r => (u, i, r)) }
    val first    = answered.filter { case (u, _, r) => !r.isError && before(r) && shows(u, r) }
                     .minByOption { case (_, i, r) => (r.record, i) }
    val readsOf  = answered.filter { case (u, _, _) => named(u) }
    OriginalReading(
      file         = Some(source.file.toString),
      inView       = Some(first.isDefined),
      how          = first.map { case (u, _, _) => if (named(u)) "read" else "result" },
      at           = first.map(_._2),
      reads        = readsOf.count { case (_, _, r) => !r.isError && before(r) },
      refusedReads = readsOf.count { case (_, _, r) => r.isError }
    )
  }
}

/** ============================================================================
  *  Credentials.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Credentials.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  Keep every credential in the subjects' environment out of a run
  *  directory (issue #237).  A subject inherits the harness's environment,
  *  so the token an endpoint needs is in it, and on an arm with a shell so is
  *  every other secret the operator exported: a subject that runs `env`, or
  *  echoes one variable, writes the value into its transcript, which the
  *  archive commits.  The harness never writes one itself (the protocol
  *  names the credential variables only as `set`), so what remains is what
  *  the subject and its client write: after each subject the harness
  *  replaces every value in the transcript, the client's stderr, and the
  *  final file with `<redacted:NAME>` before anything is judged, and records
  *  the names in `run.json`; when the report is written, it searches the
  *  whole run directory for the values and fails the run, naming the file
  *  and the variable, if one is still there.
  *
  *  Design notes
  *  ------------
  *  - A credential is a variable whose name says so (TOKEN, KEY, SECRET,
  *    PASSWORD, PASSWD, CREDENTIAL, AUTH, HEADERS, in any case), and the
  *    values looked for are its value and each whitespace-separated piece of
  *    it (a header line's token), when at least 16 characters long: a
  *    shorter value is no secret worth the false matches.  So is any
  *    variable whose value is a URL carrying userinfo or a query (a base URL
  *    with a key in it, a proxy with a password): the URL, its userinfo, and
  *    its query are looked for, by the same floor.  Longer values are
  *    replaced first, so a header line goes before the token inside it.
  *  - Each value is looked for in two spellings, as written and as it reads
  *    inside a JSON string (a quote or a backslash in it is escaped there,
  *    and the transcript is JSON), and in its UTF-8 bytes, since the files
  *    are searched byte for byte.
  *  - The values live only in this class, whose rendering names the
  *    variables and never the values, so a log line or a failed test that
  *    prints one prints no secret.
  *  - Files are read as ISO-8859-1, which maps every byte to one character,
  *    so a binary file (an interface file under the work directory) is
  *    searched without a decoding error and written back byte for byte.
  *  - The subject's work directory is not searched: it is its scratch space,
  *    the archive never copies it, and the file it leaves there is searched
  *    as the final file under `subjects/`.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.IO
import java.nio.charset.StandardCharsets.ISO_8859_1
import java.nio.file.{Files, Path}
import scala.jdk.CollectionConverters._

/** Credential values by variable, each held as the ISO-8859-1 reading of
  * its UTF-8 bytes, which is how the files are searched.
  */
final class Credentials private (secrets: Vector[(String, String)]) {

  /** The variables whose values are looked for. */
  def names: Vector[String] = secrets.map(_._1).distinct.sorted

  def isEmpty: Boolean = secrets.isEmpty

  /** The variables whose values occur in `text`. */
  def found(text: String): Vector[String] = secrets.collect { case (n, v) if text.contains(v) => n }.distinct.sorted

  /** `text` with every value replaced by `<redacted:NAME>`. */
  def redact(text: String): String =
    secrets.foldLeft(text) { case (t, (n, v)) => t.replace(v, s"<redacted:$n>") }

  override def toString: String = s"Credentials(${names.mkString(", ")})"
}

object Credentials {

  private val credentialName = "(?i).*(TOKEN|KEY|SECRET|PASSWORD|PASSWD|CREDENTIAL|AUTH|HEADERS).*"
  val minLength: Int         = 16

  /** The secret parts of a URL: the URL itself, its userinfo and the
    * password in it, its query and each value in it; none for a value that
    * is no URL or carries neither.
    */
  private def urlParts(v: String): Vector[String] =
    scala.util.Try(new java.net.URI(v.trim)).toOption.filter(_.getScheme != null).toVector.flatMap { u =>
      val user  = Option(u.getRawUserInfo).toVector
      val query = Option(u.getRawQuery).toVector
      if (user.isEmpty && query.isEmpty) Vector.empty
      else Vector(v.trim) ++ user ++ user.flatMap(_.split(":", 2).drop(1)) ++ query ++
        query.flatMap(_.split("&").toVector.flatMap(_.split("=", 2).drop(1)))
    }

  /** A value as it is written into a JSON string. */
  private def inJson(v: String): String = io.circe.Json.fromString(v).noSpaces.drop(1).dropRight(1)

  /** A value as the files are searched: its UTF-8 bytes, one character each. */
  private def asBytes(v: String): String = new String(v.getBytes(java.nio.charset.StandardCharsets.UTF_8), ISO_8859_1)

  /** The credentials of an environment, by name and value, longest values first. */
  def of(env: Map[String, String]): Credentials =
    new Credentials(env.toVector.flatMap { case (n, v) =>
      val named = if (n.matches(credentialName)) v.trim +: v.split("\\s+").toVector else Vector.empty
      (named ++ urlParts(v)).filter(_.length >= minLength).flatMap(s => Vector(s, inJson(s))).map(asBytes).distinct.map(n -> _)
    }.distinct.sortBy { case (n, v) => (-v.length, n) })

  /** Replace every value in the files that exist, and name the variables replaced. */
  def scrub(creds: Credentials, files: Vector[Path]): IO[Vector[String]] =
    if (creds.isEmpty) IO.pure(Vector.empty)
    else IO.blocking {
      files.filter(Files.isRegularFile(_)).flatMap { f =>
        val text = new String(Files.readAllBytes(f), ISO_8859_1)
        val hits = creds.found(text)
        if (hits.nonEmpty) Files.write(f, creds.redact(text).getBytes(ISO_8859_1))
        hits
      }.distinct.sorted
    }

  /** Every file under `root`, outside `skip`, that still holds a value, with the variables it holds. */
  def leaks(creds: Credentials, root: Path, skip: Path): IO[Vector[(Path, Vector[String])]] =
    if (creds.isEmpty || !Files.isDirectory(root)) IO.pure(Vector.empty)
    else IO.blocking {
      val walk = Files.walk(root)
      try walk.iterator.asScala.toVector
        .filter(p => Files.isRegularFile(p) && !p.startsWith(skip))
        .map(p => p -> creds.found(new String(Files.readAllBytes(p), ISO_8859_1)))
        .filter(_._2.nonEmpty)
      finally walk.close()
    }
}

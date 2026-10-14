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
  *    variable whose value is a URL carrying userinfo, a query, or a fragment
  *    (a base URL with a key in it, a proxy with a password), and the base URL
  *    when a path segment is long enough to be a token: the URL and those
  *    parts are looked for, by the same floor.  Longer values are
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
final class Credentials private (private val secrets: Vector[(String, String)]) {

  /** The variables whose values are looked for. */
  def names: Vector[String] = secrets.map(_._1).distinct.sorted

  def isEmpty: Boolean = secrets.isEmpty

  /** The variables whose values occur in `text`. */
  def found(text: String): Vector[String] = secrets.collect { case (n, v) if text.contains(v) => n }.distinct.sorted

  /** `text` with every value replaced by `<redacted:NAME>`. */
  def redact(text: String): String =
    secrets.foldLeft(text) { case (t, (n, v)) => t.replace(v, s"<redacted:$n>") }

  /** Both sets of values, longest first again. */
  def ++(o: Credentials): Credentials = new Credentials((secrets ++ o.secrets).distinct.sortBy { case (n, v) => (-v.length, n) })

  override def toString: String = s"Credentials(${names.mkString(", ")})"
}

object Credentials {

  private val credentialName = "(?i).*(TOKEN|KEY|SECRET|PASSWORD|PASSWD|CREDENTIAL|AUTH|HEADERS).*"
  val minLength: Int         = 16

  /** The secret parts of a URL: the URL itself, its userinfo and the
    * password in it, its query and each value in it, and its fragment; for
    * the base URL also every path segment long enough to be a token (the
    * segments the endpoint record redacts); none for a value that is no URL
    * or carries none of them.  Path segments are looked for in the base URL
    * alone: in another variable's URL they are ordinary names (a
    * repository's, a directory's) that transcripts are full of.
    */
  private def urlParts(name: String, v: String): Vector[String] =
    scala.util.Try(new java.net.URI(v.trim)).toOption.filter(_.getScheme != null).toVector.flatMap { u =>
      val user  = Option(u.getRawUserInfo).toVector
      val query = Option(u.getRawQuery).toVector
      val frag  = Option(u.getRawFragment).toVector
      val path  = if (name != Endpoint.baseUrlVar) Vector.empty
                  else Option(u.getRawPath).toVector.flatMap(_.split("/").toVector.filter(_.length >= Endpoint.tokenLength))
      val parts = user ++ user.flatMap(_.split(":", 2).drop(1)) ++ query ++
                    query.flatMap(_.split("&").toVector.flatMap(_.split("=", 2).drop(1))) ++ frag ++ path
      if (parts.isEmpty) Vector.empty else v.trim +: parts
    }

  /** A value as it is written into a JSON string. */
  private def inJson(v: String): String = io.circe.Json.fromString(v).noSpaces.drop(1).dropRight(1)

  /** A value as the files are searched: its UTF-8 bytes, one character each. */
  private def asBytes(v: String): String = new String(v.getBytes(java.nio.charset.StandardCharsets.UTF_8), ISO_8859_1)

  /** The credentials of an environment, by name and value, longest values first. */
  def of(env: Map[String, String]): Credentials =
    named(env.toVector.flatMap { case (n, v) =>
      val named = if (n.matches(credentialName)) v.trim +: v.split("\\s+").toVector else Vector.empty
      (named ++ urlParts(n, v)).map(n -> _)
    })

  /** Values under the names they are reported by, in both spellings, at
    * the length floor unless the name is exempt from it, longest first.
    */
  private def named(values: Vector[(String, String)], exempt: Set[String] = Set.empty): Credentials =
    new Credentials(values.flatMap { case (n, v) =>
      Vector(v).filter(s => s.nonEmpty && (s.length >= minLength || exempt(n))).flatMap(s => Vector(s, inJson(s))).map(asBytes).distinct.map(n -> _)
    }.distinct.sortBy { case (n, v) => (-v.length, n) })

  /** The secrets of a Codex login (issue #239), from the text of its
    * `auth.json`, which a Codex subject's own CODEX_HOME links to: the API
    * key and the three tokens, and the account's identity as the ID token
    * carries it (the e-mail address, the user and account ids), which Codex
    * writes into a session's rollout and its info-level log.  Each is
    * reported as `CODEX_LOGIN_<FIELD>`, never by value; the e-mail address
    * is looked for however short it is; a file that does not parse holds
    * nothing to look for.
    */
  def ofCodexLogin(authJson: String): Credentials = {
    val j      = io.circe.parser.parse(authJson).toOption.getOrElse(io.circe.Json.Null)
    val c      = j.hcursor
    val tokens = c.downField("tokens")
    def field(cur: io.circe.ACursor, k: String): Option[String] = cur.get[String](k).toOption.filter(_.trim.nonEmpty)
    val claims = field(tokens, "id_token").toVector.flatMap(t => t.split('.').lift(1).toVector)
      .flatMap(p => scala.util.Try(new String(java.util.Base64.getUrlDecoder.decode(p.padTo(p.length + (4 - p.length % 4) % 4, '=')),
        java.nio.charset.StandardCharsets.UTF_8)).toOption.toVector)
      .flatMap(s => io.circe.parser.parse(s).toOption.toVector)
    val identity = claims.flatMap { cl =>
      val a = cl.hcursor.downField("https://api.openai.com/auth")
      Vector("EMAIL" -> field(cl.hcursor, "email"), "SUBJECT" -> field(cl.hcursor, "sub"),
        "USER_ID" -> field(a, "chatgpt_user_id").orElse(field(a, "user_id")), "ACCOUNT_ID" -> field(a, "chatgpt_account_id"))
    }
    named((Vector("API_KEY" -> field(c, "OPENAI_API_KEY"), "ACCESS_TOKEN" -> field(tokens, "access_token"),
      "REFRESH_TOKEN" -> field(tokens, "refresh_token"), "ID_TOKEN" -> field(tokens, "id_token"),
      "ACCOUNT_ID" -> field(tokens, "account_id")) ++ identity).collect { case (n, Some(v)) => s"CODEX_LOGIN_$n" -> v },
      exempt = Set("CODEX_LOGIN_EMAIL"))
  }

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

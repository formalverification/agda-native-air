/** ============================================================================
  *  TextIO.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/io/TextIO.scala
  *  Package: struxdriver.io
  *
  *  Purpose
  *  -------
  *  The handful of text-file effects every harness needs and none should
  *  reimplement: read a UTF-8 file, write one (creating its directory),
  *  read a classpath resource, parse a JSON file leniently, and digest a
  *  string.  Pure wrappers over java.nio under `IO.blocking`; no policy.
  *
  *  ============================================================================
  */
package struxdriver.io

import cats.effect.IO
import io.circe.Json
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path}

object TextIO {

  def read(p: Path): IO[String] =
    IO.blocking(new String(Files.readAllBytes(p), StandardCharsets.UTF_8))

  /** Write, creating the parent directory when there is one. */
  def write(p: Path, s: String): IO[Unit] =
    IO.blocking {
      Option(p.getParent).foreach(d => Files.createDirectories(d))
      Files.write(p, s.getBytes(StandardCharsets.UTF_8)); ()
    }

  /** A JSON file as a value, or None when it is missing or malformed: the
    * caller decides what an absent record means.
    */
  def readJson(p: Path): IO[Option[Json]] =
    read(p).map(io.circe.parser.parse(_).toOption).handleError(_ => None)

  /** A classpath resource, by its path within the resources root. */
  def resource(name: String): IO[String] =
    IO.blocking {
      val in = Option(getClass.getClassLoader.getResourceAsStream(name))
        .getOrElse(throw new RuntimeException(s"missing classpath resource $name"))
      try new String(in.readAllBytes(), StandardCharsets.UTF_8) finally in.close()
    }

  def sha256(s: String): String = {
    val md = java.security.MessageDigest.getInstance("SHA-256")
    md.digest(s.getBytes(StandardCharsets.UTF_8)).map(b => f"$b%02x").mkString
  }
}

/** ============================================================================
  *  Toml.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Toml.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  The little of TOML a Codex subject's configuration needs (issue #239):
  *  tables of keys whose values are strings, booleans, integers, and arrays
  *  of strings, rendered in a fixed order, so the file a subject is given
  *  and the record of it are byte-for-byte what the harness meant.
  *
  *  Design notes
  *  ------------
  *  - A TOML basic string accepts every escape a JSON string uses (`\"`,
  *    `\\`, `\n`, `\t`, `\uXXXX`) and literal UTF-8 for the rest, so a
  *    string is rendered as circe renders a JSON string.
  *  - A key is bare when it is only letters, digits, `_`, and `-`, and a
  *    quoted string otherwise (a path, a `:special` token).
  *  - Codex reads the file with `--strict-config`, which refuses an unknown
  *    key, so a misspelled switch fails the subject at start instead of
  *    leaving a leak open.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import io.circe.Json

/** One table: its dotted header (empty for the root table) and its entries,
  * each a key and an already rendered value.
  */
final case class TomlTable(header: Vector[String], entries: Vector[(String, String)])

object Toml {

  def str(s: String): String              = Json.fromString(s).noSpaces
  def bool(b: Boolean): String            = b.toString
  def int(n: Int): String                 = n.toString
  def strs(xs: Vector[String]): String    = xs.map(str).mkString("[", ", ", "]")

  def key(k: String): String = if (k.nonEmpty && k.forall(c => c.isLetterOrDigit && c < 128 || c == '_' || c == '-')) k else str(k)

  /** The tables in order, the root first when it has entries, one blank
    * line between tables.
    */
  def render(tables: Vector[TomlTable]): String =
    tables.filter(t => t.header.isEmpty || t.entries.nonEmpty || tables.forall(_ eq t)).map { t =>
      val head  = if (t.header.isEmpty) Vector.empty else Vector(t.header.map(key).mkString("[", ".", "]"))
      (head ++ t.entries.map { case (k, v) => s"${key(k)} = $v" }).mkString("\n")
    }.filter(_.nonEmpty).mkString("", "\n\n", "\n")
}

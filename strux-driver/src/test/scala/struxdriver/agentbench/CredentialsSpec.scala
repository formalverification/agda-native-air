/** ============================================================================
  *  CredentialsSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/CredentialsSpec.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  Pins the credential scrub (issue #237): which variables of the subjects'
  *  environment count as credentials and which of their values are looked
  *  for; that a subject's transcript, stderr, and final file come back with
  *  every value replaced by its variable's name and every other byte as it
  *  was, the logs scrubbed even when keeping the final file fails; that a
  *  value is found in a URL, inside a JSON string, and in its UTF-8 bytes;
  *  and that the search over a run directory finds what is left, outside
  *  the work copies, by name and never by value.  The values here are
  *  stand-ins that no real credential has.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.unsafe.implicits.global
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path}
import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

final class CredentialsSpec extends AnyFunSuite with Matchers {

  private val token  = "sk-test-not-a-credential-237-token"
  private val gh     = "ghp_testNotACredential237xxxxxxxx"
  private val bearer = "bearer-test-not-a-credential-237"
  private val env    = Map(
    "PATH"                     -> "/usr/local/bin:/usr/bin:/bin:/nix/store/long-enough-path",
    "HOME"                     -> "/home/someone-with-a-long-name",
    "ANTHROPIC_AUTH_TOKEN"     -> token,
    "GH_TOKEN"                 -> gh,
    "ANTHROPIC_CUSTOM_HEADERS" -> s"Authorization: Bearer $bearer",
    "SOME_KEY"                 -> "short",
    "ANTHROPIC_BASE_URL"       -> "https://api.moonshot.ai/anthropic")

  private def write(p: Path, s: String): Path = { Files.createDirectories(p.getParent); Files.write(p, s.getBytes(StandardCharsets.UTF_8)) }
  private def read(p: Path): String = new String(Files.readAllBytes(p), StandardCharsets.UTF_8)

  test("a credential is a variable whose name says so, looked for by its value and its pieces of 16 characters or more") {
    val creds = Credentials.of(env)
    creds.names shouldBe Vector("ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_CUSTOM_HEADERS", "GH_TOKEN")    // not PATH, HOME, the base URL, or a short key
    creds.found(s"x $token y") shouldBe Vector("ANTHROPIC_AUTH_TOKEN")
    creds.found(s"the header's token alone: $bearer") shouldBe Vector("ANTHROPIC_CUSTOM_HEADERS")
    creds.found("short /usr/bin https://api.moonshot.ai/anthropic") shouldBe Vector.empty
    creds.toString should not include (token)
    creds.toString should not include (bearer)
    Credentials.of(Map("PATH" -> "/bin")).isEmpty shouldBe true
  }

  test("redaction replaces every value with its variable's name, a whole header line before the token in it") {
    val creds = Credentials.of(env)
    creds.redact(s"""{"text":"$token and $gh"}""") shouldBe """{"text":"<redacted:ANTHROPIC_AUTH_TOKEN> and <redacted:GH_TOKEN>"}"""
    creds.redact(s"Authorization: Bearer $bearer") shouldBe "<redacted:ANTHROPIC_CUSTOM_HEADERS>"
    creds.redact(s"Bearer $bearer") shouldBe "Bearer <redacted:ANTHROPIC_CUSTOM_HEADERS>"
  }

  test("a subject's files come back scrubbed, every other byte unchanged, and the names replaced are returned") {
    val dir        = Files.createTempDirectory("agentbench-scrub")
    val transcript = write(dir.resolve("transcript.jsonl"), s"""{"type":"user","message":{"content":"ANTHROPIC_AUTH_TOKEN=$token"}}\n""")
    val stderr     = write(dir.resolve("stderr.log"), "nothing secret here\n")
    val binary     = dir.resolve("final/M.agdai")
    Files.createDirectories(binary.getParent)
    val bytes      = (0 to 255).map(_.toByte).toArray ++ gh.getBytes(StandardCharsets.US_ASCII) ++ (0 to 255).reverse.map(_.toByte).toArray
    Files.write(binary, bytes)
    val before     = Files.readAllBytes(stderr)
    val replaced   = Credentials.scrub(Credentials.of(env), Vector(transcript, stderr, binary, dir.resolve("absent.log"))).unsafeRunSync()
    replaced shouldBe Vector("ANTHROPIC_AUTH_TOKEN", "GH_TOKEN")
    read(transcript) shouldBe """{"type":"user","message":{"content":"ANTHROPIC_AUTH_TOKEN=<redacted:ANTHROPIC_AUTH_TOKEN>"}}""" + "\n"
    Files.readAllBytes(stderr) shouldBe before
    val scrubbed = Files.readAllBytes(binary)
    scrubbed.take(256) shouldBe bytes.take(256)
    scrubbed.takeRight(256) shouldBe bytes.takeRight(256)
    new String(scrubbed, StandardCharsets.ISO_8859_1) should include ("<redacted:GH_TOKEN>")
    // Nothing to look for, nothing touched.
    Credentials.scrub(Credentials.of(Map.empty), Vector(transcript)).unsafeRunSync() shouldBe Vector.empty
  }

  test("the search over a run directory names every file still holding a value, outside the work copies, by variable") {
    val root = Files.createTempDirectory("agentbench-leaks").resolve("r")
    write(root.resolve("report.json"), "{}")
    write(root.resolve("subjects/x/outcome.json"), s"""{"lastWords":"$token"}""")
    write(root.resolve("work/x/scratch.txt"), token)                         // the subject's own scratch space
    val leaks = Credentials.leaks(Credentials.of(env), root, root.resolve("work")).unsafeRunSync()
    leaks.map { case (f, ns) => root.relativize(f).toString -> ns } shouldBe Vector("subjects/x/outcome.json" -> Vector("ANTHROPIC_AUTH_TOKEN"))
    Credentials.leaks(Credentials.of(Map.empty), root, root.resolve("work")).unsafeRunSync() shouldBe Vector.empty
  }

  test("a value is found inside a URL, inside a JSON string, and in its UTF-8 bytes") {
    val key   = "0123456789abcdef0123"
    val creds = Credentials.of(Map(
      "ANTHROPIC_BASE_URL" -> s"https://proxy.example/anthropic?key=$key",
      "HTTPS_PROXY"        -> "http://someone:a-long-proxy-password@proxy:3128",
      "SOME_TOKEN"         -> """sk-test/with"quote\and-backslash-237""",
      "PGPASSWORD"         -> "pässwört-not-a-credential-237",
      "PLAIN_URL"          -> "http://localhost:11434/no/secret/here"))
    creds.names shouldBe Vector("ANTHROPIC_BASE_URL", "HTTPS_PROXY", "PGPASSWORD", "SOME_TOKEN")   // not a URL with neither userinfo nor query
    creds.redact(s"""{"text":"ANTHROPIC_BASE_URL=https://proxy.example/anthropic?key=$key"}""") shouldBe
      """{"text":"ANTHROPIC_BASE_URL=<redacted:ANTHROPIC_BASE_URL>"}"""
    creds.redact(s"the key alone: $key") shouldBe "the key alone: <redacted:ANTHROPIC_BASE_URL>"
    creds.redact("HTTPS_PROXY=http://someone:a-long-proxy-password@proxy:3128") shouldBe "HTTPS_PROXY=<redacted:HTTPS_PROXY>"
    // As the client writes it into a JSON string: the quote and the
    // backslash escaped.
    creds.redact("""{"content":"SOME_TOKEN=sk-test/with\"quote\\and-backslash-237"}""") shouldBe
      """{"content":"SOME_TOKEN=<redacted:SOME_TOKEN>"}"""
    // In a file, searched byte for byte.
    val dir = Files.createTempDirectory("agentbench-bytes")
    val f   = write(dir.resolve("transcript.jsonl"), "PGPASSWORD=pässwört-not-a-credential-237\n")
    Credentials.scrub(creds, Vector(f)).unsafeRunSync() shouldBe Vector("PGPASSWORD")
    read(f) shouldBe "PGPASSWORD=<redacted:PGPASSWORD>\n"
  }

  test("a subject's logs are scrubbed before its final file is kept, so a copy that fails leaves no value behind") {
    val root    = Files.createTempDirectory("agentbench-keep").resolve("r")
    val subj    = RunLayout(root).subject("x")
    write(subj.transcript, s"""{"type":"user","message":{"content":"$token"}}""" + "\n")
    write(subj.stderr, s"stderr: $gh\n")
    val run     = SubjectRun(Some(0), 10L, killed = false, Some("2026-10-13T00:00:00Z"))
    val missing = root.resolve("work/x/Deleted.agda")                        // a shell subject removed its own file
    val failed  = Run.keep(Credentials.of(env), subj, missing, subj.finalFile("Deleted"), run).attempt.unsafeRunSync()
    failed.isLeft shouldBe true
    read(subj.transcript) should not include (token)
    read(subj.stderr) should not include (gh)
    // And when the file is there, it is kept, scrubbed, and run.json names
    // what was replaced.
    val work = write(root.resolve("work/x/M.agda"), s"-- $token\n")
    val kept = Run.keep(Credentials.of(env), subj, work, subj.finalFile("M"), run).unsafeRunSync()
    kept.redacted shouldBe Vector("ANTHROPIC_AUTH_TOKEN")                    // the logs were clean by then
    read(subj.finalFile("M")) shouldBe "-- <redacted:ANTHROPIC_AUTH_TOKEN>\n"
    read(subj.runRecord) should include ("\"redacted\"")
  }

  test("the record of credentials left in a run directory only grows: a later run that finds none, or other ones, keeps it") {
    val layout = RunLayout(Files.createTempDirectory("agentbench-leakrecord").resolve("r"))
    Files.createDirectories(layout.runRoot)
    AgentBench.recordLeaks(layout, Vector(layout.runRoot.resolve("subjects/x/transcript.jsonl") -> Vector("ANTHROPIC_AUTH_TOKEN"))).unsafeRunSync()
    AgentBench.recordLeaks(layout, Vector(layout.runRoot.resolve("report.json") -> Vector("GH_TOKEN"))).unsafeRunSync()
    val kept = io.circe.parser.parse(read(layout.leaks)).toOption.flatMap(_.asArray).getOrElse(Vector.empty)
    kept.flatMap(_.hcursor.get[String]("file").toOption) shouldBe Vector("subjects/x/transcript.jsonl", "report.json")
    read(layout.leaks) should not include (token)
  }
}

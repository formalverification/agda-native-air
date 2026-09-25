/** ============================================================================
  *  OriginalInViewSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/OriginalInViewSpec.scala
  *
  *  Purpose
  *  -------
  *  Pins the original-in-view reading (issue #188) on a synthetic transcript
  *  in the record shapes TranscriptSpec pins against a captured one
  *  (test/resources/agentbench/transcript-original-synthetic.jsonl): a
  *  `definition_of` answer that names the original's file, a Read of a range
  *  that stops short of the proof, a refused Read, a first edit, a recursive
  *  grep whose answer carries a line of the proof, the last edit, and a full
  *  Read after it.  Variants of the same stream cover the rest of the rules:
  *  the order of records against the order of calls (a result that came back
  *  after the last edit was composed), an edit the client refused, the
  *  subject's own line echoed back, a named read, a Bash command as the last
  *  edit and a redirected check that is not one, a short body, and a body
  *  not found.  Then the parts: the body of a definition in a literate file,
  *  locating the source under the roots, a path naming the file, and a shell
  *  command writing the work file.
  *
  *  Last, the committed archive, where the libraries' sources are on disk
  *  (inside `nix develop .#backend`; cancelled elsewhere, as in CI): every
  *  `original` block the judge wrote is this reading of its transcript, and
  *  the per-arm counts are the ones reported on issue #188, beside the looser
  *  reading's (any successful read of the file is enough), which are the
  *  counts of the script the issue started from.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.unsafe.implicits.global
import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths}
import scala.io.Source

import struxdriver.io.TextIO
import struxdriver.search.Scaffold

final class OriginalInViewSpec extends AnyFunSuite with Matchers {

  private def resource(name: String): String = {
    val src = Source.fromResource(s"agentbench/$name")
    try src.mkString finally src.close()
  }

  private val stream   = resource("transcript-original-synthetic.jsonl")
  private val records  = stream.linesIterator.toVector
  private val workFile = Paths.get("/w/work/x/Foo.agda")
  private val libFile  = "/lib/src/Alg/Basic.lagda.md"
  private val proof    = "foo x y = bar (baz x) y"
  private val source   = OriginalSource(Paths.get(libFile), "Alg/Basic.lagda.md", Vector(proof))

  private def isOf(id: String)(record: String): Boolean =
    record.contains(s""""id":"$id"""") || record.contains(s""""tool_use_id":"$id"""")
  private def useOf(id: String): String    = records.find(r => isOf(id)(r) && r.contains("tool_use\"")).get
  private def resultOf(id: String): String = records.find(r => isOf(id)(r) && r.contains("tool_result")).get

  /** The stream with each named call's use and result replaced by the given records. */
  private def replacing(id: String, use: String, result: String): String =
    records.map(r => if (isOf(id)(r)) (if (r.contains("tool_result")) result else use) else r).mkString("\n")

  private def use(id: String, name: String, input: String): String =
    s"""{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"$id","name":"$name","input":$input}]}}"""
  private def result(id: String, text: String, isError: Boolean = false): String =
    s"""{"type":"user","message":{"role":"user","content":[{"tool_use_id":"$id","type":"tool_result","content":${io.circe.Json.fromString(text).noSpaces},"is_error":$isError}]}}"""

  private def reading(s: String, src: OriginalSource = source): OriginalReading =
    OriginalInView.of(Transcript.parse(s), src, workFile)

  test("the synthetic stream: a grep's answer carried the proof before the last edit, and nothing else showed it") {
    val r = reading(stream)
    r shouldBe OriginalReading(Some(libFile), Some(true), Some("result"), Some(4), reads = 1, refusedReads = 1)
    r.seen shouldBe true
    r.toJson.noSpaces shouldBe s"""{"file":"$libFile","inView":true,"how":"result","at":4,"reads":1,"refusedReads":1}"""
  }

  test("a file name in an answer, a range that stops short of the proof, and a refused read show nothing; a read after the last edit shaped nothing") {
    // Without the grep, the proof reaches the subject only in the full Read
    // (t7), which came after its last edit (t6).
    val r = reading(records.filterNot(isOf("t5")).mkString("\n"))
    r shouldBe OriginalReading(Some(libFile), Some(false), None, None, reads = 1, refusedReads = 1)
    // The looser reading, in which any successful read of the file is enough,
    // would count the range read (t2); the block keeps what it needs.
    (r.seen || r.reads > 0) shouldBe true
    reading(records.filterNot(r => isOf("t5")(r) || isOf("t2")(r)).mkString("\n")).reads shouldBe 0
  }

  test("order is by record, not by call: an answer that came back after the last edit was composed shaped nothing") {
    // The grep (t5) and the last edit (t6) issued in one turn: both calls
    // precede both results, so the edit was written without the grep's answer.
    val parallel = records.filterNot(r => isOf("t5")(r) || isOf("t6")(r)).patch(
      records.indexOf(useOf("t5")), Vector(useOf("t5"), useOf("t6"), resultOf("t5"), resultOf("t6")), 0)
    val t = Transcript.parse(parallel.mkString("\n"))
    t.uses.map(_.id) shouldBe Vector("t1", "t2", "t3", "t4", "t5", "t6", "t7")
    reading(parallel.mkString("\n")).inView shouldBe Some(false)
  }

  test("an edit the client refused changed nothing, so the last edit is the one before it") {
    val refused = replacing("t6", useOf("t6"), result("t6", "String to replace not found in file.", isError = true))
    reading(refused).inView shouldBe Some(false)       // the grep came after t4, the last edit that happened
  }

  test("the subject's own line, echoed back, is not the original shown to it") {
    // A fixture that keeps the original's name: the subject writes the
    // library's line itself (t4), reads its own file back (t5), edits again (t6).
    val wrote  = replacing("t4",
      use("t4", "Edit", s"""{"file_path":"/w/work/x/Foo.agda","old_string":"foo x y = {!!}","new_string":"$proof"}"""),
      result("t4", "The file /w/work/x/Foo.agda has been updated successfully."))
    val echoed = wrote.linesIterator.toVector.map(r =>
      if (isOf("t5")(r)) (if (r.contains("tool_result")) result("t5", s"    20\t$proof") else use("t5", "Read", """{"file_path":"/w/work/x/Foo.agda"}""")) else r)
    reading(echoed.mkString("\n")).inView shouldBe Some(false)
  }

  test("a read whose input names the file and whose answer shows the proof reads `read`") {
    val sed = replacing("t5",
      use("t5", "Bash", s"""{"command":"sed -n '38,45p' $libFile"}"""),
      result("t5", s"foo : A → B → C\n$proof"))
    reading(sed) shouldBe OriginalReading(Some(libFile), Some(true), Some("read"), Some(4), reads = 2, refusedReads = 1)
  }

  test("a Bash command that writes the work file is an edit; a check with its output redirected is not") {
    val sedI = replacing("t6", use("t6", "Bash", """{"command":"sed -i 's/{! bar !}/bar (baz x) y/' Foo.agda"}"""), result("t6", ""))
    reading(sedI).inView shouldBe Some(true)           // the grep (t5) precedes the last edit, now t6
    val check = replacing("t6", use("t6", "Bash", """{"command":"agda --safe -i . /w/work/x/Foo.agda 2>&1 | tail -5"}"""), result("t6", "ok"))
    reading(check).inView shouldBe Some(false)         // the last edit is t4, before the grep
  }

  test("a body with no line longer than twelve characters is looked for only in the answer of a call that named the file") {
    val short = source.copy(body = Vector("foo = refl"))
    val grep  = replacing("t5", use("t5", "Bash", """{"command":"grep -rn refl /lib/src/Alg"}"""), result("t5", "/lib/src/Alg/Basic.lagda.md:41:foo = refl"))
    reading(grep, short).inView shouldBe Some(false)
    val read  = replacing("t5", use("t5", "Read", s"""{"file_path":"$libFile","offset":40,"limit":2}"""), result("t5", "    41\tfoo = refl"))
    reading(read, short) shouldBe OriginalReading(Some(libFile), Some(true), Some("read"), Some(4), reads = 2, refusedReads = 1)
  }

  test("a body not found at all makes any successful read of the file count") {
    reading(stream, source.copy(body = Vector.empty)) shouldBe
      OriginalReading(Some(libFile), Some(true), Some("read"), Some(1), reads = 1, refusedReads = 1)
  }

  test("no successful edit: nothing came before it") {
    val none = records.filterNot(r => isOf("t4")(r) || isOf("t6")(r)).mkString("\n")
    reading(none) shouldBe OriginalReading(Some(libFile), Some(false), None, None, reads = 0, refusedReads = 1)
  }

  // ---------------------------------------------------------------- the parts

  private val literate: String =
    """# Alg.Basic
      |
      |The map foo x y = bar (baz x) y is the one to know.
      |
      |```agda
      |module Alg.Basic where
      |
      |foo : A → B → C
      |foo x y = bar (baz x) y
      |foo′ : A
      |foo′ = foo a b
      |
      |f : ℕ → ℕ
      |f zero    = zero
      |f (suc n) = n
      |g = f
      |
      |module _ where
      |  kercon : Con 𝑨
      |  kercon =  kerRel _≈_ h ,
      |            mkcon (λ x → cong hmap x)
      |    where
      |    helper = x
      |  other = y
      |```
      |""".stripMargin

  test("body: the definition's clauses, not its signature, a prose line, a primed namesake, or what follows") {
    OriginalInView.body(literate, "foo") shouldBe Vector("foo x y = bar (baz x) y")
    OriginalInView.body(literate, "f") shouldBe Vector("f zero    = zero", "f (suc n) = n")
    OriginalInView.body(literate, "kercon") shouldBe Vector("kercon =  kerRel _≈_ h ,", "mkcon (λ x → cong hmap x)", "where", "helper = x")
    OriginalInView.body(literate, "absent") shouldBe Vector.empty
    OriginalInView.body(literate, "foo′") shouldBe Vector("foo′ = foo a b")
  }

  test("locate: the module under the first root that holds it; nothing for an untagged row or a module no root holds") {
    val base  = Files.createTempDirectory("original-in-view-")
    val empty = Files.createDirectories(base.resolve("stdlib/src"))
    val lib   = Files.createDirectories(base.resolve("alg/src"))
    Files.createDirectories(lib.resolve("Alg"))
    Files.write(lib.resolve("Alg/Basic.lagda.md"), literate.getBytes(StandardCharsets.UTF_8))
    val tagged = Gates.originalOf("Alg.Basic", "foo′", Vector("restates:Alg.Basic.foo"))
    tagged.tagged shouldBe true
    OriginalInView.locate(tagged, Vector(empty, lib)).unsafeRunSync() shouldBe
      Some(OriginalSource(lib.resolve("Alg/Basic.lagda.md").toAbsolutePath.normalize, "Alg/Basic.lagda.md", Vector(proof)))
    val untagged = Gates.originalOf("Alg.Basic", "foo′", Vector.empty)
    untagged.tagged shouldBe false
    OriginalInView.locate(untagged, Vector(lib)).unsafeRunSync() shouldBe None
    OriginalInView.locate(Gates.originalOf("Alg.Other", "foo′", Vector("restates:Alg.Other.foo")), Vector(empty, lib)).unsafeRunSync() shouldBe None
  }

  test("a path names the file only as a path of its own") {
    val rel = "Alg/Basic.lagda.md"
    OriginalInView.names(libFile, rel) shouldBe true
    OriginalInView.names("sed -n '38,45p' Alg/Basic.lagda.md", rel) shouldBe true
    OriginalInView.names("cat \"/lib/src/Alg/Basic.lagda.md\" | head", rel) shouldBe true
    OriginalInView.names("/lib/src/XAlg/Basic.lagda.md", rel) shouldBe false
    OriginalInView.names("/lib/src/Alg/Basic.lagda.mdx", rel) shouldBe false
    OriginalInView.names("/lib/_build/Alg/Basic.agdai", "Alg/Basic.agda") shouldBe false
    OriginalInView.names("/lib/src/Alg/Basic.agda:41", "Alg/Basic.agda") shouldBe true
  }

  test("a shell command writes the work file when it redirects into it, runs a writer or an interpreter on it, or cannot be read") {
    val w = workFile
    Vector(
      "sed -i 's/{!!}/refl/' Foo.agda",
      "sed -Ei 's/a/b/' /w/work/x/Foo.agda",
      "cat > Foo.agda <<'EOF'\nmodule Foo where\nEOF",
      "printf 'x' >> ./Foo.agda",
      "cp /w/work/x/draft.txt Foo.agda",
      "tee Foo.agda < draft.txt",
      "python3 fix.py Foo.agda",
      "echo $(cat Foo.agda)"
    ).foreach(c => withClue(c)(OriginalInView.bashWrites(c, w) shouldBe true))
    Vector(
      "agda --safe -i . /w/work/x/Foo.agda 2>&1 | tail -5",
      "grep -n foo Foo.agda > /dev/null",
      "cat Foo.agda",
      "sed -n '1,5p' Foo.agda",
      "cp Foo.agda /w/work/x/backup.agda",
      "sed -i 's/a/b/' Other.agda"
    ).foreach(c => withClue(c)(OriginalInView.bashWrites(c, w) shouldBe false))
  }

  // ----------------------------------------------------------- the archive

  /** The arms with agda-algebras rows, and the counts of solves with the
    * original in view: this reading's, and the looser one's.
    */
  private val arms: Vector[(String, Int, Int)] = Vector(
    ("agent-sonnet5-1", 0, 0), ("agent-opus5-1", 0, 0), ("agent-opus5-2", 0, 0),
    ("arm162-shell-1", 15, 16), ("arm162-mcp-1", 4, 5), ("arm162-both-1", 16, 16),
    ("arm184-mcp-1", 3, 5), ("arm184-both-1", 14, 15))

  test("the committed archive: every original block is this reading of its transcript, and the counts per arm are the issue's") {
    val root     = Paths.get("..").toAbsolutePath.normalize
    val registry = sys.env.get("AGDA_DIR").map(d => Paths.get(d).resolve("libraries"))
    assume(registry.exists(Files.isRegularFile(_)), "AGDA_DIR not set: the libraries' sources are read through its registry (nix develop .#backend)")
    val libraryRoots = Extractor.includesFromRegistry(registry.get).unsafeRunSync()
    val entries      = Scaffold.readIndex(root.resolve("data/benchmarks/benchmark-index.jsonl"), None).unsafeRunSync()
    val tagged       = entries.filter(e => Gates.originalOf(e.module, e.hole, e.tags).tagged)
    tagged.size shouldBe 21
    arms.foreach { case (arm, expected, looser) =>
      val run = root.resolve(s"reports/agent-bench/$arm")
      assume(Files.isDirectory(run), s"$run is not in this checkout")
      val report = TextIO.readJson(run.resolve("report.json")).unsafeRunSync().get
      val solved = report.hcursor.downField("outcomes").as[Vector[io.circe.Json]].toOption.get
        .map(o => o.hcursor.get[String]("benchmarkId").toOption.get -> o.hcursor.get[Boolean]("solved").toOption.get).toMap
      val readings = tagged.map { e =>
        val subj   = run.resolve(s"subjects/${e.id}")
        val t      = Transcript.parse(new String(Files.readAllBytes(subj.resolve("transcript.jsonl")), StandardCharsets.UTF_8))
        val roots  = TextIO.readJson(subj.resolve("subject.json")).unsafeRunSync().flatMap(SubjectRecord.fromJson).map(_.roots)
                       .getOrElse(ShellRoots(TextIO.readJson(subj.resolve("mcp.json")).unsafeRunSync().flatMap(Audit.workDirOf).get, Vector.empty, Vector.empty))
        val r      = Outcomes.originalReading(e, t, roots, libraryRoots).unsafeRunSync().get
        withClue(s"$arm ${e.id}: ") {
          r.inView should not be None
          TextIO.readJson(subj.resolve("outcome.json")).unsafeRunSync().get.hcursor.downField("original").focus
            .filterNot(_.isNull).foreach(archived => archived shouldBe r.toJson)
        }
        (e.id, r)
      }
      withClue(s"$arm: ") {
        readings.count { case (id, r) => solved(id) && r.seen } shouldBe expected
        readings.count { case (id, r) => solved(id) && (r.seen || r.reads > 0) } shouldBe looser
      }
    }
  }
}

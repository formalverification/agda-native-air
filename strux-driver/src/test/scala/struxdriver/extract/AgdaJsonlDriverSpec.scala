/**
 * Unit tests for AgdaJsonlDriver's source resolution and coverage summary.
 *
 * File: strux-driver/src/test/scala/struxdriver/extract/AgdaJsonlDriverSpec.scala
 * Package: struxdriver.extract
 *
 * Purpose
 * -------
 * Two pieces of the library-scale extraction path (issue #84).
 *
 * Source resolution.  A module name does not determine its file extension.
 * Agda 2.8.0 accepts a plain `.agda` file and six literate flavours, and
 * libraries mix them: agda-algebras is 375 `.lagda.md` files against 2 plain
 * `.agda`.  Before #84 the driver resolved only `<module>.agda`, so extracting
 * that library reported every module as "missing input file".  These tests pin
 * the contract: the candidate list is pure, ordered, and covers exactly the
 * extensions the pinned Agda accepts; resolution against a real (temporary)
 * directory finds a literate module; a module with no source file resolves to
 * nothing, so the driver reports it rather than shelling out to a doomed
 * `agda-json` call.
 *
 * Coverage summary.  `RunSummary` is what a dataset card quotes, so the
 * arithmetic has to hold: succeeded + failed = attempted, resumed modules
 * count as succeeded, and an empty run summarizes to zeros rather than to
 * something undefined.
 *
 * Design notes
 * ------------
 * No Agda and no `agda-json` are needed: everything here is either pure or a
 * filesystem probe under a temp directory, so the suite runs anywhere.
 */

package struxdriver.extract

import org.scalatest.freespec.AnyFreeSpec
import org.scalatest.matchers.should.Matchers

import cats.effect.unsafe.implicits.global

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path}

final class AgdaJsonlDriverSpec extends AnyFreeSpec with Matchers {

  /** Create `srcDir/<relative path>` with a one-line body, parents included. */
  private def touch(srcDir: Path, rel: String): Path = {
    val p = srcDir.resolve(rel)
    Files.createDirectories(p.getParent)
    Files.write(p, "-- probe\n".getBytes(StandardCharsets.UTF_8))
    p
  }

  private def withTempSrcDir[A](body: Path => A): A = {
    val dir = Files.createTempDirectory("agda-jsonl-driver-")
    try body(dir)
    finally {
      // Depth-first delete; the tree is a handful of probe files.
      Files.walk(dir).sorted(java.util.Comparator.reverseOrder[Path]())
        .forEach(p => Files.deleteIfExists(p))
    }
  }

  "agdaSourceExtensions" - {

    "covers exactly the source extensions the pinned Agda accepts" in {
      // Also exactly agda-mcp's file-flavour contract (Gate.everythingNames):
      // the two components must agree on what an Agda source file is.
      AgdaJsonlDriver.agdaSourceExtensions.toSet shouldBe Set(
        ".agda", ".lagda", ".lagda.md", ".lagda.rst",
        ".lagda.tex", ".lagda.org", ".lagda.typ", ".lagda.tree"
      )
    }

    "lists no extension twice" in {
      val exts = AgdaJsonlDriver.agdaSourceExtensions
      exts.distinct.size shouldBe exts.size
    }

    "tries plain .agda first and literate Markdown second" in {
      AgdaJsonlDriver.agdaSourceExtensions.take(2) shouldBe Vector(".agda", ".lagda.md")
    }

    "is not fooled into treating .lagda.html as Agda source" in {
      AgdaJsonlDriver.agdaSourceExtensions should not contain ".lagda.html"
    }
  }

  "moduleInputCandidates" - {

    "turns a dotted module name into a nested path, once per extension" in {
      val srcDir = java.nio.file.Paths.get("/tmp/src")
      val cands  = AgdaJsonlDriver.moduleInputCandidates(srcDir, "Overture.Signatures")

      cands.size shouldBe AgdaJsonlDriver.agdaSourceExtensions.size
      cands.map(_.toString) should contain ("/tmp/src/Overture/Signatures.agda")
      cands.map(_.toString) should contain ("/tmp/src/Overture/Signatures.lagda.md")
    }

    "handles a top-level module (no dots)" in {
      val srcDir = java.nio.file.Paths.get("/tmp/src")
      AgdaJsonlDriver.moduleInputCandidates(srcDir, "Everything").head.toString shouldBe
        "/tmp/src/Everything.agda"
    }
  }

  "nominalModuleInput" - {

    "is the plain .agda path, for diagnostics" in {
      val srcDir = java.nio.file.Paths.get("/tmp/src")
      AgdaJsonlDriver.nominalModuleInput(srcDir, "Base.Algebras.Basic").toString shouldBe
        "/tmp/src/Base/Algebras/Basic.agda"
    }
  }

  "runOne on the resume path" - {

    // A row that JsonlValidate accepts as a Full row, so an existing output
    // counts as valid and resume takes over before any backend runs.
    val validRow =
      """{"file":"X","module":"M","name":"f","qname":"M.f","type":"A","kind":"definition","astSize":1}"""

    /** A Config whose backend path does not exist: if resume fails to
      * short-circuit, the run fails loudly instead of quietly passing. */
    def resumeConfig(src: Path, out: Path): AgdaJsonlDriver.Config =
      AgdaJsonlDriver.Config(
        projectRoot = src,
        agdaDir     = src,
        srcDir      = src,
        modulesFile = src.resolve("modules.txt"),
        outDir      = out,
        agdaJsonBin = src.resolve("no-such-agda-json"),
        parallelism = 1,
        resume      = true,
        runner      = AgdaJsonlDriver.Runner.Local,
        sparkMaster = "local[1]",
        failOnError = false
      )

    def seedOutput(out: Path, mod: String): Unit = {
      val jsonl = out.resolve("jsonl").resolve(mod.replace('.', '/') + ".jsonl")
      Files.createDirectories(jsonl.getParent)
      Files.write(jsonl, (validRow + "\n").getBytes(StandardCharsets.UTF_8))
    }

    "reports the literate source it was extracted from, not the nominal .agda" in
      withTempSrcDir { src =>
        val out = Files.createTempDirectory("agda-jsonl-out-")
        val expected = touch(src, "Overture/Signatures.lagda.md")
        seedOutput(out, "Overture.Signatures")

        val run = AgdaJsonlDriver
          .runOne(resumeConfig(src, out), "Overture.Signatures")
          .unsafeRunSync()

        run.skipped shouldBe true
        run.ok shouldBe true
        run.rows shouldBe 1L
        // The defect this pins: `inputFile` used to be `.../Signatures.agda`,
        // a file that does not exist, for every literate module resume served.
        run.inputFile shouldBe expected.toString
      }

    "reports a plain .agda source unchanged" in withTempSrcDir { src =>
      val out = Files.createTempDirectory("agda-jsonl-out-")
      val expected = touch(src, "Everything.agda")
      seedOutput(out, "Everything")

      val run = AgdaJsonlDriver.runOne(resumeConfig(src, out), "Everything").unsafeRunSync()

      run.skipped shouldBe true
      run.inputFile shouldBe expected.toString
    }

    "falls back to the nominal path when a valid output outlives its source" in
      withTempSrcDir { src =>
        val out = Files.createTempDirectory("agda-jsonl-out-")
        seedOutput(out, "Gone")

        val run = AgdaJsonlDriver.runOne(resumeConfig(src, out), "Gone").unsafeRunSync()

        run.skipped shouldBe true
        run.inputFile shouldBe src.resolve("Gone.agda").toString
      }

    "with no output to resume from, and no source, reports every candidate" in
      withTempSrcDir { src =>
        val out = Files.createTempDirectory("agda-jsonl-out-")

        val run = AgdaJsonlDriver.runOne(resumeConfig(src, out), "Absent").unsafeRunSync()

        run.ok shouldBe false
        run.skipped shouldBe false
        run.validateErrors.mkString should include ("Absent.lagda.md")
        run.validateErrors.mkString should include ("missing input file")
      }
  }

  "RunSummary.of" - {

    /** A ModuleRun with just the fields the summary reads. */
    def run(mod: String, ok: Boolean, skipped: Boolean, rows: Long): AgdaJsonlDriver.ModuleRun =
      AgdaJsonlDriver.ModuleRun(
        module         = mod,
        inputFile      = s"/src/$mod.lagda.md",
        outputFile     = s"/out/jsonl/$mod.jsonl",
        logFile        = s"/out/logs/$mod.log",
        skipped        = skipped,
        ok             = ok,
        exitCode       = if (skipped) None else Some(if (ok) 0 else 1),
        seconds        = 1.0,
        rows           = rows,
        validateOk     = ok,
        validateErrors = if (ok) Vector.empty else Vector("exit_code=1")
      )

    "accounts for every module attempted" in {
      val results = Vector(
        run("A", ok = true,  skipped = false, rows = 10),
        run("B", ok = true,  skipped = true,  rows = 5),
        run("C", ok = false, skipped = false, rows = 0)
      )
      val s = AgdaJsonlDriver.RunSummary.of(results)

      s.attempted shouldBe 3
      s.succeeded shouldBe 2
      s.failed shouldBe 1
      s.succeeded + s.failed shouldBe s.attempted
    }

    "counts resumed modules as succeeded and as skipped" in {
      val results = Vector(run("A", ok = true, skipped = true, rows = 7))
      val s = AgdaJsonlDriver.RunSummary.of(results)

      s.succeeded shouldBe 1
      s.skipped shouldBe 1
      s.failed shouldBe 0
    }

    "totals the rows written" in {
      val results = Vector(
        run("A", ok = true,  skipped = false, rows = 10),
        run("B", ok = false, skipped = false, rows = 0),
        run("C", ok = true,  skipped = true,  rows = 32)
      )
      AgdaJsonlDriver.RunSummary.of(results).rows shouldBe 42L
    }

    "is empty, not undefined, for an empty run" in {
      val s = AgdaJsonlDriver.RunSummary.of(Vector.empty)
      s shouldBe AgdaJsonlDriver.RunSummary(0, 0, 0, 0, 0L)
    }
  }

  "ModuleRun JSON" - {

    /** A failed run: the case whose serialization the manifest depends on. */
    val failed = AgdaJsonlDriver.ModuleRun(
      module         = "Setoid.Categories.Algebra",
      inputFile      = "/src/Setoid/Categories/Algebra.lagda.md",
      outputFile     = "/out/jsonl/Setoid/Categories/Algebra.jsonl",
      logFile        = "/out/logs/Setoid/Categories/Algebra.log",
      skipped        = false,
      ok             = false,
      exitCode       = Some(42),
      seconds        = 4.18,
      rows           = 0L,
      validateOk     = false,
      validateErrors = Vector("exit_code=42")
    )

    "writes validateErrors as a flat array of strings" in {
      val json = ujson.read(upickle.default.write(failed))
      json("validateErrors") shouldBe ujson.Arr(ujson.Str("exit_code=42"))
      // The uPickle varargs overload would nest it; the manifest a dataset
      // card reads must not need unwrapping.
      json("validateErrors").arr.map(_.str) shouldBe Seq("exit_code=42")
    }

    "writes an empty validateErrors as an empty array" in {
      val ok   = failed.copy(ok = true, exitCode = Some(0), validateErrors = Vector.empty)
      val json = ujson.read(upickle.default.write(ok))
      json("validateErrors").arr shouldBe empty
    }

    "omits exitCode when there is none (a resumed module)" in {
      val resumed = failed.copy(skipped = true, ok = true, exitCode = None)
      val json    = ujson.read(upickle.default.write(resumed))
      json.obj.contains("exitCode") shouldBe false
    }

    "round-trips through its own reader" in {
      val back = upickle.default.read[AgdaJsonlDriver.ModuleRun](
        upickle.default.write(failed)
      )
      back shouldBe failed
    }
  }

  "resolveModuleInput" - {

    "finds a literate Markdown module (the agda-algebras case)" in withTempSrcDir { src =>
      val expected = touch(src, "Overture/Signatures.lagda.md")

      AgdaJsonlDriver.resolveModuleInput(src, "Overture.Signatures").unsafeRunSync() shouldBe
        Some(expected)
    }

    "finds a plain .agda module" in withTempSrcDir { src =>
      val expected = touch(src, "Everything.agda")

      AgdaJsonlDriver.resolveModuleInput(src, "Everything").unsafeRunSync() shouldBe
        Some(expected)
    }

    "finds each of the other literate flavours" in withTempSrcDir { src =>
      val flavours =
        Seq(".lagda", ".lagda.rst", ".lagda.tex", ".lagda.org", ".lagda.typ", ".lagda.tree")

      flavours.zipWithIndex.foreach { case (ext, i) =>
        val mod      = s"Flavour.M$i"
        val expected = touch(src, s"Flavour/M$i$ext")
        AgdaJsonlDriver.resolveModuleInput(src, mod).unsafeRunSync() shouldBe Some(expected)
      }
    }

    "prefers plain .agda when a module somehow has two source files" in withTempSrcDir { src =>
      val plain = touch(src, "Ambiguous.agda")
      val _     = touch(src, "Ambiguous.lagda.md")

      AgdaJsonlDriver.resolveModuleInput(src, "Ambiguous").unsafeRunSync() shouldBe Some(plain)
    }

    "returns None when the module has no source file at all" in withTempSrcDir { src =>
      AgdaJsonlDriver.resolveModuleInput(src, "Not.There").unsafeRunSync() shouldBe None
    }

    "does not confuse a directory for a module source" in withTempSrcDir { src =>
      // `Overture/` exists as a directory; `Overture` as a module does not.
      touch(src, "Overture/Signatures.lagda.md")

      AgdaJsonlDriver.resolveModuleInput(src, "Overture").unsafeRunSync() shouldBe None
    }
  }
}

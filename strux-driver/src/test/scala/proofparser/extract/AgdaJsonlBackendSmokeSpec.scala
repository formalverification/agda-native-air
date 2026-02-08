/**
 * Integration smoke tests for the Haskell `agda-json` backend.
 *
 * File: proof-parser/src/test/scala/proofparser/extract/AgdaJsonlBackendSmokeSpec.scala
 *
 * What this test covers
 * ---------------------
 * This suite checks the "contract" between:
 *
 *   Scala orchestration code  <-->  Haskell `agda-json` backend  <-->  JSONL validator
 *
 * Specifically, it verifies that:
 *
 *   1) The backend can be invoked successfully (exit code 0) when the environment
 *      is correctly configured (AGDA_DIR + AGDA_JSON_BIN).
 *   2) The backend produces an output file at the requested location.
 *   3) JsonlValidate accepts valid backend output.
 *   4) Empty output is NOT an error when the input module has no extractable defs:
 *        - output exists
 *        - output may be empty
 *        - validator returns ok=true, rows=0
 *
 * How to Run
 * ----------
 * Run these tests inside pinned Nix dev shell so that:
 *
 *   - AGDA_DIR points at the pinned Agda config (libraries/defaults)
 *   - AGDA_JSON_BIN points at the correct `agda-json` executable
 *
 * If these variables are missing, the tests will be skipped (cancelled) rather
 * than failing.
 */
package proofparser.extract

import org.scalatest.freespec.AnyFreeSpec
import org.scalatest.matchers.should.Matchers

import cats.effect.IO
import cats.effect.unsafe.implicits.global

import java.nio.file.{Files, Path, Paths}

object AgdaJsonlBackendSmokeSpec {
  private final case class BackendEnv(repoRoot: Path, agdaDir: Path, agdaJsonBin: Path)
}

final class AgdaJsonlBackendSmokeSpec extends AnyFreeSpec with Matchers {
  import AgdaJsonlBackendSmokeSpec.BackendEnv

  // -------- helpers --------

  private def repoRootFromCwd(): Path = {
    // Tests typically run with cwd = proof-parser (sbt base dir).
    val cwd = Paths.get(".").toAbsolutePath.normalize()
    if (cwd.getFileName != null && cwd.getFileName.toString == "proof-parser") cwd.getParent
    else cwd
  }

  private def envOrCancel(name: String): String =
    sys.env.get(name) match {
      case Some(v) if v.trim.nonEmpty => v.trim
      case _ =>
        // ScalaTest "cancel" marks the test as skipped.
        org.scalatest.Assertions.cancel(
          s"Skipping backend smoke test: missing required env var $name. " +
          s"Run inside nix develop / pinned shell."
        )
    }
        // ScalaTest "cancel" marks the test as skipped.

  private def requireFile(p: Path, label: String): Unit =
    if (!Files.exists(p)) fail(s"$label does not exist: $p")

  private def backendEnv(): BackendEnv = {
    val repoRoot   = repoRootFromCwd()
    val agdaDir    = Paths.get(envOrCancel("AGDA_DIR")).toAbsolutePath.normalize()
    val agdaJson   = Paths.get(envOrCancel("AGDA_JSON_BIN")).toAbsolutePath.normalize()

    requireFile(agdaDir, "AGDA_DIR")
    requireFile(agdaJson, "AGDA_JSON_BIN")
    BackendEnv(repoRoot, agdaDir, agdaJson)
  }

  private def runBackend(
    benv: BackendEnv,
    input: Path,
    out: Path,
    log: Path,
    includeDir: Path
  ): IO[(Proc.ExecResult, JsonlValidate.Result)] = {
    val cmd = Seq(
      benv.agdaJsonBin.toString,
      "--input",  input.toString,
      "--output", out.toString,
      "--include", includeDir.toString
    )

    val env = Map("AGDA_DIR" -> benv.agdaDir.toString)

    for {
      exec <- Proc.runLogged(cmd, cwd = benv.repoRoot, env = env, logFile = log)
      _    <- IO.raiseWhen(exec.exitCode != 0)(
                new RuntimeException(s"agda-json failed (exit=${exec.exitCode}). Log: $log")
              )
      v    <- JsonlValidate.validateFile(out)
    } yield (exec, v)
  }

  private def fixture(repoRoot: Path, fileName: String): Path =
    // repoRoot.resolve("agda-backend-jsonl").resolve("test").resolve("resources").resolve(fileName)
    repoRoot.resolve("data").resolve("agda").resolve(fileName)

  // -------- tests --------

  "agda-json backend smoke (no Spark)" - {

    "Example.agda: produces non-empty JSONL and validates" in {
      val benv = backendEnv()
      val repoRoot = benv.repoRoot

      val example = fixture(repoRoot, "Example.agda")
      requireFile(example, "Example fixture")

      val tmp = Files.createTempDirectory("agda-jsonl-backend-smoke-")
      val out = tmp.resolve("Example.jsonl")
      val log = tmp.resolve("Example.log")
      val inc = example.getParent

      val (_, v) = runBackend(benv, example, out, log, inc).unsafeRunSync()

      Files.exists(out) shouldBe true
      v.ok shouldBe true
      v.rows should be > 0L
      v.errors shouldBe Vector.empty
    }

    "Empty.agda: produces empty JSONL but still validates (rows=0)" in {
      val benv = backendEnv()
      val repoRoot = benv.repoRoot

      val empty = fixture(repoRoot, "Empty.agda")
      requireFile(empty, "Empty fixture")

      val tmp = Files.createTempDirectory("agda-jsonl-backend-smoke-")
      val out = tmp.resolve("Empty.jsonl")
      val log = tmp.resolve("Empty.log")
      val inc = empty.getParent

      val (_, v) = runBackend(benv, empty, out, log, inc).unsafeRunSync()

      Files.exists(out) shouldBe true
      v.ok shouldBe true
      v.rows shouldBe 0L
      v.errors shouldBe Vector.empty

      // Optional extra guard: output should be actually empty (or only whitespace).
      val bytes = Files.readAllBytes(out)
      val isAllWs = bytes.forall(b => b == '\n' || b == '\r' || b == '\t' || b == ' ')
      (bytes.isEmpty || isAllWs) shouldBe true
    }
  }
}

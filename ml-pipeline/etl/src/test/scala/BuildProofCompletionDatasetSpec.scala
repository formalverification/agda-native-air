/**
 * BuildProofCompletionDatasetSpec.scala
 *
 * Minimal regression tests for the v0 dataset builder.
 *
 * NOTE: This assumes ScalaTest is already in the etl test dependencies.
 * If your project uses MUnit instead, the assertions translate 1:1.
 */
package etl

import com.fasterxml.jackson.databind.ObjectMapper

import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path}

import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

final class BuildProofCompletionDatasetSpec extends AnyFunSuite with Matchers {

  private val mapper = new ObjectMapper()

  private def tmpFile(prefix: String, suffix: String): Path =
    Files.createTempFile(prefix, suffix)

  private def writeUtf8(p: Path, s: String): Unit =
    Files.write(p, s.getBytes(StandardCharsets.UTF_8))

  private def readLines(p: Path): Vector[String] =
    scala.io.Source.fromFile(p.toFile)(scala.io.Codec.UTF8).getLines().toVector

  test("resolves @0 to innermost binder (de Bruijn direction)") {
    // bar : {α}{A} → A → A
    // body="@0" should resolve to the anonymous explicit binder (innermost),
    // which v0 names x0.
    val in = tmpFile("proof-completion-in", ".jsonl")
    val out = tmpFile("proof-completion-out", ".jsonl")

    val row =
      """{"file":"NoetherLike.agda","prettyQname":"NoetherLike.Nested.bar","type":"{α : Level} {A : Set α} → A → A","typeAstVersion":"0.3-v0","typeAst":{"sort":{"tag":"Inf"},"tag":"Type","term":{"binder":{"hiding":"implicit","nameHint":"α"},"cod":{"sort":{"tag":"Inf"},"tag":"Type","term":{"binder":{"hiding":"implicit","nameHint":"A"},"cod":{"sort":{"tag":"Inf"},"tag":"Type","term":{"binder":{"hiding":"explicit","nameHint":null},"cod":{"sort":{"tag":"Inf"},"tag":"Type","term":{"elims":[],"ix":0,"tag":"Var"}},"dom":{"sort":{"tag":"Inf"},"tag":"Type","term":{"elims":[],"ix":0,"tag":"Var"}},"tag":"Pi"}},"dom":{"sort":{"tag":"Inf"},"tag":"Type","term":{"sort":{"level":{"max":0,"plus":[{"atom":{"elims":[],"ix":0,"tag":"Var"},"k":0}],"tag":"Level"},"tag":"Set"},"tag":"Sort"}},"tag":"Pi"}},"dom":{"sort":{"tag":"Inf"},"tag":"Type","term":{"elims":[],"qname":"Agda.Primitive.Level","tag":"Def"}},"tag":"Pi"}},"body":"@0","hasBody":true}"""

    writeUtf8(in, row + "\n")

    BuildProofCompletionDataset.main(Array(
      "--in", in.toAbsolutePath.toString,
      "--out", out.toAbsolutePath.toString,
      "--limit", "10"
    ))

    val lines = readLines(out)
    lines.size shouldBe 1
    val n = mapper.readTree(lines.head)

    n.get("targetRaw").asText() shouldBe "@0"
    n.get("target").asText() shouldBe "x0"
    n.get("targetResolver").asText() shouldBe "atIndex"
    n.get("targetResolved").asBoolean() shouldBe true
    n.get("targetHadAnonModule").asBoolean() shouldBe false
    n.get("targetHead").asText() shouldBe "@0"
  }

  test("normalizes anonymous-module segments '_' in dotted identifiers") {
    val in = tmpFile("proof-completion-in2", ".jsonl")
    val out = tmpFile("proof-completion-out2", ".jsonl")

    val row =
      """{"file":"NoetherLike.agda","prettyQname":"NoetherLike.FirstHomTheorem|Set","type":"{α : Level} {A : Set α} → A → A","typeAstVersion":"0.3-v0","typeAst":{"sort":{"tag":"Inf"},"tag":"Type","term":{"binder":{"hiding":"implicit","nameHint":"α"},"cod":{"sort":{"tag":"Inf"},"tag":"Type","term":{"binder":{"hiding":"implicit","nameHint":"A"},"cod":{"sort":{"tag":"Inf"},"tag":"Type","term":{"binder":{"hiding":"explicit","nameHint":null},"cod":{"sort":{"tag":"Inf"},"tag":"Type","term":{"elims":[],"ix":0,"tag":"Var"}},"dom":{"sort":{"tag":"Inf"},"tag":"Type","term":{"elims":[],"ix":0,"tag":"Var"}},"tag":"Pi"}},"dom":{"sort":{"tag":"Inf"},"tag":"Type","term":{"sort":{"level":{"max":0,"plus":[{"atom":{"elims":[],"ix":0,"tag":"Var"},"k":0}],"tag":"Level"},"tag":"Set"},"tag":"Sort"}},"tag":"Pi"}},"dom":{"sort":{"tag":"Inf"},"tag":"Type","term":{"elims":[],"qname":"Agda.Primitive.Level","tag":"Def"}},"tag":"Pi"}},"body":"NoetherLike._.secId","hasBody":true}"""

    writeUtf8(in, row + "\n")

    BuildProofCompletionDataset.main(Array(
      "--in", in.toAbsolutePath.toString,
      "--out", out.toAbsolutePath.toString,
      "--limit", "10"
    ))

    val lines = readLines(out)
    lines.size shouldBe 1
    val n = mapper.readTree(lines.head)

    n.get("targetRaw").asText() shouldBe "NoetherLike._.secId"
    n.get("target").asText() shouldBe "NoetherLike.secId"
    n.get("targetResolver").asText() shouldBe "anonModuleNormalize"
    n.get("targetResolved").asBoolean() shouldBe false
    n.get("targetHadAnonModule").asBoolean() shouldBe true
  }

  test("computes targetHead from a short application without changing targetRaw") {
    val in = tmpFile("proof-completion-in3", ".jsonl")
    val out = tmpFile("proof-completion-out3", ".jsonl")

    // Minimal Pi-chain typeAst: enough for binder collection; much harder to break JSON.
    val typeAst =
      """{"tag":"Type","term":{"tag":"Pi","binder":{"hiding":"implicit","nameHint":"A"},"cod":{"tag":"Type","term":{"tag":"Pi","binder":{"hiding":"explicit","nameHint":"x"},"cod":{"tag":"Type","term":{"tag":"Pi","binder":{"hiding":"explicit","nameHint":"y"},"cod":{"tag":"Type","term":{"tag":"Var","ix":0,"elims":[]}}}}}}}}"""

    val row =
      s"""{"file":"Proofs.agda","prettyQname":"Proofs.Rel","type":"{A : Set} → A → A → A","typeAstVersion":"0.3-v0","typeAst":$typeAst,"body":"REL @1 @1 @0","hasBody":true}"""

    // Optional: fail fast if we ever break JSON again.
    mapper.readTree(row) // will throw if invalid

    writeUtf8(in, row + "\n")

    BuildProofCompletionDataset.main(Array(
      "--in", in.toAbsolutePath.toString,
      "--out", out.toAbsolutePath.toString,
      "--limit", "10",
      "--all-bodies"
    ))

    val lines = readLines(out)
    lines.size shouldBe 1
    val n = mapper.readTree(lines.head)

    n.get("targetRaw").asText() shouldBe "REL @1 @1 @0"
    n.get("target").asText() shouldBe "REL @1 @1 @0"
    n.get("targetResolver").asText() shouldBe "raw"
    n.get("targetResolved").asBoolean() shouldBe false
    n.get("targetHead").asText() shouldBe "REL"
  }
}

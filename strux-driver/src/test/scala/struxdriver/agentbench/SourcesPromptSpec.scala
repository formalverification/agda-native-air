/** ============================================================================
  *  SourcesPromptSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/SourcesPromptSpec.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  Pins the source directories the shell arms' prompts name (issue #189).  A
  *  shell subject is audited against read roots it was never shown: on the
  *  hard tier, Opus 5 searched `/` or the repository root for agda-algebras'
  *  sources on nine rows, and the isolation gate failed each one though the
  *  file type-checked.  So the shell and both prompts now list every
  *  registered library's source roots, named, and Agda's own primitive
  *  modules, all of them read roots; the server arm's prompt, whose Read is
  *  confined by the client, is unchanged.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.unsafe.implicits.global
import java.nio.file.{Files, Path, Paths}
import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers

final class SourcesPromptSpec extends AnyFunSuite with Matchers {

  private def template(name: String): String =
    scala.io.Source.fromResource(s"agentbench/$name")(scala.io.Codec.UTF8).mkString

  /** A registry of two libraries: one named, with two include roots, and one
    * with no `name:` line, which is then known by its file's stem.
    */
  private def registry(): (Path, Path, Path) = {
    val dir  = Files.createTempDirectory("agentbench-sources")
    val a    = Files.createDirectories(dir.resolve("lib-a"))
    val b    = Files.createDirectories(dir.resolve("lib-b"))
    Files.write(a.resolve("alpha.agda-lib"), "name: alpha-1.0\ninclude: src extra\ndepend: standard-library\n".getBytes("UTF-8"))
    Files.write(b.resolve("beta.agda-lib"), "include: agda\n".getBytes("UTF-8"))
    val reg  = dir.resolve("libraries")
    Files.write(reg, s"${a.resolve("alpha.agda-lib")}\n${b.resolve("beta.agda-lib")}\n\n".getBytes("UTF-8"))
    (reg, a, b)
  }

  test("each library's source roots are named in the registry's order, a nameless library by its file's stem") {
    val (reg, a, b) = registry()
    Extractor.namedIncludesFromRegistry(reg).unsafeRunSync() shouldBe Vector(
      "alpha-1.0" -> a.resolve("src"), "alpha-1.0" -> a.resolve("extra"), "beta" -> b.resolve("agda"))
  }

  test("the named roots are exactly the include roots the read roots are built from, in the read roots' form") {
    val (reg, _, _) = registry()
    Extractor.namedIncludesFromRegistry(reg).unsafeRunSync().map(_._2) shouldBe
      Extractor.includesFromRegistry(reg).unsafeRunSync().map(_.toAbsolutePath.normalize)
    Extractor.namedIncludesFromRegistry(reg).unsafeRunSync().forall(_._2.isAbsolute) shouldBe true
  }

  test("the block lists each root with its library, then Agda's primitive modules when the run found them") {
    val named = Vector("standard-library-2.3" -> Paths.get("/nix/store/s/src"), "agda-algebras" -> Paths.get("/nix/store/a/src"))
    Subject.sourcesBlock(named, Some(Paths.get("/nix/store/d/lib/prim"))) shouldBe
      "    /nix/store/s/src   (standard-library-2.3)\n" +
      "    /nix/store/a/src   (agda-algebras)\n" +
      "    /nix/store/d/lib/prim   (Agda's own Agda.Builtin and Agda.Primitive)"
    Subject.sourcesBlock(named, None).linesIterator.size shouldBe 2
  }

  test("the shell and both prompts name the sources and forbid searching elsewhere; the server arm's does not change") {
    val block = Subject.sourcesBlock(Vector("agda-algebras" -> Paths.get("/nix/store/a/src")), None)
    for (arm <- Vector("shell", "both")) {
      val t = template(s"system-prompt-$arm.md")
      t should include ("{{sources}}")
      val rendered = Subject.render(t, Paths.get("/w/M.agda"), "m", "agda M.agda", Paths.get("/c.jsonl"), block)
      rendered should include ("    /nix/store/a/src   (agda-algebras)")
      rendered should include ("do not search the rest of the filesystem for sources")
      // The judge's own command names the registry (`--library-file`), which is
      // no source directory; the boundary must admit it (PR #200 review).
      rendered should include ("the paths the command above already names")
      rendered should not include ("{{")
    }
    template("system-prompt-mcp.md") should not include ("{{sources}}")
  }
}

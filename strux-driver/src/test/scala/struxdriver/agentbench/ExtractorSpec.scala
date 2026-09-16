/** ============================================================================
  *  ExtractorSpec.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/test/scala/struxdriver/agentbench/ExtractorSpec.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  Pins the extractor's process discipline (issue #154): an `agda-json` that
  *  never finishes is bounded by the harness's timeout, named as such, and
  *  destroyed, so a hung child cannot outlive the judge.  Driven with a stand
  *  -in binary rather than the real extractor, so it needs no toolchain.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.unsafe.implicits.global
import java.nio.file.{Files, Path}
import org.scalatest.funsuite.AnyFunSuite
import org.scalatest.matchers.should.Matchers
import scala.concurrent.duration._

final class ExtractorSpec extends AnyFunSuite with Matchers {

  /** A stand-in extractor that records its pid and then never finishes. */
  private def hangingBin(dir: Path, pidFile: Path): Path = {
    val bin = dir.resolve("agda-json-that-hangs")
    Files.write(bin, s"#!/bin/sh\necho $$$$ > $pidFile\nexec sleep 300\n".getBytes("UTF-8"))
    bin.toFile.setExecutable(true)
    bin
  }

  test("an extractor that never finishes is bounded, named, and destroyed") {
    val dir     = Files.createTempDirectory("agentbench-extractor")
    val pidFile = dir.resolve("pid")
    val input   = dir.resolve("M.agda")
    Files.write(input, "module M where\n".getBytes("UTF-8"))

    val t0  = System.nanoTime()
    val res = Extractor(hangingBin(dir, pidFile), Vector.empty, dir.toString, 2.seconds).rows(input).unsafeRunSync()
    val ms  = (System.nanoTime() - t0) / 1000000L

    res.left.getOrElse("") should include ("did not finish within 2s")
    ms should be < 60000L                                  // the wait is bounded, not the process's own lifetime

    val pid = new String(Files.readAllBytes(pidFile), "UTF-8").trim.toLong
    val alive = (1 to 20).foldLeft(true) { (still, _) =>
      if (!still) false
      else {
        val a = ProcessHandle.of(pid).map[Boolean](_.isAlive).orElse(false)
        if (a) { Thread.sleep(50); true } else false
      }
    }
    alive shouldBe false                                   // destroyed, not left behind
  }

  test("a stand-in that exits non-zero is reported with its output, and leaves no temp tree behind") {
    val dir   = Files.createTempDirectory("agentbench-extractor-fail")
    val input = dir.resolve("M.agda")
    Files.write(input, "module M where\n".getBytes("UTF-8"))
    val bin = dir.resolve("agda-json-that-fails")
    Files.write(bin, "#!/bin/sh\necho 'boom: no such include'\nexit 3\n".getBytes("UTF-8"))
    bin.toFile.setExecutable(true)

    val before = Files.list(java.nio.file.Paths.get(System.getProperty("java.io.tmpdir"))).count()
    val res    = Extractor(bin, Vector.empty, dir.toString, 30.seconds).rows(input).unsafeRunSync()
    res.left.getOrElse("") should include ("agda-json exit 3")
    res.left.getOrElse("") should include ("boom: no such include")
    Files.list(java.nio.file.Paths.get(System.getProperty("java.io.tmpdir"))).count() should be <= before
  }
}

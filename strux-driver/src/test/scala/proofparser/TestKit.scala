/** ============================================================================
 *  TestKit.scala
 *  ----------------------------------------------------------------------------
 *
 *  File: proof-parser/src/test/scala/proofparser/TestKit.scala
 *  Package: proofparser
 *  Copyright: (c) 2024 Thmpr Lab, LLC.
 *
 *  Description
 *  -----------
 *  A base trait providing common utilities for tests in the proofparser package.
 *  It includes methods for loading test resources and generators for property-based
 *  testing.
 *
 *  Run: `sbt test`
 ** ============================================================================ */

package proofparser

import org.scalatest.EitherValues
import org.scalatest.matchers.should.Matchers
import org.scalatest.wordspec.AnyWordSpec
import org.scalacheck.{Arbitrary, Gen}
import scala.io.Source
// import java.nio.file.{Paths, Files}

trait TestKit extends AnyWordSpec with Matchers with EitherValues {
  def loadResource(path: String): String = {
    val url = Option(getClass.getResource(path))
      .getOrElse(sys.error(s"Test resource not found: $path"))
    val src = Source.fromURL(url, "UTF-8")
    try src.mkString finally src.close()
  }

  // A simple gen for premise-like identifiers
  val genIdent: Gen[String] = for {
    base <- Gen.oneOf("+", "-", "_", "foo", "bar", "baz")
    n    <- Gen.choose(1, 99)
  } yield s"$base$n"

  // Example Arbitrary for property tests (optional)
  implicit val arbIdent: Arbitrary[String] = Arbitrary(genIdent)
}

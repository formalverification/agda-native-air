// File: agda-ai-prover/proof-parser/build.sbt

// Define Scala version for the entire build
ThisBuild / scalaVersion := "2.13.17"

Compile / run / fork := true

// Spark 3.5.1 uses json4s 3.7.0-M11; keep them aligned.
val json4sV = "3.7.0-M11"

// Root project definition
lazy val ProofParser = project.in(file("."))
  .settings(
    name := "ProofParser",
    version := "0.1.0",

    // Main class setting:
    // Compile / run / mainClass := Some("proofparser.AgdaExtractorMain")
    Compile / mainClass := Some("proofparser.extract.AgdaJsonlDriver"),
    // All library dependencies consolidated here
    libraryDependencies ++= Seq(
      "com.lihaoyi" %% "upickle"    % "3.1.2",
      "org.scalatest" %% "scalatest" % "3.2.19" % Test,
      "org.scalacheck" %% "scalacheck" % "1.17.0"  % Test,
      "org.json4s" %% "json4s-jackson" % json4sV,
      "org.json4s" %% "json4s-native" % json4sV,
      "org.scalatestplus" %% "scalacheck-1-17" % "3.2.18.0" % Test,
      "org.typelevel" %% "cats-core"   % "2.10.0",
      "org.typelevel" %% "cats-effect" % "3.5.4",
      "co.fs2" %% "fs2-core" % "3.9.3",
      "co.fs2" %% "fs2-io" % "3.9.3",
      "org.apache.spark" %% "spark-sql" % "4.1.0",
      "org.apache.spark" %% "spark-core" % "4.1.0"
    ),

  // Nice defaults
  scalacOptions ++= Seq("-deprecation", "-feature"),
  Test / parallelExecution := false,

  // We fork java and grant JDK21 module opens for Spark (Run + Test)
  fork := true,
  // These apply to `sbt run` (which our `make etl` uses):
  Compile / run / fork := true,
  Compile / run / javaOptions ++= Seq(
    "--add-exports=java.base/sun.nio.ch=ALL-UNNAMED",
    "--add-opens=java.base/java.nio=ALL-UNNAMED"
  ),
    // ---------- IMPORTANT for Java 17/21 ----------
    // Fixes "IllegalAccessError: sun.nio.ch.DirectBuffer" when running Spark under Java 17+.
    // These apply to `sbt test` (Spark inside tests).
    // If we ever switch dev shell to JDK 17, we can remove these flags.
  Test / javaOptions ++= Seq(
    "--add-exports=java.base/sun.nio.ch=ALL-UNNAMED",
    "--add-opens=java.base/java.nio=ALL-UNNAMED"
  )
)

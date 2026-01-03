// File: agda-ai-prover/proof-parser/build.sbt

// Define Scala version for the entire build
ThisBuild / scalaVersion := "2.12.20"

Compile / run / fork := true

// Spark 3.5.1 uses json4s 3.7.0-M11; keep them aligned.
val json4sV = "3.7.0-M11"

// Root project definition
lazy val ProofParser = (project in file("."))
  .settings(
    name := "proof-parser",
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
      "org.apache.spark" %% "spark-core" % "3.5.1",
      "org.apache.spark" %% "spark-sql"  % "3.5.1"
    )


  )

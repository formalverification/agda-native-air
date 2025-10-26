// File: agda-ai-prover/proof-parser/build.sbt

// Define Scala version for the entire build
ThisBuild / scalaVersion := "2.13.12"

// Root project definition
lazy val root = (project in file("."))
  .settings(
    name := "proof-parser",
    version := "0.1.0",

    // Main class setting:
    // Compile / run / mainClass := Some("proofparser.AgdaExtractorMain")
    Compile / mainClass := Some("proofparser.AgdaExtractorMain"),

    // All library dependencies consolidated here
    libraryDependencies ++= Seq(
      "com.lihaoyi" %% "upickle"    % "3.1.2",
      "org.scalatest" %% "scalatest" % "3.2.19" % Test,
      "org.scalacheck" %% "scalacheck" % "1.17.0"  % Test,
      "org.json4s" %% "json4s-native" % "4.0.6",
    )
    // Old dependencies:
    // // Testing libraries
    // "org.scalatest" %% "scalatest" % "3.2.18" % Test,
    // "com.lihaoyi" %% "utest" % "0.8.1" % Test,

    // // JSON libraries - choose either json4s or circe+upickle as needed
    // "io.circe" %% "circe-core" % "0.14.6",
    // "io.circe" %% "circe-generic" % "0.14.6",
    // "io.circe" %% "circe-parser" % "0.14.6",
    // "com.lihaoyi" %% "upickle" % "3.1.3"

    // Assembly plugin settings
    // N.B. Plugin should be in project/plugins.sbt, not in build.sbt.
    // If we really want a fat JAR later, create a file named project/plugins.sbt
    // with the following content:
    // addSbtPlugin("com.eed3si9n" % "sbt-assembly" % "1.2.0")
  )

// Define Scala version for the entire build
ThisBuild / scalaVersion := "2.13.12"

// Root project definition
lazy val root = (project in file("."))
  .settings(
    name := "ProofParser",
    version := "0.1.0",

    // All library dependencies consolidated here
    libraryDependencies ++= Seq(
      // Testing libraries
      "org.scalatest" %% "scalatest" % "3.2.18" % Test,
      "com.lihaoyi" %% "utest" % "0.8.1" % Test,

      // JSON libraries - choose either json4s or circe+upickle based on your needs
      "org.json4s" %% "json4s-native" % "4.0.6",
      "io.circe" %% "circe-core" % "0.14.6",
      "io.circe" %% "circe-generic" % "0.14.6",
      "io.circe" %% "circe-parser" % "0.14.6",
      "com.lihaoyi" %% "upickle" % "3.1.3"
    ),

    // Main class setting (updated syntax)
    Compile / run / mainClass := Some("proofparser.AgdaExtractorMain")

    // Assembly plugin settings
    assembly / mainClass := Some("proofparser.Agda2TrainTransformer")
  )

// Plugin should be in project/plugins.sbt, not in build.sbt
// Create a file named project/plugins.sbt with the following content:
// addSbtPlugin("com.eed3si9n" % "sbt-assembly" % "1.2.0")

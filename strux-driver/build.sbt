ThisBuild / scalaVersion := "2.13.12"

libraryDependencies += "org.scalatest" %% "scalatest" % "3.2.18" % Test

libraryDependencies ++= Seq(
  "com.lihaoyi" %% "upickle" % "3.1.3",
  "org.scalatest" %% "scalatest" % "3.2.18" % Test
)

lazy val root = (project in file("."))
  .settings(
    name := "AgdaExtractor",
    version := "0.1.0",
    libraryDependencies ++= Seq(
      "io.circe" %% "circe-core" % "0.14.6",
      "io.circe" %% "circe-generic" % "0.14.6",
      "io.circe" %% "circe-parser" % "0.14.6"
    )
  )

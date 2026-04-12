// File: agda-native-air/strux-driver/build.sbt

ThisBuild / scalaVersion := "2.13.17"

Compile / run / fork := true

val catsCoreVersion = "2.12.0"

val circeVersion = "0.14.9"

val fs2Version = "3.10.2"

// json4s pinned to match Spark's transitive dependency.
// Verify alignment after Spark upgrades with `sbt "show dependencyTree"`
// or, check for version evictions of all dependencies at once:
//   sbt dependencyTree | grep evicted | grep -E \
//   'cats-core|cats-effect|json4s|fs2|circe|upickle|scalatest|scalacheck'
val json4sV = "4.0.7"

val sparkVersion = "4.1.0"

// Root project definition
lazy val StruxDriver = project.in(file("."))
  .settings(
    name := "StruxDriver",
    version := "0.1.0",

    // Main class setting:
    Compile / mainClass := Some("struxdriver.extract.AgdaJsonlDriver"),
    libraryDependencies ++= Seq(
      "com.lihaoyi"       %% "upickle"         % "3.1.2",
      "org.scalatest"     %% "scalatest"       % "3.2.19" % Test,
      "org.scalacheck"    %% "scalacheck"      % "1.17.0"  % Test,
      "org.json4s"        %% "json4s-jackson"  % json4sV,
      "org.json4s"        %% "json4s-native"   % json4sV,
      "org.scalatestplus" %% "scalacheck-1-17" % "3.2.18.0" % Test,
      "org.typelevel"     %% "cats-core"       % catsCoreVersion,
      "org.typelevel"     %% "cats-effect"     % "3.5.4",
      "co.fs2"            %% "fs2-core"        % fs2Version,
      "co.fs2"            %% "fs2-io"          % fs2Version,
      "org.apache.spark"  %% "spark-sql"       % sparkVersion,
      "org.apache.spark"  %% "spark-core"      % sparkVersion,
      "io.circe"          %% "circe-core"      % circeVersion,
      "io.circe"          %% "circe-generic"   % circeVersion,
      "io.circe"          %% "circe-parser"    % circeVersion
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

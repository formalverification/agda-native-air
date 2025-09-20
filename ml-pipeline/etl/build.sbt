name := "ETL"

version := "0.1"

scalaVersion := "2.12.10"

// Spark dependencies
libraryDependencies ++= Seq(
  "org.apache.spark" %% "spark-core" % "3.4.1", // % "provided",
  "org.apache.spark" %% "spark-sql"  % "3.4.1" // % "provided"
)

// Correctly typed override
dependencyOverrides := Seq(
  "org.apache.hadoop" % "hadoop-client-api" % "3.3.4",
  "org.apache.hadoop" % "hadoop-client-runtime" % "3.3.4"
)

// JVM options for JDK 17 compatibility
ThisBuild / fork := true
ThisBuild / classLoaderLayeringStrategy := ClassLoaderLayeringStrategy.Flat
ThisBuild / javaOptions ++= Seq(
  "--add-exports=java.base/sun.nio.ch=ALL-UNNAMED",
  "-Dspark.driver.userClassPathFirst=true",
  "-Dspark.executor.userClassPathFirst=true",
  "-Dspark.driver.extraClassPath=target/scala-2.12/classes",
  "-Dspark.executor.extraClassPath=target/scala-2.12/classes"
)

Global / excludeLintKeys += classLoaderLayeringStrategy

Compile / mainClass := Some("PreprocessAgda")

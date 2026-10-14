/** ============================================================================
  *  CodexPrepare.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/CodexPrepare.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  What a Codex run settles once, before its first subject (issue #239):
  *  the Codex it runs (the npm wrapper on PATH, and the native binary it
  *  launches, by content), the pinned model catalog and the effort it
  *  allows, the read server's command, the checkout's trust entries, the
  *  operator's login (by kind, never by value), and the price that turns a
  *  subject's tokens into its budget; then the run's own copies of the
  *  catalog and of the configuration template.  A run that cannot be made
  *  faithfully is refused here, before anything spawns: a catalog with no
  *  entry for the model, an effort the model does not take, no login, or a
  *  `.codex` directory in the checkout, whose configuration a trusted
  *  project would layer into every subject.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.IO
import cats.syntax.all._
import io.circe.Json
import io.circe.syntax._
import java.nio.file.{Files, Path, Paths}
import scala.jdk.CollectionConverters._

import struxdriver.io.TextIO

/** A Codex run as prepared: the setup every subject shares, the endpoint
  * block, the protocol's extra inputs, and the run's read roots.
  */
final case class CodexPrepared(setup: CodexSetup, endpoint: Json, inputs: Json, authPath: Path, readRoots: Vector[Path]) {

  def context: CodexContext = CodexContext(setup, authPath, endpoint)

  /** The configuration every subject is given, with each subject's own
    * values as placeholders: what the protocol records by digest.
    */
  def template(cfg: AgentBenchConfig, sysP: String): String = {
    val placeholderCfg = SubjectConfig.of(cfg, sysP, "")
    val work           = Paths.get("{{workDir}}")
    val server         = Subject.server(placeholderCfg, work, Paths.get("{{workDir}}/{{file}}"), Paths.get("{{corpus}}"))
    Toml.render(CodexSubject.tables(cfg.model.getOrElse(""), setup, "{{systemPrompt}}", work, readRoots, server,
                                    "{{runId}}/{{id}}", cfg.serverTimeout + 60))
  }
}

object CodexPrepare {

  /** The read server, from the project root. */
  val readServerScript: String = "scripts/python/bench_read_server.py"

  private def refuse(why: String): IO[Nothing] = IO.raiseError(new RuntimeException(s"--harness codex: $why"))

  /** The model's catalog entry: its default effort and the efforts it takes. */
  def efforts(catalog: Json, model: String): Option[(String, Vector[String])] =
    catalog.hcursor.downField("models").focus.flatMap(_.asArray).getOrElse(Vector.empty)
      .find(_.hcursor.get[String]("slug").toOption.contains(model)).map { m =>
        val c = m.hcursor
        (c.get[String]("default_reasoning_level").getOrElse(""),
         c.downField("supported_reasoning_levels").focus.flatMap(_.asArray).getOrElse(Vector.empty)
           .flatMap(_.hcursor.get[String]("effort").toOption))
      }

  /** The main checkout of the repository the project root is in: Codex
    * resolves a worktree to it when it writes a trust entry.
    */
  private def mainCheckout(root: Path): IO[Option[Path]] =
    IO.blocking {
      val p   = new ProcessBuilder("git", "-C", root.toString, "rev-parse", "--path-format=absolute", "--git-common-dir").redirectErrorStream(true).start()
      val out = new String(p.getInputStream.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8).trim
      if (p.waitFor() == 0 && out.nonEmpty) Option(Paths.get(out).getParent) else None
    }.handleError(_ => None)

  /** Is a Codex app-server daemon running?  Its token refreshes share the
    * operator's login with the subjects', so the run warns.
    */
  private val daemonRunning: IO[Boolean] =
    IO.blocking {
      ProcessHandle.allProcesses().iterator().asScala.exists { h =>
        val cmd = h.info().commandLine()
        cmd.isPresent && cmd.get.contains("codex") && cmd.get.contains("app-server")
      }
    }.handleError(_ => false)

  private def fileId(p: Path): IO[Json] =
    struxdriver.search.Digest.sha256Hex(p).map(d => Json.obj("path" -> p.toString.asJson, "sha256" -> d.asJson))

  /** Settle the run (the header's list), or refuse it. */
  def prepare(cfg: AgentBenchConfig, prices: PriceTable, readRoots: Vector[Path], versionOutput: String): IO[CodexPrepared] = {
    val model   = cfg.model.getOrElse("")
    val pathEnv = cfg.env.vars.get("PATH").orElse(sys.env.get("PATH"))
    for {
      wrapper  <- CodexSubject.resolve(cfg.codexBin, pathEnv).fold[IO[Path]](refuse(s"no ${cfg.codexBin} on PATH"))(IO.pure)
      _        <- CodexSubject.versionOf(versionOutput).fold[IO[Unit]](refuse(s"${cfg.codexBin} --version printed ${versionOutput.trim.take(200)}, no Codex version"))(_ => IO.unit)
      pkg       = CodexSubject.packageRoot(cfg.codexBin, pathEnv)
      native   <- pkg.fold(IO.pure(Option.empty[Path]))(CodexSubject.nativeBinary)
      catPath  <- cfg.codexCatalog.fold[IO[Path]](refuse("no --codex-catalog"))(IO.pure)
      catalog  <- TextIO.readJson(catPath).flatMap(_.fold[IO[Json]](refuse(s"the model catalog $catPath is not JSON"))(IO.pure))
      levels   <- efforts(catalog, model).fold[IO[(String, Vector[String])]](refuse(s"the model catalog has no entry for $model"))(IO.pure)
      effort    = cfg.effort.getOrElse(levels._1)
      _        <- if (levels._2.contains(effort)) IO.unit else refuse(s"$model takes effort ${levels._2.mkString("|")}, not $effort")
      python   <- CodexSubject.resolve("python3", pathEnv).fold[IO[Path]](refuse("no python3 on PATH for the read server"))(IO.pure)
      script    = cfg.projectRoot.resolve(readServerScript)
      main     <- mainCheckout(cfg.projectRoot)
      trust     = (cfg.projectRoot +: main.toVector).map(_.toAbsolutePath.normalize).distinct
      dotCodex <- IO.blocking(trust.map(_.resolve(".codex")).filter(Files.exists(_)))
      _        <- if (dotCodex.isEmpty) IO.unit else refuse(s"${dotCodex.mkString(", ")} exists; a project configuration would reach every subject")
      authPath  = CodexSubject.operatorAuth(cfg.env.vars)
      authText <- TextIO.read(authPath).handleErrorWith(_ => refuse(s"no Codex login at $authPath (codex login)"))
      _        <- CodexSubject.loginRefusal(authText).fold(IO.unit)(refuse)
      daemon   <- daemonRunning
      _        <- if (daemon) IO.println("!! a Codex app-server daemon is running; its token refreshes share the login with the subjects'") else IO.unit
      ids      <- Vector(Some("codexBin" -> native.getOrElse(wrapper)), Some("readServer" -> script)).flatten
                    .traverse { case (k, p) => fileId(p).map(k -> _) }
      catSha   <- struxdriver.search.Digest.sha256Hex(catPath)
      setup     = CodexSetup(
                    codexBin    = wrapper.toString,
                    effort      = effort,
                    catalog     = cfg.layout.codexModels,
                    readServer  = Vector(python.toString, script.toString),
                    packageRoot = pkg,
                    trustRoots  = trust,
                    price       = prices.priceOfModelId(model))
    } yield CodexPrepared(
      setup     = setup,
      endpoint  = CodexSubject.endpoint(CodexSubject.authModeOf(authText)),
      inputs    = Json.obj((ids ++ Vector(
                    "codexCatalog"     -> Json.obj("path" -> Layout.codexModelsFile.asJson, "sha256" -> catSha.asJson),
                    "readServerPython" -> python.toString.asJson)): _*),
      authPath  = authPath,
      readRoots = readRoots)
  }

  /** The run's own copies: the catalog (a fresh run's; a resume keeps the
    * one it started with, which the protocol's digest checks) and the
    * configuration template under the prompts.
    */
  def record(cfg: AgentBenchConfig, c: CodexPrepared, sysP: String): IO[Unit] =
    for {
      have <- IO.blocking(Files.isRegularFile(cfg.layout.codexModels))
      _    <- if (have && cfg.resume) IO.unit
              else cfg.codexCatalog.fold(IO.unit)(src => IO.blocking {
                Files.copy(src, cfg.layout.codexModels, java.nio.file.StandardCopyOption.REPLACE_EXISTING); ()
              })
      _    <- TextIO.write(cfg.layout.prompts.resolve(Layout.codexConfigTemplate), c.template(cfg, sysP))
    } yield ()
}

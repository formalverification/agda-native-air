/** ============================================================================
  *  McpClient.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/search/McpClient.scala
  *  Package: struxdriver.search
  *
  *  Purpose
  *  -------
  *  A minimal MCP client for driving agda-mcp over its real JSON-RPC stdio
  *  transport: spawn the server binary, `initialize`, then issue `tools/call`
  *  requests one at a time, timing each round trip on a monotonic clock.
  *
  *  Design notes
  *  ------------
  *  - The search deliberately drives the server as a CLIENT over the public
  *    tool contract (sub-issue #119's host-language rationale): the same
  *    newline-delimited framing, double-encoded payloads, and isError handling
  *    every other agent gets — so search stress doubles as server field-testing.
  *  - Requests are strictly sequential (a Semaphore(1) enforces what the flow
  *    already guarantees); responses for other ids and non-JSON noise are
  *    skipped, never fatal, since only a line carrying OUR id answers us.
  *  - The per-call wall clock (clientNanos) is half of the P0 measurement: the
  *    difference between it and the server-reported `elapsedMs` (the Agda
  *    subprocess) is the transport-plus-handling overhead an in-process rewrite
  *    could at most remove.
  *  - The server's stderr goes to a log file: its banner and progress lines
  *    would otherwise interleave with the harness's own output.
  *  - Shutdown closes stdin, which the server answers by exiting cleanly; a
  *    process still alive after a grace period is destroyed forcibly so no
  *    orphan `agda` survives a crashed run.
  *
  *  Integration
  *  -----------
  *  Wrapped by Oracle.scala; configured and owned by SingleStepHarness.scala.
  *
  *  ============================================================================
  */
package struxdriver.search

import cats.effect.{IO, Ref, Resource}
import cats.effect.std.Semaphore
import cats.syntax.all._
import io.circe.Json
import io.circe.syntax._
import java.io.{BufferedReader, BufferedWriter, File, InputStreamReader, OutputStreamWriter}
import java.nio.charset.StandardCharsets
import java.nio.file.Path
import scala.concurrent.duration._
import scala.jdk.CollectionConverters._

/** How to run the server: the binary, the Agda flag string it forwards, the
  * per-Agda-call bound it enforces, the working directory it must start in
  * (relative flag paths resolve there), and where its stderr goes.
  */
final case class ServerConfig(
  bin:        Path,
  agdaFlags:  String,
  timeoutSec: Int,
  cwd:        Path,
  stderrLog:  Path
) {
  /** Outer client bound per call: the server's own Agda bound plus slack for
    * everything around it, so the client outlives any call the server itself
    * still considers live.
    */
  def callTimeout: FiniteDuration = (timeoutSec + 120).seconds
}

/** One timed value: the payload plus the client-observed wall-clock nanos. */
final case class Timed[A](value: A, clientNanos: Long) {
  def clientMs: Double = clientNanos / 1e6
}

/** The one operation the search needs from a transport: call a tool, get the
  * timed reply.  A trait so Oracle can be exercised against a counting fake in
  * the unit tests while production wires in the real stdio client.
  */
trait ToolCaller {
  def callTool(tool: String, args: Json): IO[Timed[ToolReply]]
}

final class McpClient private (
  proc:   Process,
  writer: BufferedWriter,
  reader: BufferedReader,
  ids:    Ref[IO, Long],
  lock:   Semaphore[IO],
  cfg:    ServerConfig
) extends ToolCaller {

  /** Call one tool and return its reply with the round-trip time.  Fails the
    * IO on a dead transport, a protocol-level error for our id, or the outer
    * timeout — all of which mean the run, not the candidate, is broken.
    */
  override def callTool(tool: String, args: Json): IO[Timed[ToolReply]] =
    lock.permit.use { _ =>
      for {
        id    <- ids.updateAndGet(_ + 1)
        req    = Json.obj(
                   "jsonrpc" -> "2.0".asJson,
                   "id"      -> id.asJson,
                   "method"  -> "tools/call".asJson,
                   "params"  -> Json.obj("name" -> tool.asJson, "arguments" -> args)
                 )
        t0    <- IO.monotonic
        reply <- send(req.noSpaces) *> awaitReply(id)
        t1    <- IO.monotonic
      } yield Timed(reply, (t1 - t0).toNanos)
    }.timeoutTo(
      cfg.callTimeout,
      IO.raiseError(new RuntimeException(
        s"agda-mcp client: no reply to $tool within ${cfg.callTimeout} (server stderr: ${cfg.stderrLog})"))
    )

  /** The MCP handshake.  Its response carries no tool content (serverInfo
    * only), so it has its own await: any line with our id and no error means
    * the transport is up.  A regression here surfaces before the first real
    * call, which is where a client would want it.
    */
  private[search] def initialize: IO[Unit] =
    lock.permit.use { _ =>
      for {
        id  <- ids.updateAndGet(_ + 1)
        req  = Json.obj(
                 "jsonrpc" -> "2.0".asJson,
                 "id"      -> id.asJson,
                 "method"  -> "initialize".asJson,
                 "params"  -> Json.obj()
               )
        _   <- send(req.noSpaces)
        _   <- awaitInit(id)
      } yield ()
    }.timeoutTo(
      60.seconds,
      IO.raiseError(new RuntimeException(
        s"agda-mcp client: no initialize reply within 60s (server stderr: ${cfg.stderrLog})"))
    )

  private def awaitInit(id: Long): IO[Unit] =
    IO.blocking(Option(reader.readLine())).flatMap {
      case None =>
        stderrTail.flatMap(tail => IO.raiseError(new RuntimeException(
          s"agda-mcp exited during initialize; stderr tail:\n$tail")))
      case Some(line) =>
        io.circe.parser.parse(line).toOption match {
          case Some(json) if json.hcursor.get[Long]("id").toOption.contains(id) =>
            json.hcursor.downField("error").focus match {
              case Some(err) => IO.raiseError(new RuntimeException(s"agda-mcp initialize failed: ${err.noSpaces}"))
              case None      => IO.unit
            }
          case _ => awaitInit(id)
        }
    }

  private def send(line: String): IO[Unit] =
    IO.blocking {
      writer.write(line); writer.write("\n"); writer.flush()
    }

  /** Read lines until one carries our id.  EOF means the server died; its
    * stderr tail is the only useful evidence, so surface it.
    */
  private def awaitReply(id: Long): IO[ToolReply] =
    IO.blocking(Option(reader.readLine())).flatMap {
      case None =>
        stderrTail.flatMap(tail => IO.raiseError(new RuntimeException(
          s"agda-mcp exited while awaiting reply id=$id; stderr tail:\n$tail")))
      case Some(line) =>
        Wire.envelope(line, id) match {
          case Wire.Envelope.NotOurs             => awaitReply(id)
          case Wire.Envelope.ProtocolError(msg)  =>
            IO.raiseError(new RuntimeException(s"agda-mcp protocol error for id=$id: $msg"))
          case Wire.Envelope.Reply(reply)        => IO.pure(reply)
        }
    }

  private def stderrTail: IO[String] =
    IO.blocking {
      val f = cfg.stderrLog.toFile
      if (f.exists()) {
        val lines = java.nio.file.Files.readAllLines(cfg.stderrLog, StandardCharsets.UTF_8).asScala
        lines.takeRight(15).mkString("\n")
      } else "(no stderr log)"
    }
}

object McpClient {

  /** Spawn the server and complete the `initialize` handshake; shut it down by
    * closing stdin (its clean-exit signal), escalating to destroy after a
    * grace period.
    */
  def resource(cfg: ServerConfig): Resource[IO, McpClient] =
    Resource.make(start(cfg))(shutdown).evalMap { case (proc, w, r) =>
      for {
        ids  <- Ref.of[IO, Long](0L)
        lock <- Semaphore[IO](1)
        c     = new McpClient(proc, w, r, ids, lock, cfg)
        _    <- c.initialize
      } yield c
    }

  private def start(cfg: ServerConfig): IO[(Process, BufferedWriter, BufferedReader)] =
    IO.blocking {
      val cmd = List(
        cfg.bin.toString,
        "--agda-flags", cfg.agdaFlags,
        "--timeout", cfg.timeoutSec.toString
      )
      val pb = new ProcessBuilder(cmd.asJava)
      pb.directory(cfg.cwd.toFile)
      pb.redirectError(ProcessBuilder.Redirect.to(new File(cfg.stderrLog.toString)))
      val proc   = pb.start()
      val writer = new BufferedWriter(new OutputStreamWriter(proc.getOutputStream, StandardCharsets.UTF_8))
      val reader = new BufferedReader(new InputStreamReader(proc.getInputStream, StandardCharsets.UTF_8))
      (proc, writer, reader)
    }

  private def shutdown(h: (Process, BufferedWriter, BufferedReader)): IO[Unit] = {
    val (proc, writer, _) = h
    IO.blocking {
      // Closing stdin is the server's documented clean-exit signal.
      try writer.close() catch { case _: java.io.IOException => () }
      if (!proc.waitFor(10, java.util.concurrent.TimeUnit.SECONDS)) {
        proc.destroy()
        if (!proc.waitFor(5, java.util.concurrent.TimeUnit.SECONDS)) { proc.destroyForcibly(); () }
      }
    }
  }

}

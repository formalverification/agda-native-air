/** ============================================================================
  *  Oracle.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/search/Oracle.scala
  *  Package: struxdriver.search
  *
  *  Purpose
  *  -------
  *  The search's view of agda-mcp: check_file (state observation and the final
  *  verdict), get_goal (what a proposer sees), type_of (lane knowledge for
  *  binder counts and peeks, issue #122), and fill_hole (the probe) —
  *  each timed, and probes memoised on OracleKey, since every miss costs an
  *  Agda subprocess (#112's "the oracle is the cost centre" lesson).
  *
  *  Design notes
  *  ------------
  *  - The memo is keyed on (content fingerprint, hole position, candidate), so
  *    a committed edit changes the fingerprint and can never reuse a stale
  *    judgement; a cache hit records a TimingRow with cached=true and no
  *    server time, so the measurement never counts saved calls as oracle time.
  *  - Every real call appends one TimingRow: the client-observed round trip,
  *    the server-reported Agda subprocess time (`elapsedMs`), and their
  *    difference — the transport-plus-handling overhead that is P0's decisive
  *    number for the #113 host-language fork.
  *  - A probe whose reply is isError (e.g. an addressing mistake) degrades to
  *    a Crash outcome carrying the reply text, so one bad candidate cannot
  *    abort a sweep; check_file and get_goal errors are surfaced to the caller
  *    instead, since without them the fixture cannot be driven at all.
  *
  *  Integration
  *  -----------
  *  Built on McpClient.scala and the Wire.scala decoders; consumed by
  *  SingleStepHarness.scala, which drains `timings` at the end of a run.
  *
  *  ============================================================================
  */
package struxdriver.search

import cats.effect.{IO, Ref}
import cats.syntax.all._
import io.circe.{Encoder, Json}
import io.circe.syntax._
import java.nio.file.Path

/** Where a call happened, for the timing ledger. */
final case class CallCtx(pass: Int, fixtureId: String, phase: String, rank: Option[Int])

/** One row of the timing ledger (`proof-search-timing.v0`): the split, per
  * call.  `overheadMs = clientMs - serverElapsedMs` when the server reported
  * its subprocess time; a cached row has clientMs ~ 0 and no server fields.
  */
final case class TimingRow(
  pass:              Int,
  fixtureId:         String,
  phase:             String,
  candidateRank:     Option[Int],
  clientMs:          Double,
  serverElapsedMs:   Option[Long],
  overheadMs:        Option[Double],
  checkedFromSource: Option[Boolean],
  cached:            Boolean
)
object TimingRow {
  val schemaVersion: String = "proof-search-timing.v0"

  implicit val encoder: Encoder[TimingRow] = (t: TimingRow) =>
    Json.obj(
      "schemaVersion"     -> schemaVersion.asJson,
      "pass"              -> t.pass.asJson,
      "fixtureId"         -> t.fixtureId.asJson,
      "phase"             -> t.phase.asJson,
      "candidateRank"     -> t.candidateRank.asJson,
      "clientMs"          -> BigDecimal(t.clientMs).setScale(3, BigDecimal.RoundingMode.HALF_UP).asJson,
      "serverElapsedMs"   -> t.serverElapsedMs.asJson,
      "overheadMs"        -> t.overheadMs.map(o => BigDecimal(o).setScale(3, BigDecimal.RoundingMode.HALF_UP)).asJson,
      "checkedFromSource" -> t.checkedFromSource.asJson,
      "cached"            -> t.cached.asJson
    ).dropNullValues
}

/** A decoded oracle answer plus the raw reply text (for the per-candidate log
  * files), the client-observed round-trip milliseconds (0.0 on a memo hit,
  * which spends none — this is the wall-clock the eval schema's `elapsedMs`
  * is defined as), and whether it came from the memo.
  */
final case class OracleAnswer[A](body: A, raw: String, clientMs: Double, cached: Boolean)

final class Oracle private (
  client:      ToolCaller,
  memo:        Ref[IO, Map[OracleKey, OracleAnswer[ProbeOutcome]]],
  val timings: Ref[IO, Vector[TimingRow]]
) {

  /** check_file: the batch verdict and the authoritative hole list. */
  def checkFile(ctx: CallCtx, file: Path): IO[OracleAnswer[CheckFileBody]] =
    for {
      timed <- client.callTool("check_file", Json.obj("filePath" -> file.toString.asJson))
      _     <- IO.raiseWhen(timed.value.isError)(new RuntimeException(
                 s"check_file failed on $file: ${timed.value.text.take(400)}"))
      body  <- IO.fromEither(timed.value.decodeAs[CheckFileBody].leftMap(new RuntimeException(_)))
      _     <- record(ctx, timed, Some(body.elapsedMs), body.checkedFromSource)
    } yield OracleAnswer(body, timed.value.text, timed.clientMs, cached = false)

  /** get_goal at one obligation: the goal type and resolved module name. */
  def getGoal(ctx: CallCtx, file: Path, ob: Obligation): IO[OracleAnswer[GetGoalBody]] =
    for {
      timed <- client.callTool("get_goal", Json.obj(
                 "filePath" -> file.toString.asJson,
                 "line"     -> ob.line.asJson,
                 "column"   -> ob.col.asJson))
      _     <- IO.raiseWhen(timed.value.isError)(new RuntimeException(
                 s"get_goal failed on $file at (${ob.line},${ob.col}): ${timed.value.text.take(400)}"))
      body  <- IO.fromEither(timed.value.decodeAs[GetGoalBody].leftMap(new RuntimeException(_)))
      _     <- record(ctx, timed, Some(body.elapsedMs), None)
    } yield OracleAnswer(body, timed.value.text, timed.clientMs, cached = false)

  /** type_of on the interaction lane: the knowledge query behind the P1
    * binder counts (phase "type_of") and the candidate pre-filter (phase
    * "peek" — the ledger phase issue #122 adds).  Milliseconds once the lane
    * has the file loaded, so it is NOT memoised: a memo would hide the lane
    * reload cost the peek experiment must measure.  A reply-level failure
    * (isError — e.g. a dead lane) degrades to a Left rather than aborting the
    * sweep, because these calls inform proposals and peeks only; a Left never
    * rejects a candidate and never decides anything.
    */
  def typeOf(ctx: CallCtx, file: Path, expr: String, pos: Option[(Int, Int)]): IO[OracleAnswer[Either[String, TypeOfBody]]] =
    for {
      timed <- client.callTool("type_of", Json.obj(
                 (Vector(
                   "filePath" -> file.toString.asJson,
                   "expr"     -> expr.asJson
                 ) ++ pos.toVector.flatMap { case (l, c) =>
                   Vector("line" -> l.asJson, "column" -> c.asJson)
                 }): _*))
      body  <- if (timed.value.isError)
                 IO.pure(Left(timed.value.text.take(400)): Either[String, TypeOfBody])
               else
                 // Wire drift on a normal reply still raises (strict decoders):
                 // a drifted shape is an anomaly, not a rejected candidate.
                 IO.fromEither(timed.value.decodeAs[TypeOfBody].leftMap(new RuntimeException(_)))
                   .map(b => Right(b): Either[String, TypeOfBody])
      _     <- record(ctx, timed, body.toOption.map(_.elapsedMs), None)
    } yield OracleAnswer(body, timed.value.text, timed.clientMs, cached = false)

  /** The memo's answer for a probe, when it already holds one — the same
    * cached ledger row and zero-cost semantics as a memo hit inside `probe`,
    * without ever risking an Agda call.  Exists as its own door so the P1
    * loop can honor "memo hits are free" even at the probe budget's cap: a
    * replay must never be refused for budget only a real call would spend
    * (Copilot round 1 on PR #126).  `probe` itself answers hits through
    * this same path, so the two can never drift.
    */
  def cachedProbe(ctx: CallCtx, contentFp: String, ob: Obligation, candidate: String): IO[Option[OracleAnswer[ProbeOutcome]]] =
    memo.get.flatMap(_.get(OracleKey(contentFp, ob.line, ob.col, candidate)) match {
      case Some(hit) =>
        // A hit spends no oracle time; the ledger row says so explicitly.
        timings.update(_ :+ TimingRow(ctx.pass, ctx.fixtureId, ctx.phase, ctx.rank,
          clientMs = 0.0, serverElapsedMs = None, overheadMs = None, checkedFromSource = None, cached = true))
          .as(Option(hit.copy(clientMs = 0.0, cached = true)))
      case None => IO.pure(Option.empty[OracleAnswer[ProbeOutcome]])
    })

  /** fill_hole as a probe: memoised on (content, hole, candidate).  The server
    * restores the file whatever the answer, so this never changes state; an
    * isError reply becomes a Crash outcome rather than aborting the run.
    */
  def probe(ctx: CallCtx, file: Path, contentFp: String, ob: Obligation, candidate: String): IO[OracleAnswer[ProbeOutcome]] = {
    val key = OracleKey(contentFp, ob.line, ob.col, candidate)
    cachedProbe(ctx, contentFp, ob, candidate).flatMap {
      case Some(hit) => IO.pure(hit)
      case None =>
        for {
          timed  <- client.callTool("fill_hole", Json.obj(
                      "filePath"  -> file.toString.asJson,
                      "line"      -> ob.line.asJson,
                      "column"    -> ob.col.asJson,
                      "candidate" -> candidate.asJson))
          // Decode exactly once; a strict-decoder failure on a normal reply is
          // wire drift and raises, which the harness records as an anomaly.
          decoded <- if (timed.value.isError) IO.pure(Option.empty[FillHoleBody])
                     else IO.fromEither(timed.value.decodeAs[FillHoleBody].leftMap(new RuntimeException(_))).map(Option(_))
          answer  = decoded match {
                      case Some(b) => OracleAnswer(b.toOutcome, timed.value.text, timed.clientMs, cached = false)
                      case None    => OracleAnswer(
                        ProbeOutcome(candidate, ProbeStatus.Crash, Vector.empty, Some(timed.value.text.take(400))),
                        timed.value.text, timed.clientMs, cached = false)
                    }
          _      <- record(ctx, timed, decoded.map(_.elapsedMs), decoded.flatMap(_.checkedFromSource))
          _      <- memo.update(_ + (key -> answer))
        } yield answer
    }
  }

  /** The candidateRank / rc pair the eval-schema rows want, without re-parsing
    * at the call site: fill_hole's verdict exit code when the reply had one.
    */
  def exitCodeOf(raw: String): Option[Int] =
    io.circe.parser.parse(raw).toOption
      .flatMap(_.hcursor.downField("verdict").downField("exitCode").as[Option[Int]].toOption)
      .flatten

  private def record(ctx: CallCtx, timed: Timed[ToolReply], serverMs: Option[Long], cfs: Option[Boolean]): IO[Unit] =
    timings.update(_ :+ TimingRow(
      pass              = ctx.pass,
      fixtureId         = ctx.fixtureId,
      phase             = ctx.phase,
      candidateRank     = ctx.rank,
      clientMs          = timed.clientMs,
      serverElapsedMs   = serverMs,
      overheadMs        = serverMs.map(s => timed.clientMs - s.toDouble),
      checkedFromSource = cfs,
      cached            = false
    ))

  /** Record proposal time (client-side candidate generation) in the same
    * ledger, so the split is read from one place.
    */
  def recordProposal(ctx: CallCtx, nanos: Long): IO[Unit] =
    timings.update(_ :+ TimingRow(ctx.pass, ctx.fixtureId, "proposal", None,
      clientMs = nanos / 1e6, serverElapsedMs = None, overheadMs = None, checkedFromSource = None, cached = false))
}

object Oracle {
  def create(client: ToolCaller): IO[Oracle] =
    for {
      memo <- Ref.of[IO, Map[OracleKey, OracleAnswer[ProbeOutcome]]](Map.empty)
      tim  <- Ref.of[IO, Vector[TimingRow]](Vector.empty)
    } yield new Oracle(client, memo, tim)
}

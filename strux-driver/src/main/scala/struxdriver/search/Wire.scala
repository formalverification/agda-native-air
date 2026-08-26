/** ============================================================================
  *  Wire.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/search/Wire.scala
  *  Package: struxdriver.search
  *
  *  Purpose
  *  -------
  *  The agda-mcp wire shapes the search consumes, as circe decoders: the
  *  JSON-RPC envelope (whose tool payload is a JSON document INSIDE the
  *  `content[0].text` string — double-encoded, so unwrapping takes two parses)
  *  and the bodies of check_file, get_goal, fill_hole, and type_of.
  *
  *  Design notes
  *  ------------
  *  - Decoders read only the fields the search needs and tolerate everything
  *    else, so server-side response enrichment cannot break the client.
  *  - A failing tool call arrives as `result.isError == true` with content that
  *    is EITHER prose or a JSON object (the skill note: branch, don't assume);
  *    `ToolReply` preserves the raw text for both cases and logging.
  *  - Every decoder is pinned in WireSpec against responses captured verbatim
  *    from the live server (strux-driver/src/test/resources/search/wire-*.json),
  *    per the driving-agda-mcp discipline: verify shapes on the wire, not from
  *    the Haskell.
  *
  *  Integration
  *  -----------
  *  Used by McpClient.scala (envelope) and Oracle.scala (bodies).
  *
  *  ============================================================================
  */
package struxdriver.search

import io.circe.{Decoder, DecodingFailure, HCursor, Json}
import io.circe.parser.{parse => parseJson}

/** One hole as the server lists it (`[{index, line, col, goal}]`), the
  * re-anchored shape every proof-state response carries (issue #79).
  */
final case class WireHole(index: Int, line: Int, col: Int, goal: String)
object WireHole {
  implicit val decoder: Decoder[WireHole] = (c: HCursor) =>
    for {
      index <- c.get[Int]("index")
      line  <- c.get[Int]("line")
      col   <- c.get[Int]("col")
      goal  <- c.getOrElse[String]("goal")("?")
    } yield WireHole(index, line, col, goal)

  def toObligation(h: WireHole): Obligation = Obligation(h.line, h.col, h.goal)
}

/** check_file, reduced to what the search reads: the exit-code-derived verdict
  * (`success`), the hole list, and the measurements.  `holes`, `holesCount`,
  * and `elapsedMs` are REQUIRED: the hole list is the obligation set and the
  * elapsed time is the measurement, so a response missing either is wire
  * drift that must fail loudly, never default silently (a defaulted-empty
  * hole list would read as "no obligations").  The count is cross-checked
  * against the list for the same reason.
  */
final case class CheckFileBody(
  success:           Boolean,
  holes:             Vector[WireHole],
  holesCount:        Int,
  timedOut:          Boolean,
  elapsedMs:         Long,
  checkedFromSource: Option[Boolean],
  exitCode:          Option[Int]
)
object CheckFileBody {
  implicit val decoder: Decoder[CheckFileBody] = (c: HCursor) =>
    for {
      success  <- c.get[Boolean]("success")
      holes    <- c.get[Vector[WireHole]]("holes")
      count    <- c.get[Int]("holesCount")
      _        <- Either.cond(count == holes.size, (),
                    DecodingFailure(s"check_file drift: holesCount $count but ${holes.size} holes listed", c.history))
      timedOut <- c.getOrElse[Boolean]("timedOut")(false)
      elapsed  <- c.get[Long]("elapsedMs")
      cfs      <- c.get[Option[Boolean]]("checkedFromSource")
      exit     <- c.downField("verdict").downField("exitCode").as[Option[Int]]
    } yield CheckFileBody(success, holes, count, timedOut, elapsed, cfs, exit)
}

/** One local-context entry as get_goal reports it.  The lane path carries
  * `{name, type}` only; the injected-macro path adds `visibility` and `index`
  * (agda-mcp/README.md), so those stay optional while name and type — the
  * fields the P1 assumption proposals read — are required.
  */
final case class CtxEntry(name: String, tpe: String, visibility: Option[String])
object CtxEntry {
  implicit val decoder: Decoder[CtxEntry] = (c: HCursor) =>
    for {
      name <- c.get[String]("name")
      tpe  <- c.get[String]("type")
      vis  <- c.get[Option[String]]("visibility")
    } yield CtxEntry(name, tpe, vis)
}

/** get_goal, reduced to what the search reads: the goal type, the local
  * context (the P1 assumption candidates), the module name Agda resolved, and
  * which lane answered (`interaction-lane` vs `injected-macro`, issue #108).
  * `context` is REQUIRED: both server paths serialize it unconditionally
  * (AgdaMCP.Types.GoalInfo), so an absent list is wire drift, and a
  * silently-defaulted empty one would starve the action space of every
  * assumption without a visible failure.
  */
final case class GetGoalBody(
  goal:      String,
  context:   Vector[CtxEntry],
  module:    Option[String],
  source:    Option[String],
  elapsedMs: Long
)
object GetGoalBody {
  implicit val decoder: Decoder[GetGoalBody] = (c: HCursor) =>
    for {
      goal    <- c.get[String]("goal")
      ctx     <- c.get[Vector[CtxEntry]]("context")
      module  <- c.get[Option[String]]("module")
      source  <- c.get[Option[String]]("source")
      elapsed <- c.get[Long]("elapsedMs")
    } yield GetGoalBody(goal, ctx, module, source, elapsed)
}

/** type_of, the interaction-lane knowledge query the P1 proposer and peek
  * read (docs/agda-mcp-interaction-lane.md § 5).  Verified on the wire
  * (issue #122 probes, captures in test/resources/search/): a successful
  * inference carries `type` — with under-determined metas ANSWERED, printed
  * as named metas (`_x_9 ≡ _x_9`), never errored — while an expression Agda
  * rejects carries an in-body `error` object with `isError` still false
  * (NotInScope, CannotApply, UnequalTerms all arrive this way, in
  * milliseconds once the file is loaded).  Exactly one of the two must be
  * present; both or neither is drift.  These answers inform proposals and
  * peeks only — they never decide anything (only fill_hole judges).
  */
final case class TypeOfError(code: String, message: String)
object TypeOfError {
  implicit val decoder: Decoder[TypeOfError] = (c: HCursor) =>
    for {
      code <- c.get[String]("code")
      msg  <- c.get[String]("message")
    } yield TypeOfError(code, msg)
}

final case class TypeOfBody(
  inferred:  Option[String],
  error:     Option[TypeOfError],
  elapsedMs: Long
)
object TypeOfBody {
  implicit val decoder: Decoder[TypeOfBody] = (c: HCursor) =>
    for {
      tpe     <- c.get[Option[String]]("type")
      err     <- c.get[Option[TypeOfError]]("error")
      _       <- Either.cond(tpe.isDefined != err.isDefined, (),
                   DecodingFailure(
                     s"type_of drift: expected exactly one of type/error, got type=${tpe.isDefined} error=${err.isDefined}",
                     c.history))
      elapsed <- c.get[Long]("elapsedMs")
    } yield TypeOfBody(tpe, err, elapsed)
}

/** fill_hole, the oracle's judgement of one candidate.  `holes` describes the
  * file as the candidate would leave it; the file on disk is restored either
  * way, which is what makes every fill_hole a probe.
  */
final case class FillHoleBody(
  status:            String,
  candidate:         String,
  holes:             Vector[WireHole],
  remainingHoles:    Int,
  message:           Option[String],
  elapsedMs:         Long,
  checkedFromSource: Option[Boolean],
  exitCode:          Option[Int]
) {
  def toOutcome: ProbeOutcome =
    ProbeOutcome(candidate, ProbeStatus.parse(status), holes.map(WireHole.toObligation), message)
}
object FillHoleBody {
  /** `status`, `holes`, `remainingHoles`, and `elapsedMs` are REQUIRED, and
    * the count is cross-checked against the list: `holes` decides ranking and
    * `closesAll` (a silently-defaulted empty list would turn any Ok answer
    * into a closer), and `elapsedMs` feeds the timing split — wire drift on
    * either must fail the decode visibly, not bend the measurement.  Every
    * captured response carries them on every status, empty list included on
    * the type_error path (WireSpec pins this against the live captures).
    */
  implicit val decoder: Decoder[FillHoleBody] = (c: HCursor) =>
    for {
      status    <- c.get[String]("status")
      candidate <- c.getOrElse[String]("candidate")("")
      holes     <- c.get[Vector[WireHole]]("holes")
      remaining <- c.get[Int]("remainingHoles")
      _         <- Either.cond(remaining == holes.size, (),
                     DecodingFailure(s"fill_hole drift: remainingHoles $remaining but ${holes.size} holes listed", c.history))
      message   <- c.get[Option[String]]("message")
      elapsed   <- c.get[Long]("elapsedMs")
      cfs       <- c.get[Option[Boolean]]("checkedFromSource")
      exit      <- c.downField("verdict").downField("exitCode").as[Option[Int]]
    } yield FillHoleBody(status, candidate, holes, remaining, message, elapsed, cfs, exit)
}

/** A tool call's reply, unwrapped one level: `isError` from the result, and
  * the raw `content[0].text` (a JSON document for normal replies; prose or a
  * JSON object for errors).
  */
final case class ToolReply(isError: Boolean, text: String) {
  /** Second-level parse: the tool body as JSON, when it is JSON. */
  def bodyJson: Either[String, Json] = parseJson(text).left.map(_.message)

  def decodeAs[A: Decoder]: Either[String, A] =
    bodyJson.flatMap(_.as[A].left.map(_.getMessage))
}

object Wire {
  /** Unwrap one JSON-RPC response line for the given request id.  Lines with a
    * different id (or none — e.g. the server's own -32700 replies to garbage)
    * are not this call's answer; the client skips them, so this returns a
    * three-way answer: not-ours / protocol error / the reply.
    */
  sealed trait Envelope extends Product with Serializable
  object Envelope {
    case object NotOurs                          extends Envelope
    final case class ProtocolError(msg: String)  extends Envelope
    final case class Reply(reply: ToolReply)     extends Envelope
  }

  def envelope(line: String, expectId: Long): Envelope =
    parseJson(line) match {
      case Left(_) => Envelope.NotOurs // non-JSON noise on stdout is not ours to fail on
      case Right(json) =>
        val c = json.hcursor
        c.get[Long]("id").toOption match {
          case Some(id) if id == expectId =>
            c.downField("error").focus match {
              case Some(err) =>
                Envelope.ProtocolError(err.hcursor.get[String]("message").getOrElse(err.noSpaces))
              case None =>
                val res     = c.downField("result")
                val isError = res.get[Boolean]("isError").getOrElse(false)
                res.downField("content").downArray.get[String]("text") match {
                  case Right(text) => Envelope.Reply(ToolReply(isError, text))
                  case Left(_)     => Envelope.ProtocolError(s"response for id=$expectId has no content[0].text")
                }
            }
          case _ => Envelope.NotOurs
        }
    }
}

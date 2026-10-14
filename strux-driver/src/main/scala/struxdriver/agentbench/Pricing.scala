/** ============================================================================
  *  Pricing.scala
  *  ----------------------------------------------------------------------------
  *
  *  File: strux-driver/src/main/scala/struxdriver/agentbench/Pricing.scala
  *  Package: struxdriver.agentbench
  *
  *  Purpose
  *  -------
  *  A subject's cost priced from its own tokens at a table the run names
  *  (issue #237), kept beside the client's figure (`costUsd`) rather than in
  *  place of it.  The client's figure is its own arithmetic at Anthropic's
  *  list prices, which is not another provider's bill: for a model it has no
  *  price for, it prices the tokens at a fallback rate and says so
  *  (`costBasis: "unknown"`).  The priced figure is the one an arm on another
  *  endpoint quotes, beside the provider's usage page.
  *
  *  Design notes
  *  ------------
  *  - A subject is priced per model, from the result record's `modelUsage`,
  *    which every model the session called feeds; the `usage` block (the
  *    report's `tokens`) counts only the main loop's calls, and can miss one.
  *    The difference is measured on the archive: at Anthropic's list prices
  *    the `modelUsage` figure equals the client's on all 1,263 archived
  *    subjects in 57 runs, while the `usage` figure falls short on 336 of them
  *    in 10 runs (client 2.1.261 made one Haiku call of about USD 0.0011 per
  *    session beside the subject's model, and one subject's `usage` omits a
  *    call its `modelUsage` counts).  So `usage` is never priced: a row with
  *    no result record (a wall-cap kill, a crash) or no `modelUsage` is
  *    unpriced, with the reason, since the provider bills it all the same.
  *  - A model is found by its own id, then by the `canonicalModel` the client
  *    reports beside it, which the client names its own pricing key (so the
  *    archive's `claude-haiku-4-5-20251001` is the row `claude-haiku-4-5`);
  *    the row that priced each model is recorded beside it (`pricedAs`).
  *  - A model that spent tokens and has no row leaves its subject unpriced:
  *    `None`, with the model named, never a zero that reads as free.  A
  *    slice of rows sums the rows that have a figure and counts the rest
  *    (`unpricedRows`): with any unpriced row the sum is a lower bound, and
  *    says so.
  *  - The table is flat per token class: input (uncached), cache write,
  *    cache read, output, in USD per million tokens, with one cache-write
  *    rate, which for Anthropic is the one-hour write (twice the input
  *    price), the write the client asks for.  The client's own arithmetic
  *    also knows five-minute writes, a 1.1 multiplier for
  *    `inference_geo: "us"`, web searches, and fast mode; no archived subject
  *    has any of them, which is why the archive pins the table to the cent,
  *    and a row that has one carries a caveat naming it (`caveats`).
  *  - A Codex subject (issue #239) reports no cost of its own (`costUsd`
  *    None, `costBasis` "none"), so the priced figure is its only one.  Its
  *    counts come from its adapter in the same four classes, the reasoning
  *    tokens inside output (OpenAI bills them as output, and they are never
  *    added a second time); the ChatGPT backend reports cache writes as 0,
  *    so written tokens are priced as uncached input, at most 20 % under
  *    OpenAI's write price.
  *  - Strict parsing: a row carries exactly the four prices, each a number no
  *    smaller than 0, so a misspelled or missing price refuses the table at
  *    start instead of pricing a run wrongly.  Amounts are BigDecimal, so a
  *    priced figure is exact and prints as a decimal.
  *
  *  ============================================================================
  */
package struxdriver.agentbench

import cats.effect.IO
import cats.syntax.all._
import io.circe.{Json, JsonObject}
import io.circe.syntax._
import java.nio.file.Path

import struxdriver.io.TextIO
import struxdriver.search.Digest

/** Token counts, in the shape of the report's `tokens`. */
final case class Tokens(input: Long, output: Long, cacheRead: Long, cacheCreation: Long) {
  def +(o: Tokens): Tokens = Tokens(input + o.input, output + o.output, cacheRead + o.cacheRead, cacheCreation + o.cacheCreation)
  def isZero: Boolean      = input == 0 && output == 0 && cacheRead == 0 && cacheCreation == 0
  def fields: Vector[(String, Json)] = Vector(
    "input"         -> Json.fromLong(input),
    "output"        -> Json.fromLong(output),
    "cacheRead"     -> Json.fromLong(cacheRead),
    "cacheCreation" -> Json.fromLong(cacheCreation)
  )
  def toJson: Json = Json.fromFields(fields)
}

object Tokens {
  val zero: Tokens = Tokens(0, 0, 0, 0)

  /** The report's `tokens` block; a count it lacks is 0, as in `ResultRecord.tokens`. */
  def fromJson(j: Json): Tokens = {
    def n(k: String): Long = j.hcursor.get[Long](k).getOrElse(0L)
    Tokens(n("input"), n("output"), n("cacheRead"), n("cacheCreation"))
  }
}

/** What one model spent in one session, as the client reports it: the token
  * counts, its own figure for them, and the pricing facts it sends beside
  * them (the id it priced by, the provider that served the model, and which
  * of its price tables it used: `list`, `managed`, or `unknown`).
  */
final case class ModelUsage(
  model:     String,
  tokens:    Tokens,
  costUsd:   Option[Double],
  canonical: Option[String],
  provider:  Option[String],
  costBasis: Option[String]
) {
  /** The counts first, then the client's figure and pricing facts it sent. */
  def fields: Vector[(String, Json)] = tokens.fields ++ Vector(
    "costUsd"        -> costUsd.asJson,
    "canonicalModel" -> canonical.asJson,
    "provider"       -> provider.asJson,
    "costBasis"      -> costBasis.asJson
  ).filterNot(_._2.isNull)
  def toJson: Json = Json.fromFields(fields)
}

object ModelUsage {

  /** The price basis of a client that reports no cost at all (a Codex
    * subject, issue #239), as its derived transcript names it.
    */
  val noFigure: String = "none"

  /** One entry of the client's `modelUsage` object, keyed by `model`.  A
    * missing figure reads 0, as every archived entry did, unless the
    * entry's basis says the client reports none.
    */
  def fromClient(model: String, j: Json): ModelUsage = {
    val c = j.hcursor
    def n(k: String): Long = c.get[Long](k).getOrElse(0L)
    val basis = c.get[String]("costBasis").toOption
    ModelUsage(
      model     = model,
      tokens    = Tokens(n("inputTokens"), n("outputTokens"), n("cacheReadInputTokens"), n("cacheCreationInputTokens")),
      costUsd   = c.get[Double]("costUSD").toOption.orElse(if (basis.contains(noFigure)) None else Some(0.0)),
      canonical = c.get[String]("canonicalModel").toOption,
      provider  = c.get[String]("provider").toOption,
      costBasis = basis)
  }

  /** Two sessions' usage of the same models, summed per model, in
    * first-seen order; the client's figure is None when no session of the
    * model had one.
    */
  def totals(us: Vector[ModelUsage]): Vector[(String, Tokens, Option[Double])] =
    us.map(_.model).distinct.map { m =>
      val mine = us.filter(_.model == m)
      val figs = mine.flatMap(_.costUsd)
      (m, mine.map(_.tokens).foldLeft(Tokens.zero)(_ + _), if (figs.isEmpty) None else Some(figs.sum))
    }
}

/** One row of a price table, in USD per million tokens. */
final case class ModelPrice(input: BigDecimal, cacheWrite: BigDecimal, cacheRead: BigDecimal, output: BigDecimal) {
  def toJson: Json = Json.obj(
    "input" -> input.asJson, "cacheWrite" -> cacheWrite.asJson, "cacheRead" -> cacheRead.asJson, "output" -> output.asJson)
  def cost(t: Tokens): BigDecimal =
    (BigDecimal(t.input) * input + BigDecimal(t.cacheCreation) * cacheWrite +
      BigDecimal(t.cacheRead) * cacheRead + BigDecimal(t.output) * output) / Pricing.perMillion
}

/** A subject's priced cost, or why it has none (and the models without a
  * row, when that is why); and the table row that priced each model.
  */
final case class Priced(usd: Option[BigDecimal], unpriced: Option[String], models: Vector[String], pricedAs: Map[String, String]) {
  def isPriced: Boolean = usd.isDefined
}

object Priced {
  /** A row whose subject never spawned: it spent nothing. */
  val nothing: Priced = Priced(Some(BigDecimal(0)), None, Vector.empty, Map.empty)

  /** A row the harness could not price, and why. */
  def unread(why: String): Priced = Priced(None, Some(why), Vector.empty, Map.empty)

  /** A slice's priced figure: the sum over its priced rows, and how many rows had none. */
  final case class Total(usd: BigDecimal, unpricedRows: Int)

  def total(ps: Vector[Priced]): Total = Total(ps.flatMap(_.usd).sum, ps.count(!_.isPriced))
}

/** A price table as a run reads it: the file by path and content, the date
  * its prices were taken, and the rows.
  */
final case class PriceTable(path: Path, sha256: String, asOf: String, source: Option[String], models: Map[String, ModelPrice]) {

  /** The key of a model's row: its own id, then the id the client priced it
    * by, then the id without a trailing snapshot date, which is what the
    * client's canonical id drops (`claude-haiku-4-5-20251001`); the one rule
    * both before a run (`priceOfModelId`) and for every subject.
    */
  def rowOf(model: String, canonical: Option[String] = None): Option[String] =
    (Vector(model) ++ canonical.toVector :+ model.replaceAll("-[0-9]{8}$", "")).find(models.contains)

  def priceOf(model: String, canonical: Option[String] = None): Option[ModelPrice] =
    rowOf(model, canonical).flatMap(models.get)

  /** The row a `--model` id is priced at before any subject has run, by the
    * same rule as a subject's.
    */
  def priceOfModelId(id: String): Option[ModelPrice] = priceOf(id)

  /** One subject's usage priced: the sum over its models, or None naming
    * every model that spent tokens and has no row.
    */
  def price(usages: Vector[ModelUsage]): Priced = {
    val rows    = usages.map(u => u -> rowOf(u.model, u.canonical))
    val missing = rows.collect { case (u, None) if !u.tokens.isZero => u.model }.distinct
    val as      = rows.collect { case (u, Some(r)) => u.model -> r }.toMap
    if (missing.nonEmpty) Priced(None, Some(s"no price for ${missing.mkString(", ")} in the table"), missing, as)
    else Priced(Some(rows.collect { case (u, Some(r)) => models(r).cost(u.tokens) }.sum), None, Vector.empty, as)
  }

  /** The table as a report names it: the file, its digest, its date, and
    * the rates of the rows that report used, so its priced figures can be
    * recomputed from the report alone, whatever table a later re-judge is
    * given.
    */
  def toJson(used: Vector[String]): Json = Json.fromFields(Vector(
    "path"   -> path.toString.asJson,
    "sha256" -> sha256.asJson,
    "asOf"   -> asOf.asJson) ++
    source.map(s => "source" -> s.asJson) ++
    Vector("rows" -> Json.obj(used.distinct.sorted.flatMap(r => models.get(r).map(p => r -> p.toJson)): _*)))
}

object Pricing {

  val schemaVersion: String   = "agent-bench-prices.v0"
  val perMillion: BigDecimal  = BigDecimal(1000000)

  private val tableKeys = Set("schemaVersion", "asOf", "source", "unit", "models")
  private val priceKeys = Vector("input", "cacheWrite", "cacheRead", "output")

  /** One row: exactly the four prices, each a number no smaller than 0. */
  private def rowOf(model: String, j: Json): Either[String, ModelPrice] =
    j.asObject.toRight(s"$model: not an object").flatMap { o =>
      val extra   = o.keys.toVector.filterNot(priceKeys.contains)
      val missing = priceKeys.filterNot(o.contains)
      if (extra.nonEmpty) Left(s"$model: unknown field(s) ${extra.mkString(", ")} (a row is exactly ${priceKeys.mkString(", ")})")
      else if (missing.nonEmpty) Left(s"$model: missing ${missing.mkString(", ")}")
      else {
        val values = priceKeys.map(k => k -> o(k).flatMap(_.asNumber).flatMap(_.toBigDecimal))
        values.collectFirst { case (k, v) if !v.exists(_ >= 0) => k } match {
          case Some(k) => Left(s"$model: $k is not a number no smaller than 0")
          case None    =>
            val v = values.flatMap(_._2)
            Right(ModelPrice(input = v(0), cacheWrite = v(1), cacheRead = v(2), output = v(3)))
        }
      }
    }

  /** A table from its JSON, refused by name: the schema, a date, at least
    * one row, and every row strict.
    */
  def parse(j: Json, path: Path, sha256: String): Either[String, PriceTable] =
    for {
      top    <- j.asObject.toRight("not a JSON object")
      extra   = top.keys.toVector.filterNot(tableKeys.contains)
      _      <- Either.cond(extra.isEmpty, (), s"unknown field(s) ${extra.mkString(", ")}")
      schema <- top("schemaVersion").flatMap(_.asString).toRight("missing schemaVersion")
      _      <- Either.cond(schema == schemaVersion, (), s"schemaVersion $schema is not $schemaVersion")
      asOf   <- top("asOf").flatMap(_.asString).filter(_.trim.nonEmpty).toRight("missing asOf (the date the prices were taken)")
      models <- top("models").flatMap(_.asObject).toRight("missing models")
      _      <- Either.cond(models.nonEmpty, (), "models names no model")
      rows   <- models.toVector.foldLeft[Either[String, Vector[(String, ModelPrice)]]](Right(Vector.empty)) {
                  case (acc, (m, row)) => acc.flatMap(rs => rowOf(m, row).map(p => rs :+ (m -> p)))
                }
    } yield PriceTable(path, sha256, asOf, top("source").flatMap(_.asString), rows.toMap)

  /** Read a table, identified by content as the protocol's inputs are; a
    * table that does not parse fails the run at start, naming the file.
    */
  def load(path: Path): IO[PriceTable] =
    for {
      text  <- TextIO.read(path).adaptError { case e => new RuntimeException(s"no price table at $path: ${e.getMessage}") }
      sha   <- Digest.sha256Hex(path)
      json  <- IO.fromEither(io.circe.parser.parse(text).left.map(e => new RuntimeException(s"price table $path is not JSON: ${e.getMessage}")))
      table <- IO.fromEither(parse(json, path, sha).left.map(e => new RuntimeException(s"price table $path refused: $e")))
    } yield table

  /** A subject's priced cost from its result record: unpriced, with the
    * reason, when there is none (a wall-cap kill or a crash) or it carries
    * no `modelUsage`; else its models priced at the table.
    */
  def ofResult(result: Option[ResultRecord], prices: PriceTable): Priced =
    result match {
      case None                            => Priced.unread("no result record: the subject was killed or crashed, and the client reported nothing")
      case Some(r) if r.modelUsage.isEmpty => Priced.unread("the client reported no modelUsage")
      case Some(r)                         => prices.price(r.modelUsage)
    }

  /** A USD amount as the report's slices carry one: to the tenth of a cent, half up. */
  def round3(d: BigDecimal): BigDecimal = d.setScale(3, BigDecimal.RoundingMode.HALF_UP)

  /** The JSON object of a model-to-usage map, in first-seen order, each
    * model with the table row that priced it (null when none did).
    */
  def byModelJson(us: Vector[ModelUsage], pricedAs: Map[String, String]): Json =
    Json.fromJsonObject(JsonObject.fromIterable(us.map(u => u.model -> Json.fromFields(u.fields :+ ("pricedAs" -> pricedAs.get(u.model).asJson)))))

  /** What a result record's `usage` block says the flat table cannot price
    * exactly, in the client's own terms: five-minute cache writes (the table
    * has the one-hour rate), the 1.1 multiplier for `inference_geo: "us"`,
    * web searches, and fast mode.  Empty on every archived subject.
    */
  def caveats(usage: Json): Vector[String] = {
    val c = usage.hcursor
    Vector(
      c.downField("cache_creation").get[Long]("ephemeral_5m_input_tokens").toOption.filter(_ > 0)
        .map(n => s"$n five-minute cache-write tokens, priced at the one-hour rate"),
      c.get[String]("inference_geo").toOption.filter(_ == "us").map(_ => "inference_geo us, which the client prices at 1.1 times the rate"),
      c.downField("server_tool_use").get[Long]("web_search_requests").toOption.filter(_ > 0).map(n => s"$n web searches, not priced"),
      c.get[String]("speed").toOption.filter(_ == "fast").map(_ => "fast mode, priced at the standard rate"),
      // A Codex subject's usage (issue #239): OpenAI prices a response over
      // 272K input tokens, and a tier other than the standard one, higher.
      c.get[Long]("long_context_responses").toOption.filter(_ > 0)
        .map(n => s"$n responses over 272K input tokens, priced at the short-context rate"),
      c.get[String]("service_tier").toOption.filterNot(t => t == "standard" || t == "default" || t == "auto")
        .map(t => s"service tier $t, priced at the standard rate")
    ).flatten
  }
}

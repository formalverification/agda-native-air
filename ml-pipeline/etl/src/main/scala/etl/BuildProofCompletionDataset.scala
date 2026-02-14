/**
 * BuildProofCompletionDataset.scala
 *
 * File: agda-ai-prover/ml-pipeline/etl/src/main/scala/etl/BuildProofCompletionDataset.scala
 *
 * Purpose
 * -------
 *   Build a deterministic proof-completion-style dataset from the canonical Agda backend JSONL.
 *
 * Context in the project
 * ----------------------
 *   Upstream proof-parser extractor (AgdaJsonlDriver + agda-json backend) produces
 *   JSONL rows:
 *
 *   file, module, name, qname, prettyQname, type, typeAstVersion, typeAst, body, hasBody, ...
 *
 *   This tool turns those definition rows into "(goal, context) -> target" training rows,
 *   with a deliberately minimal resolver:
 *
 *     1.  keep targetRaw == extracted body (exactly),
 *     2.  if body matches ^@\\d+$, resolve via the Π-binder list from typeAst,
 *         taking care with de Bruijn direction (innermost binder = @0),
 *     3.  otherwise, do one tiny normalization step: drop anonymous-module segments
 *         "_" in dotted names, but keep a boolean feature indicating we saw one,
 *     4.  compute a cheap "head symbol" feature from targetRaw (e.g. REL from
 *         "REL @1 @1 @0", proj₁ from "proj₁ p"), without changing targetRaw/target.
 *
 * Output (JSONL)
 * --------------
 *   Each output row has the following stable keys:
 *
 *     - schemaVersion: "proof-completion.v0"
 *     - sourcePrettyQname
 *     - sourceFile
 *     - type (raw type string, mostly for debugging)
 *     - goal (codomain from the type string, best-effort)
 *     - context: array of {name, type, hiding}
 *     - targetRaw: the extracted "body" exactly
 *     - target: resolved/normalized target when possible, else == targetRaw
 *     - targetResolver: one of "atIndex" | "anonModuleNormalize" | "raw"
 *     - targetResolved: boolean (true iff @i resolved)
 *     - targetHadAnonModule: boolean (true iff targetRaw contained a "._." segment)
 *     - targetHead: optional head symbol from targetRaw
 *
 * Determinism / CI-friendliness
 * -----------------------------
 *   - Streaming read/write (does not load the whole corpus).
 *   - Deterministic: reads input in order and stops after --limit emitted rows.
 *   - Default filter: only “simple” bodies (no whitespace) to keep v0 targets term-like.
 *
 * Usage
 * -----
 *   From repo root (example):
 *
 *     sbt "project etl" "runMain etl.BuildProofCompletionDataset \
 *        --in  /abs/path/to/combined.jsonl \
 *        --out /abs/path/to/out/proof_completion.jsonl \
 *        --limit 200 \
 *        --strict"
 *
 * Notes on de Bruijn direction
 * ----------------------------
 *   Agda de Bruijn indices count from the innermost binder:
 *     @0 = most recently introduced binder (innermost)
 *     @1 = next-outer binder, ...
 *
 *   The Π-binders in typeAst are naturally encountered outermost -> innermost.
 *   If we collect binder names as:
 *     bindersOuterToInner = Vector(b0, b1, ..., b(n-1))
 *   then:
 *     @i resolves to bindersOuterToInner(n - 1 - i).
 */
package etl

import com.fasterxml.jackson.databind.{JsonNode, ObjectMapper}

import java.io.{BufferedWriter, File}
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Path, Paths}
import scala.annotation.tailrec
import scala.util.Try

object BuildProofCompletionDataset {

  // ---------------------------------------------------------------------------
  // Output schema version
  // ---------------------------------------------------------------------------
  private val SchemaVersion: String = "proof-completion.v0"

  // ---------------------------------------------------------------------------
  // Config + tiny error model
  // ---------------------------------------------------------------------------

  final case class Config(
    inJsonl: Path,
    outJsonl: Path,
    limit: Int,
    simpleOnly: Boolean,
    strict: Boolean
  )

  sealed trait BuildError {
    def message: String
  }
  final case class ArgError(message: String) extends BuildError
  final case class IoError(message: String, cause: Throwable) extends BuildError
  final case class JsonError(message: String, cause: Throwable) extends BuildError

  // ---------------------------------------------------------------------------
  // Minimal data models (kept small on purpose)
  // ---------------------------------------------------------------------------

  final case class BinderHint(nameHint: Option[String], hiding: String)
  final case class CtxEntry(name: String, `type`: String, hiding: String)

  final case class InputRow(
    sourceFile: String,
    sourcePrettyQname: String,
    typeStr: String,
    typeAstVersion: Option[String],
    typeAstJson: Option[String],
    body: String,
    hasBody: Boolean
  )

  final case class OutputRow(
    schemaVersion: String,
    sourcePrettyQname: String,
    sourceFile: String,
    `type`: String,
    goal: String,
    context: Vector[CtxEntry],
    targetRaw: String,
    target: String,
    targetResolver: String,
    targetResolved: Boolean,
    targetHadAnonModule: Boolean,
    targetHead: Option[String]
  )

  // ---------------------------------------------------------------------------
  // JSON helpers (no extra deps; Spark already brings Jackson)
  // ---------------------------------------------------------------------------

  private val mapper: ObjectMapper = new ObjectMapper()

  private def optText(n: JsonNode, k: String): Option[String] = {
    val v = n.get(k)
    if (v == null || v.isNull) None
    else {
      val s = v.asText()
      if (s == null) None else Option(s).map(_.trim).filter(_.nonEmpty)
    }
  }

  private def boolValue(n: JsonNode, k: String): Boolean = {
    val v = n.get(k)
    if (v == null || v.isNull) false else v.asBoolean(false)
  }

  private def optTypeAstJson(n: JsonNode): Option[String] = {
    // Accept either:
    //   - "typeAstJson": "<json-string>"  (post-ETL style)
    //   - "typeAst": { ... }            (backend full JSONL style)
    optText(n, "typeAstJson")
      .orElse {
        val v = n.get("typeAst")
        if (v == null || v.isNull) None
        else Option(v.toString).map(_.trim).filter(_.nonEmpty)
      }
  }

  private def parseInputRow(line: String): Either[BuildError, InputRow] = {
    Try(mapper.readTree(line)).toEither.left.map(e => JsonError(s"Invalid JSONL row (parse failed).", e)).flatMap { n =>
      val file = optText(n, "file").getOrElse("")
      val pq   = optText(n, "prettyQname").orElse(optText(n, "prettyQName")).getOrElse("") // tiny back-compat
      val ty   = optText(n, "type").getOrElse("")
      val body = optText(n, "body").getOrElse("")
      val hb   = boolValue(n, "hasBody")
      val tav  = optText(n, "typeAstVersion")
      val taj  = optTypeAstJson(n)

      Right(
        InputRow(
          sourceFile = file,
          sourcePrettyQname = pq,
          typeStr = ty,
          typeAstVersion = tav,
          typeAstJson = taj,
          body = body,
          hasBody = hb
        )
      )
    }
  }

  // Serialize OutputRow deterministically (stable key order) using LinkedHashMap
  private def toJsonLine(r: OutputRow): String = {
    val root = new java.util.LinkedHashMap[String, Any]()
    root.put("schemaVersion", r.schemaVersion)
    root.put("sourcePrettyQname", r.sourcePrettyQname)
    root.put("sourceFile", r.sourceFile)
    root.put("type", r.`type`)
    root.put("goal", r.goal)
    val ctx = new java.util.ArrayList[Any]()
    r.context.foreach { e =>
      val m = new java.util.LinkedHashMap[String, Any]()
      m.put("name", e.name)
      m.put("type", e.`type`)
      m.put("hiding", e.hiding)
      ctx.add(m)
    }
    root.put("context", ctx)
    root.put("targetRaw", r.targetRaw)
    root.put("target", r.target)
    root.put("targetResolver", r.targetResolver)
    root.put("targetResolved", java.lang.Boolean.valueOf(r.targetResolved))
    root.put("targetHadAnonModule", java.lang.Boolean.valueOf(r.targetHadAnonModule))
    root.put("targetHead", r.targetHead.orNull)
    mapper.writeValueAsString(root)
  }

  // ---------------------------------------------------------------------------
  // 1) Collect Π-binders from typeAst (outermost -> innermost)
  // ---------------------------------------------------------------------------

  private def isTag(n: JsonNode, tag: String): Boolean =
    n != null && !n.isNull && n.has("tag") && tag == n.get("tag").asText("")

  // typeAst nodes wrap term nodes in { sort, tag:"Type", term:<...> }.
  // We want to peel "Type" wrappers when descending to the Π-chain.
  private def unwrapTypeNode(n: JsonNode): JsonNode =
    if (n != null && !n.isNull && isTag(n, "Type") && n.has("term")) n.get("term") else n

  private def collectPiBindersOuterToInner(typeAstJson: String): Either[BuildError, Vector[BinderHint]] = {
    Try(mapper.readTree(typeAstJson)).toEither.left.map(e => JsonError("typeAst JSON parse failed.", e)).map { root =>
      val start = {
        // root is expected to be a "Type" node with a "term"
        val t = root.get("term")
        if (t == null || t.isNull) root else t
      }

      @tailrec
      def loop(term: JsonNode, acc: Vector[BinderHint]): Vector[BinderHint] = {
        if (term == null || term.isNull) acc
        else if (!isTag(term, "Pi")) acc
        else {
          val b = term.get("binder")
          val hiding =
            if (b != null && !b.isNull && b.has("hiding")) b.get("hiding").asText("explicit")
            else "explicit"

          val nameHint =
            if (b != null && !b.isNull && b.has("nameHint") && !b.get("nameHint").isNull) {
              val s = b.get("nameHint").asText("")
              Option(s).map(_.trim).filter(_.nonEmpty)
            } else None

          // cod is itself a Type node; unwrap to its term
          val next = unwrapTypeNode(term.get("cod"))
          loop(next, acc :+ BinderHint(nameHint = nameHint, hiding = hiding))
        }
      }

      loop(start, Vector.empty)
    }
  }

  /**
   * Assign stable binder names to the Π-binders.
   *
   * - Prefer nameHint when present.
   * - Otherwise generate:
   *     implicit  -> i<dbIndex>
   *     explicit  -> x<dbIndex>
   *
   * IMPORTANT: dbIndex counts from innermost binder:
   *   - innermost binder has dbIndex 0
   *   - next outer has dbIndex 1
   *   - ...
   *
   * Our binders are ordered outer->inner, so dbIndex = (n - 1 - position).
   */
  private def assignBinderNamesOuterToInner(bindersOuterToInner: Vector[BinderHint]): Vector[String] = {
    val n = bindersOuterToInner.size
    bindersOuterToInner.zipWithIndex.map { case (b, pos) =>
      val dbIndex = (n - 1 - pos)
      b.nameHint.getOrElse {
        val pref = if (b.hiding == "implicit") "i" else "x"
        s"$pref$dbIndex"
      }
    }
  }

  private def resolveAtIndex(body: String, binderNamesOuterToInner: Vector[String]): Option[String] = {
    // match ^@\d+$
    if (body == null) None
    else if (!body.startsWith("@")) None
    else {
      val digits = body.drop(1)
      if (digits.nonEmpty && digits.forall(_.isDigit)) {
        val i = Try(digits.toInt).toOption.getOrElse(-1)
        val n = binderNamesOuterToInner.size
        val pos = n - 1 - i
        if (i >= 0 && pos >= 0 && pos < n) Some(binderNamesOuterToInner(pos)) else None
      } else None
    }
  }

  // ---------------------------------------------------------------------------
  // 2) Parse the string type into (context, goal) (best-effort, v0)
  // ---------------------------------------------------------------------------

  /**
   * Split a string on top-level arrows (→ or ->), ignoring arrows nested in (), {}, [].
   * This is a minimal scanner; it’s not a full Agda pretty-printer.
   */
  private def splitTopLevelArrows(s: String): Vector[String] = {
    val buf = new StringBuilder()
    val out = Vector.newBuilder[String]

    @tailrec
    def loop(i: Int, depthParen: Int, depthBrace: Int, depthBracket: Int): Vector[String] = {
      if (i >= s.length) {
        out += buf.toString
        out.result()
      } else {
        val c = s.charAt(i)
        val (dp, db, dk) =
          c match {
            case '(' => (depthParen + 1, depthBrace, depthBracket)
            case ')' => (math.max(0, depthParen - 1), depthBrace, depthBracket)
            case '{' => (depthParen, depthBrace + 1, depthBracket)
            case '}' => (depthParen, math.max(0, depthBrace - 1), depthBracket)
            case '[' => (depthParen, depthBrace, depthBracket + 1)
            case ']' => (depthParen, depthBrace, math.max(0, depthBracket - 1))
            case _   => (depthParen, depthBrace, depthBracket)
          }

        val atTop = (dp == 0 && db == 0 && dk == 0)

        // Unicode arrow '→'
        if (atTop && c == '→') {
          out += buf.toString
          buf.clear()
          loop(i + 1, dp, db, dk)
        }
        // ASCII arrow '->'
        else if (atTop && c == '-' && (i + 1) < s.length && s.charAt(i + 1) == '>') {
          out += buf.toString
          buf.clear()
          loop(i + 2, dp, db, dk)
        }
        else {
          buf.append(c)
          loop(i + 1, dp, db, dk)
        }
      }
    }

    loop(0, 0, 0, 0).map(_.trim).filter(_.nonEmpty)
  }

  final case class TelescopeBinder(name: String, typ: String, hiding: String)

  /**
   * Parse a leading telescope of {..} and (..) binders from the front of a type string.
   *
   * Handles multiple names sharing a type:
   *   {a b c : Level}  =>  a:Level, b:Level, c:Level
   */
  private def parseLeadingTelescope(typeStr: String): (Vector[TelescopeBinder], String) = {
    val s = if (typeStr == null) "" else typeStr.trim

    def isOpen(c: Char): Boolean = (c == '{' || c == '(')
    def closeOf(c: Char): Char = if (c == '{') '}' else ')'
    def hidingOfOpen(c: Char): String = if (c == '{') "implicit" else "explicit"

    // Find the matching close for the binder block starting at position 0.
    def takeBalancedBlock(str: String): Option[(Char, String, String)] = {
      if (str.isEmpty) None
      else {
        val open = str.charAt(0)
        if (!isOpen(open)) None
        else {
          val close = closeOf(open)
          @tailrec
          def loop(i: Int, stack: List[Char]): Option[Int] = {
            if (i >= str.length) None
            else {
              val c = str.charAt(i)
              val stack2 =
                if (isOpen(c)) c :: stack
                else if (c == '}' || c == ')') stack match {
                  case h :: t if closeOf(h) == c => t
                  case other                      => other // malformed; keep going
                }
                else stack

              if (stack2.isEmpty) Some(i)
              else loop(i + 1, stack2)
            }
          }

          loop(1, List(open)).map { endIx =>
            val content = str.substring(1, endIx) // inside braces
            val rest = str.substring(endIx + 1)
            (open, content, rest)
          }
        }
      }
    }

    @tailrec
    def loop(rest: String, acc: Vector[TelescopeBinder]): (Vector[TelescopeBinder], String) = {
      val r = rest.dropWhile(_.isWhitespace)
      if (r.isEmpty) (acc, r)
      else {
        takeBalancedBlock(r) match {
          case None => (acc, r)
          case Some((open, content, after)) =>
            val hiding = hidingOfOpen(open)
            val parts = content.split(":", 2)
            if (parts.length != 2) loop(after, acc) // best-effort
            else {
              val namesPart = parts(0).trim
              val typPart = parts(1).trim
              val names = namesPart.split("\\s+").toVector.map(_.trim).filter(_.nonEmpty)
              val added = names.map(n => TelescopeBinder(name = n, typ = typPart, hiding = hiding))
              loop(after, acc ++ added)
            }
        }
      }
    }

    loop(s, Vector.empty)
  }

  /**
   * Build (context, goal) from the raw type string.
   *
   * Strategy (v0):
   *   1) parse leading telescope binders {x : T} / (x : T)
   *   2) split remaining on top-level arrows into domains + goal
   *   3) name anonymous arrow domains using binderNamesOuterToInner, aligned by position
   */
  private def typeToContextGoal(typeStr: String, binderNamesOuterToInner: Vector[String]): (Vector[CtxEntry], String) = {
    val (tel, rest0) = parseLeadingTelescope(typeStr)
    val arrowParts = splitTopLevelArrows(rest0.trim)

    val telCtx: Vector[CtxEntry] =
      tel.map(b => CtxEntry(name = b.name, `type` = b.typ, hiding = b.hiding))

    if (arrowParts.isEmpty) {
      // No arrows; treat the entire remainder as the goal.
      (telCtx, rest0.trim)
    } else {
      val domains = arrowParts.dropRight(1)
      val goal = arrowParts.last.trim

      // Align domain binders after the telescope. typeAst binder list should match.
      val offset = telCtx.size
      val domCtx =
        domains.zipWithIndex.map { case (dom, j) =>
          val name = binderNamesOuterToInner.lift(offset + j).getOrElse(s"x$j")
          CtxEntry(name = name, `type` = dom.trim, hiding = "explicit")
        }.toVector

      (telCtx ++ domCtx, goal)
    }
  }

  // ---------------------------------------------------------------------------
  // 3) next simplest resolver after @i: drop anonymous-module segments "_"
  // ---------------------------------------------------------------------------

  private def splitDottedSegments(s: String): Vector[String] =
    if (s == null) Vector.empty
    else s.split("\\.").toVector.map(_.trim).filter(_.nonEmpty)

  private def hasAnonModuleSegment(s: String): Boolean =
    splitDottedSegments(s).contains("_")

  private def normalizeAnonModuleSegments(s: String): String = {
    if (s == null) ""
    else if (!s.contains(".")) s.trim
    else {
      val parts = splitDottedSegments(s)
      val kept  = parts.filterNot(_ == "_")
      val norm  = kept.mkString(".")
      // avoid producing an empty identifier if input was "_" or similar
      if (norm.trim.nonEmpty) norm else s.trim
    }
  }

  // ---------------------------------------------------------------------------
  // 4) Cheap "head symbol" feature (does not change targetRaw/target)
  // ---------------------------------------------------------------------------

  /**
   * Extract a "head symbol" from the raw body.
   *
   * Examples:
   *   "REL @1 @1 @0"                       -> Some("REL")
   *   "proj₁ p"                            -> Some("proj₁")
   *   "properties.+-comm zero @0"          -> Some("properties.+-comm")
   *   "λ h₁ h₂ x y h₃ → h₂ x y (h₁ x y h₃)" -> Some("λ")
   *
   * Heuristic: take the first token up to whitespace or an opening delimiter.
   */
  private def extractHeadSymbol(raw: String): Option[String] = {
    val s = if (raw == null) "" else raw.trim
    if (s.isEmpty) None
    else {
      val stopIx =
        s.indexWhere(ch => ch.isWhitespace || ch == '(' || ch == '{' || ch == '[')
      val tok = if (stopIx < 0) s else s.substring(0, stopIx)
      Option(tok).map(_.trim).filter(_.nonEmpty)
    }
  }

  // ---------------------------------------------------------------------------
  // Row construction (pure-ish)
  // ---------------------------------------------------------------------------

  private def isSimpleBody(body: String): Boolean =
    body != null && body.trim.nonEmpty && !body.exists(_.isWhitespace)

  private def buildOutputRow(in: InputRow): Either[BuildError, OutputRow] = {
    val bodyTrim = if (in.body == null) "" else in.body.trim
    val typeTrim = if (in.typeStr == null) "" else in.typeStr.trim
    val headSym  = extractHeadSymbol(in.body)
    val hadAnon  = hasAnonModuleSegment(bodyTrim)

    // We want binder names for resolving @i; require typeAst for v0.
    in.typeAstJson match {
      case None =>
        Left(ArgError("Missing typeAst/typeAstJson (cannot resolve binders in v0)."))
      case Some(taj) =>
        collectPiBindersOuterToInner(taj).map { binders =>
          val binderNamesOuterToInner = assignBinderNamesOuterToInner(binders)
          val (ctx, goal) = typeToContextGoal(typeTrim, binderNamesOuterToInner)

          // Resolver pipeline:
          val at = resolveAtIndex(bodyTrim, binderNamesOuterToInner)
          val (target, resolver, resolved) =
            at match {
              case Some(x) => (x, "atIndex", true)
              case None =>
                val norm = normalizeAnonModuleSegments(bodyTrim)
                if (norm != bodyTrim) (norm, "anonModuleNormalize", false)
                else (bodyTrim, "raw", false)
            }

          OutputRow(
            schemaVersion = SchemaVersion,
            sourcePrettyQname = in.sourcePrettyQname,
            sourceFile = in.sourceFile,
            `type` = typeTrim,
            goal = goal,
            context = ctx,
            targetRaw = bodyTrim,
            target = target,
            targetResolver = resolver,
            targetResolved = resolved,
            targetHadAnonModule = hadAnon,
            targetHead = headSym
          )
        }
    }
  }

  // ---------------------------------------------------------------------------
  // Streaming build
  // ---------------------------------------------------------------------------

  final case class Stats(seen: Long, emitted: Long, skipped: Long, parseErrors: Long, firstParseError: Option[String])

  private def build(cfg: Config): Either[BuildError, Stats] = {
    val inFile = cfg.inJsonl.toFile
    if (!inFile.exists()) return Left(ArgError(s"--in does not exist: ${cfg.inJsonl}"))

    val parent = cfg.outJsonl.getParent
    if (parent != null) Files.createDirectories(parent)

    var src: scala.io.Source = null
    var out: BufferedWriter = null

    try {
      src = scala.io.Source.fromFile(inFile)(scala.io.Codec.UTF8)
      out = Files.newBufferedWriter(cfg.outJsonl, StandardCharsets.UTF_8)

      val it = src.getLines()

      @tailrec
      def loop(stats: Stats): Stats = {
        if (!it.hasNext) stats
        else if (stats.emitted >= cfg.limit) stats
        else {
          val line = it.next()
          val st1 = stats.copy(seen = stats.seen + 1)

          val nextStats: Stats =
            parseInputRow(line) match {
              case Left(e) =>
                val first =
                  st1.firstParseError.orElse {
                    val cause =
                      e match {
                        case JsonError(_, c) => Option(c.getMessage).getOrElse(c.toString)
                        case IoError(_, c)   => Option(c.getMessage).getOrElse(c.toString)
                        case _               => ""
                      }
                    val prefix = if (line.length <= 200) line else line.take(200) + "…"
                    Some(s"${e.message}${if (cause.nonEmpty) s" cause=$cause" else ""}\nlinePrefix=$prefix")
                  }
                st1.copy(parseErrors = st1.parseErrors + 1, skipped = st1.skipped + 1, firstParseError = first)

              case Right(in) =>
                val keepHasBody = in.hasBody && in.body != null && in.body.trim.nonEmpty
                val keepSimple  = if (cfg.simpleOnly) isSimpleBody(in.body) else true

                if (!keepHasBody || !keepSimple) st1.copy(skipped = st1.skipped + 1)
                else {
                  buildOutputRow(in) match {
                    case Left(_) =>
                      st1.copy(skipped = st1.skipped + 1)
                    case Right(row) =>
                      out.write(toJsonLine(row))
                      out.newLine()
                      st1.copy(emitted = st1.emitted + 1)
                  }
                }
            }

          loop(nextStats)
        }
      }

      Right(loop(Stats(seen = 0L, emitted = 0L, skipped = 0L, parseErrors = 0L, firstParseError = None)))
    } catch {
      case e: java.io.IOException =>
        Left(IoError(s"I/O error while building dataset: ${e.getMessage}", e))
      case e: RuntimeException =>
        Left(IoError(s"Runtime error while building dataset: ${e.getMessage}", e))
    } finally {
      if (src != null) try src.close() catch { case _: Throwable => () }
      if (out != null) try out.close() catch { case _: Throwable => () }
    }
  }

  // ---------------------------------------------------------------------------
  // CLI parsing (tail-recursive, immutable)
  // ---------------------------------------------------------------------------

  private val usage: String =
    """Usage:
      |  runMain etl.BuildProofCompletionDataset \
      |    --in   <abs/path/combined.jsonl> \
      |    --out  <abs/path/out.jsonl> \
      |    [--limit N] [--all-bodies] [--strict]
      |
      |Defaults:
      |  --limit 200
      |  --simple-only (enabled)  (use --all-bodies to include bodies with whitespace)
      |  --strict (disabled)      (when enabled: parseErrors > 0 => nonzero exit)
      |""".stripMargin

  private def parseArgs(args: List[String]): Either[BuildError, Config] = {
    @tailrec
    def loop(rest: List[String], acc: Map[String, String], flags: Set[String]): Either[BuildError, (Map[String, String], Set[String])] = {
      rest match {
        case Nil => Right((acc, flags))
        case "--all-bodies" :: xs =>
          loop(xs, acc, flags + "all-bodies")
        case "--strict" :: xs =>
          loop(xs, acc, flags + "strict")
        case "--in" :: v :: xs =>
          loop(xs, acc.updated("in", v), flags)
        case "--out" :: v :: xs =>
          loop(xs, acc.updated("out", v), flags)
        case "--limit" :: v :: xs =>
          loop(xs, acc.updated("limit", v), flags)
        case bad :: _ =>
          Left(ArgError(s"Unknown/invalid arg: $bad\n\n$usage"))
      }
    }

    loop(args, Map.empty, Set.empty).flatMap { case (m, flags) =>
      val inOpt  = m.get("in").map(s => Paths.get(s).toAbsolutePath.normalize())
      val outOpt = m.get("out").map(s => Paths.get(s).toAbsolutePath.normalize())

      val limit =
        m.get("limit").flatMap(s => Try(s.toInt).toOption).getOrElse(200)

      val simpleOnly = !flags.contains("all-bodies")
      val strict    = flags.contains("strict")

      (inOpt, outOpt) match {
        case (Some(inP), Some(outP)) =>
          Right(Config(inJsonl = inP, outJsonl = outP, limit = limit, simpleOnly = simpleOnly, strict = strict))
        case _ =>
          Left(ArgError(s"Missing required args: --in and --out\n\n$usage"))
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Main
  // ---------------------------------------------------------------------------

  def main(argv: Array[String]): Unit = {
    parseArgs(argv.toList) match {
      case Left(e) =>
        System.err.println(s"[BuildProofCompletionDataset] ❌ ${e.message}")
        System.exit(2)

      case Right(cfg) =>
        build(cfg) match {
          case Left(e) =>
            System.err.println(s"[BuildProofCompletionDataset] ❌ ${e.message}")
            System.exit(2)
          case Right(st) =>
            println(s"[BuildProofCompletionDataset] ✅ wrote dataset: ${cfg.outJsonl}")
            println(s"[BuildProofCompletionDataset]    seen=${st.seen} emitted=${st.emitted} skipped=${st.skipped} parseErrors=${st.parseErrors}")
            if (st.parseErrors > 0) {
              System.err.println(s"[BuildProofCompletionDataset] ⚠️  parseErrors=${st.parseErrors}")
              st.firstParseError.foreach { msg =>
                System.err.println("[BuildProofCompletionDataset] ⚠️  first parse error:")
                System.err.println(msg)
              }
              if (cfg.strict) {
                System.err.println("[BuildProofCompletionDataset] ❌ --strict enabled: failing due to parse errors")
                System.exit(3)
              }
            }
        }
    }
  }
}

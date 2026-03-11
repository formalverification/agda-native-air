/** ======================================================================
 *  Agda2TrainReducer.scala
 *  ----------------------------------------------------------------------
 *
 *  File: strux-driver/src/main/scala/struxdriver/reduce/Agda2TrainReducer.scala
 *  Package: struxdriver.reduce
 *
 *  Description
 *  -----------
 *  Legacy adapter for “Agda2Train-style” JSON dumps.
 *
 *  This tool walks over a (possibly messy) JSON structure produced by older
 *  Agda2Train experiments and reduces it to our canonical JSONL row format
 *  `struxdriver.schema.AgdaData`.
 *
 *  It is deliberately tolerant of schema drift:
 *    - probes multiple alternative keys for module / file / name / type / body,
 *    - accepts both a single JSON document (object/array) and JSONL,
 *    - treats imports/opens as a crude stand-in for "available premises".
 *
 *  The preferred path for new pipelines is:
 *
 *      Agda reflection JSON  -->  transform/Agda2TrainTransformer.scala
 *
 *  This reducer remains useful for:
 *    - legacy dumps that do not match the newer reflection schema;
 *    - quick experiments or micro-benchmarks on older Agda2Train outputs.
 *
 *  Usage
 *  -----
 *      sbt "project strux-driver" \
 *          "runMain struxdriver.reduce.Agda2TrainReducer <in.json|jsonl> <out.jsonl>"
 *
 *  Output
 *  ------
 *  JSONL where each line is a canonical `AgdaData` record:
 *
 *      {
 *        "file": "...",
 *        "module": "...",
 *        "name": "...",
 *        "agdaType": "...",
 *        "proof": "...",
 *        "premises": [...],
 *        "declKind": "...",
 *        "astSize": N
 *      }
 *
 *  Notes
 *  -----
 *  - Ranges/positions present in the source JSON are currently ignored.
 *  - All important normalization (names, premises, whitespace) is delegated
 *    to `AgdaDataOps.normalize`, so the reducer itself stays simple.
 *
 * ====================================================================== */
package struxdriver.reduce
import java.nio.charset.StandardCharsets
import java.nio.file.{Files, Paths, Path}
import scala.util.control.NonFatal
import ujson.Value
import upickle.default._
import struxdriver.AgdaJsonParser.JsonUtil.{optStr, pickPretty, pickStringArray}
import struxdriver.schema.{AgdaData, AgdaDataOps, SemanticInfo, DeclKind,Semantic}
import struxdriver.util.EitherUtil.catchNonFatal

/** Reduce legacy Agda2Train JSON → canonical AgdaData JSONL. */
object Agda2TrainReducer {

  // ---------------------------------------------------------------------------
  // I/O helpers (functional core: Either-based)
  // ---------------------------------------------------------------------------

  private def slurp(path: Path): Either[String, String] =
    catchNonFatal(
      new String(Files.readAllBytes(path), StandardCharsets.UTF_8)
    )

  private def isLikelyJsonl(s: String): Boolean =
    s.linesIterator.take(5).exists(_.trim.startsWith("{")) &&
      s.trim.nonEmpty &&
      !s.trim.startsWith("{") && !s.trim.startsWith("[")

  private def tryArr(v: Value): List[Value] = v match {
    case ujson.Arr(values) => values.toList
    case other             => List(other)
  }

  private def parseLines(lines: List[String]): Either[String, List[Value]] =
    lines.foldLeft[Either[String, List[Value]]](Right(Nil)) { (accE, line) =>
      val trimmed = line.trim
      if (trimmed.isEmpty) accE
      else
        for {
          acc <- accE
          v   <- catchNonFatal(ujson.read(trimmed))
        } yield acc :+ v
    }

  /** Read either a single JSON doc (object/array) or JSONL. */
  private def readAnyJson(path: Path): Either[String, List[Value]] =
    slurp(path).flatMap { s =>
      if (isLikelyJsonl(s)) {
        parseLines(s.linesIterator.toList)
      } else {
        catchNonFatal(tryArr(ujson.read(s)))
      }
    }

  // ---------------------------------------------------------------------------
  // JSON → AgdaData reduction
  // ---------------------------------------------------------------------------

  /** Extract file, module, short name from a "decl-like" name, if needed.
    *
    * For this reducer we assume:
    *   - `module` is provided separately when possible;
    *   - `name` is a local identifier (not necessarily fully qualified).
    *
    * If no file is present we synthesize a placeholder path.
    */
  private def assembleIdentity(
    module: Option[String],
    file: Option[String],
    localName: String
  ): (String, Option[String], String) = {
    val mod  = module.map(_.trim).filter(_.nonEmpty)
    val path = file
      .map(_.trim)
      .filter(_.nonEmpty)
      .getOrElse(mod.map(m => s"$m.agda").getOrElse("unknown-file.agda"))
    (path, mod, localName.trim)
  }

  /** Reduce a single JSON document (object/array) into a list of AgdaData rows. */
  private def reduceDoc(root: Value): List[AgdaData] = {

    def isDeclLike(
      name: Option[String],
      tpe: Option[String],
      body: Option[String],
      clauses: List[String]
    ): Boolean =
      name.isDefined && (tpe.isDefined || body.isDefined || clauses.nonEmpty)

    def mkRow(
      module: Option[String],
      file: Option[String],
      name: String,
      tpe: Option[String],
      body: Option[String],
      imports: List[String]
    ): AgdaData = {
      val (filePath, modOpt, shortName) =
        assembleIdentity(module, file, name)

      val sem: SemanticInfo =
        Semantic.from(
          name     = shortName,
          agdaType = tpe,
          module   = modOpt,
          proof    = body
        )

      val raw = AgdaData(
        file     = filePath,
        module   = modOpt,
        name     = shortName,
        agdaType = tpe,
        proof    = body,
        // We treat "imports/opens" as a coarse stand-in for "available premises"
        premises = imports,
        declKind = sem.kind,
        astSize  = sem.astSize
      )

      AgdaDataOps.normalize(raw)
    }

    def collect(v: Value, parentModule: Option[String], parentFile: Option[String]): List[AgdaData] =
      v match {
        case o: ujson.Obj =>
          val module =
            optStr(o, "module")
              .orElse(optStr(o, "moduleName"))
              .orElse(optStr(o, "modName"))
              .orElse(parentModule)

          val file =
            optStr(o, "file")
              .orElse(optStr(o, "path"))
              .orElse(parentFile)

          val name =
            optStr(o, "decl")
              .orElse(optStr(o, "declName"))
              .orElse(optStr(o, "declaredName"))
              .orElse(optStr(o, "name"))

          val typePretty: Option[String] =
            o.value.get("type").flatMap(pickPretty)
              .orElse(optStr(o, "typePretty"))
              .orElse(optStr(o, "declaredType"))
              .orElse(optStr(o, "signature"))
              .orElse(optStr(o, "sig"))
              .orElse(o.value.get("ty").flatMap(pickPretty))

          val rhsPretty: Option[String] =
            o.value.get("rhs").flatMap(pickPretty)
              .orElse(o.value.get("def").flatMap(pickPretty))
              .orElse(o.value.get("definition").flatMap(pickPretty))

          val clauseStrings: List[String] =
            o.value.get("clauses").collect {
              case a: ujson.Arr => a.value.toList.flatMap(pickPretty)
            }.getOrElse(Nil)

          val imports: List[String] =
            pickStringArray(o, "imports", "opens", "openImports")

          val here: List[AgdaData] =
            if (isDeclLike(name, typePretty, rhsPretty, clauseStrings)) {
              val body: Option[String] =
                (rhsPretty.toList ++
                  (if (clauseStrings.nonEmpty) List(clauseStrings.mkString("\n")) else Nil)) match {
                  case Nil    => None
                  case single => Some(single.mkString("\n"))
                }

              name.toList.map { nm =>
                mkRow(module, file, nm, typePretty, body, imports)
              }
            } else Nil

          val children: List[AgdaData] =
            o.value.values.toList.flatMap { child =>
              collect(child, module.orElse(parentModule), file.orElse(parentFile))
            }

          here ++ children

        case ujson.Arr(values) =>
          values.toList.flatMap(v2 => collect(v2, parentModule, parentFile))

        case _ =>
          Nil
      }

    collect(root, None, None)
  }

  // ---------------------------------------------------------------------------
  // Write JSONL
  // ---------------------------------------------------------------------------

  private def writeJsonl(rows: List[AgdaData], out: Path): Either[String, Unit] =
    catchNonFatal {
      val parent = out.getParent
      if (parent != null) Files.createDirectories(parent)
      val w = Files.newBufferedWriter(out, StandardCharsets.UTF_8)
      try rows.foreach { r => w.write(write(r)); w.write("\n") }
      finally w.close()
    }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /** Pure entry point: read → reduce → write. */
  def reduceFile(in: Path, out: Path): Either[String, Int] =
    for {
      docs <- readAnyJson(in)
      rows  = docs.flatMap(reduceDoc)
      _    <- writeJsonl(rows, out)
    } yield rows.size

  // Tiny impure wrapper for CLI use.
  def main(args: Array[String]): Unit = {
    if (args.length < 2) {
      Console.err.println("Usage: Agda2TrainReducer <in.json|jsonl> <out.jsonl>")
      sys.exit(1)
    }

    val in  = Paths.get(args(0))
    val out = Paths.get(args(1))

    reduceFile(in, out) match {
      case Right(n) =>
        println(s"[Agda2TrainReducer] wrote $n rows to $out")

      case Left(msg) =>
        Console.err.println(s"[Agda2TrainReducer] error: $msg")
        sys.exit(2)
    }
  }
}

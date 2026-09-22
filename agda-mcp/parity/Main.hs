-- | Main.hs
--
-- File: agda-native-air/agda-mcp/parity/Main.hs
--
-- Description:
--   The replay driver for issue #163: does the interaction lane's reading of
--   a @Cmd_give@ name the same class a batch @fill_hole@ names for the same
--   candidate on the same file?
--
--   It is a measurement harness, not a tool and not a lane.  Nothing here is
--   reachable from the MCP server; the executable exists so the two-lane
--   policy can be argued from a table rather than from a plausible story, and
--   it is deliberately the /shipped/ code on both sides:
--
--     * the batch side is 'AgdaMCP.Tools.ProofState.handleFillHole', the very
--       function the @fill_hole@ tool dispatches to, so the verdict column is
--       the verdict of record and not a re-implementation of it;
--     * the lane side is 'AgdaMCP.Interaction.giveCandidate' over a real
--       'AgdaMCP.Interaction.withLane' child, with the per-load argv assembled
--       exactly as 'AgdaMCP.Tools.LiveQueries.withLiveFile' assembles it, so
--       the two sides resolve one file against one tree by construction.
--
--   Haskell rather than Scala, and the reason is not taste: the lane's give is
--   a library function that no tool registers (issue #163 stops before a tool
--   shape), so a client driving the server over stdio cannot reach it at all.
--   A Scala driver would have to spawn a second @agda --interaction-json@
--   child of its own and re-implement the framing, the escaping, and the
--   reload policy, which is what the issue's hand probes did and what this
--   session exists to replace with the real lane.
--
--   Design notes:
--
--   * The case set is built from what the repository commits, since the
--     proof-search sweeps' per-candidate rows are not in it (they write under
--     the gitignored @data/benchmarks/reports/@).  Two sources: the
--     agent-bench probe rows under @reports/agent-bench/agent-*/@, each a real
--     @fill_hole@ a frontier model issued, and the 55 benchmark golds, whose
--     @goldTerm@ is a candidate exactly when splicing it over the obligation's
--     hole reproduces the gold file (whitespace-normalized); see 'termModeGold'.
--     Cases are deduplicated by (obligation, candidate): running the identical
--     judgment twice measures nothing, so the row carries how many archived
--     rows it stands for and which statuses they carried.
--   * Per obligation the lane pass runs first, inside one 'withLane' body and
--     one load, and the batch pass after it.  A batch @fill_hole@ patches the
--     file in place and restores it, which moves its mtime; doing the passes in
--     this order keeps each lane load attributable to the case set rather than
--     to the other lane's bookkeeping.
--   * @--cases FILE@ replaces the built-in set with a JSON list, which is how
--     the issue's constructed cases stay reproducible rather than driven by
--     hand: @parity/probe-cases.json@ is the issue's own probe table,
--     @parity/deliberate-cases.json@ the deliberate set, and
--     @parity/cost-cases-*.json@ the repeated single candidates the cost
--     table is read off.  A case list may address a fixture of its own;
--     @parity/fixtures/@ holds the one the benchmark suite has no shape for.
--   * Timings are reported as the measurer measured them: the lane's give and
--     reset in microseconds (a give is single-digit milliseconds, so the
--     millisecond resolution the server reports in would quantize away most of
--     what is being measured), the batch run in the milliseconds its own
--     'frElapsedMs' reports.

{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Control.Monad (forM, forM_, when)
import Data.Aeson
  ( FromJSON (..), Value (..), (.:), (.:?), (.!=), (.=)
  , encode, object, withObject )
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy.Char8 as BL8
import Data.Char (isSpace)
import Data.List (isPrefixOf, nub, sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import System.Directory
  ( doesDirectoryExist, doesFileExist, listDirectory, makeAbsolute
  , setCurrentDirectory )
import System.Environment (getArgs)
import System.Exit (die, exitFailure, exitSuccess)
import System.FilePath ((</>), takeFileName)
import System.IO (hFlush, hPutStrLn, stderr, stdout)

import AgdaMCP.Agda (AgdaConfig (..), defaultConfig)
import AgdaMCP.Diagnostics (parseDiagnostics)
import AgdaMCP.Holes (HoleRef (..))
import AgdaMCP.Interaction
  ( GiveClass (..), GiveForce (..), GiveOutcome (..), GiveReading (..)
  , InteractionLanes, IPoint (..), LaneFailure (..), LoadReport (..)
  , IRange (..), LaneHandle, LoadedInfo (..), LaneMeta (..), ensureLoaded
  , giveCandidate, newInteractionLanes, shutdownLanes, withLane )
import AgdaMCP.Project
  (fileDirIncludeFlags, projectExtraFlags, resolveProject)
import AgdaMCP.Tools.ProofState (handleFillHole)
import AgdaMCP.Types
  ( Diagnostic (..), FillHoleParams (..), FillResult (..), FillStatus (..)
  , ProjectContext (..) )


-- ---------------------------------------------------------------------------
-- Options
-- ---------------------------------------------------------------------------

-- | The committed flag set, which is also the one the archived agent-bench
-- subjects' servers ran with (their @mcp.json@ files record it verbatim).
-- Reproducing an archived status means reproducing its flags.
defaultAgdaFlags :: [String]
defaultAgdaFlags =
  [ "-i", "agda-dojang/agda", "--library-file=agda/libraries"
  , "-l", "agda-dojang", "-l", "standard-library", "-l", "agda-algebras" ]

data Opts = Opts
  { optRoot    :: FilePath        -- ^ Repository root.  The process enters it
                                  --   before anything resolves a path: the
                                  --   committed flag set is written relative
                                  --   to the root, and Agda finds a project's
                                  --   @.agda-lib@ by walking up from the
                                  --   process's own directory rather than
                                  --   from the file it is handed.
  , optFlags   :: [String]
  , optOut     :: Maybe FilePath
  , optCases   :: Maybe FilePath  -- ^ A case list to replace the built-in one.
  , optOnly    :: [Text]          -- ^ Restrict to these benchmark ids.
  , optLimit   :: Maybe Int
  , optTimeout :: Int
  , optListOnly :: Bool           -- ^ Print the case set and stop.
  } deriving (Show)

defaultOpts :: Opts
defaultOpts = Opts
  { optRoot = "."
  , optFlags = defaultAgdaFlags
  , optOut = Nothing
  , optCases = Nothing
  , optOnly = []
  , optLimit = Nothing
  , optTimeout = 900
  , optListOnly = False
  }

usage :: String
usage = unlines
  [ "lane-give-parity: replay candidates through both lanes (issue #163)"
  , ""
  , "  --root DIR          repository root (default: .)"
  , "  --agda-flags STR    flag set for both lanes (default: the committed set)"
  , "  --cases FILE        a JSON case list, replacing the built-in one"
  , "  --only ID           restrict to this benchmark id (repeatable)"
  , "  --limit N           stop after N cases"
  , "  --timeout SECS      per-call bound for both lanes (default: 900)"
  , "  --out FILE          write the rows as JSONL here (default: stdout)"
  , "  --list              print the case set and stop"
  ]

parseArgs :: [String] -> Opts -> Opts
parseArgs [] o = o
parseArgs ("--root" : v : rest) o = parseArgs rest o { optRoot = v }
parseArgs ("--agda-flags" : v : rest) o = parseArgs rest o { optFlags = words v }
parseArgs ("--cases" : v : rest) o = parseArgs rest o { optCases = Just v }
parseArgs ("--only" : v : rest) o = parseArgs rest o { optOnly = optOnly o <> [T.pack v] }
parseArgs ("--limit" : v : rest) o = parseArgs rest o { optLimit = Just (read v) }
parseArgs ("--timeout" : v : rest) o = parseArgs rest o { optTimeout = read v }
parseArgs ("--out" : v : rest) o = parseArgs rest o { optOut = Just v }
parseArgs ("--list" : rest) o = parseArgs rest o { optListOnly = True }
parseArgs (x : _) _ = error ("unknown argument: " <> x <> "\n" <> usage)


-- ---------------------------------------------------------------------------
-- The case set
-- ---------------------------------------------------------------------------

-- | Case: one (obligation, hole, candidate) triple to judge on both lanes.
data Case = Case
  { caseSource :: Text        -- ^ Where the candidate came from.
  , caseBench  :: Text        -- ^ The benchmark id of its obligation.
  , caseObl    :: FilePath    -- ^ Repository-relative path of the obligation.
  , caseTier   :: Text        -- ^ Which benchmark tier the obligation is in.
  , caseCand   :: Text
  , caseHole   :: Int         -- ^ 0-based hole index, the tool's addressing.
  , caseForce  :: GiveForce
  , caseArch   :: [Text]      -- ^ The archived batch statuses of this pair.
  , caseRuns   :: [Text]      -- ^ The archive runs those statuses came from.
  , caseNote   :: Maybe Text
  }

-- | A case as a JSON file may state it, for the deliberate cases of issue
-- #163, which are constructed rather than archived.
instance FromJSON Case where
  parseJSON = withObject "Case" $ \o -> do
    obl <- o .: "obligation"
    cand <- o .: "candidate"
    src <- o .:? "source" .!= "deliberate"
    bench <- o .:? "benchmarkId" .!= T.pack (takeFileName obl)
    hole <- o .:? "holeIndex" .!= 0
    force <- o .:? "force" .!= ("WithoutForce" :: Text)
    note <- o .:? "note"
    pure Case
      { caseSource = src
      , caseBench = bench
      , caseObl = obl
      , caseTier = tierOf obl
      , caseCand = cand
      , caseHole = hole
      , caseForce = if force == "WithForce" then WithForce else WithoutForce
      , caseArch = []
      , caseRuns = []
      , caseNote = note
      }

-- | tierOf: which benchmark tier a repository-relative obligation path is in.
-- A path outside @data/benchmarks/@ (a deliberate case's own fixture) is
-- reported as such rather than guessed at.
tierOf :: FilePath -> Text
tierOf p = case filter (not . null) (splitOn '/' p) of
  ("data" : "benchmarks" : tier : _) -> T.pack tier
  _                                  -> "fixture"

splitOn :: Char -> String -> [String]
splitOn c s = case break (== c) s of
  (a, [])       -> [a]
  (a, _ : rest) -> a : splitOn c rest

-- | IndexEntry: the fields of one @benchmark-index.jsonl@ line this needs.
data IndexEntry = IndexEntry
  { ieId         :: Text
  , ieObligation :: FilePath
  , ieGold       :: FilePath
  , ieGoldTerm   :: Text
  }

instance FromJSON IndexEntry where
  parseJSON = withObject "IndexEntry" $ \o ->
    IndexEntry <$> o .: "id" <*> o .: "obligation" <*> o .: "gold"
               <*> o .: "goldTerm"

-- | ProbeRow: the fields of one archived agent-bench attempt row this needs.
data ProbeRow = ProbeRow
  { prBench     :: Text
  , prCandidate :: Text
  , prHoleIndex :: Int
  , prStatus    :: Text
  }

instance FromJSON ProbeRow where
  parseJSON = withObject "ProbeRow" $ \o ->
    ProbeRow <$> o .: "benchmarkId" <*> o .: "candidate"
             <*> o .:? "holeIndex" .!= 0 <*> o .: "status"

-- | readJsonl: every non-blank line of a JSONL file, or a named failure.
--
-- Deliberately not a 'mapMaybe' over 'decodeStrict''.  This executable's whole
-- product is a count ("80 candidates, 0 disagreements"), and a decoder that
-- drops what it cannot read can only make that count smaller without making it
-- look wrong: two truncated lines in the archive cost 16 candidates and a whole
-- obligation, silently, at exit 0 (measured; a Copilot review catch on PR 174).
-- A malformed row stops the run and names the file and the line instead.
readJsonl :: FromJSON a => FilePath -> IO [a]
readJsonl p = do
  bytes <- BS.readFile p
  let numbered = [ (n, l) | (n, l) <- zip [1 :: Int ..] (BS8.lines bytes)
                 , not (BS8.all isSpace l) ]
  forM numbered $ \(n, l) -> case Aeson.eitherDecodeStrict' l of
    Right v  -> pure v
    Left err -> die (p <> ":" <> show n <> ": could not read this JSONL row: " <> err)

-- | termModeGold: is this row's @goldTerm@ a candidate, or prose describing a
-- strategy?
--
-- The index's @goldTerm@ field is documentation, and for a gold that rewrites
-- the clause (@induction on xs; base refl, step cong suc IH@) it is a
-- sentence, not a term.  The test is structural and needs no judgment: splice
-- the goldTerm over the obligation's hole and ask whether the result is the
-- gold file, comparing whitespace-normalized text from each file's @module@
-- line (their header comments differ by construction, and three golds reflow
-- the term across continuation lines).
termModeGold :: Text -> Text -> Text -> Bool
termModeGold obligation gold term =
  case T.breakOn "{!!}" (fromModuleLine obligation) of
    (_, after) | T.null after -> False
    (before, after) ->
      normalizeSpace (before <> term <> T.drop 4 after)
        == normalizeSpace (fromModuleLine gold)
  where
    fromModuleLine = T.unlines . dropWhile (not . T.isPrefixOf "module ") . T.lines
    normalizeSpace = T.unwords . T.words

-- | builtinCases: the candidates this repository commits, deduplicated by
-- (obligation, candidate).
--
-- Source one: every archived agent-bench @fill_hole@ probe.  Source two: every
-- gold, as its @goldTerm@; a gold whose term is prose is kept and labeled
-- @gold-prose@ rather than dropped, because "a candidate that does not parse"
-- is a class both lanes have to classify and one an agent can produce.
builtinCases :: IO [Case]
builtinCases = do
  entries <- readJsonl "data/benchmarks/benchmark-index.jsonl"
  let byId = Map.fromList [(ieId e, e) | e <- entries]
  runDirs <- archiveRuns
  probed <- forM runDirs $ \(runName, dir) -> do
    rows <- readJsonl (dir </> "results.jsonl")
    pure [(runName, n, r) | (n, r) <- zip [1 :: Int ..] rows]
  goldCases <- forM entries $ \e -> do
    obligation <- TIO.readFile (ieObligation e)
    gold <- TIO.readFile (ieGold e)
    let isTerm = termModeGold obligation gold (ieGoldTerm e)
    pure Case
      { caseSource = if isTerm then "gold" else "gold-prose"
      , caseBench = ieId e
      , caseObl = ieObligation e
      , caseTier = tierOf (ieObligation e)
      , caseCand = ieGoldTerm e
      , caseHole = 0
      , caseForce = WithoutForce
      , caseArch = []
      , caseRuns = []
      , caseNote = Nothing
      }
  -- An archived row naming a benchmark the index does not define stops the
  -- run.  A pattern guard here would have filtered it out instead, which is
  -- the same completeness hole 'readJsonl' closes one layer down: the archive
  -- is committed and the index is not, so a renamed or retired obligation
  -- would quietly shrink the candidate set and the parity count with it (a
  -- Copilot review catch on PR 174).
  probeCases <- forM (concat probed) $ \(runName, n, r) ->
    case Map.lookup (prBench r) byId of
      Nothing -> die $ "reports/agent-bench/" <> T.unpack runName
        <> "/results.jsonl:" <> show n <> ": this archived probe row names benchmark id "
        <> show (T.unpack (prBench r))
        <> ", which data/benchmarks/benchmark-index.jsonl does not define"
      Just e -> pure Case
        { caseSource = "agent-bench"
        , caseBench = prBench r
        , caseObl = ieObligation e
        , caseTier = tierOf (ieObligation e)
        , caseCand = prCandidate r
        , caseHole = prHoleIndex r
        , caseForce = WithoutForce
        , caseArch = [prStatus r]
        , caseRuns = [runName]
        , caseNote = Nothing
        }
  pure (mergeCases (probeCases <> goldCases))

-- | archiveRuns: the agent-bench run directories that carry probe rows.
archiveRuns :: IO [(Text, FilePath)]
archiveRuns = do
  let base = "reports/agent-bench"
  there <- doesDirectoryExist base
  if not there then pure [] else do
    names <- listDirectory base
    found <- forM (sortOn id names) $ \n -> do
      let dir = base </> n
      ok <- doesFileExist (dir </> "results.jsonl")
      pure [(T.pack n, dir) | ok && "agent-" `isPrefixOf` n]
    pure (concat found)

-- | mergeCases: one row per (obligation, candidate, hole, force), carrying
-- every archived status the pair was seen with.
--
-- Running the identical judgment twice measures nothing, so the duplicates
-- collapse; what they carry (that the same candidate was answered @crash@
-- once and @ok@ the next time) is kept, because it is evidence about what
-- an archived @crash@ is.
mergeCases :: [Case] -> [Case]
mergeCases cs = map snd (Map.toAscList (foldl add Map.empty cs))
  where
    add m c =
      let k = (caseObl c, caseCand c, caseHole c, forceKey (caseForce c))
      in Map.insertWith combine k c m
    combine new old = old
      { caseSource = if caseSource old == caseSource new
                       then caseSource old
                       else caseSource old <> "+" <> caseSource new
      , caseArch = caseArch old <> caseArch new
      , caseRuns = nub (caseRuns old <> caseRuns new)
      }
    forceKey WithoutForce = 0 :: Int
    forceKey WithForce = 1


-- ---------------------------------------------------------------------------
-- Running one obligation's cases
-- ---------------------------------------------------------------------------

-- | LaneAnswer: what the lane pass produced for one case, or why it could not.
type LaneAnswer = Either Text GiveOutcome

-- | runObligation: the lane pass and the batch pass over one obligation's
-- cases, in that order.
--
-- The flag assembly is 'AgdaMCP.Tools.LiveQueries.withLiveFile'’s, restated
-- here because that function is internal to the tool layer: the server's
-- flags, plus what project resolution implies, plus the file's own directory
-- when nothing else reaches it.  The batch side is handed the /base/ config
-- and repeats the same assembly inside 'handleFillHole'’s own @withProject@,
-- which is the point: neither side is told the answer by this driver.
runObligation
  :: InteractionLanes -> AgdaConfig -> FilePath -> [Case] -> IO [Value]
runObligation lanes cfg0 oblRel cs = do
  absPath <- makeAbsolute oblRel
  resolved <- resolveProject cfg0 absPath
  case resolved of
    Left _ -> pure [errorRow c "project resolution refused the obligation" | c <- cs]
    Right pc0 -> do
      let baseFlags = agdaFlags cfg0 <> projectExtraFlags pc0
      dirFlags <- fileDirIncludeFlags baseFlags pc0 absPath
      let effFlags = baseFlags <> dirFlags
          cfg = cfg0 { agdaFlags = effFlags }
      -- Lane pass: one forced load, then every candidate through the give,
      -- each of them its OWN lane request.  'withLane' takes one deadline for
      -- its whole body, so a single request around the load and every give
      -- would make --timeout an obligation-wide budget on this lane while the
      -- batch side gets a fresh bound per call, and a long obligation could
      -- then fail its later candidates for nothing the candidates did (a
      -- Copilot review catch on PR 174).  Splitting the requests costs no
      -- child and no load: the registry hands back the same lane, and the
      -- second and later calls find the file already loaded.
      let root = pcRoot pc0
      loadRes <- onLane lanes cfg root $ \lh -> do
        loaded <- ensureLoaded lh True absPath effFlags
        pure $ case loaded of
          Left lf -> Left (laneFailureText lf)
          Right lr -> case lrOutcome lr of
            Left msg -> Left ("the obligation did not load: " <> oneLine msg)
            Right li -> Right (lrElapsedMs lr, liPoints li)
      (loadMs, points, laneAnswers) <- case loadRes of
        Left err -> pure (0, [], [Left err | _ <- cs])
        Right (ms, ps) -> do
          as <- forM cs $ \c -> case indexPoint (caseHole c) ps of
            Nothing -> pure (Left ("the load announced no interaction point at index "
                                    <> T.pack (show (caseHole c))) :: LaneAnswer)
            Just p -> onLane lanes cfg root $ \lh -> do
              -- Not forced: the load above (or the previous candidate's own
              -- reset) already put the lane in the state this give is to be
              -- timed against, so this is a stamp check and nothing more.
              -- A lane the previous candidate's timeout killed is respawned
              -- here instead, which is the recovery this split buys.
              ready <- ensureLoaded lh False absPath effFlags
              case ready of
                Left lf -> pure (Left (laneFailureText lf))
                Right lr -> case lrOutcome lr of
                  Left msg -> pure (Left ("the obligation did not load: " <> oneLine msg))
                  Right _ -> either (Left . laneFailureText) Right
                    <$> giveCandidate lh absPath effFlags (ipId p) (caseForce c) (caseCand c)
          pure (ms, ps, as)
      -- Batch pass: the shipped handler, one cold agda per candidate.
      batchAnswers <- forM cs $ \c ->
        handleFillHole cfg0 (FillHoleParams absPath (ByIndex (caseHole c)) (caseCand c))
      pure
        [ row c loadMs points (indexPoint (caseHole c) points) lane batch
        | (c, lane, batch) <- zip3 cs laneAnswers batchAnswers ]

-- | indexPoint: the interaction point at a 0-based /index/ of the load's own
-- point list.
--
-- Deliberately not @the point whose id is n@: @fill_hole@ addresses a hole by
-- its index in the source-order scan, and the lane addresses one by Agda's
-- interaction-point id.  On a freshly loaded file the two agree, and the
-- two-hole deliberate case checks that they do; assuming it would make a
-- whole table depend on an unstated coincidence.
indexPoint :: Int -> [IPoint] -> Maybe IPoint
indexPoint n ps
  | n < 0     = Nothing
  | otherwise = case drop n ps of
      (p : _) -> Just p
      []      -> Nothing


-- | onLane: one lane request, with its own copy of the configured timeout,
-- flattened to the driver's @Either Text@.
--
-- Every caller here is one unit of work that the batch side also runs as one
-- bounded call, which is the whole reason this exists rather than a single
-- request around the obligation.
onLane
  :: InteractionLanes -> AgdaConfig -> FilePath
  -> (LaneHandle -> IO (Either Text a)) -> IO (Either Text a)
onLane lanes cfg root body =
  either (Left . laneFailureText) id <$> withLane lanes cfg root body

laneFailureText :: LaneFailure -> Text
laneFailureText lf = T.pack (show (lfEvent lf)) <> ": " <> oneLine (lfMessage lf)

oneLine :: Text -> Text
oneLine = T.unwords . T.words


-- ---------------------------------------------------------------------------
-- The row
-- ---------------------------------------------------------------------------

-- | row: one candidate's two answers, side by side.
--
-- @agree@ is the projection the table is read on, and it is defined only when
-- both lanes answered: a case the lane could not judge because the lane
-- itself failed is not a disagreement about Agda, and recording it as one
-- would be the plausible-wrong table this measurement exists to avoid.
row :: Case -> Int -> [IPoint] -> Maybe IPoint -> LaneAnswer
    -> Either e FillResult -> Value
row c loadMs before mPoint lane batch = object $
  [ "source"        .= caseSource c
  , "benchmarkId"   .= caseBench c
  , "obligation"    .= caseObl c
  , "tier"          .= caseTier c
  , "candidate"     .= caseCand c
  , "holeIndex"     .= caseHole c
  , "force"         .= forceText (caseForce c)
  , "archivedStatus" .= caseArch c
  , "archivedRuns"  .= caseRuns c
  , "occurrences"   .= length (caseArch c)
  , "laneLoadMs"    .= loadMs
  , "lanePointId"   .= (ipId <$> mPoint)
  ]
  <> maybe [] (\n -> ["note" .= n]) (caseNote c)
  <> laneFields
  <> batchFields
  <> agreement
  where
    forceText WithoutForce = "WithoutForce" :: Text
    forceText WithForce    = "WithForce"

    laneFields = case lane of
      Left err -> [ "laneClass" .= Aeson.Null, "laneError" .= err ]
      Right o ->
        let r = goReading o in
        [ "laneClass"     .= classText (grClass r)
        , "laneGiven"     .= grGiven r
          -- The two conjuncts the reading added to fail closed, carried as
          -- evidence rather than only consulted: whether the give could be
          -- shown to have landed on the point it was aimed at, and how many
          -- lines of its response window were not JSON.  Across this archive
          -- the first is true and the second is zero on every accepted give,
          -- which is what makes them safe conjuncts.
        , "laneHere"      .= grHere r
        , "laneUnreadable" .= length (grUnreadable r)
        , "laneText"      .= grText r
        , "lanePoint"     .= grPoint r
          -- Every interaction point Agda announced AFTER the give, which is
          -- not the same as the points the candidate introduced: a give into
          -- one hole of a two-hole file leaves the other one standing, and
          -- reporting that as a new point would misread the evidence (a
          -- Copilot review catch on PR 174, where this field was called
          -- laneNewPoints and counted both).
        , "laneRemainingPoints" .= (length <$> grPoints r)
          -- The points the candidate actually introduced: those whose id was
          -- not in the load's own point list.  Agda's ids are stable across a
          -- give, so the set difference is exact.
        , "laneNewPoints" .= (length . filter isNew <$> grPoints r)
          -- Each remaining point, with whether it is new and the range Agda
          -- gave it as [line, col, endLine, endCol].  The distinction is the
          -- whole reason this is a list and not a count: a NEW point's range
          -- is in the /candidate expression's/ coordinates (giving `s≤s {!!}`
          -- reports `1.5-9`, where the sub-hole sits inside the string), while
          -- a point that was already open keeps its range in the FILE.  The
          -- wire shape is identical, so any tool that promises a re-anchored
          -- hole list turns on telling them apart.  The issue records refine's
          -- new points as rangeless; a give's are not.
        , "lanePoints" .= (map pointJson <$> grPoints r)
        , "laneMetas"     .= map lmetaName (grMetas r)
        , "laneGoals"     .= grGoals r
        , "laneCodes"     .= grCodes r
        , "laneMessage"   .= (oneLine <$> firstOf (grErrors r))
        , "laneGiveUs"    .= goGiveUs o
        , "laneResetUs"   .= goResetUs o
        ]

    batchFields = case batch of
      Left _ -> [ "batchStatus" .= Aeson.Null
                , "batchError" .= ("fill_hole refused the call" :: Text) ]
      Right f ->
        [ "batchStatus"    .= statusText (frStatus f)
        , "batchMs"        .= frElapsedMs f
        , "batchCodes"     .= mapMaybe diagCode (parseDiagnostics (fromMaybe "" (frMessage f)))
        , "batchMessage"   .= (oneLine . T.take 400 <$> frMessage f)
        , "batchRemaining" .= frRemainingHoles f
        ]

    -- A timeout and a crash are facts about a process, and the lane's reading
    -- has no counterpart for either, so a row carrying one is unjudged rather
    -- than a disagreement: comparing the two texts would have recorded
    -- `agree: false` for all four such combinations, inflating the count the
    -- table is read on and contradicting the README's own contract (a Copilot
    -- review catch on PR 174; no archived row carries one, so no measured
    -- figure moves).
    agreement = case (lane, batch) of
      (Right o, Right f)
        | Just judged <- semanticStatus (frStatus f) ->
            [ "agree" .= (classText (grClass (goReading o)) == judged) ]
      _ -> [ "agree" .= Aeson.Null ]

    firstOf (x : _) = Just x
    firstOf []      = Nothing

    beforeIds = map ipId before
    isNew p   = ipId p `notElem` beforeIds
    pointJson p = object
      [ "id"    .= ipId p
      , "new"   .= isNew p
      , "range" .= rangeOf p
      ]

-- | rangeOf: one interaction point's range as [line, col, endLine, endCol],
-- or the empty list when the wire carried none.
rangeOf :: IPoint -> [Int]
rangeOf p = case ipRange p of
  Nothing -> []
  Just r  -> [irLine r, irCol r, irEndLine r, irEndCol r]

classText :: GiveClass -> Text
classText GiveClassOk        = "ok"
classText GiveClassTypeError = "type_error"

statusText :: FillStatus -> Text
statusText FillOk        = "ok"
statusText FillTypeError = "type_error"
statusText FillTimeout   = "timeout"
statusText FillCrash     = "crash"

-- | semanticStatus: the two @fill_hole@ statuses that are a judgment about the
-- candidate, as opposed to a report about the process that ran.  Only these
-- are comparable with a lane reading.
semanticStatus :: FillStatus -> Maybe Text
semanticStatus FillOk        = Just "ok"
semanticStatus FillTypeError = Just "type_error"
semanticStatus FillTimeout   = Nothing
semanticStatus FillCrash     = Nothing

errorRow :: Case -> Text -> Value
errorRow c msg = object
  [ "source"      .= caseSource c
  , "benchmarkId" .= caseBench c
  , "obligation"  .= caseObl c
  , "candidate"   .= caseCand c
  , "laneClass"   .= Aeson.Null
  , "batchStatus" .= Aeson.Null
  , "agree"       .= Aeson.Null
  , "error"       .= msg
  ]


-- ---------------------------------------------------------------------------
-- main
-- ---------------------------------------------------------------------------

main :: IO ()
main = do
  args <- getArgs
  when ("--help" `elem` args) (putStrLn usage >> exitSuccess)
  let opts = parseArgs args defaultOpts
  -- Enter the root before anything resolves a path, exactly as the server's
  -- --cwd does and for the same reason (issue #103): both lanes are about to
  -- run an Agda whose project discovery is anchored to the process directory.
  setCurrentDirectory (optRoot opts)
  cases0 <- case optCases opts of
    Nothing -> builtinCases
    Just f -> do
      bytes <- BS.readFile f
      case Aeson.eitherDecodeStrict' bytes of
        Left err -> hPutStrLn stderr ("could not read " <> f <> ": " <> err) >> exitFailure
        Right cs -> pure (cs :: [Case])
  let selected = filter keep cases0
      keep c = null (optOnly opts) || caseBench c `elem` optOnly opts
      cases = maybe id take (optLimit opts) selected
      byObligation = Map.toAscList (Map.fromListWith (flip (<>)) [(caseObl c, [c]) | c <- cases])
  hPutStrLn stderr $ "cases: " <> show (length cases) <> " over "
    <> show (length byObligation) <> " obligations"
  when (optListOnly opts) $ do
    forM_ cases $ \c -> TIO.hPutStrLn stdout $ T.intercalate "\t"
      [ caseSource c, caseTier c, caseBench c, T.pack (show (length (caseArch c)))
      , T.intercalate "," (caseArch c), oneLine (caseCand c) ]
    exitSuccess
  let cfg = defaultConfig
        { agdaFlags = optFlags opts
        , agdaTimeout = Just (optTimeout opts)
        }
  lanes <- newInteractionLanes
  rows <- forM (zip [1 :: Int ..] byObligation) $ \(i, (obl, cs)) -> do
    hPutStrLn stderr $ "[" <> show i <> "/" <> show (length byObligation) <> "] "
      <> obl <> " (" <> show (length cs) <> " candidates)"
    rs <- runObligation lanes cfg obl cs
    forM_ rs $ \r -> hPutStrLn stderr ("    " <> summarize r)
    pure rs
  shutdownLanes lanes
  let allRows = concat rows
      out = BL8.unlines (map encode allRows)
  case optOut opts of
    Nothing -> BL8.putStr out
    Just f -> BL8.writeFile f out >> hPutStrLn stderr ("wrote " <> f)
  report allRows
  hFlush stdout

-- | summarize: one line per row on stderr, so a long run is watchable.
summarize :: Value -> String
summarize v = T.unpack $ T.intercalate "  "
  [ pad 11 (scalar "laneClass"), pad 11 (scalar "batchStatus")
  , pad 4 (scalar "agree"), pad 9 (scalar "laneGiveUs" <> " us")
  , pad 8 (scalar "batchMs" <> " ms"), T.take 60 (scalar "candidate") ]
  where
    scalar k = renderScalar (field k v)
    pad n = T.justifyLeft n ' '

field :: Text -> Value -> Maybe Value
field k (Object o) = KM.lookup (Key.fromText k) o
field _ _          = Nothing

renderScalar :: Maybe Value -> Text
renderScalar (Just (String t)) = oneLine t
renderScalar (Just (Number n)) = T.pack (show (round n :: Integer))
renderScalar (Just (Bool b))   = if b then "yes" else "NO"
renderScalar _                 = "-"

-- | report: the counts a reader of the table wants first.
report :: [Value] -> IO ()
report rows = do
  let judged = [r | r <- rows, isBool (field "agree" r)]
      agreed = [r | r <- judged, field "agree" r == Just (Bool True)]
  hPutStrLn stderr ""
  hPutStrLn stderr $ "rows: " <> show (length rows)
    <> "  judged on both lanes: " <> show (length judged)
    <> "  agree: " <> show (length agreed)
    <> "  disagree: " <> show (length judged - length agreed)
  forM_ [r | r <- judged, field "agree" r /= Just (Bool True)] $ \r ->
    hPutStrLn stderr $ "  DISAGREE " <> T.unpack (renderScalar (field "benchmarkId" r))
      <> "  lane=" <> T.unpack (renderScalar (field "laneClass" r))
      <> "  batch=" <> T.unpack (renderScalar (field "batchStatus" r))
      <> "  " <> T.unpack (T.take 80 (renderScalar (field "candidate" r)))
  where
    isBool (Just (Bool _)) = True
    isBool _               = False

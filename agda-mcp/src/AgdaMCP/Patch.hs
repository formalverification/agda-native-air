-- | Patch.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Patch.hs
--
-- Description:
--   Building a 'AgdaMCP.Types.TextPatch' (issue #136): the edit that replaces
--   a span of a file's text, in the form a client applies to its own copy.
--
--   How this fits: 'AgdaMCP.Tools.ProofState' calls 'textPatch' for the
--   candidate @fill_hole@ checked, when the call asked for it.  The span is a
--   pair of character offsets, not a hole, so the two tools that will answer
--   edits of other shapes build theirs here too: a refinement's term with its
--   new holes (issue #209), and a case split's clauses over the whole clause
--   they replace (issue #207).
--
-- Design notes:
--
--   * The patch is derived from the very values the server acted on.  Its
--     @digest@ is of the bytes read, as read; its @resultDigest@ is of the
--     bytes written over the file for the check, as written; and its
--     @newText@ is the replacement that produced them.  So what a client
--     writes by applying it is what Agda judged, byte for byte, and the suite
--     checks that with a stand-in Agda that records the bytes it was given.
--   * The offsets it takes index characters of the decoded text, which is how
--     'AgdaMCP.Holes' reports a span; the positions it answers are in the two
--     units the type documents ('AgdaMCP.Types.TextPatch'), lines and columns
--     for a holder of a text and bytes for a holder of the file.
--   * It is pure, and cheap enough to compute per call, but it is computed
--     only on request: a default answer carries no patch and pays for none.

module AgdaMCP.Patch
  ( textPatch
  ) where

import qualified Data.ByteString as BS
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE

import AgdaMCP.Digest (sourceDigest)
import AgdaMCP.Holes (positionOfOffset)
import AgdaMCP.Types (DiagRange (..), TextPatch (..))

-- | textPatch: the edit that replaced the characters from @start@ up to (not
-- including) @end@ of @src@ with @replacement@.
--
-- @originalBytes@ are the file's bytes, of which @src@ is the decoding, and
-- @patchedBytes@ the bytes the edit produced; both are passed in rather than
-- recomputed so that the two digests name exactly what was read and what was
-- written.
--
-- Neither end of the span may fall between the CR and the LF of a CR LF pair.
-- A hole's never does.  A span that ends its line must end before the CR:
-- that offset is the line's end as Agda counts it, and as a client whose text
-- holds no CRs does, while the offset after the CR has a column neither of
-- them has ('AgdaMCP.Holes'), so a range that ended there could not be
-- applied by line and column.  The tool that replaces whole clauses (issue
-- #207) is the first caller this binds.
textPatch
  :: FilePath       -- ^ The file, as resolved.
  -> BS.ByteString  -- ^ Its bytes as read.
  -> Text           -- ^ Their decoding.
  -> Int            -- ^ 0-based character offset of the span's start.
  -> Int            -- ^ 0-based character offset one past its end.
  -> Text           -- ^ The replacement.
  -> BS.ByteString  -- ^ The bytes with the replacement made.
  -> TextPatch
textPatch path originalBytes src start end replacement patchedBytes = TextPatch
  { tpFile         = path
  , tpDigest       = sourceDigest originalBytes
  , tpRange        = DiagRange startLine startCol endLine endCol
  , tpByteStart    = byteStart
  , tpByteEnd      = byteStart + BS.length (TE.encodeUtf8 old)
  , tpOldText      = old
  , tpNewText      = replacement
  , tpResultDigest = sourceDigest patchedBytes
  }
  where
    (before, rest)        = T.splitAt start src
    old                   = T.take (end - start) rest
    -- Strict decoding and encoding are inverse on valid UTF-8, so the bytes
    -- of the text before the span are the file's own bytes before it.
    byteStart             = BS.length (TE.encodeUtf8 before)
    (startLine, startCol) = positionOfOffset src start
    (endLine, endCol)     = positionOfOffset src end

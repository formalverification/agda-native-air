-- | Digest.hs
--
-- File: agda-native-air/agda-mcp/src/AgdaMCP/Digest.hs
--
-- Description:
--   The digest that names a file's text in a patch (issue #136): SHA-256 of
--   the file's bytes, written @sha256:@ and 64 lowercase hexadecimal digits.
--
--   How this fits: 'AgdaMCP.Patch' puts two of them in every patch, one for
--   the text the patch applies to and one for the text it produces, and
--   'AgdaMCP.Tools.ProofState' names with them the bytes it expected and the
--   bytes it found when a file changed under a check.  A client holding a
--   text compares its own digest with the patch's before it writes, so the
--   text it patches is the text that was checked.
--
-- Design notes:
--
--   * The form is agda-native-ide's basis (its ADR 0003, § 4): @sha256:@ and
--     the digest of the UTF-8 text Agda read.  The file-taking tools accept
--     only valid UTF-8 ('AgdaMCP.Path.withSourceFile' decodes strictly, and
--     strict decoding followed by encoding gives the same bytes back), so the
--     digest of a file's bytes here is that same digest, a leading
--     byte-order mark and every carriage return included.
--   * It is written here, after FIPS 180-4, and not taken from a library:
--     the backend shell's package set has no SHA-256 (@ghc-pkg list@ shows
--     only hashable, murmur-hash and data-hash), and a new dependency would
--     change the shell every lane of CI builds.  'AgdaMCP.AgdaStamp.fnv1a'
--     stays what the lane's stamps use: it distinguishes edits inside one
--     process, while this digest is compared with one another program
--     computed.
--   * The suite holds it to the standard's own vectors (the empty message,
--     @abc@, the two-block message, a million @a@s), to every length across
--     the two padding boundaries, and to coreutils' @sha256sum@ on the
--     fixtures when that program is on the path.
--   * Cost: one pass over the bytes, measured at 1.3 ms per 100 KiB and
--     12.6 ms per MiB (GHC 9.10.3, -O1; 2026-11-24).  The largest source in
--     the pinned libraries is 379 KB, and a patch computes two digests.  A
--     call that asks for no patch computes none.

{-# LANGUAGE BangPatterns      #-}
{-# LANGUAGE OverloadedStrings #-}

module AgdaMCP.Digest
  ( sourceDigest
  , sha256Hex
  ) where

import Control.Monad (forM_)
import Control.Monad.ST (ST, runST)
import Data.Bits (complement, rotateR, shiftL, shiftR, xor, (.&.), (.|.))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Unsafe as BSU
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Vector.Unboxed as VU
import qualified Data.Vector.Unboxed.Mutable as MU
import Data.Word (Word32, Word64)
import Numeric (showHex)

-- | sourceDigest: the name of a text in a patch, @sha256:@ and the digest of
-- its bytes.
sourceDigest :: BS.ByteString -> Text
sourceDigest bytes = "sha256:" <> sha256Hex bytes

-- | sha256Hex: the SHA-256 digest of a byte string, as 64 lowercase
-- hexadecimal digits.
sha256Hex :: BS.ByteString -> Text
sha256Hex = T.pack . concatMap hex8 . wordsOf . sha256
  where
    hex8 w = let s = showHex w "" in replicate (8 - length s) '0' <> s
    wordsOf (H a b c d e f g h) = [a, b, c, d, e, f, g, h]

-- | The eight working words of FIPS 180-4, § 6.2.
data H = H !Word32 !Word32 !Word32 !Word32 !Word32 !Word32 !Word32 !Word32

-- | The initial hash value, § 5.3.3.
initial :: H
initial = H 0x6a09e667 0xbb67ae85 0x3c6ef372 0xa54ff53a
            0x510e527f 0x9b05688c 0x1f83d9ab 0x5be0cd19

-- | The round constants, § 4.2.2.
roundConstants :: VU.Vector Word32
roundConstants = VU.fromList
  [ 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
  , 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
  , 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
  , 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
  , 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85
  , 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
  , 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
  , 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ]

-- | sha256: the digest's eight words.
--
-- The message is padded as § 5.1.1 says (a one bit, zeros, and the length in
-- bits as 64 bits, to a multiple of 64 bytes), then each 64-byte block is
-- folded into the hash value.
sha256 :: BS.ByteString -> H
sha256 message = runST $ do
  schedule <- MU.new 64
  let blocks = BS.length padded `div` 64
      go !h !i
        | i >= blocks = pure h
        | otherwise   = do
            h' <- compress schedule h (i * 64)
            go h' (i + 1)
  go initial 0
  where
    len    = BS.length message
    zeros  = (55 - len) `mod` 64
    bits   = fromIntegral len * 8 :: Word64
    padded = BS.concat
      [ message
      , BS.singleton 0x80
      , BS.replicate zeros 0
      , BS.pack [ fromIntegral (bits `shiftR` s) | s <- [56, 48 .. 0] ]
      ]

    -- One block, § 6.2.2: the message schedule, then the 64 rounds.
    compress :: MU.MVector s Word32 -> H -> Int -> ST s H
    compress w h0@(H a0 b0 c0 d0 e0 f0 g0 h0') off = do
      forM_ [0 .. 15] $ \t -> MU.unsafeWrite w t (wordAt (off + 4 * t))
      forM_ [16 .. 63] $ \t -> do
        w2  <- MU.unsafeRead w (t - 2)
        w7  <- MU.unsafeRead w (t - 7)
        w15 <- MU.unsafeRead w (t - 15)
        w16 <- MU.unsafeRead w (t - 16)
        MU.unsafeWrite w t (smallSigma1 w2 + w7 + smallSigma0 w15 + w16)
      let rounds !t s@(H a b c d e f g h)
            | t >= 64   = pure s
            | otherwise = do
                wt <- MU.unsafeRead w t
                let t1 = h + bigSigma1 e + ch e f g + VU.unsafeIndex roundConstants t + wt
                    t2 = bigSigma0 a + maj a b c
                rounds (t + 1) (H (t1 + t2) a b c (d + t1) e f g)
      H a b c d e f g h <- rounds (0 :: Int) h0
      pure (H (a0 + a) (b0 + b) (c0 + c) (d0 + d) (e0 + e) (f0 + f) (g0 + g) (h0' + h))

    -- A big-endian word of the padded message.
    wordAt :: Int -> Word32
    wordAt i =
          (byteAt i       `shiftL` 24) .|. (byteAt (i + 1) `shiftL` 16)
      .|. (byteAt (i + 2) `shiftL` 8)  .|.  byteAt (i + 3)
    byteAt :: Int -> Word32
    byteAt = fromIntegral . BSU.unsafeIndex padded

    -- The six functions of § 4.1.2.
    ch, maj :: Word32 -> Word32 -> Word32 -> Word32
    ch  x y z = (x .&. y) `xor` (complement x .&. z)
    maj x y z = (x .&. y) `xor` (x .&. z) `xor` (y .&. z)
    bigSigma0, bigSigma1, smallSigma0, smallSigma1 :: Word32 -> Word32
    bigSigma0   x = rotateR x 2  `xor` rotateR x 13 `xor` rotateR x 22
    bigSigma1   x = rotateR x 6  `xor` rotateR x 11 `xor` rotateR x 25
    smallSigma0 x = rotateR x 7  `xor` rotateR x 18 `xor` shiftR x 3
    smallSigma1 x = rotateR x 17 `xor` rotateR x 19 `xor` shiftR x 10

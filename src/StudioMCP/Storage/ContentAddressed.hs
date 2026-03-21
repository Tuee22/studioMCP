{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Storage.ContentAddressed
  ( ContentAddress (..),
    deriveContentAddress,
  )
where

import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    Value (String),
    withText,
  )
import qualified Data.ByteString as BS
import Data.Bits (xor)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Data.Word (Word64)
import Numeric (showHex)
import StudioMCP.DAG.Hashing (normalizeSegment)

newtype ContentAddress = ContentAddress
  { unContentAddress :: Text
  }
  deriving (Eq, Ord, Show)

instance FromJSON ContentAddress where
  parseJSON = withText "ContentAddress" (pure . ContentAddress)

instance ToJSON ContentAddress where
  toJSON (ContentAddress value) = String value

deriveContentAddress :: [Text] -> ContentAddress
deriveContentAddress semanticSegments =
  ContentAddress ("ca:fnv64:" <> Text.pack (padHex (showHex digest "")))
  where
    normalizedSegments = map normalizeSegment semanticSegments
    digest = BS.foldl' updateDigest fnvOffsetBasis (Text.encodeUtf8 (Text.intercalate "|" normalizedSegments))
    updateDigest currentDigest byteValue =
      (currentDigest `xor` fromIntegral byteValue) * fnvPrime

fnvOffsetBasis :: Word64
fnvOffsetBasis = 14695981039346656037

fnvPrime :: Word64
fnvPrime = 1099511628211

padHex :: String -> String
padHex rawHex = replicate (16 - length rawHex) '0' <> rawHex

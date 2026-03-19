{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.DAG.Memoization
  ( MemoPolicy (..),
    MemoKey (..),
    memoPolicyFromText,
    deriveMemoKey,
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import StudioMCP.DAG.Hashing (normalizeSegment)

data MemoPolicy
  = Memoize
  | NoMemoize
  deriving (Eq, Ord, Show)

newtype MemoKey = MemoKey
  { unMemoKey :: Text
  }
  deriving (Eq, Ord, Show)

memoPolicyFromText :: Text -> Either Text MemoPolicy
memoPolicyFromText rawValue =
  case normalizeSegment rawValue of
    "memoize" -> Right Memoize
    "no-memoize" -> Right NoMemoize
    "no_memoize" -> Right NoMemoize
    otherValue -> Left ("Unknown memoization policy: " <> otherValue)

deriveMemoKey :: [Text] -> MemoKey
deriveMemoKey segments =
  MemoKey ("memo:" <> Text.intercalate ":" (map normalizeSegment segments))

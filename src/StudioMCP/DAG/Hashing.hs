{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.DAG.Hashing
  ( normalizeSegment,
  )
where

import Data.Text (Text)
import qualified Data.Text as Text

normalizeSegment :: Text -> Text
normalizeSegment =
  Text.replace " " "-" . Text.toLower . Text.strip

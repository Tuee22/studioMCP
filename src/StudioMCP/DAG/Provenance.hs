{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.DAG.Provenance
  ( Provenance (..),
    emptyProvenance,
  )
where

import Data.Text (Text)

data Provenance = Provenance
  { provenanceDagName :: Text,
    provenanceDagVersion :: Text,
    provenanceRequestedBy :: Text
  }
  deriving (Eq, Show)

emptyProvenance :: Text -> Provenance
emptyProvenance dagNameValue =
  Provenance
    { provenanceDagName = dagNameValue,
      provenanceDagVersion = "draft",
      provenanceRequestedBy = "local-dev"
    }

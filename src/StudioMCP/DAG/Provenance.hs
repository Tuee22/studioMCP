{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.DAG.Provenance
  ( Provenance (..),
    emptyProvenance,
  )
where

import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    object,
    withObject,
    (.:),
    (.=),
  )
import Data.Text (Text)

data Provenance = Provenance
  { provenanceDagName :: Text,
    provenanceDagVersion :: Text,
    provenanceRequestedBy :: Text
  }
  deriving (Eq, Show)

instance FromJSON Provenance where
  parseJSON = withObject "Provenance" $ \obj ->
    Provenance
      <$> obj .: "dagName"
      <*> obj .: "dagVersion"
      <*> obj .: "requestedBy"

instance ToJSON Provenance where
  toJSON provenance =
    object
      [ "dagName" .= provenanceDagName provenance,
        "dagVersion" .= provenanceDagVersion provenance,
        "requestedBy" .= provenanceRequestedBy provenance
      ]

emptyProvenance :: Text -> Provenance
emptyProvenance dagNameValue =
  Provenance
    { provenanceDagName = dagNameValue,
      provenanceDagVersion = "draft",
      provenanceRequestedBy = "local-dev"
    }

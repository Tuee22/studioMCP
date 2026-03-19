module StudioMCP.Storage.Manifests
  ( ArtifactRef (..),
  )
where

import Data.Text (Text)

data ArtifactRef = ArtifactRef
  { artifactBucket :: Text,
    artifactKey :: Text
  }
  deriving (Eq, Show)

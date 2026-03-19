module StudioMCP.Storage.MinIO
  ( MinIOConfig (..),
  )
where

import Data.Text (Text)

data MinIOConfig = MinIOConfig
  { minioEndpointUrl :: Text,
    minioAccessKey :: Text,
    minioSecretKey :: Text
  }
  deriving (Eq, Show)

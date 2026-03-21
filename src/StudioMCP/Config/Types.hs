module StudioMCP.Config.Types
  ( AppMode (..),
    AppConfig (..),
  )
where

import Data.Text (Text)

data AppMode
  = ServerMode
  | InferenceMode
  | WorkerMode
  deriving (Eq, Show)

data AppConfig = AppConfig
  { appMode :: AppMode,
    pulsarHttpUrl :: Text,
    pulsarBinaryUrl :: Text,
    minioEndpoint :: Text,
    minioAccessKey :: Text,
    minioSecretKey :: Text
  }
  deriving (Eq, Show)

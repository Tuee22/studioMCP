{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.API.Version
  ( VersionInfo (..),
    apiVersion,
    versionInfoForMode,
  )
where

import Data.Aeson (FromJSON (parseJSON), ToJSON (toJSON), object, withObject, (.:), (.=))
import Data.Text (Text)
import StudioMCP.Config.Types (AppMode (InferenceMode, ServerMode, WorkerMode))

apiVersion :: Text
apiVersion = "0.1.0.0"

data VersionInfo = VersionInfo
  { versionNumber :: Text,
    versionMode :: Text
  }
  deriving (Eq, Show)

instance ToJSON VersionInfo where
  toJSON versionInfo =
    object
      [ "version" .= versionNumber versionInfo,
        "mode" .= versionMode versionInfo
      ]

instance FromJSON VersionInfo where
  parseJSON = withObject "VersionInfo" $ \obj ->
    VersionInfo
      <$> obj .: "version"
      <*> obj .: "mode"

versionInfoForMode :: AppMode -> VersionInfo
versionInfoForMode appModeValue =
  VersionInfo
    { versionNumber = apiVersion,
      versionMode =
        case appModeValue of
          ServerMode -> "server"
          InferenceMode -> "inference"
          WorkerMode -> "worker"
    }

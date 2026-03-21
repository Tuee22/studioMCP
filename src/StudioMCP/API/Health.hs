{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.API.Health
  ( DependencyHealth (..),
    HealthReport (..),
    HealthStatus (..),
    probeDependencies,
  )
where

import Control.Exception (SomeException, try)
import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    Value (String),
    object,
    withObject,
    withText,
    (.:),
    (.=),
  )
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as Text
import Network.HTTP.Client
  ( Manager,
    Request,
    Request (responseTimeout),
    Response,
    Response (responseStatus),
    httpLbs,
    parseRequest,
    responseTimeoutMicro,
  )
import Network.HTTP.Types.Status (statusCode)
import StudioMCP.Config.Types (AppConfig (..))

data HealthStatus = Healthy | Degraded
  deriving (Eq, Show)

instance ToJSON HealthStatus where
  toJSON healthStatusValue =
    String $
      case healthStatusValue of
        Healthy -> "healthy"
        Degraded -> "degraded"

instance FromJSON HealthStatus where
  parseJSON =
    withText "HealthStatus" $ \value ->
      case value of
        "healthy" -> pure Healthy
        "degraded" -> pure Degraded
        _ -> fail ("Unknown health status: " <> Text.unpack value)

data DependencyHealth = DependencyHealth
  { dependencyName :: Text,
    dependencyStatus :: HealthStatus,
    dependencyDetail :: Text
  }
  deriving (Eq, Show)

instance ToJSON DependencyHealth where
  toJSON dependencyHealth =
    object
      [ "name" .= dependencyName dependencyHealth,
        "status" .= dependencyStatus dependencyHealth,
        "detail" .= dependencyDetail dependencyHealth
      ]

instance FromJSON DependencyHealth where
  parseJSON = withObject "DependencyHealth" $ \obj ->
    DependencyHealth
      <$> obj .: "name"
      <*> obj .: "status"
      <*> obj .: "detail"

data HealthReport = HealthReport
  { healthStatus :: HealthStatus,
    healthDependencies :: [DependencyHealth]
  }
  deriving (Eq, Show)

instance ToJSON HealthReport where
  toJSON healthReport =
    object
      [ "status" .= healthStatus healthReport,
        "dependencies" .= healthDependencies healthReport
      ]

instance FromJSON HealthReport where
  parseJSON = withObject "HealthReport" $ \obj ->
    HealthReport
      <$> obj .: "status"
      <*> obj .: "dependencies"

probeDependencies :: Manager -> AppConfig -> IO HealthReport
probeDependencies manager appConfig = do
  pulsarHealth <- probeHttpDependency manager "pulsar" (pulsarHttpUrl appConfig <> "/admin/v2/clusters")
  minioHealth <- probeHttpDependency manager "minio" (minioEndpoint appConfig <> "/minio/health/live")
  let dependencies = [pulsarHealth, minioHealth]
      overallStatus =
        if all ((== Healthy) . dependencyStatus) dependencies
          then Healthy
          else Degraded
  pure
    HealthReport
      { healthStatus = overallStatus,
        healthDependencies = dependencies
      }

probeHttpDependency :: Manager -> Text -> Text -> IO DependencyHealth
probeHttpDependency manager dependency url = do
  requestOrException <- try (parseRequest (Text.unpack url)) :: IO (Either SomeException Request)
  case requestOrException of
    Left exn ->
      pure
        DependencyHealth
          { dependencyName = dependency,
            dependencyStatus = Degraded,
            dependencyDetail = Text.pack (show exn)
          }
    Right request -> do
      responseOrException <-
        try
          ( httpLbs
              request {responseTimeout = responseTimeoutMicro 2000000}
              manager
          ) :: IO (Either SomeException (Response LBS.ByteString))
      case responseOrException of
        Left exn ->
          pure
            DependencyHealth
              { dependencyName = dependency,
                dependencyStatus = Degraded,
                dependencyDetail = Text.pack (show exn)
              }
        Right response ->
          let code = statusCode (responseStatus response)
           in pure
                DependencyHealth
                  { dependencyName = dependency,
                    dependencyStatus =
                      if code >= 200 && code < 400 then Healthy else Degraded,
                    dependencyDetail = "http_status=" <> Text.pack (show code)
                  }

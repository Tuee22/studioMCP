{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.API.Health
  ( DependencyHealth (..),
    HealthReport (..),
    HealthStatus (..),
    healthReportFromChecks,
    probeDependencies,
    probePlatformDependencyChecks,
  )
where

import Control.Concurrent.Async (mapConcurrently)
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
import Data.Text (Text)
import Data.Text qualified as Text
import Network.HTTP.Client (Manager)
import StudioMCP.Config.Types (AppConfig (..))
import StudioMCP.API.Readiness
  ( ReadinessCheck (..),
    probeHttpCheck,
  )

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
  healthReportFromChecks <$> probePlatformDependencyChecks manager appConfig

probePlatformDependencyChecks :: Manager -> AppConfig -> IO [ReadinessCheck]
probePlatformDependencyChecks manager appConfig =
  mapConcurrently id
    [ probeHttpCheck
        manager
        "pulsar"
        (pulsarHttpUrl appConfig <> "/admin/v2/clusters")
        [200]
        "dependency-ready"
        "dependency-unavailable",
      probeHttpCheck
        manager
        "minio"
        (minioEndpoint appConfig <> "/minio/health/ready")
        [200]
        "dependency-ready"
        "dependency-unavailable"
    ]

healthReportFromChecks :: [ReadinessCheck] -> HealthReport
healthReportFromChecks checks =
  let dependencies = map readinessCheckToDependency checks
      overallStatus =
        if all ((== Healthy) . dependencyStatus) dependencies
          then Healthy
          else Degraded
   in HealthReport
        { healthStatus = overallStatus,
          healthDependencies = dependencies
        }

readinessCheckToDependency :: ReadinessCheck -> DependencyHealth
readinessCheckToDependency readinessCheck =
  DependencyHealth
    { dependencyName = readinessCheckName readinessCheck,
      dependencyStatus =
        if readinessCheckReady readinessCheck
          then Healthy
          else Degraded,
      dependencyDetail =
        readinessCheckReason readinessCheck
          <> ": "
          <> readinessCheckDetail readinessCheck
    }

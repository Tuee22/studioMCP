{-# LANGUAGE OverloadedStrings #-}

module API.HealthSpec
  ( spec,
  )
where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Exception (bracket)
import Data.String (fromString)
import Data.Text (Text)
import Network.HTTP.Client (defaultManagerSettings, newManager)
import Network.HTTP.Types (hContentType, methodGet, status200)
import Network.Wai (Application, Response, pathInfo, requestMethod, responseLBS)
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort, setTimeout)
import StudioMCP.API.Health
  ( DependencyHealth (dependencyStatus),
    HealthReport (..),
    HealthStatus (Degraded, Healthy),
    probeDependencies,
  )
import StudioMCP.Config.Types (AppConfig (..), AppMode (ServerMode))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec =
  describe "probeDependencies" $ do
    it "reports healthy when both sidecars are reachable" $
      withDependencyServer 38111 $ do
        manager <- newManager defaultManagerSettings
        healthReport <- probeDependencies manager (healthyConfig 38111)
        healthStatus healthReport `shouldBe` Healthy
        healthDependencies healthReport `shouldSatisfy` all ((== Healthy) . dependencyStatus)

    it "reports degraded when a dependency is unavailable" $
      withDependencyServer 38112 $ do
        manager <- newManager defaultManagerSettings
        healthReport <- probeDependencies manager (degradedConfig 38112)
        healthStatus healthReport `shouldBe` Degraded
        healthDependencies healthReport `shouldSatisfy` any ((== Degraded) . dependencyStatus)

withDependencyServer :: Int -> IO a -> IO a
withDependencyServer port action =
  bracket
    (forkIO (runSettings (setHost "127.0.0.1" (setPort port (setTimeout 0 defaultSettings))) dependencyApplication))
    killThread
    (\_ -> threadDelay 100000 >> action)

dependencyApplication :: Application
dependencyApplication request respond =
  case (requestMethod request, pathInfo request) of
    (methodValue, ["admin", "v2", "clusters"]) | methodValue == methodGet ->
      respond (jsonReadyResponse "{\"status\":\"ready\"}")
    (methodValue, ["minio", "health", "ready"]) | methodValue == methodGet ->
      respond (jsonReadyResponse "{\"status\":\"ready\"}")
    _ ->
      respond (jsonReadyResponse "{\"status\":\"ready\"}")

jsonReadyResponse :: String -> Response
jsonReadyResponse body =
  responseLBS status200 [(hContentType, "application/json")] (fromString body)

healthyConfig :: Int -> AppConfig
healthyConfig port =
  AppConfig
    { appMode = ServerMode,
      pulsarHttpUrl = baseUrl port,
      pulsarBinaryUrl = "pulsar://studiomcp-pulsar:6650",
      minioEndpoint = baseUrl port,
      minioPublicEndpoint = baseUrl port,
      minioAccessKey = "minioadmin",
      minioSecretKey = "minioadmin123"
    }

degradedConfig :: Int -> AppConfig
degradedConfig port =
  (healthyConfig port)
    { pulsarHttpUrl = "http://127.0.0.1:39999"
    }

baseUrl :: Int -> Text
baseUrl port = fromString ("http://127.0.0.1:" <> show port)

{-# LANGUAGE OverloadedStrings #-}

module API.ReadinessSpec
  ( spec,
  )
where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Exception (bracket)
import Data.String (fromString)
import Data.Text qualified as Text
import Network.HTTP.Client (defaultManagerSettings, newManager)
import Network.HTTP.Types (Status, hContentType, methodGet, status200, status404)
import Network.Wai (Application, Response, pathInfo, requestMethod, responseLBS)
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort, setTimeout)
import StudioMCP.API.Readiness
import Test.Hspec (Spec, describe, it, shouldBe, shouldContain)

spec :: Spec
spec = do
  describe "buildReadinessReport" $ do
    it "marks the report blocked when any check is blocked" $ do
      let report =
            buildReadinessReport
              "studiomcp-test"
              [ readyCheck "pulsar" "dependency-ready" "ok"
              , blockedCheck "redis" "session-store-unavailable" "connection refused"
              ]
      readinessStatus report `shouldBe` ReadinessBlocked
      length (readinessBlockingChecks report) `shouldBe` 1
      Text.unpack (renderBlockingChecks report) `shouldContain` "redis=session-store-unavailable"

    it "marks the report ready when all checks pass" $ do
      let report =
            buildReadinessReport
              "studiomcp-test"
              [ readyCheck "pulsar" "dependency-ready" "ok"
              , readyCheck "minio" "dependency-ready" "ok"
              ]
      readinessStatus report `shouldBe` ReadinessReady
      readinessBlockingChecks report `shouldBe` []

  describe "probeAnyHttpCheck" $
    it "accepts the first successful readiness URL" $
      withReadinessServer 38113 $ do
        manager <- newManager defaultManagerSettings
        readinessCheck <-
          probeAnyHttpCheck
            manager
            "reference-model"
            [ "http://127.0.0.1:38113/api/tags"
            , "http://127.0.0.1:38113/healthz"
            ]
            [200]
            "reference-model-ready"
            "reference-model-unavailable"
        readinessCheckReady readinessCheck `shouldBe` True
        readinessCheckReason readinessCheck `shouldBe` "reference-model-ready"

withReadinessServer :: Int -> IO a -> IO a
withReadinessServer port action =
  bracket
    (forkIO (runSettings (setHost "127.0.0.1" (setPort port (setTimeout 0 defaultSettings))) readinessApplication))
    killThread
    (\_ -> threadDelay 100000 >> action)

readinessApplication :: Application
readinessApplication request respond =
  case (requestMethod request, pathInfo request) of
    (methodValue, ["healthz"]) | methodValue == methodGet ->
      respond (jsonResponse status200 "{\"status\":\"ready\"}")
    (methodValue, ["api", "tags"]) | methodValue == methodGet ->
      respond (jsonResponse status404 "{\"error\":\"not-ready\"}")
    _ ->
      respond (jsonResponse status404 "{\"error\":\"not-found\"}")

jsonResponse :: Status -> String -> Response
jsonResponse statusValue body =
  responseLBS statusValue [(hContentType, "application/json")] (fromString body)

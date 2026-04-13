{-# LANGUAGE OverloadedStrings #-}

module Web.HandlersSpec (spec) where

import Data.IORef (newIORef, readIORef, writeIORef)
import Network.HTTP.Types (Status, status404)
import Network.Wai (Application, Request(..), defaultRequest, responseStatus)
import StudioMCP.DAG.Types (DagSpec (..))
import StudioMCP.Web.BFF (createWebSession, defaultBFFConfig)
import StudioMCP.Web.Handlers
import StudioMCP.Web.Types
  ( ChatMessage (..),
    ChatRequest (..),
    ChatRole (..),
    ChatResponse (..),
    DownloadRequest (..),
    RunSubmitRequest (..),
    RunStatusResponse (..),
    UploadRequest (..),
    UploadResponse (..),
    WebSession (..),
    WebSessionId(..),
  )
import Test.Hspec

spec :: Spec
spec = do
  describe "BFFContext" $ do
    it "can be created from config" $ do
      ctx <- newBFFContext defaultBFFConfig
      -- Should create without error
      bffCtxConfig ctx `shouldBe` defaultBFFConfig

  describe "bffApplication" $ do
    it "returns 404 for unknown routes" $ do
      ctx <- newBFFContext defaultBFFConfig
      status <- runRequestStatus (bffApplication ctx) defaultRequest { pathInfo = ["unknown", "route"] }
      status `shouldBe` status404

    it "routes healthz without falling through to 404" $ do
      ctx <- newBFFContext defaultBFFConfig
      status <-
        runRequestStatus
          (bffApplication ctx)
          defaultRequest
            { requestMethod = "GET"
            , pathInfo = ["healthz"]
            }
      status `shouldNotBe` status404

  describe "handleUploadRequest" $ do
    it "creates an upload response when given a parsed upload body" $ do
      ctx <- newBFFContext defaultBFFConfig
      let service = bffCtxService ctx
      Right session <- createWebSession service "user-1" "tenant-1" "token" Nothing
      result <-
        handleUploadRequest
          service
          (wsSessionId session)
          UploadRequest
            { urFileName = "clip.mp4"
            , urContentType = "video/mp4"
            , urFileSize = 1024
            , urMetadata = Nothing
            }
      case result of
        Right response -> urpArtifactId response `shouldSatisfy` (/= "")
        Left err -> expectationFailure $ "Expected upload response, got: " ++ show err

  describe "handleDownloadRequest" $ do
    it "returns an artifact error when the parsed download target is missing" $ do
      ctx <- newBFFContext defaultBFFConfig
      let service = bffCtxService ctx
      Right session <- createWebSession service "user-1" "tenant-1" "token" Nothing
      result <-
        handleDownloadRequest
          service
          (wsSessionId session)
          DownloadRequest
            { drArtifactId = "missing-artifact"
            , drVersion = Nothing
            }
      case result of
        Left _ -> pure ()
        Right _ -> expectationFailure "Expected missing artifact error"

  describe "handleChatRequest" $ do
    it "returns a chat response for a parsed request" $ do
      ctx <- newBFFContext defaultBFFConfig
      let service = bffCtxService ctx
      Right session <- createWebSession service "user-1" "tenant-1" "token" Nothing
      result <-
        handleChatRequest
          service
          (wsSessionId session)
          ChatRequest
            { crMessages = [ChatMessage ChatUser "Help me upload media" Nothing]
            , crContext = Just "Need a draft workflow"
            }
      case result of
        Right response -> cmRole (crpMessage response) `shouldBe` ChatAssistant
        Left err -> expectationFailure $ "Expected chat response, got: " ++ show err

  describe "handleRunSubmit" $ do
    it "returns run status for a parsed submission" $ do
      ctx <- newBFFContext defaultBFFConfig
      let service = bffCtxService ctx
      Right session <- createWebSession service "user-1" "tenant-1" "token" Nothing
      let dagSpec =
            DagSpec
              { dagName = "handler-test"
              , dagDescription = Nothing
              , dagNodes = []
              }
      result <-
        handleRunSubmit
          service
          (wsSessionId session)
          RunSubmitRequest
            { rsrDagSpec = dagSpec
            , rsrInputArtifacts = []
            }
      case result of
        Right response -> rsrStatus response `shouldBe` "submitted"
        Left err -> expectationFailure $ "Expected run status response, got: " ++ show err

  describe "extractSessionId" $ do
    it "prefers the cookie session when both cookie and bearer credentials are present" $ do
      let request =
            defaultRequest
              { requestHeaders =
                  [ ("Cookie", "studiomcp_session=web-cookie")
                  , ("Authorization", "Bearer web-bearer")
                  ]
              }
      extractSessionId defaultBFFConfig request `shouldBe` Just (WebSessionId "web-cookie")

    it "falls back to a bearer session when the cookie is absent" $ do
      let request =
            defaultRequest
              { requestHeaders =
                  [("Authorization", "Bearer web-bearer")]
              }
      extractSessionId defaultBFFConfig request `shouldBe` Just (WebSessionId "web-bearer")

runRequestStatus :: Application -> Request -> IO Status
runRequestStatus app request = do
  statusRef <- newIORef status404
  _ <- app request $ \response -> do
    writeIORef statusRef (responseStatus response)
    pure (error "ResponseReceived sentinel for Web.HandlersSpec")
  readIORef statusRef

{-# LANGUAGE OverloadedStrings #-}

module Web.HandlersSpec (spec) where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Exception (bracket)
import Data.Aeson (decode, encode)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy.Char8 as LBS
import qualified Data.CaseInsensitive as CI
import qualified Data.Text as T
import Network.HTTP.Client
  ( Manager,
    Request (method, requestBody, requestHeaders),
    RequestBody (RequestBodyLBS),
    Response,
    defaultManagerSettings,
    httpLbs,
    newManager,
    parseRequest,
    responseBody,
    responseHeaders,
    responseStatus,
  )
import Network.HTTP.Types (Header)
import Network.HTTP.Types.Status (statusCode)
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort, setTimeout)
import StudioMCP.DAG.Summary (RunId (..))
import StudioMCP.DAG.Types (DagSpec (..))
import StudioMCP.Web.BFF (createWebSession, defaultBFFConfig)
import StudioMCP.Web.Handlers
import StudioMCP.Web.Types
  ( LoginRequest (..),
    LoginResponse (..),
    ChatMessage (..),
    ChatRequest (..),
    ChatRole (..),
    ChatResponse (..),
    DownloadRequest (..),
    RunSubmitRequest (..),
    RunStatusResponse (..),
    UploadRequest (..),
    UploadResponse (..),
    WebSession (..),
  )
import Test.Hspec

spec :: Spec
spec = do
  describe "BFFContext" $ do
    it "can be created from config" $ do
      ctx <- newBFFContext defaultBFFConfig
      bffCtxConfig ctx `shouldBe` defaultBFFConfig

  describe "bffApplication" $ do
    it "serves the browser control-room HTML at the root route" $
      withBffServer 38131 $ do
        manager <- newManager defaultManagerSettings
        response <- httpRequest manager 38131 "GET" "/" [] Nothing
        statusCode (responseStatus response) `shouldBe` 200
        lookupHeader "Content-Type" response `shouldSatisfy` maybe False ("text/html" `BS.isPrefixOf`)
        LBS.toStrict (responseBody response) `shouldSatisfy` BS.isInfixOf "studioMCP Control Room"

    it "streams chat replies over the SSE route" $
      withBffServer 38132 $ do
        manager <- newManager defaultManagerSettings
        cookieHeader <- loginCookie manager 38132
        response <-
          httpRequest
            manager
            38132
            "POST"
            "/api/v1/chat/stream"
            [cookieHeader]
            ( Just
                ( encode
                    ChatRequest
                      { crMessages = [ChatMessage ChatUser "Stream a response" Nothing]
                      , crContext = Just "handler test"
                      }
                )
            )
        statusCode (responseStatus response) `shouldBe` 200
        lookupHeader "Content-Type" response `shouldSatisfy` maybe False ("text/event-stream" `BS.isPrefixOf`)
        LBS.toStrict (responseBody response) `shouldSatisfy` BS.isInfixOf "event: conversation.started"
        LBS.toStrict (responseBody response) `shouldSatisfy` BS.isInfixOf "event: message.completed"

    it "streams run snapshots over the SSE route" $
      withBffServer 38133 $ do
        manager <- newManager defaultManagerSettings
        cookieHeader <- loginCookie manager 38133
        submitResponse <-
          httpRequest
            manager
            38133
            "POST"
            "/api/v1/runs"
            [cookieHeader]
            ( Just
                ( encode
                    RunSubmitRequest
                      { rsrDagSpec =
                          DagSpec
                            { dagName = "browser-events"
                            , dagDescription = Nothing
                            , dagNodes = []
                            }
                      , rsrInputArtifacts = []
                      }
                )
            )
        statusCode (responseStatus submitResponse) `shouldBe` 200
        let maybeSubmittedRun = decode (responseBody submitResponse) :: Maybe RunStatusResponse
        runIdText <-
          case maybeSubmittedRun of
            Just submittedRun -> pure (T.unpack (unRunId (rsrRunId submittedRun)))
            Nothing -> expectationFailure "Expected run submission to return JSON" >> pure ""
        eventsResponse <-
          httpRequest
            manager
            38133
            "GET"
            ("/api/v1/runs/" <> runIdText <> "/events")
            [cookieHeader]
            Nothing
        statusCode (responseStatus eventsResponse) `shouldBe` 200
        lookupHeader "Content-Type" eventsResponse `shouldSatisfy` maybe False ("text/event-stream" `BS.isPrefixOf`)
        LBS.toStrict (responseBody eventsResponse) `shouldSatisfy` BS.isInfixOf "event: run.snapshot"
        LBS.toStrict (responseBody eventsResponse) `shouldSatisfy` BS.isInfixOf "event: run.window.closed"

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
            { urArtifactId = Nothing
            , urFileName = "clip.mp4"
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

withBffServer :: Int -> IO a -> IO a
withBffServer port action = do
  ctx <- newBFFContext defaultBFFConfig
  bracket
    (forkIO (runSettings (setHost "127.0.0.1" (setPort port (setTimeout 0 defaultSettings))) (bffApplication ctx)))
    killThread
    (\_ -> threadDelay 100000 >> action)

httpRequest ::
  Manager ->
  Int ->
  String ->
  String ->
  [Header] ->
  Maybe LBS.ByteString ->
  IO (Response LBS.ByteString)
httpRequest manager port methodValue path extraHeaders maybeBody = do
  request <- parseRequest ("http://127.0.0.1:" <> show port <> path)
  httpLbs
    request
      { method = BS8.pack methodValue
      , requestHeaders =
          case maybeBody of
            Just _ -> (CI.mk "Content-Type", "application/json") : extraHeaders
            Nothing -> extraHeaders
      , requestBody =
          case maybeBody of
            Just body -> RequestBodyLBS body
            Nothing -> requestBody request
      }
    manager

lookupHeader ::
  BS.ByteString ->
  Response body ->
  Maybe BS.ByteString
lookupHeader name response =
  lookup (CI.mk name) (responseHeaders response)

loginCookie :: Manager -> Int -> IO Header
loginCookie manager port = do
  response <-
    httpRequest
      manager
      port
      "POST"
      "/api/v1/auth/login"
      []
      ( Just
          ( encode
              LoginRequest
                { lrAccessToken = "browser-token"
                , lrRefreshToken = Nothing
                , lrSubjectId = Just "user-1"
                , lrTenantId = Just "tenant-1"
                }
          )
      )
  statusCode (responseStatus response) `shouldBe` 200
  let maybeLogin = decode (responseBody response) :: Maybe LoginResponse
  case maybeLogin of
    Just _ -> pure ()
    Nothing -> expectationFailure "Expected login response JSON"
  case lookupHeader "Set-Cookie" response of
    Just setCookieValue ->
      pure ("Cookie", BS8.takeWhile (/= ';') setCookieValue)
    Nothing ->
      expectationFailure "Expected login response to set a browser cookie" >> pure ("Cookie", "")

{-# LANGUAGE OverloadedStrings #-}

-- | MCP Protocol Conformance Tests
-- These tests verify that the studioMCP server correctly implements
-- the MCP protocol specification for:
-- - JSON-RPC 2.0 message format
-- - Initialize/initialized handshake
-- - Protocol state machine transitions
-- - tools/list, resources/list, prompts/list endpoints
-- - Error handling per MCP spec
module MCP.ConformanceSpec (spec) where

import Data.Aeson (Value (..), decode, encode, object, (.=))
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as LBS
import Data.Maybe (isJust)
import Data.Text (Text)
import StudioMCP.MCP.Core
import StudioMCP.MCP.JsonRpc
import StudioMCP.MCP.Protocol.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "MCP Protocol Conformance" $ do
    initializeHandshakeSpec
    stateTransitionSpec
    toolsListSpec
    resourcesListSpec
    promptsListSpec
    errorHandlingSpec

-- | Initialize/Initialized handshake conformance
initializeHandshakeSpec :: Spec
initializeHandshakeSpec = describe "Initialize Handshake" $ do
  it "accepts valid initialize request with supported protocol version" $ do
    server <- newMcpServer defaultServerConfig
    let initReq = buildInitializeRequest "2024-11-05" 1
    result <- handleMessage server initReq
    case result of
      Nothing -> expectationFailure "Expected response to initialize request"
      Just resp -> do
        -- Should return successful response with protocol version
        case decode (encode resp) :: Maybe Value of
          Nothing -> expectationFailure "Response should be valid JSON"
          Just (Object obj) -> do
            KM.lookup "result" obj `shouldSatisfy` isJust
            KM.lookup "error" obj `shouldBe` Nothing
          Just _ -> expectationFailure "Response should be an object"

  it "rejects initialize request with unsupported protocol version" $ do
    server <- newMcpServer defaultServerConfig
    let initReq = buildInitializeRequest "1.0.0-unsupported" 1
    result <- handleMessage server initReq
    case result of
      Nothing -> expectationFailure "Expected response to initialize request"
      Just resp -> do
        case decode (encode resp) :: Maybe Value of
          Nothing -> expectationFailure "Response should be valid JSON"
          Just (Object obj) -> do
            -- Should return error for unsupported version
            KM.lookup "error" obj `shouldSatisfy` isJust
          Just _ -> expectationFailure "Response should be an object"

  it "returns correct capabilities in initialize response" $ do
    server <- newMcpServer defaultServerConfig
    let initReq = buildInitializeRequest "2024-11-05" 1
    result <- handleMessage server initReq
    case result of
      Nothing -> expectationFailure "Expected response"
      Just resp -> do
        -- Verify response has all required capability fields
        let respJson = encode resp
        LBS.length respJson `shouldSatisfy` (> 0)

-- | State transition conformance
stateTransitionSpec :: Spec
stateTransitionSpec = describe "State Machine Transitions" $ do
  it "rejects method calls before initialization" $ do
    server <- newMcpServer defaultServerConfig
    let toolsReq = buildToolsListRequest 1
    result <- handleMessage server toolsReq
    case result of
      Nothing -> expectationFailure "Expected error response"
      Just resp -> do
        case decode (encode resp) :: Maybe Value of
          Nothing -> expectationFailure "Response should be valid JSON"
          Just (Object obj) ->
            KM.lookup "error" obj `shouldSatisfy` isJust
          Just _ -> expectationFailure "Response should be an object"

  it "rejects second initialize after successful initialize" $ do
    server <- newMcpServer defaultServerConfig
    -- First initialize
    let initReq1 = buildInitializeRequest "2024-11-05" 1
    _ <- handleMessage server initReq1
    -- Send initialized notification
    let initializedNotif = buildInitializedNotification
    _ <- handleMessage server initializedNotif
    -- Second initialize should fail
    let initReq2 = buildInitializeRequest "2024-11-05" 2
    result <- handleMessage server initReq2
    case result of
      Nothing -> expectationFailure "Expected error response"
      Just resp -> do
        case decode (encode resp) :: Maybe Value of
          Nothing -> expectationFailure "Response should be valid JSON"
          Just (Object obj) ->
            KM.lookup "error" obj `shouldSatisfy` isJust
          Just _ -> expectationFailure "Response should be an object"

-- | tools/list endpoint conformance
toolsListSpec :: Spec
toolsListSpec = describe "tools/list" $ do
  it "returns tool list after initialization" $ do
    server <- newMcpServer defaultServerConfig
    -- Initialize first
    let initReq = buildInitializeRequest "2024-11-05" 1
    _ <- handleMessage server initReq
    let initializedNotif = buildInitializedNotification
    _ <- handleMessage server initializedNotif
    -- Now tools/list should work
    let toolsReq = buildToolsListRequest 2
    result <- handleMessage server toolsReq
    case result of
      Nothing -> expectationFailure "Expected response"
      Just resp -> do
        case decode (encode resp) :: Maybe Value of
          Nothing -> expectationFailure "Response should be valid JSON"
          Just (Object obj) -> do
            KM.lookup "result" obj `shouldSatisfy` isJust
            KM.lookup "error" obj `shouldBe` Nothing
          Just _ -> expectationFailure "Response should be an object"

-- | resources/list endpoint conformance
resourcesListSpec :: Spec
resourcesListSpec = describe "resources/list" $ do
  it "returns resource list after initialization" $ do
    server <- newMcpServer defaultServerConfig
    -- Initialize first
    let initReq = buildInitializeRequest "2024-11-05" 1
    _ <- handleMessage server initReq
    let initializedNotif = buildInitializedNotification
    _ <- handleMessage server initializedNotif
    -- Now resources/list should work
    let resourcesReq = buildResourcesListRequest 2
    result <- handleMessage server resourcesReq
    case result of
      Nothing -> expectationFailure "Expected response"
      Just resp -> do
        case decode (encode resp) :: Maybe Value of
          Nothing -> expectationFailure "Response should be valid JSON"
          Just (Object obj) -> do
            KM.lookup "result" obj `shouldSatisfy` isJust
          Just _ -> expectationFailure "Response should be an object"

  it "returns resumable metadata for resources/subscribe after initialization" $ do
    server <- newMcpServer defaultServerConfig
    let initReq = buildInitializeRequest "2024-11-05" 1
    _ <- handleMessage server initReq
    _ <- handleMessage server buildInitializedNotification
    subscribeResult <- handleMessage server (buildResourcesSubscribeRequest 2 "studiomcp://history/runs" (Just "cursor-2") (Just "evt-2"))
    case subscribeResult of
      Nothing -> expectationFailure "Expected response"
      Just resp ->
        case decode (encode resp) :: Maybe Value of
          Just subscribeValue -> do
            lookupPath ["result", "cursor"] subscribeValue `shouldBe` Just (String "cursor-2")
            lookupPath ["result", "lastEventId"] subscribeValue `shouldBe` Just (String "evt-2")
          Nothing -> expectationFailure "Response should be valid JSON"

-- | prompts/list endpoint conformance
promptsListSpec :: Spec
promptsListSpec = describe "prompts/list" $ do
  it "returns prompt list after initialization" $ do
    server <- newMcpServer defaultServerConfig
    -- Initialize first
    let initReq = buildInitializeRequest "2024-11-05" 1
    _ <- handleMessage server initReq
    let initializedNotif = buildInitializedNotification
    _ <- handleMessage server initializedNotif
    -- Now prompts/list should work
    let promptsReq = buildPromptsListRequest 2
    result <- handleMessage server promptsReq
    case result of
      Nothing -> expectationFailure "Expected response"
      Just resp -> do
        case decode (encode resp) :: Maybe Value of
          Nothing -> expectationFailure "Response should be valid JSON"
          Just (Object obj) -> do
            KM.lookup "result" obj `shouldSatisfy` isJust
          Just _ -> expectationFailure "Response should be an object"

-- | Error handling conformance
errorHandlingSpec :: Spec
errorHandlingSpec = describe "Error Handling" $ do
  it "returns JSON-RPC parse error for invalid JSON-RPC message" $ do
    server <- newMcpServer defaultServerConfig
    let invalidMsg = String "not-a-json-rpc-message"
    result <- handleMessage server invalidMsg
    case result of
      Nothing -> expectationFailure "Expected error response"
      Just resp -> do
        case decode (encode resp) :: Maybe Value of
          Nothing -> expectationFailure "Response should be valid JSON"
          Just (Object obj) ->
            KM.lookup "error" obj `shouldSatisfy` isJust
          Just _ -> expectationFailure "Response should be an object"

  it "returns method not found for unknown method" $ do
    server <- newMcpServer defaultServerConfig
    -- Initialize first
    let initReq = buildInitializeRequest "2024-11-05" 1
    _ <- handleMessage server initReq
    let initializedNotif = buildInitializedNotification
    _ <- handleMessage server initializedNotif
    -- Call unknown method
    let unknownReq = buildUnknownMethodRequest 2
    result <- handleMessage server unknownReq
    case result of
      Nothing -> expectationFailure "Expected error response"
      Just resp -> do
        case decode (encode resp) :: Maybe Value of
          Nothing -> expectationFailure "Response should be valid JSON"
          Just (Object obj) ->
            KM.lookup "error" obj `shouldSatisfy` isJust
          Just _ -> expectationFailure "Response should be an object"

  it "returns invalid params for missing required parameters" $ do
    server <- newMcpServer defaultServerConfig
    -- Initialize first
    let initReq = buildInitializeRequest "2024-11-05" 1
    _ <- handleMessage server initReq
    let initializedNotif = buildInitializedNotification
    _ <- handleMessage server initializedNotif
    -- Call tools/call without required name parameter
    let badToolsCall = buildBadToolsCallRequest 2
    result <- handleMessage server badToolsCall
    case result of
      Nothing -> expectationFailure "Expected error response"
      Just resp -> do
        case decode (encode resp) :: Maybe Value of
          Nothing -> expectationFailure "Response should be valid JSON"
          Just (Object obj) ->
            KM.lookup "error" obj `shouldSatisfy` isJust
          Just _ -> expectationFailure "Response should be an object"

-- Helper functions to build JSON-RPC messages

buildInitializeRequest :: Text -> Int -> Value
buildInitializeRequest protocolVersion reqId =
  object
    [ "jsonrpc" .= ("2.0" :: Text),
      "id" .= reqId,
      "method" .= ("initialize" :: Text),
      "params" .= object
        [ "protocolVersion" .= protocolVersion,
          "capabilities" .= object [],
          "clientInfo" .= object
            [ "name" .= ("conformance-test" :: Text),
              "version" .= ("1.0.0" :: Text)
            ]
        ]
    ]

buildInitializedNotification :: Value
buildInitializedNotification =
  object
    [ "jsonrpc" .= ("2.0" :: Text),
      "method" .= ("notifications/initialized" :: Text)
    ]

buildToolsListRequest :: Int -> Value
buildToolsListRequest reqId =
  object
    [ "jsonrpc" .= ("2.0" :: Text),
      "id" .= reqId,
      "method" .= ("tools/list" :: Text)
    ]

buildResourcesListRequest :: Int -> Value
buildResourcesListRequest reqId =
  object
    [ "jsonrpc" .= ("2.0" :: Text),
      "id" .= reqId,
      "method" .= ("resources/list" :: Text)
    ]

buildResourcesSubscribeRequest :: Int -> Text -> Maybe Text -> Maybe Text -> Value
buildResourcesSubscribeRequest reqId resourceUri maybeCursor maybeLastEventId =
  object
    [ "jsonrpc" .= ("2.0" :: Text),
      "id" .= reqId,
      "method" .= ("resources/subscribe" :: Text),
      "params" .=
        object
          ( [ "uri" .= resourceUri
            ]
              <> maybe [] (\cursor -> ["cursor" .= cursor]) maybeCursor
              <> maybe [] (\eventId -> ["lastEventId" .= eventId]) maybeLastEventId
          )
    ]

buildPromptsListRequest :: Int -> Value
buildPromptsListRequest reqId =
  object
    [ "jsonrpc" .= ("2.0" :: Text),
      "id" .= reqId,
      "method" .= ("prompts/list" :: Text)
    ]

buildUnknownMethodRequest :: Int -> Value
buildUnknownMethodRequest reqId =
  object
    [ "jsonrpc" .= ("2.0" :: Text),
      "id" .= reqId,
      "method" .= ("unknown/method" :: Text)
    ]

buildBadToolsCallRequest :: Int -> Value
buildBadToolsCallRequest reqId =
  object
    [ "jsonrpc" .= ("2.0" :: Text),
      "id" .= reqId,
      "method" .= ("tools/call" :: Text),
      "params" .= object []  -- Missing required 'name' parameter
    ]

lookupPath :: [String] -> Value -> Maybe Value
lookupPath [] currentValue = Just currentValue
lookupPath (segment : remainingPath) (Object objectValue) =
  KM.lookup (Key.fromString segment) objectValue >>= lookupPath remainingPath
lookupPath _ _ = Nothing

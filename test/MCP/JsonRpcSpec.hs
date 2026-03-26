{-# LANGUAGE OverloadedStrings #-}

module MCP.JsonRpcSpec
  ( spec,
  )
where

import Data.Aeson (decode, eitherDecode, encode, object, (.=))
import Data.Maybe (isJust)
import StudioMCP.MCP.JsonRpc
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
  describe "JSON-RPC 2.0 Request" $ do
    it "round-trips request JSON with string ID" $ do
      let request =
            JsonRpcRequest
              { reqJsonRpc = JsonRpcVersion "2.0",
                reqId = RequestIdString "abc123",
                reqMethod = "test/method",
                reqParams = Just (object ["key" .= ("value" :: String)])
              }
      eitherDecode (encode request) `shouldBe` Right request

    it "round-trips request JSON with numeric ID" $ do
      let request =
            JsonRpcRequest
              { reqJsonRpc = JsonRpcVersion "2.0",
                reqId = RequestIdNumber 42,
                reqMethod = "test/method",
                reqParams = Nothing
              }
      eitherDecode (encode request) `shouldBe` Right request

    it "rejects requests with invalid JSON-RPC version" $ do
      let invalidJson =
            object
              [ "jsonrpc" .= ("1.0" :: String),
                "id" .= (1 :: Int),
                "method" .= ("test" :: String)
              ]
      (decode (encode invalidJson) :: Maybe JsonRpcRequest) `shouldBe` Nothing

  describe "JSON-RPC 2.0 Notification" $ do
    it "round-trips notification JSON" $ do
      let notification =
            JsonRpcNotification
              { notifJsonRpc = JsonRpcVersion "2.0",
                notifMethod = "notifications/initialized",
                notifParams = Nothing
              }
      eitherDecode (encode notification) `shouldBe` Right notification

  describe "JSON-RPC 2.0 Response" $ do
    it "round-trips success response" $ do
      let response =
            JsonRpcResponse
              { respJsonRpc = JsonRpcVersion "2.0",
                respId = RequestIdNumber 1,
                respResult = Just (object ["data" .= ("result" :: String)]),
                respError = Nothing
              }
      eitherDecode (encode response) `shouldBe` Right response

    it "round-trips error response" $ do
      let err = JsonRpcError InvalidParams "Missing required parameter" Nothing
      let response =
            JsonRpcResponse
              { respJsonRpc = JsonRpcVersion "2.0",
                respId = RequestIdNumber 1,
                respResult = Nothing,
                respError = Just err
              }
      eitherDecode (encode response) `shouldBe` Right response

  describe "JSON-RPC 2.0 Error Codes" $ do
    it "serializes standard error codes correctly" $ do
      encode ParseError `shouldBe` "-32700"
      encode InvalidRequest `shouldBe` "-32600"
      encode MethodNotFound `shouldBe` "-32601"
      encode InvalidParams `shouldBe` "-32602"
      encode InternalError `shouldBe` "-32603"

    it "serializes MCP protocol error codes correctly" $ do
      encode ServerNotInitialized `shouldBe` "-32002"
      encode UnsupportedProtocolVersion `shouldBe` "-32003"
      encode CapabilityNotSupported `shouldBe` "-32004"

    it "serializes domain error codes correctly" $ do
      encode AuthRequired `shouldBe` "-31001"
      encode AuthDenied `shouldBe` "-31002"
      encode TenantNotFound `shouldBe` "-31003"
      encode DagValidationFailed `shouldBe` "-31004"
      encode ExecutionFailed `shouldBe` "-31005"
      encode ResourceNotFound `shouldBe` "-31006"
      encode ArtifactAccessDenied `shouldBe` "-31007"
      encode QuotaExceeded `shouldBe` "-31008"

    it "round-trips error codes" $ do
      eitherDecode (encode ParseError) `shouldBe` Right ParseError
      eitherDecode (encode InvalidParams) `shouldBe` Right InvalidParams
      eitherDecode (encode ServerNotInitialized) `shouldBe` Right ServerNotInitialized
      eitherDecode (encode AuthRequired) `shouldBe` Right AuthRequired

  describe "JSON-RPC 2.0 Message Parsing" $ do
    it "parses request messages correctly" $ do
      let requestJson =
            object
              [ "jsonrpc" .= ("2.0" :: String),
                "id" .= (1 :: Int),
                "method" .= ("test" :: String)
              ]
      let parsed = decode (encode requestJson) :: Maybe JsonRpcMessage
      parsed `shouldSatisfy` isJust
      case parsed of
        Just (MsgRequest _) -> pure ()
        _ -> fail "Expected MsgRequest"

    it "parses notification messages correctly" $ do
      let notificationJson =
            object
              [ "jsonrpc" .= ("2.0" :: String),
                "method" .= ("notifications/test" :: String)
              ]
      let parsed = decode (encode notificationJson) :: Maybe JsonRpcMessage
      parsed `shouldSatisfy` isJust
      case parsed of
        Just (MsgNotification _) -> pure ()
        _ -> fail "Expected MsgNotification"

    it "parses response messages correctly" $ do
      let responseJson =
            object
              [ "jsonrpc" .= ("2.0" :: String),
                "id" .= (1 :: Int),
                "result" .= object []
              ]
      let parsed = decode (encode responseJson) :: Maybe JsonRpcMessage
      parsed `shouldSatisfy` isJust
      case parsed of
        Just (MsgResponse _) -> pure ()
        _ -> fail "Expected MsgResponse"

    it "identifies notifications correctly" $ do
      let notif =
            JsonRpcNotification
              { notifJsonRpc = JsonRpcVersion "2.0",
                notifMethod = "test",
                notifParams = Nothing
              }
      isNotification (MsgNotification notif) `shouldBe` True
      let req =
            JsonRpcRequest
              { reqJsonRpc = JsonRpcVersion "2.0",
                reqId = RequestIdNumber 1,
                reqMethod = "test",
                reqParams = Nothing
              }
      isNotification (MsgRequest req) `shouldBe` False

  describe "Error Constructors" $ do
    it "creates parse errors correctly" $ do
      let err = parseError "Invalid syntax"
      errCode err `shouldBe` ParseError
      errMessage err `shouldBe` "Invalid syntax"
      errData err `shouldBe` Nothing

    it "creates method not found errors correctly" $ do
      let err = methodNotFound "unknown/method"
      errCode err `shouldBe` MethodNotFound
      errMessage err `shouldBe` "unknown/method"

    it "creates server not initialized error correctly" $ do
      errCode serverNotInitialized `shouldBe` ServerNotInitialized

  describe "Response Builders" $ do
    it "creates success responses correctly" $ do
      let reqId = RequestIdNumber 42
      let result = object ["status" .= ("ok" :: String)]
      let response = makeResponse reqId result
      respId response `shouldBe` reqId
      respResult response `shouldBe` Just result
      respError response `shouldBe` Nothing

    it "creates error responses correctly" $ do
      let reqId = RequestIdString "req-1"
      let err = invalidParams "Missing field"
      let response = makeErrorResponse reqId err
      respId response `shouldBe` reqId
      respResult response `shouldBe` Nothing
      respError response `shouldBe` Just err

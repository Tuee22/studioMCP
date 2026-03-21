{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Inference.ReferenceModel
  ( ReferenceModelConfig (..),
    requestReferenceAdvice,
  )
where

import Control.Exception (SomeException, try)
import Data.Aeson
  ( FromJSON (parseJSON),
    eitherDecode,
    encode,
    object,
    withObject,
    (.:),
    (.=),
  )
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Map.Strict qualified as Map
import Network.HTTP.Client
  ( Manager,
    Request,
    Request (method, requestBody, requestHeaders),
    RequestBody (RequestBodyLBS),
    Response,
    httpLbs,
    parseRequest,
    responseBody,
    responseStatus,
  )
import Network.HTTP.Types.Status (statusCode)
import StudioMCP.Result.Failure
  ( FailureCategory (ToolProcessFailure),
    FailureDetail (..),
  )

newtype ReferenceModelConfig = ReferenceModelConfig
  { referenceModelUrl :: String
  }
  deriving (Eq, Show)

requestReferenceAdvice :: Manager -> ReferenceModelConfig -> Text -> IO (Either FailureDetail Text)
requestReferenceAdvice manager referenceModelConfig promptText = do
  requestOrException <- try (parseRequest (referenceModelUrl referenceModelConfig)) :: IO (Either SomeException Request)
  case requestOrException of
    Left exn ->
      pure (Left (referenceModelUnavailable (show exn)))
    Right request -> do
      responseOrException <-
        try
          ( httpLbs
              request
                { method = "POST",
                  requestHeaders = [("Content-Type", "application/json")],
                  requestBody =
                    RequestBodyLBS
                      ( encode
                          ( object
                              [ "prompt" .= promptText,
                                "stream" .= False
                              ]
                          )
                      )
                }
              manager
          ) :: IO (Either SomeException (Response LBS.ByteString))
      case responseOrException of
        Left exn ->
          pure (Left (referenceModelUnavailable (show exn)))
        Right response
          | statusCode (responseStatus response) /= 200 ->
              pure
                ( Left
                    FailureDetail
                      { failureCategory = ToolProcessFailure,
                        failureCode = "reference-model-http-failed",
                        failureMessage = "The reference model host returned a non-success HTTP status.",
                        failureRetryable = True,
                        failureContext =
                          Map.fromList
                            [("statusCode", Text.pack (show (statusCode (responseStatus response))))]
                      }
                )
          | otherwise ->
              pure
                ( case parseResponse (responseBody response) of
                    Left failureDetail -> Left failureDetail
                    Right adviceText -> Right adviceText
                )

newtype ReferenceModelResponse = ReferenceModelResponse
  { responseText :: Text
  }

instance FromJSON ReferenceModelResponse where
  parseJSON = withObject "ReferenceModelResponse" $ \obj ->
    ReferenceModelResponse <$> obj .: "response"

parseResponse :: LBS.ByteString -> Either FailureDetail Text
parseResponse responseBodyBytes =
  case eitherDecode responseBodyBytes of
    Left decodeError ->
      Left
        FailureDetail
          { failureCategory = ToolProcessFailure,
            failureCode = "reference-model-decode-failed",
            failureMessage = "The reference model host returned a payload that did not match the expected JSON contract.",
            failureRetryable = False,
            failureContext = Map.fromList [("decodeError", Text.pack decodeError)]
          }
    Right responseValue -> Right (responseText responseValue)

referenceModelUnavailable :: String -> FailureDetail
referenceModelUnavailable detailText =
  FailureDetail
    { failureCategory = ToolProcessFailure,
      failureCode = "reference-model-unavailable",
      failureMessage = "The reference model host could not be reached.",
      failureRetryable = True,
      failureContext = Map.fromList [("detail", Text.pack detailText)]
    }

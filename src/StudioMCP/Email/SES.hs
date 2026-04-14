{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Email.SES
  ( SESConfig (..),
    loadSESConfigFromEnv,
    sendRenderedEmail,
  )
where

import Control.Exception (SomeException, try)
import Crypto.Hash (Digest, SHA256, hash)
import Crypto.MAC.HMAC (HMAC, hmac)
import Data.Aeson (encode, object, (.=))
import Data.ByteArray (convert)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import qualified Data.ByteString.Char8 as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Text.Encoding.Error (lenientDecode)
import Data.Time (UTCTime, getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.Maybe (fromMaybe)
import Network.HTTP.Client
  ( Request (method, path, requestBody, requestHeaders),
    RequestBody (RequestBodyLBS),
    Response,
    defaultManagerSettings,
    httpLbs,
    newManager,
    parseRequest,
    responseBody,
    responseStatus,
  )
import Network.HTTP.Types (status200, status201, status202)
import StudioMCP.Email.Templates (RenderedEmail (..))
import StudioMCP.Result.Failure
  ( FailureCategory (ToolProcessFailure),
    FailureDetail (..),
  )
import qualified Data.Map.Strict as FailureMap
import System.Environment (lookupEnv)

data SESConfig = SESConfig
  { sesRegion :: Text,
    sesAccessKeyId :: Text,
    sesSecretAccessKey :: Text,
    sesSenderAddress :: Text,
    sesEndpoint :: Text
  }
  deriving (Eq, Show)

loadSESConfigFromEnv :: IO SESConfig
loadSESConfigFromEnv = do
  region <- maybe "us-east-1" Text.pack <$> lookupEnv "STUDIOMCP_SES_REGION"
  accessKeyId <- maybe "" Text.pack <$> lookupEnv "AWS_ACCESS_KEY_ID"
  secretAccessKey <- maybe "" Text.pack <$> lookupEnv "AWS_SECRET_ACCESS_KEY"
  senderAddress <- maybe "no-reply@resolvefintech.com" Text.pack <$> lookupEnv "STUDIOMCP_SES_SENDER"
  endpointOverride <- lookupEnv "STUDIOMCP_SES_ENDPOINT"
  let endpoint =
        maybe
          ("https://email." <> region <> ".amazonaws.com/v2/email/outbound-emails")
          Text.pack
          endpointOverride
  pure
    SESConfig
      { sesRegion = region,
        sesAccessKeyId = accessKeyId,
        sesSecretAccessKey = secretAccessKey,
        sesSenderAddress = senderAddress,
        sesEndpoint = endpoint
      }

sendRenderedEmail :: SESConfig -> Text -> RenderedEmail -> IO (Either FailureDetail Text)
sendRenderedEmail sesConfig recipientAddress renderedEmail = do
  requestResult <- try (signedSesRequest sesConfig recipientAddress renderedEmail) :: IO (Either SomeException Request)
  case requestResult of
    Left exn -> pure (Left (sesFailure "ses-request-build-failed" (Text.pack (show exn))))
    Right request -> do
      manager <- newManager defaultManagerSettings
      responseResult <- try (httpLbs request manager) :: IO (Either SomeException (Response LBS.ByteString))
      pure $
        case responseResult of
          Left exn -> Left (sesFailure "ses-send-failed" (Text.pack (show exn)))
          Right response
            | responseStatus response `elem` [status200, status201, status202] ->
                Right (TextEncoding.decodeUtf8With lenientDecode (LBS.toStrict (responseBody response)))
            | otherwise ->
                Left
                  FailureDetail
                    { failureCategory = ToolProcessFailure,
                      failureCode = "ses-send-rejected",
                      failureMessage = "The SES endpoint rejected the send request.",
                      failureRetryable = True,
                      failureContext =
                        FailureMap.fromList
                          [ ("status", Text.pack (show (responseStatus response))),
                            ("body", Text.take 240 (TextEncoding.decodeUtf8With lenientDecode (LBS.toStrict (responseBody response))))
                          ]
                    }

signedSesRequest :: SESConfig -> Text -> RenderedEmail -> IO Request
signedSesRequest sesConfig recipientAddress renderedEmail = do
  now <- getCurrentTime
  request <- parseRequest (Text.unpack (sesEndpoint sesConfig))
  let payload =
        encode
          ( object
              [ "FromEmailAddress" .= sesSenderAddress sesConfig,
                "Destination" .= object ["ToAddresses" .= [recipientAddress]],
                "Content" .=
                  object
                    [ "Simple" .=
                        object
                          [ "Subject" .= object ["Data" .= reSubject renderedEmail],
                            "Body" .=
                              object
                                [ "Text" .= object ["Data" .= reTextBody renderedEmail],
                                  "Html" .= object ["Data" .= reHtmlBody renderedEmail]
                                ]
                          ]
                    ]
              ]
          )
      amzDate = formatAmzDate now
      credentialDate = formatCredentialDate now
      payloadHash = sha256Lazy payload
      hostHeader = endpointHost (sesEndpoint sesConfig)
      canonicalHeaders =
        [ ("content-type", "application/json"),
          ("host", hostHeader),
          ("x-amz-content-sha256", payloadHash),
          ("x-amz-date", amzDate)
        ]
      signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"
      canonicalRequest =
        Text.intercalate
          "\n"
          [ "POST",
            requestPath request,
            "",
            renderCanonicalHeaders canonicalHeaders,
            signedHeaders,
            payloadHash
          ]
      scope = credentialDate <> "/" <> sesRegion sesConfig <> "/ses/aws4_request"
      stringToSign =
        Text.intercalate
          "\n"
          [ "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            sha256Text canonicalRequest
          ]
      signature =
        hmacSha256Hex
          (signingKey (sesSecretAccessKey sesConfig) credentialDate (sesRegion sesConfig) "ses")
          stringToSign
      authorizationHeader =
        TextEncoding.encodeUtf8 $
          "AWS4-HMAC-SHA256 Credential="
            <> sesAccessKeyId sesConfig
            <> "/"
            <> scope
            <> ", SignedHeaders="
            <> signedHeaders
            <> ", Signature="
            <> signature
  pure
    request
      { method = "POST",
        requestBody = RequestBodyLBS payload,
        requestHeaders =
          [ ("Content-Type", "application/json"),
            ("Host", TextEncoding.encodeUtf8 hostHeader),
            ("X-Amz-Content-Sha256", TextEncoding.encodeUtf8 payloadHash),
            ("X-Amz-Date", TextEncoding.encodeUtf8 amzDate),
            ("Authorization", authorizationHeader)
          ]
      }

endpointHost :: Text -> Text
endpointHost endpoint =
  Text.takeWhile (/= '/')
    ( fromMaybe strippedHttps (Text.stripPrefix "http://" strippedHttps)
    )
  where
    strippedHttps = fromMaybe endpoint (Text.stripPrefix "https://" endpoint)

requestPath :: Request -> Text
requestPath request =
  let pathBytes = BS.takeWhile (/= '?') (path request)
   in if BS.null pathBytes
        then "/"
        else TextEncoding.decodeUtf8 pathBytes

renderCanonicalHeaders :: [(Text, Text)] -> Text
renderCanonicalHeaders headers =
  Text.concat [name <> ":" <> Text.strip value <> "\n" | (name, value) <- headers]

formatAmzDate :: UTCTime -> Text
formatAmzDate =
  Text.pack . formatTime defaultTimeLocale "%Y%m%dT%H%M%SZ"

formatCredentialDate :: UTCTime -> Text
formatCredentialDate =
  Text.pack . formatTime defaultTimeLocale "%Y%m%d"

sha256Text :: Text -> Text
sha256Text =
  TextEncoding.decodeUtf8 . convertToBase Base16 . (hash . TextEncoding.encodeUtf8 :: Text -> Digest SHA256)

sha256Lazy :: LBS.ByteString -> Text
sha256Lazy =
  TextEncoding.decodeUtf8 . convertToBase Base16 . (hash . LBS.toStrict :: LBS.ByteString -> Digest SHA256)

signingKey :: Text -> Text -> Text -> Text -> BS.ByteString
signingKey secret credentialDate region serviceName =
  hmacSha256Raw
    ( hmacSha256Raw
        (hmacSha256Raw (hmacSha256Raw ("AWS4" <> TextEncoding.encodeUtf8 secret) credentialDate) region)
        serviceName
    )
    "aws4_request"

hmacSha256Raw :: BS.ByteString -> Text -> BS.ByteString
hmacSha256Raw key message =
  convert (hmac key (TextEncoding.encodeUtf8 message) :: HMAC SHA256)

hmacSha256Hex :: BS.ByteString -> Text -> Text
hmacSha256Hex key message =
  TextEncoding.decodeUtf8 (convertToBase Base16 (hmac key (TextEncoding.encodeUtf8 message) :: HMAC SHA256))

sesFailure :: Text -> Text -> FailureDetail
sesFailure codeValue detailText =
  FailureDetail
    { failureCategory = ToolProcessFailure,
      failureCode = codeValue,
      failureMessage = "The SES request failed.",
      failureRetryable = True,
      failureContext = FailureMap.fromList [("detail", detailText)]
    }

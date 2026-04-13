{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.API.Readiness
  ( ReadinessCheck (..),
    ReadinessReport (..),
    ReadinessStatus (..),
    blockedCheck,
    buildReadinessReport,
    probeAnyHttpCheck,
    probeHttpCheck,
    readinessHttpStatus,
    readyCheck,
    renderBlockingChecks,
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
import Data.List (find)
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
import Network.HTTP.Types.Status (Status, status200, status503, statusCode)

data ReadinessStatus
  = ReadinessReady
  | ReadinessBlocked
  deriving (Eq, Show)

instance ToJSON ReadinessStatus where
  toJSON readinessStatusValue =
    String $
      case readinessStatusValue of
        ReadinessReady -> "ready"
        ReadinessBlocked -> "blocked"

instance FromJSON ReadinessStatus where
  parseJSON =
    withText "ReadinessStatus" $ \value ->
      case value of
        "ready" -> pure ReadinessReady
        "blocked" -> pure ReadinessBlocked
        _ -> fail ("Unknown readiness status: " <> Text.unpack value)

data ReadinessCheck = ReadinessCheck
  { readinessCheckName :: Text,
    readinessCheckReady :: Bool,
    readinessCheckReason :: Text,
    readinessCheckDetail :: Text
  }
  deriving (Eq, Show)

instance ToJSON ReadinessCheck where
  toJSON readinessCheck =
    object
      [ "name" .= readinessCheckName readinessCheck,
        "ready" .= readinessCheckReady readinessCheck,
        "reason" .= readinessCheckReason readinessCheck,
        "detail" .= readinessCheckDetail readinessCheck
      ]

instance FromJSON ReadinessCheck where
  parseJSON = withObject "ReadinessCheck" $ \obj ->
    ReadinessCheck
      <$> obj .: "name"
      <*> obj .: "ready"
      <*> obj .: "reason"
      <*> obj .: "detail"

data ReadinessReport = ReadinessReport
  { readinessService :: Text,
    readinessStatus :: ReadinessStatus,
    readinessChecks :: [ReadinessCheck],
    readinessBlockingChecks :: [ReadinessCheck]
  }
  deriving (Eq, Show)

instance ToJSON ReadinessReport where
  toJSON readinessReport =
    object
      [ "service" .= readinessService readinessReport,
        "status" .= readinessStatus readinessReport,
        "checks" .= readinessChecks readinessReport,
        "blocking" .= readinessBlockingChecks readinessReport
      ]

instance FromJSON ReadinessReport where
  parseJSON = withObject "ReadinessReport" $ \obj ->
    ReadinessReport
      <$> obj .: "service"
      <*> obj .: "status"
      <*> obj .: "checks"
      <*> obj .: "blocking"

readyCheck :: Text -> Text -> Text -> ReadinessCheck
readyCheck checkName reason detail =
  ReadinessCheck
    { readinessCheckName = checkName,
      readinessCheckReady = True,
      readinessCheckReason = reason,
      readinessCheckDetail = detail
    }

blockedCheck :: Text -> Text -> Text -> ReadinessCheck
blockedCheck checkName reason detail =
  ReadinessCheck
    { readinessCheckName = checkName,
      readinessCheckReady = False,
      readinessCheckReason = reason,
      readinessCheckDetail = detail
    }

buildReadinessReport :: Text -> [ReadinessCheck] -> ReadinessReport
buildReadinessReport serviceName checks =
  let blockingChecks = filter (not . readinessCheckReady) checks
   in ReadinessReport
        { readinessService = serviceName,
          readinessStatus =
            if null blockingChecks
              then ReadinessReady
              else ReadinessBlocked,
          readinessChecks = checks,
          readinessBlockingChecks = blockingChecks
        }

readinessHttpStatus :: ReadinessReport -> Status
readinessHttpStatus readinessReport =
  case readinessStatus readinessReport of
    ReadinessReady -> status200
    ReadinessBlocked -> status503

renderBlockingChecks :: ReadinessReport -> Text
renderBlockingChecks readinessReport =
  case readinessBlockingChecks readinessReport of
    [] -> "none"
    blockingChecks ->
      Text.intercalate
        "; "
        [ readinessCheckName readinessCheck
            <> "="
            <> readinessCheckReason readinessCheck
            <> " ("
            <> readinessCheckDetail readinessCheck
            <> ")"
        | readinessCheck <- blockingChecks
        ]

probeHttpCheck ::
  Manager ->
  Text ->
  Text ->
  [Int] ->
  Text ->
  Text ->
  IO ReadinessCheck
probeHttpCheck manager checkName url expectedStatuses successReason failureReason = do
  requestOrException <- try (parseRequest (Text.unpack url)) :: IO (Either SomeException Request)
  case requestOrException of
    Left exn ->
      pure (blockedCheck checkName failureReason (Text.pack (show exn)))
    Right request -> do
      responseOrException <-
        try
          ( httpLbs
              request {responseTimeout = responseTimeoutMicro 2000000}
              manager
          ) :: IO (Either SomeException (Response LBS.ByteString))
      case responseOrException of
        Left exn ->
          pure (blockedCheck checkName failureReason (Text.pack (show exn)))
        Right response ->
          let httpStatusCode = statusCode (responseStatus response)
              detail = "url=" <> url <> " http_status=" <> Text.pack (show httpStatusCode)
           in if httpStatusCode `elem` expectedStatuses
                then pure (readyCheck checkName successReason detail)
                else pure (blockedCheck checkName failureReason detail)

probeAnyHttpCheck ::
  Manager ->
  Text ->
  [Text] ->
  [Int] ->
  Text ->
  Text ->
  IO ReadinessCheck
probeAnyHttpCheck manager checkName urls expectedStatuses successReason failureReason = do
  checks <- mapM probeCandidate urls
  pure $
    case find readinessCheckReady checks of
      Just readinessCheck ->
        readinessCheck
          { readinessCheckDetail =
              "selected=" <> readinessCheckDetail readinessCheck
          }
      Nothing ->
        blockedCheck
          checkName
          failureReason
          (Text.intercalate " | " (map readinessCheckDetail checks))
  where
    probeCandidate url =
      probeHttpCheck manager checkName url expectedStatuses successReason failureReason

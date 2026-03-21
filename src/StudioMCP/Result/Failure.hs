{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Result.Failure
  ( FailureCategory (..),
    FailureDetail (..),
    validationFailure,
    timeoutFailure,
    invariantFailure,
  )
where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
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
import qualified Data.Text as Text
import StudioMCP.DAG.Types (NodeId (..))

data FailureCategory
  = TimeoutFailure
  | ValidationFailure
  | ToolProcessFailure
  | BadOutputDecoding
  | DependencyMissing
  | StorageFailure
  | MessagingFailure
  | InternalInvariantFailure
  deriving (Eq, Ord, Show)

instance FromJSON FailureCategory where
  parseJSON =
    withText "FailureCategory" $ \value ->
      case value of
        "timeout" -> pure TimeoutFailure
        "validation" -> pure ValidationFailure
        "tool_process" -> pure ToolProcessFailure
        "bad_output_decoding" -> pure BadOutputDecoding
        "dependency_missing" -> pure DependencyMissing
        "storage" -> pure StorageFailure
        "messaging" -> pure MessagingFailure
        "internal_invariant" -> pure InternalInvariantFailure
        _ -> fail ("Unknown FailureCategory: " <> Text.unpack value)

instance ToJSON FailureCategory where
  toJSON failureCategoryValue =
    String $
      case failureCategoryValue of
        TimeoutFailure -> "timeout"
        ValidationFailure -> "validation"
        ToolProcessFailure -> "tool_process"
        BadOutputDecoding -> "bad_output_decoding"
        DependencyMissing -> "dependency_missing"
        StorageFailure -> "storage"
        MessagingFailure -> "messaging"
        InternalInvariantFailure -> "internal_invariant"

data FailureDetail = FailureDetail
  { failureCategory :: FailureCategory,
    failureCode :: Text,
    failureMessage :: Text,
    failureRetryable :: Bool,
    failureContext :: Map Text Text
  }
  deriving (Eq, Show)

instance FromJSON FailureDetail where
  parseJSON = withObject "FailureDetail" $ \obj ->
    FailureDetail
      <$> obj .: "category"
      <*> obj .: "code"
      <*> obj .: "message"
      <*> obj .: "retryable"
      <*> obj .: "context"

instance ToJSON FailureDetail where
  toJSON failureDetail =
    object
      [ "category" .= failureCategory failureDetail,
        "code" .= failureCode failureDetail,
        "message" .= failureMessage failureDetail,
        "retryable" .= failureRetryable failureDetail,
        "context" .= failureContext failureDetail
      ]

validationFailure :: Text -> Text -> FailureDetail
validationFailure code message =
  FailureDetail
    { failureCategory = ValidationFailure,
      failureCode = code,
      failureMessage = message,
      failureRetryable = False,
      failureContext = Map.empty
    }

timeoutFailure :: NodeId -> Int -> FailureDetail
timeoutFailure (NodeId nodeIdText) seconds =
  FailureDetail
    { failureCategory = TimeoutFailure,
      failureCode = "node-timeout",
      failureMessage = "Node " <> nodeIdText <> " exceeded its timeout budget.",
      failureRetryable = True,
      failureContext =
        Map.fromList
          [ ("nodeId", nodeIdText),
            ("timeoutSeconds", showText seconds)
          ]
    }

invariantFailure :: Text -> FailureDetail
invariantFailure message =
  FailureDetail
    { failureCategory = InternalInvariantFailure,
      failureCode = "internal-invariant",
      failureMessage = message,
      failureRetryable = False,
      failureContext = Map.empty
    }

showText :: Show a => a -> Text
showText = Text.pack . show

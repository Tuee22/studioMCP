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

data FailureDetail = FailureDetail
  { failureCategory :: FailureCategory,
    failureCode :: Text,
    failureMessage :: Text,
    failureRetryable :: Bool,
    failureContext :: Map Text Text
  }
  deriving (Eq, Show)

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

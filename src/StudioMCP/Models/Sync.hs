{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Models.Sync
  ( ModelStatus (..),
    ModelSyncResult (..),
    listModelStatuses,
    syncAllModels,
    verifyAllModels,
  )
where

import Control.Exception (SomeException, try)
import Crypto.Hash (Digest, SHA256, hashlazy)
import Data.ByteArray.Encoding (Base (Base16), convertToBase)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import Data.Text (Text)
import Network.HTTP.Client
  ( HttpException,
    Request,
    Response,
    defaultManagerSettings,
    httpLbs,
    newManager,
    parseRequest,
    responseBody,
  )
import StudioMCP.Models.Registry
  ( ModelArtifact (..),
    allModelArtifacts,
    modelsBucket,
    resolveModelSourceUrl,
  )
import StudioMCP.Result.Failure
  ( FailureCategory (StorageFailure),
    FailureDetail (..),
  )
import StudioMCP.Storage.Keys (ObjectKey (..))
import StudioMCP.Storage.MinIO
  ( MinIOConfig,
    ensureBucketExists,
    objectExists,
    readObjectBytes,
    writeObjectBytes,
  )

data ModelStatus
  = ModelMissing
  | ModelPresent
  | ModelVerified
  deriving (Eq, Show)

data ModelSyncResult = ModelSyncResult
  { msrModel :: ModelArtifact,
    msrStatus :: ModelStatus,
    msrChecksum :: Text
  }
  deriving (Eq, Show)

syncAllModels :: MinIOConfig -> IO (Either FailureDetail [ModelSyncResult])
syncAllModels config = do
  ensureBucketResult <- ensureBucketExists config modelsBucket
  case ensureBucketResult of
    Left failureDetail -> pure (Left failureDetail)
    Right () -> go [] allModelArtifacts
  where
    go reversedResults [] = pure (Right (reverse reversedResults))
    go reversedResults (modelArtifact : remainingModels) = do
      modelResult <- syncModel config modelArtifact
      case modelResult of
        Left failureDetail -> pure (Left failureDetail)
        Right syncResult -> go (syncResult : reversedResults) remainingModels

listModelStatuses :: MinIOConfig -> IO (Either FailureDetail [ModelSyncResult])
listModelStatuses config = do
  ensureBucketResult <- ensureBucketExists config modelsBucket
  case ensureBucketResult of
    Left failureDetail -> pure (Left failureDetail)
    Right () -> sequence <$> traverse (statusForModel config) allModelArtifacts

verifyAllModels :: MinIOConfig -> IO (Either FailureDetail [ModelSyncResult])
verifyAllModels config = do
  ensureBucketResult <- ensureBucketExists config modelsBucket
  case ensureBucketResult of
    Left failureDetail -> pure (Left failureDetail)
    Right () -> sequence <$> traverse (verifyModel config) allModelArtifacts

syncModel :: MinIOConfig -> ModelArtifact -> IO (Either FailureDetail ModelSyncResult)
syncModel config modelArtifact = do
  objectExistsResult <- objectExists config modelsBucket (modelObjectKey modelArtifact)
  case objectExistsResult of
    Left failureDetail -> pure (Left failureDetail)
    Right True -> statusForModel config modelArtifact
    Right False -> do
      sourceUrlResult <- resolveModelSourceUrl modelArtifact
      case sourceUrlResult of
        Left errText -> pure (Left (modelConfigFailure modelArtifact errText))
        Right sourceUrl -> do
          sourceBytesResult <- downloadSourceBytes sourceUrl
          case sourceBytesResult of
            Left failureDetail -> pure (Left failureDetail)
            Right sourceBytes -> do
              writeResult <- writeObjectBytes config modelsBucket (modelObjectKey modelArtifact) sourceBytes
              case writeResult of
                Left failureDetail -> pure (Left failureDetail)
                Right () ->
                  pure
                    ( Right
                        ModelSyncResult
                          { msrModel = modelArtifact,
                            msrStatus = ModelPresent,
                            msrChecksum = sha256Bytes sourceBytes
                          }
                    )

statusForModel :: MinIOConfig -> ModelArtifact -> IO (Either FailureDetail ModelSyncResult)
statusForModel config modelArtifact = do
  objectExistsResult <- objectExists config modelsBucket (modelObjectKey modelArtifact)
  pure $
    case objectExistsResult of
      Left failureDetail -> Left failureDetail
      Right exists ->
        Right
          ModelSyncResult
            { msrModel = modelArtifact,
              msrStatus = if exists then ModelPresent else ModelMissing,
              msrChecksum = if exists then "present" else "missing"
            }

verifyModel :: MinIOConfig -> ModelArtifact -> IO (Either FailureDetail ModelSyncResult)
verifyModel config modelArtifact = do
  sourceUrlResult <- resolveModelSourceUrl modelArtifact
  case sourceUrlResult of
    Left errText -> pure (Left (modelConfigFailure modelArtifact errText))
    Right sourceUrl -> do
      sourceBytesResult <- downloadSourceBytes sourceUrl
      case sourceBytesResult of
        Left failureDetail -> pure (Left failureDetail)
        Right sourceBytes -> do
          objectReadResult <- readObjectBytes config modelsBucket (modelObjectKey modelArtifact)
          case objectReadResult of
            Left failureDetail -> pure (Left failureDetail)
            Right objectBytes ->
              let sourceChecksum = sha256Bytes sourceBytes
                  objectChecksum = sha256Bytes objectBytes
               in if sourceChecksum /= objectChecksum
                    then pure (Left (modelChecksumMismatch modelArtifact sourceChecksum objectChecksum))
                    else
                      pure
                        ( Right
                            ModelSyncResult
                              { msrModel = modelArtifact,
                                msrStatus = ModelVerified,
                                msrChecksum = objectChecksum
                              }
                        )

downloadSourceBytes :: Text -> IO (Either FailureDetail LBS.ByteString)
downloadSourceBytes sourceUrl =
  case Text.stripPrefix "file://" sourceUrl of
    Just localPath -> do
      fileResult <- try (LBS.readFile (Text.unpack localPath)) :: IO (Either SomeException LBS.ByteString)
      pure $
        case fileResult of
          Left exn -> Left (sourceReadFailure sourceUrl (Text.pack (show exn)))
          Right payload -> Right payload
    Nothing -> do
      manager <- newManager defaultManagerSettings
      requestResult <- try (parseRequest (Text.unpack sourceUrl)) :: IO (Either HttpException Request)
      case requestResult of
        Left exn -> pure (Left (sourceReadFailure sourceUrl (Text.pack (show exn))))
        Right request -> do
          responseResult <- try (httpLbs request manager) :: IO (Either HttpException (Response LBS.ByteString))
          pure $
            case responseResult of
              Left exn -> Left (sourceReadFailure sourceUrl (Text.pack (show exn)))
              Right response -> Right (responseBody response)

sha256Bytes :: LBS.ByteString -> Text
sha256Bytes =
  TextEncoding.decodeUtf8
    . convertToBase Base16
    . (id :: Digest SHA256 -> Digest SHA256)
    . hashlazy

modelConfigFailure :: ModelArtifact -> Text -> FailureDetail
modelConfigFailure modelArtifact errText =
  FailureDetail
    { failureCategory = StorageFailure,
      failureCode = "model-source-unconfigured",
      failureMessage = "The model source URL is not configured.",
      failureRetryable = False,
      failureContext =
        Map.fromList
          [ ("modelId", modelId modelArtifact),
            ("detail", errText)
          ]
    }

sourceReadFailure :: Text -> Text -> FailureDetail
sourceReadFailure sourceUrl detailText =
  FailureDetail
    { failureCategory = StorageFailure,
      failureCode = "model-source-download-failed",
      failureMessage = "The model source could not be downloaded.",
      failureRetryable = True,
      failureContext =
        Map.fromList
          [ ("sourceUrl", sourceUrl),
            ("detail", detailText)
          ]
    }

modelChecksumMismatch :: ModelArtifact -> Text -> Text -> FailureDetail
modelChecksumMismatch modelArtifact expectedChecksum observedChecksum =
  FailureDetail
    { failureCategory = StorageFailure,
      failureCode = "model-checksum-mismatch",
      failureMessage = "The synced model bytes do not match the configured source.",
      failureRetryable = False,
      failureContext =
        Map.fromList
          [ ("modelId", modelId modelArtifact),
            ("expectedChecksum", expectedChecksum),
            ("observedChecksum", observedChecksum),
            ("objectKey", unObjectKey (modelObjectKey modelArtifact))
          ]
    }

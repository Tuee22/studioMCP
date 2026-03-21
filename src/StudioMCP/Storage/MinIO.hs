{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Storage.MinIO
  ( MinIOConfig (..),
    classifyMinioFailure,
    readManifest,
    readMemoObject,
    writeArtifactObject,
    readSummary,
    validateMinioRoundTrip,
    writeManifest,
    writeMemoObject,
    writeSummary,
  )
where

import Control.Exception (IOException, evaluate, try)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Lazy.Char8 as LBS8
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Data.Text.Encoding.Error (lenientDecode)
import Data.Time (getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import StudioMCP.DAG.Provenance (emptyProvenance)
import StudioMCP.DAG.Summary
  ( NodeExecutionStatus (NodeSucceeded),
    NodeOutcome (..),
    RunId (..),
    Summary,
    buildSummary,
  )
import StudioMCP.DAG.Types (NodeId (..))
import StudioMCP.Result.Failure
  ( FailureCategory (StorageFailure),
    FailureDetail (..),
    failureCode,
  )
import StudioMCP.Storage.ContentAddressed (deriveContentAddress)
import StudioMCP.Storage.Keys
  ( BucketName (..),
    ManifestRef (..),
    MemoObjectRef (..),
    ObjectKey (..),
    SummaryRef (..),
    manifestRefForRun,
    memoObjectRef,
    summaryRefForRun,
  )
import StudioMCP.Storage.Manifests
  ( ArtifactRef (..),
    ManifestEntry (..),
    RunManifest,
    buildRunManifest,
  )
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.IO (BufferMode (NoBuffering), hClose, hSetBinaryMode, hSetBuffering)
import System.Process
  ( CreateProcess (env, std_err, std_in, std_out),
    StdStream (CreatePipe),
    proc,
    waitForProcess,
    withCreateProcess,
  )

data MinIOConfig = MinIOConfig
  { minioEndpointUrl :: Text,
    minioAccessKey :: Text,
    minioSecretKey :: Text
  }
  deriving (Eq, Show)

writeMemoObject :: MinIOConfig -> MemoObjectRef -> LBS.ByteString -> IO (Either FailureDetail ())
writeMemoObject config memoRef =
  writeObjectBytes config (memoRefBucket memoRef) (memoRefKey memoRef)

writeArtifactObject :: MinIOConfig -> ArtifactRef -> LBS.ByteString -> IO (Either FailureDetail ())
writeArtifactObject config artifactRef =
  writeObjectBytes config (artifactBucket artifactRef) (artifactKey artifactRef)

readMemoObject :: MinIOConfig -> MemoObjectRef -> IO (Either FailureDetail LBS.ByteString)
readMemoObject config memoRef =
  readObjectBytes config (memoRefBucket memoRef) (memoRefKey memoRef)

writeManifest :: MinIOConfig -> ManifestRef -> RunManifest -> IO (Either FailureDetail ())
writeManifest config manifestRef =
  writeJsonValue config (manifestRefBucket manifestRef) (manifestRefKey manifestRef)

readManifest :: MinIOConfig -> ManifestRef -> IO (Either FailureDetail RunManifest)
readManifest config manifestRef =
  readJsonValue config (manifestRefBucket manifestRef) (manifestRefKey manifestRef)

writeSummary :: MinIOConfig -> SummaryRef -> Summary -> IO (Either FailureDetail ())
writeSummary config summaryRef =
  writeJsonValue config (summaryRefBucket summaryRef) (summaryRefKey summaryRef)

readSummary :: MinIOConfig -> SummaryRef -> IO (Either FailureDetail Summary)
readSummary config summaryRef =
  readJsonValue config (summaryRefBucket summaryRef) (summaryRefKey summaryRef)

validateMinioRoundTrip :: MinIOConfig -> IO (Either FailureDetail ())
validateMinioRoundTrip config = do
  currentTime <- getCurrentTime
  let runToken = Text.pack (formatTime defaultTimeLocale "%Y%m%d%H%M%S%q" currentTime)
      runId = RunId ("minio-validation-" <> runToken)
      memoRef = memoObjectRef (deriveContentAddress ["minio-validation", runToken, "memo"])
      missingMemoRef = memoObjectRef (deriveContentAddress ["minio-validation", runToken, "missing"])
      summaryRef = summaryRefForRun runId
      manifestRef = manifestRefForRun runId
      memoPayload = LBS.pack [0, 1, 2, 10, 13, 65, 66, 67, 255]
      summary =
        buildSummary
          runId
          currentTime
          (emptyProvenance "minio-validation")
          [ NodeOutcome
              { outcomeNodeId = NodeId "validation-node",
                outcomeStatus = NodeSucceeded,
                outcomeCached = False,
                outcomeOutputReference = Just (memoObjectUri memoRef),
                outcomeFailure = Nothing
              }
          ]
      manifest =
        buildRunManifest
          runId
          summaryRef
          [ ManifestEntry
              { manifestEntryNodeId = NodeId "validation-node",
                manifestEntryMemoRef = memoRef,
                manifestEntryArtifactRef = Nothing
              }
          ]

  memoWriteResult <- writeMemoObject config memoRef memoPayload
  case memoWriteResult of
    Left failureDetail -> pure (Left failureDetail)
    Right () -> do
      memoReadResult <- readMemoObject config memoRef
      case memoReadResult of
        Left failureDetail -> pure (Left failureDetail)
        Right observedPayload
          | observedPayload /= memoPayload ->
              pure (Left (roundTripMismatch "minio-memo-round-trip-mismatch" "Memo object bytes did not round-trip unchanged." memoRef))
          | otherwise -> do
              summaryWriteResult <- writeSummary config summaryRef summary
              case summaryWriteResult of
                Left failureDetail -> pure (Left failureDetail)
                Right () -> do
                  summaryReadResult <- readSummary config summaryRef
                  case summaryReadResult of
                    Left failureDetail -> pure (Left failureDetail)
                    Right observedSummary
                      | observedSummary /= summary ->
                          pure (Left (summaryRoundTripMismatch summaryRef))
                      | otherwise -> do
                          manifestWriteResult <- writeManifest config manifestRef manifest
                          case manifestWriteResult of
                            Left failureDetail -> pure (Left failureDetail)
                            Right () -> do
                              manifestReadResult <- readManifest config manifestRef
                              case manifestReadResult of
                                Left failureDetail -> pure (Left failureDetail)
                                Right observedManifest
                                  | observedManifest /= manifest ->
                                      pure (Left (manifestRoundTripMismatch manifestRef))
                                  | otherwise -> do
                                      missingReadResult <- readMemoObject config missingMemoRef
                                      pure (validateMissingObjectFailure missingMemoRef missingReadResult)

classifyMinioFailure :: Text -> BucketName -> ObjectKey -> Maybe Int -> Text -> FailureDetail
classifyMinioFailure operationName bucketName objectKey maybeExitCode commandOutput =
  FailureDetail
    { failureCategory = StorageFailure,
      failureCode = failureCodeValue,
      failureMessage = failureMessageValue,
      failureRetryable = failureRetryableValue,
      failureContext =
        Map.fromList
          ( [ ("operation", operationName),
              ("bucket", unBucketName bucketName),
              ("key", unObjectKey objectKey),
              ("outputSnippet", summarizeOutput commandOutput)
            ]
              <> maybe [] (\exitCodeValue -> [("exitCode", Text.pack (show exitCodeValue))]) maybeExitCode
          )
    }
  where
    loweredOutput = Text.toLower commandOutput
    (failureCodeValue, failureMessageValue, failureRetryableValue)
      | "object does not exist" `Text.isInfixOf` loweredOutput =
          ( "minio-object-not-found",
            "MinIO reported that the requested object does not exist.",
            False
          )
      | "bucket does not exist" `Text.isInfixOf` loweredOutput =
          ( "minio-bucket-not-found",
            "MinIO reported that the requested bucket does not exist.",
            False
          )
      | "connection refused" `Text.isInfixOf` loweredOutput
          || "service unavailable" `Text.isInfixOf` loweredOutput
          || "no such host" `Text.isInfixOf` loweredOutput
          || "i/o timeout" `Text.isInfixOf` loweredOutput =
          ( "minio-service-unavailable",
            "MinIO was not reachable through the configured service endpoint.",
            True
          )
      | "error dialing backend" `Text.isInfixOf` loweredOutput =
          ( "minio-service-unavailable",
            "MinIO was not reachable through the configured service endpoint.",
            True
          )
      | otherwise =
          ( "minio-command-failed",
            "The MinIO client command failed with an unexpected error.",
            True
          )

writeObjectBytes :: MinIOConfig -> BucketName -> ObjectKey -> LBS.ByteString -> IO (Either FailureDetail ())
writeObjectBytes config bucketName objectKey payload = do
  commandResult <- runMcCommand config "write" bucketName objectKey ["pipe", objectTarget bucketName objectKey] payload
  case commandResult of
    Left failureDetail -> pure (Left failureDetail)
    Right _ -> pure (Right ())

readObjectBytes :: MinIOConfig -> BucketName -> ObjectKey -> IO (Either FailureDetail LBS.ByteString)
readObjectBytes config bucketName objectKey =
  runMcCommand config "read" bucketName objectKey ["cat", objectTarget bucketName objectKey] LBS.empty

writeJsonValue :: Aeson.ToJSON a => MinIOConfig -> BucketName -> ObjectKey -> a -> IO (Either FailureDetail ())
writeJsonValue config bucketName objectKey value =
  writeObjectBytes config bucketName objectKey (Aeson.encode value)

readJsonValue :: Aeson.FromJSON a => MinIOConfig -> BucketName -> ObjectKey -> IO (Either FailureDetail a)
readJsonValue config bucketName objectKey = do
  readResult <- readObjectBytes config bucketName objectKey
  case readResult of
    Left failureDetail -> pure (Left failureDetail)
    Right payload ->
      pure
        ( case Aeson.eitherDecode payload of
            Left decodeError ->
              Left
                FailureDetail
                  { failureCategory = StorageFailure,
                    failureCode = "minio-json-decode-failed",
                    failureMessage = "MinIO returned an object that did not decode as the expected JSON contract.",
                    failureRetryable = False,
                    failureContext =
                      Map.fromList
                        [ ("bucket", unBucketName bucketName),
                          ("key", unObjectKey objectKey),
                          ("decodeError", Text.pack decodeError)
                        ]
                  }
            Right decodedValue -> Right decodedValue
        )

runMcCommand ::
  MinIOConfig ->
  Text ->
  BucketName ->
  ObjectKey ->
  [String] ->
  LBS.ByteString ->
  IO (Either FailureDetail LBS.ByteString)
runMcCommand config operationName bucketName objectKey mcArgs stdinPayload = do
  inheritedEnv <- getEnvironment
  let mergedEnv =
        ( "MC_HOST_local",
          Text.unpack (endpointWithCredentials config)
        ) :
        filter ((/= "MC_HOST_local") . fst) inheritedEnv
  commandResult <-
    try
      ( withCreateProcess
          (proc "mc" mcArgs)
            { std_in = CreatePipe,
              std_out = CreatePipe,
              std_err = CreatePipe,
              env = Just mergedEnv
            }
          runProcessHandles
      ) :: IO (Either IOException (ExitCode, LBS.ByteString, LBS.ByteString))
  case commandResult of
    Left ioException ->
      pure (Left (classifyMinioFailure operationName bucketName objectKey Nothing (Text.pack (show ioException))))
    Right (exitCodeValue, stdoutBytes, stderrBytes) ->
      let combinedOutput = decodeBytes (stdoutBytes <> stderrBytes)
       in case exitCodeValue of
            ExitSuccess -> pure (Right stdoutBytes)
            ExitFailure codeValue ->
              pure (Left (classifyMinioFailure operationName bucketName objectKey (Just codeValue) combinedOutput))
  where
    runProcessHandles maybeStdin maybeStdout maybeStderr processHandle =
      case (maybeStdin, maybeStdout, maybeStderr) of
        (Just stdinHandle, Just stdoutHandle, Just stderrHandle) -> do
          hSetBinaryMode stdinHandle True
          hSetBinaryMode stdoutHandle True
          hSetBinaryMode stderrHandle True
          hSetBuffering stdinHandle NoBuffering
          LBS.hPut stdinHandle stdinPayload
          hClose stdinHandle
          stdoutBytes <- LBS.hGetContents stdoutHandle
          stderrBytes <- LBS.hGetContents stderrHandle
          _ <- evaluate (LBS.length stdoutBytes)
          _ <- evaluate (LBS.length stderrBytes)
          exitCodeValue <- waitForProcess processHandle
          pure (exitCodeValue, stdoutBytes, stderrBytes)
        _ ->
          pure
            ( ExitFailure 1,
              LBS.empty,
              LBS8.pack "MinIO client process did not expose stdin/stdout/stderr handles as expected."
            )

endpointWithCredentials :: MinIOConfig -> Text
endpointWithCredentials config =
  case Text.stripPrefix "http://" (minioEndpointUrl config) of
    Just rest ->
      "http://"
        <> minioAccessKey config
        <> ":"
        <> minioSecretKey config
        <> "@"
        <> rest
    Nothing ->
      case Text.stripPrefix "https://" (minioEndpointUrl config) of
        Just rest ->
          "https://"
            <> minioAccessKey config
            <> ":"
            <> minioSecretKey config
            <> "@"
            <> rest
        Nothing -> minioEndpointUrl config

objectTarget :: BucketName -> ObjectKey -> String
objectTarget bucketName objectKey =
  Text.unpack ("local/" <> unBucketName bucketName <> "/" <> unObjectKey objectKey)

decodeBytes :: LBS.ByteString -> Text
decodeBytes = Text.decodeUtf8With lenientDecode . LBS.toStrict

summarizeOutput :: Text -> Text
summarizeOutput =
  Text.take 240
    . Text.unwords
    . Text.words

memoObjectUri :: MemoObjectRef -> Text
memoObjectUri memoRef =
  "minio://" <> unBucketName (memoRefBucket memoRef) <> "/" <> unObjectKey (memoRefKey memoRef)

roundTripMismatch :: Text -> Text -> MemoObjectRef -> FailureDetail
roundTripMismatch failureCodeValue failureMessageValue memoRef =
  FailureDetail
    { failureCategory = StorageFailure,
      failureCode = failureCodeValue,
      failureMessage = failureMessageValue,
      failureRetryable = False,
      failureContext =
        Map.fromList
          [ ("bucket", unBucketName (memoRefBucket memoRef)),
            ("key", unObjectKey (memoRefKey memoRef))
          ]
    }

summaryRoundTripMismatch :: SummaryRef -> FailureDetail
summaryRoundTripMismatch summaryRef =
  FailureDetail
    { failureCategory = StorageFailure,
      failureCode = "minio-summary-round-trip-mismatch",
      failureMessage = "Summary JSON did not round-trip unchanged through MinIO.",
      failureRetryable = False,
      failureContext =
        Map.fromList
          [ ("bucket", unBucketName (summaryRefBucket summaryRef)),
            ("key", unObjectKey (summaryRefKey summaryRef))
          ]
    }

manifestRoundTripMismatch :: ManifestRef -> FailureDetail
manifestRoundTripMismatch manifestRef =
  FailureDetail
    { failureCategory = StorageFailure,
      failureCode = "minio-manifest-round-trip-mismatch",
      failureMessage = "Manifest JSON did not round-trip unchanged through MinIO.",
      failureRetryable = False,
      failureContext =
        Map.fromList
          [ ("bucket", unBucketName (manifestRefBucket manifestRef)),
            ("key", unObjectKey (manifestRefKey manifestRef))
          ]
    }

validateMissingObjectFailure :: MemoObjectRef -> Either FailureDetail LBS.ByteString -> Either FailureDetail ()
validateMissingObjectFailure missingMemoRef readResult =
  case readResult of
    Left failureDetail
      | failureCode failureDetail == "minio-object-not-found" -> Right ()
      | otherwise ->
          Left
            FailureDetail
              { failureCategory = StorageFailure,
                failureCode = "minio-failure-mapping-mismatch",
                failureMessage = "Missing-object lookup did not map to the expected storage failure contract.",
                failureRetryable = False,
                failureContext =
                  Map.fromList
                    [ ("bucket", unBucketName (memoRefBucket missingMemoRef)),
                      ("key", unObjectKey (memoRefKey missingMemoRef)),
                      ("observedFailureCode", failureCode failureDetail)
                    ]
              }
    Right _ ->
      Left
        FailureDetail
          { failureCategory = StorageFailure,
            failureCode = "minio-missing-object-unexpected-success",
            failureMessage = "Reading a missing MinIO object unexpectedly succeeded.",
            failureRetryable = False,
            failureContext =
              Map.fromList
                [ ("bucket", unBucketName (memoRefBucket missingMemoRef)),
                  ("key", unObjectKey (memoRefKey missingMemoRef))
                ]
          }

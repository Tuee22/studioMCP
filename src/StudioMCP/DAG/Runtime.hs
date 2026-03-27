{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.DAG.Runtime
  ( PersistedRun (..),
    RuntimeConfig (..),
    runDagSpecEndToEnd,
    validateEndToEndRuntime,
  )
where

import Control.Monad (foldM)
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Time (getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import StudioMCP.Config.Types (AppConfig (..))
import StudioMCP.DAG.Executor
  ( ExecutionReport (..),
    ExecutorAdapters (..),
    executeParallel,
  )
import StudioMCP.DAG.Hashing (normalizeSegment)
import StudioMCP.DAG.Parser (loadDagFile)
import StudioMCP.DAG.Scheduler (scheduleTopologically)
import StudioMCP.DAG.Summary
  ( RunId (..),
    RunStatus (..),
    Summary (..),
  )
import StudioMCP.DAG.Types
  ( DagSpec (..),
    NodeId (..),
    NodeSpec (..),
    OutputType (..),
    TimeoutPolicy (..),
  )
import StudioMCP.DAG.Validator (renderFailures, validateDag)
import StudioMCP.Messaging.Events
  ( ExecutionEvent (..),
    ExecutionEventType (..),
  )
import StudioMCP.Messaging.Pulsar
  ( PulsarConfig (..),
    consumeExecutionEvents,
    publishExecutionEvents,
    validationTopicForRunId,
  )
import StudioMCP.Messaging.Topics (TopicName)
import StudioMCP.Result.Failure
  ( FailureCategory (StorageFailure, ToolProcessFailure, TimeoutFailure),
    FailureDetail (..),
    failureCode,
    validationFailure,
  )
import StudioMCP.Result.Types (Result (Failure, Success))
import StudioMCP.Storage.ContentAddressed (deriveContentAddress)
import StudioMCP.Storage.Keys
  ( BucketName (..),
    ManifestRef,
    MemoObjectRef,
    ObjectKey (..),
    SummaryRef,
    artifactsBucket,
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
import StudioMCP.Storage.MinIO
  ( MinIOConfig (..),
    readSummary,
    writeArtifactObject,
    writeManifest,
    writeMemoObject,
    writeSummary,
  )
import StudioMCP.Tools.Boundary
  ( BoundaryCommand (..),
    runBoundaryCommand,
  )
import StudioMCP.Tools.FFmpeg (seedDeterministicFixtures)
import StudioMCP.Util.Logging (logInfo)
import System.Directory (doesFileExist, getTemporaryDirectory)
import System.FilePath ((</>))

data RuntimeConfig = RuntimeConfig
  { runtimePulsarConfig :: PulsarConfig,
    runtimeMinioConfig :: MinIOConfig,
    runtimeTopicName :: TopicName
  }

data PersistedRun = PersistedRun
  { persistedReport :: ExecutionReport,
    persistedSummaryRef :: SummaryRef,
    persistedManifestRef :: ManifestRef,
    persistedManifest :: RunManifest
  }

runDagSpecEndToEnd ::
  RuntimeConfig ->
  RunId ->
  DagSpec ->
  IO (Either FailureDetail PersistedRun)
runDagSpecEndToEnd runtimeConfig runIdValue dagSpec = do
  startedAt <- getCurrentTime
  manifestEntriesRef <- newIORef []
  scheduleResult <- publishSchedule runtimeConfig runIdValue dagSpec
  case scheduleResult of
    Left failureDetail -> pure (Left failureDetail)
    Right () -> do
      executionResult <-
        executeParallel
          (buildRuntimeAdapters runtimeConfig runIdValue manifestEntriesRef)
          runIdValue
          startedAt
          dagSpec
      case executionResult of
        Left failureDetail -> pure (Left failureDetail)
        Right executionReport -> persistRun runtimeConfig runIdValue executionReport manifestEntriesRef

validateEndToEndRuntime :: AppConfig -> IO (Either FailureDetail ())
validateEndToEndRuntime appConfig = do
  let AppConfig _ pulsarHttp pulsarBinary minioUrl minioAccess minioSecret = appConfig
  successDagResult <- loadValidatedDagFixture "examples/dags/transcode-basic.yaml"
  case successDagResult of
    Left failureDetail -> pure (Left failureDetail)
    Right successDag -> do
      failureDagResult <- loadValidatedDagFixture "examples/dags/transcode-missing-input.yaml"
      case failureDagResult of
        Left failureDetail -> pure (Left failureDetail)
        Right failureDag -> do
          successRunId <- freshRunId "e2e-success"
          failureRunId <- freshRunId "e2e-failure"
          let runtimeConfigFor runIdValue =
                RuntimeConfig
                  { runtimePulsarConfig = PulsarConfig pulsarHttp pulsarBinary,
                    runtimeMinioConfig = MinIOConfig minioUrl minioAccess minioSecret,
                    runtimeTopicName = validationTopicForRunId runIdValue
                  }
          successRunResult <- runDagSpecEndToEnd (runtimeConfigFor successRunId) successRunId successDag
          case successRunResult of
            Left failureDetail -> pure (Left failureDetail)
            Right persistedSuccessRun -> do
              successValidation <- validatePersistedRun runtimeConfigFor successRunId persistedSuccessRun RunSucceeded NodeCompleted 9
              case successValidation of
                Left failureDetail -> pure (Left failureDetail)
                Right () -> do
                  failureRunResult <- runDagSpecEndToEnd (runtimeConfigFor failureRunId) failureRunId failureDag
                  case failureRunResult of
                    Left failureDetail -> pure (Left failureDetail)
                    Right persistedFailureRun ->
                      validatePersistedRun runtimeConfigFor failureRunId persistedFailureRun RunFailed NodeFailedEvent 9

buildRuntimeAdapters ::
  RuntimeConfig ->
  RunId ->
  IORef [ManifestEntry] ->
  ExecutorAdapters
buildRuntimeAdapters runtimeConfig runIdValue manifestEntriesRef =
  ExecutorAdapters
    { executePureNode = executePureRuntimeNode runtimeConfig runIdValue manifestEntriesRef,
      executeBoundaryNode = executeBoundaryRuntimeNode runtimeConfig runIdValue manifestEntriesRef,
      observeNodeOutcome = \_ -> pure (),
      observeSummary = \_ -> pure ()
    }

executePureRuntimeNode ::
  RuntimeConfig ->
  RunId ->
  IORef [ManifestEntry] ->
  NodeSpec ->
  [Text] ->
  IO (Either FailureDetail Text)
executePureRuntimeNode runtimeConfig runIdValue manifestEntriesRef nodeSpec _ = do
  logInfo (renderNodeLog runIdValue nodeSpec "pure-node-started")
  startedEvent <- publishNodeEvent runtimeConfig runIdValue nodeSpec NodeStarted "pure-node-started"
  case startedEvent of
    Left failureDetail -> pure (Left failureDetail)
    Right () -> do
      outputReferenceResult <- resolvePureOutputReference nodeSpec
      case outputReferenceResult of
        Left failureDetail -> do
          _ <- publishNodeEvent runtimeConfig runIdValue nodeSpec NodeFailedEvent (failureCode failureDetail)
          pure (Left failureDetail)
        Right outputReference -> do
          persistResult <- persistPureNodeOutput runtimeConfig runIdValue manifestEntriesRef nodeSpec outputReference
          case persistResult of
            Left failureDetail -> do
              _ <- publishNodeEvent runtimeConfig runIdValue nodeSpec NodeFailedEvent (failureCode failureDetail)
              pure (Left failureDetail)
            Right () -> do
              completedEvent <- publishNodeEvent runtimeConfig runIdValue nodeSpec NodeCompleted "pure-node-completed"
              case completedEvent of
                Left failureDetail -> pure (Left failureDetail)
                Right () -> do
                  logInfo (renderNodeLog runIdValue nodeSpec "pure-node-completed")
                  pure (Right outputReference)

executeBoundaryRuntimeNode ::
  RuntimeConfig ->
  RunId ->
  IORef [ManifestEntry] ->
  NodeSpec ->
  [Text] ->
  IO (Either FailureDetail Text)
executeBoundaryRuntimeNode runtimeConfig runIdValue manifestEntriesRef nodeSpec inputReferences = do
  logInfo (renderNodeLog runIdValue nodeSpec "boundary-node-started")
  startedEvent <- publishNodeEvent runtimeConfig runIdValue nodeSpec NodeStarted "boundary-node-started"
  case startedEvent of
    Left failureDetail -> pure (Left failureDetail)
    Right () ->
      case fmap Text.toLower (nodeTool nodeSpec) of
        Just "ffmpeg" -> do
          boundaryResult <- executeFFmpegNode runtimeConfig runIdValue manifestEntriesRef nodeSpec inputReferences
          case boundaryResult of
            Left failureDetail -> do
              let eventType =
                    case failureCategory failureDetail of
                      TimeoutFailure -> NodeTimedOutEvent
                      _ -> NodeFailedEvent
              _ <- publishNodeEvent runtimeConfig runIdValue nodeSpec eventType (failureCode failureDetail)
              pure (Left failureDetail)
            Right outputReference -> do
              completedEvent <- publishNodeEvent runtimeConfig runIdValue nodeSpec NodeCompleted "boundary-node-completed"
              case completedEvent of
                Left failureDetail -> pure (Left failureDetail)
                Right () -> do
                  logInfo (renderNodeLog runIdValue nodeSpec "boundary-node-completed")
                  pure (Right outputReference)
        _ ->
          pure
            ( Left
                ( validationFailure
                    "unsupported-boundary-tool"
                    ("Boundary node " <> unNodeId (nodeId nodeSpec) <> " does not map to a supported runtime adapter.")
                )
            )

persistRun ::
  RuntimeConfig ->
  RunId ->
  ExecutionReport ->
  IORef [ManifestEntry] ->
  IO (Either FailureDetail PersistedRun)
persistRun runtimeConfig runIdValue executionReport manifestEntriesRef = do
  finishedAt <- getCurrentTime
  logInfo ("runId=" <> renderRunId runIdValue <> " event=summary-persist-started")
  let finalizedSummary =
        (reportSummary executionReport)
          { summaryFinishedAt = Just finishedAt
          }
      summaryRef = summaryRefForRun runIdValue
      manifestRef = manifestRefForRun runIdValue
  summaryWriteResult <- writeSummary (runtimeMinioConfig runtimeConfig) summaryRef finalizedSummary
  case summaryWriteResult of
    Left failureDetail -> pure (Left failureDetail)
    Right () -> do
      manifestEntries <- reverse <$> readIORef manifestEntriesRef
      let runManifest = buildRunManifest runIdValue summaryRef manifestEntries
      manifestWriteResult <- writeManifest (runtimeMinioConfig runtimeConfig) manifestRef runManifest
      case manifestWriteResult of
        Left failureDetail -> pure (Left failureDetail)
        Right () -> do
          summaryEvent <- publishSummaryEvent runtimeConfig runIdValue
          case summaryEvent of
            Left failureDetail -> pure (Left failureDetail)
            Right () -> do
              logInfo ("runId=" <> renderRunId runIdValue <> " event=summary-persist-completed")
              pure
                ( Right
                    PersistedRun
                      { persistedReport = executionReport {reportSummary = finalizedSummary},
                        persistedSummaryRef = summaryRef,
                        persistedManifestRef = manifestRef,
                        persistedManifest = runManifest
                      }
                )

loadValidatedDagFixture :: FilePath -> IO (Either FailureDetail DagSpec)
loadValidatedDagFixture dagPath = do
  decoded <- loadDagFile dagPath
  case decoded of
    Left parseFailure ->
      pure
        ( Left
            FailureDetail
              { failureCategory = ToolProcessFailure,
                failureCode = "dag-fixture-parse-failed",
                failureMessage = "The end-to-end validation fixture could not be parsed as YAML.",
                failureRetryable = False,
                failureContext =
                  Map.fromList
                    [ ("path", Text.pack dagPath),
                      ("parseFailure", Text.pack parseFailure)
                    ]
              }
        )
    Right dagSpec ->
      case validateDag dagSpec of
        Success validDag -> pure (Right validDag)
        Failure failures ->
          pure
            ( Left
                FailureDetail
                  { failureCategory = ToolProcessFailure,
                    failureCode = "dag-fixture-invalid",
                    failureMessage = "The end-to-end validation fixture did not satisfy DAG validation.",
                    failureRetryable = False,
                    failureContext =
                      Map.fromList
                        [ ("path", Text.pack dagPath),
                          ("failures", Text.pack (renderFailures failures))
                        ]
                  }
            )

publishSchedule :: RuntimeConfig -> RunId -> DagSpec -> IO (Either FailureDetail ())
publishSchedule runtimeConfig runIdValue dagSpec = do
  submittedEvent <- publishRunLevelEvent runtimeConfig runIdValue RunSubmitted "run-submitted"
  case submittedEvent of
    Left failureDetail -> pure (Left failureDetail)
    Right () ->
      case scheduleTopologically dagSpec of
        Left failureDetail -> pure (Left failureDetail)
        Right orderedNodes ->
          foldM
            ( \result nodeSpec ->
                case result of
                  Left failureDetail -> pure (Left failureDetail)
                  Right () -> publishNodeEvent runtimeConfig runIdValue nodeSpec NodeScheduled "node-scheduled"
            )
            (Right ())
            orderedNodes

publishRunLevelEvent :: RuntimeConfig -> RunId -> ExecutionEventType -> Text -> IO (Either FailureDetail ())
publishRunLevelEvent runtimeConfig runIdValue eventTypeValue detailText = do
  timestamp <- getCurrentTime
  publishExecutionEvents
    (runtimePulsarConfig runtimeConfig)
    (runtimeTopicName runtimeConfig)
    [ ExecutionEvent
        { eventRunId = runIdValue,
          eventNodeId = Nothing,
          eventType = eventTypeValue,
          eventDetail = detailText,
          eventTimestamp = timestamp
        }
    ]

publishNodeEvent :: RuntimeConfig -> RunId -> NodeSpec -> ExecutionEventType -> Text -> IO (Either FailureDetail ())
publishNodeEvent runtimeConfig runIdValue nodeSpec =
  publishNodeEventById runtimeConfig runIdValue (nodeId nodeSpec)

publishNodeEventById :: RuntimeConfig -> RunId -> NodeId -> ExecutionEventType -> Text -> IO (Either FailureDetail ())
publishNodeEventById runtimeConfig runIdValue nodeIdValue eventTypeValue detailText = do
  timestamp <- getCurrentTime
  publishExecutionEvents
    (runtimePulsarConfig runtimeConfig)
    (runtimeTopicName runtimeConfig)
    [ ExecutionEvent
        { eventRunId = runIdValue,
          eventNodeId = Just nodeIdValue,
          eventType = eventTypeValue,
          eventDetail = detailText,
          eventTimestamp = timestamp
        }
    ]

publishSummaryEvent :: RuntimeConfig -> RunId -> IO (Either FailureDetail ())
publishSummaryEvent runtimeConfig runIdValue =
  publishRunLevelEvent runtimeConfig runIdValue SummaryEmitted "summary-emitted"

persistPureNodeOutput ::
  RuntimeConfig ->
  RunId ->
  IORef [ManifestEntry] ->
  NodeSpec ->
  Text ->
  IO (Either FailureDetail ())
persistPureNodeOutput runtimeConfig runIdValue manifestEntriesRef nodeSpec outputReference = do
  payload <- payloadForReference outputReference
  let contentAddress =
        deriveContentAddress
          [ unRunId runIdValue,
            unNodeId (nodeId nodeSpec),
            "pure",
            outputReference
          ]
      memoRef = memoObjectRef contentAddress
  memoWriteResult <- writeMemoObject (runtimeMinioConfig runtimeConfig) memoRef payload
  case memoWriteResult of
    Left failureDetail -> pure (Left failureDetail)
    Right () -> do
      recordManifestEntry manifestEntriesRef nodeSpec memoRef Nothing
      pure (Right ())

executeFFmpegNode ::
  RuntimeConfig ->
  RunId ->
  IORef [ManifestEntry] ->
  NodeSpec ->
  [Text] ->
  IO (Either FailureDetail Text)
executeFFmpegNode runtimeConfig runIdValue manifestEntriesRef nodeSpec inputReferences =
  case inputReferences of
    [] ->
      pure
        ( Left
            FailureDetail
              { failureCategory = ToolProcessFailure,
                failureCode = "ffmpeg-input-missing",
                failureMessage = "The FFmpeg runtime adapter requires at least one input reference.",
                failureRetryable = False,
                failureContext = Map.fromList [("nodeId", unNodeId (nodeId nodeSpec))]
              }
        )
    inputReference : _ -> do
      tempDirectory <- getTemporaryDirectory
      let outputPath =
            tempDirectory
              </> ("studiomcp-" <> Text.unpack (normalizedRunNodeSegment runIdValue nodeSpec) <> ".wav")
          boundaryCommand =
            BoundaryCommand
              { boundaryExecutable = "ffmpeg",
                boundaryArguments =
                  [ "-y",
                    "-hide_banner",
                    "-loglevel",
                    "error",
                    "-i",
                    Text.unpack inputReference,
                    "-ac",
                    "1",
                    "-ar",
                    "22050",
                    "-c:a",
                    "pcm_s16le",
                    outputPath
                  ],
                boundaryStdin = "",
                boundaryTimeoutSeconds = timeoutSeconds (nodeTimeout nodeSpec)
              }
      commandResult <- runBoundaryCommand boundaryCommand
      case commandResult of
        Left failureDetail -> pure (Left failureDetail)
        Right _ -> do
          outputExists <- doesFileExist outputPath
          if not outputExists
            then
              pure
                ( Left
                    FailureDetail
                      { failureCategory = StorageFailure,
                        failureCode = "ffmpeg-output-missing",
                        failureMessage = "The FFmpeg adapter did not leave behind the expected output artifact.",
                        failureRetryable = False,
                        failureContext = Map.fromList [("outputPath", Text.pack outputPath)]
                      }
                )
            else do
              artifactBytes <- LBS.readFile outputPath
              let contentAddress =
                    deriveContentAddress
                      [ unRunId runIdValue,
                        unNodeId (nodeId nodeSpec),
                        "ffmpeg",
                        inputReference
                      ]
                  memoRef = memoObjectRef contentAddress
                  artifactRef =
                    ArtifactRef
                      { artifactBucket = artifactsBucket,
                        artifactKey =
                          ObjectKey
                            ( "artifacts/"
                                <> normalizeSegment (unNodeId (nodeId nodeSpec))
                                <> "-"
                                <> renderRunId runIdValue
                                <> ".wav"
                            ),
                        artifactAddress = Just contentAddress
                      }
                  artifactUri = renderArtifactUri artifactRef
              memoWriteResult <- writeMemoObject (runtimeMinioConfig runtimeConfig) memoRef artifactBytes
              case memoWriteResult of
                Left failureDetail -> pure (Left failureDetail)
                Right () -> do
                  artifactWriteResult <- writeArtifactObject (runtimeMinioConfig runtimeConfig) artifactRef artifactBytes
                  case artifactWriteResult of
                    Left failureDetail -> pure (Left failureDetail)
                    Right () -> do
                      recordManifestEntry manifestEntriesRef nodeSpec memoRef (Just artifactRef)
                      pure (Right artifactUri)

recordManifestEntry ::
  IORef [ManifestEntry] ->
  NodeSpec ->
  MemoObjectRef ->
  Maybe ArtifactRef ->
  IO ()
recordManifestEntry manifestEntriesRef nodeSpec memoRef artifactRef =
  modifyIORef'
    manifestEntriesRef
    ( ManifestEntry
        { manifestEntryNodeId = nodeId nodeSpec,
          manifestEntryMemoRef = memoRef,
          manifestEntryArtifactRef = artifactRef
        }
        :
    )

resolvePureOutputReference :: NodeSpec -> IO (Either FailureDetail Text)
resolvePureOutputReference nodeSpec =
  case Text.toLower (unOutputType (nodeOutputType nodeSpec)) of
    "media/input" -> do
      seeded <- seedDeterministicFixtures
      case seeded of
        Left failureDetail -> pure (Left failureDetail)
        Right fixturePath -> pure (Right (Text.pack fixturePath))
    "media/missing-input" ->
      pure (Right "examples/assets/audio/does-not-exist.wav")
    _ ->
      pure (Right ("pure://" <> unNodeId (nodeId nodeSpec)))

payloadForReference :: Text -> IO LBS.ByteString
payloadForReference outputReference = do
  let outputPath = Text.unpack outputReference
  fileExists <- doesFileExist outputPath
  if fileExists
    then LBS.readFile outputPath
    else pure (LBS.fromStrict (Text.encodeUtf8 outputReference))

validatePersistedRun ::
  (RunId -> RuntimeConfig) ->
  RunId ->
  PersistedRun ->
  RunStatus ->
  ExecutionEventType ->
  Int ->
  IO (Either FailureDetail ())
validatePersistedRun runtimeConfigFor runIdValue persistedRun expectedStatus expectedEventType expectedEventCount = do
  readBackResult <- readSummary (runtimeMinioConfig (runtimeConfigFor runIdValue)) (persistedSummaryRef persistedRun)
  case readBackResult of
    Left failureDetail -> pure (Left failureDetail)
    Right observedSummary
      | observedSummary /= summary ->
          pure (Left (summaryMismatch summary observedSummary))
      | summaryStatus summary /= expectedStatus ->
          pure (Left (statusMismatch expectedStatus summary))
      | otherwise -> do
          consumedEventsResult <-
            consumeExecutionEvents
              (runtimePulsarConfig (runtimeConfigFor runIdValue))
              (runtimeTopicName (runtimeConfigFor runIdValue))
              ("studiomcp-e2e-" <> renderRunId runIdValue)
              expectedEventCount
          case consumedEventsResult of
            Left failureDetail -> pure (Left failureDetail)
            Right events
              | not (all ((== runIdValue) . eventRunId) events) ->
                  pure (Left (eventRunIdMismatch runIdValue))
              | not (any ((== SummaryEmitted) . eventType) events) ->
                  pure (Left (missingSummaryEvent runIdValue))
              | not (any ((== expectedEventType) . eventType) events) ->
                  pure (Left (missingExpectedEvent runIdValue expectedEventType))
              | otherwise -> pure (Right ())
  where
    summary = reportSummary (persistedReport persistedRun)

freshRunId :: Text -> IO RunId
freshRunId prefix = do
  currentTime <- getCurrentTime
  pure (RunId (prefix <> "-" <> Text.pack (formatTime defaultTimeLocale "%Y%m%d%H%M%S%q" currentTime)))

normalizedRunNodeSegment :: RunId -> NodeSpec -> Text
normalizedRunNodeSegment runIdValue nodeSpec =
  normalizeSegment (renderRunId runIdValue <> "-" <> unNodeId (nodeId nodeSpec))

renderRunId :: RunId -> Text
renderRunId (RunId value) = normalizeSegment value

renderArtifactUri :: ArtifactRef -> Text
renderArtifactUri artifactRef =
  "minio://"
    <> unBucketName (artifactBucket artifactRef)
    <> "/"
    <> unObjectKey (artifactKey artifactRef)

renderNodeLog :: RunId -> NodeSpec -> Text -> Text
renderNodeLog runIdValue nodeSpec eventText =
  "runId=" <> renderRunId runIdValue <> " nodeId=" <> unNodeId (nodeId nodeSpec) <> " event=" <> eventText

summaryMismatch :: Summary -> Summary -> FailureDetail
summaryMismatch expectedSummary observedSummary =
  FailureDetail
    { failureCategory = StorageFailure,
      failureCode = "e2e-summary-mismatch",
      failureMessage = "The persisted summary did not match the in-memory execution summary.",
      failureRetryable = False,
      failureContext =
        Map.fromList
          [ ("expectedStatus", Text.pack (show (summaryStatus expectedSummary))),
            ("observedStatus", Text.pack (show (summaryStatus observedSummary)))
          ]
    }

statusMismatch :: RunStatus -> Summary -> FailureDetail
statusMismatch expectedStatus summary =
  FailureDetail
    { failureCategory = StorageFailure,
      failureCode = "e2e-summary-status-mismatch",
      failureMessage = "The persisted summary did not carry the expected terminal run status.",
      failureRetryable = False,
      failureContext =
        Map.fromList
          [ ("expectedStatus", Text.pack (show expectedStatus)),
            ("observedStatus", Text.pack (show (summaryStatus summary)))
          ]
    }

eventRunIdMismatch :: RunId -> FailureDetail
eventRunIdMismatch runIdValue =
  validationFailure
    "e2e-event-run-id-mismatch"
    ("Consumed Pulsar events did not all belong to run " <> renderRunId runIdValue <> ".")

missingSummaryEvent :: RunId -> FailureDetail
missingSummaryEvent runIdValue =
  validationFailure
    "e2e-summary-event-missing"
    ("The execution lifecycle for run " <> renderRunId runIdValue <> " did not emit a summary event.")

missingExpectedEvent :: RunId -> ExecutionEventType -> FailureDetail
missingExpectedEvent runIdValue eventTypeValue =
  validationFailure
    "e2e-expected-event-missing"
    ( "The execution lifecycle for run "
        <> renderRunId runIdValue
        <> " did not emit event "
        <> Text.pack (show eventTypeValue)
        <> "."
    )

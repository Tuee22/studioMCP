{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.MCP.Tools
  ( -- * Tool Catalog
    ToolCatalog (..),
    newToolCatalog,
    newToolCatalogWithExecutor,
    newToolCatalogWithRuntime,
    listTools,
    callTool,
    WorkflowRunRecord (..),
    listWorkflowRunsForTenant,
    lookupWorkflowRunRecord,

    -- * Tool Names
    ToolName (..),
    allToolNames,

    -- * Tool Execution
    ToolExecutor (..),
    ToolResult (..),
    ToolError (..),
    toolErrorCode,

    -- * Tool Definitions
    workflowSubmitTool,
    workflowStatusTool,
    workflowCancelTool,
    workflowListTool,
    artifactGetTool,
    artifactDownloadUrlTool,
    artifactUploadUrlTool,
    artifactHideTool,
    artifactArchiveTool,
    tenantInfoTool,

    -- * Tool Authorization
    toolRequiredScopes,
  )
where

import Control.Concurrent (forkIO)
import Control.Concurrent.STM (TVar, atomically, modifyTVar', newTVarIO, readTVarIO)
import Data.Aeson
  ( FromJSON (parseJSON),
    Result (Error, Success),
    ToJSON (toJSON),
    Value (..),
    encode,
    fromJSON,
    object,
    withObject,
    withText,
    (.:),
    (.:?),
    (.=),
  )
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy as LBS
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Ord (Down (..))
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time (UTCTime, getCurrentTime)
import Data.Time.Clock (diffUTCTime)
import StudioMCP.Auth.Types (SubjectId (..), TenantId (..))
import StudioMCP.DAG.Executor (ExecutorAdapters, ExecutionReport (..), executeSequential)
import StudioMCP.DAG.Parser (decodeDagBytes)
import StudioMCP.DAG.Runtime (PersistedRun (..), RuntimeConfig (..), runDagSpecEndToEnd)
import StudioMCP.DAG.Summary (RunId (..), summaryFinishedAt, summaryStartedAt, summaryStatus)
import StudioMCP.DAG.Types (DagSpec)
import Data.Time.Format (defaultTimeLocale, formatTime)
import StudioMCP.MCP.Protocol.Types
  ( CallToolParams (..),
    CallToolResult (..),
    ContentType (..),
    ToolContent (..),
    ToolDefinition (..),
    ToolInputSchema (..),
  )
import StudioMCP.Observability.McpMetrics
  ( McpMetricsService,
    recordToolCall,
  )
import StudioMCP.Storage.Governance
  ( ArtifactState (..),
    GovernanceService,
    GovernanceMetadata (..),
    archiveArtifact,
    defaultGovernancePolicy,
    getArtifactState,
    hideArtifact,
    newGovernanceService,
  )
import StudioMCP.Storage.Keys (summaryRefForRun)
import StudioMCP.Storage.MinIO (MinIOConfig, readSummary)
import StudioMCP.Storage.TenantStorage
  ( TenantArtifact (..),
    TenantStorageError (..),
    TenantStorageService,
    createTenantArtifact,
    defaultTenantStorageConfig,
    generateDownloadUrl,
    generateUploadUrl,
    getTenantArtifact,
    listTenantArtifacts,
    newTenantStorageService,
    puExpiresAt,
    puHeaders,
    puMethod,
    puUrl,
  )

-- | Tool names in the catalog
data ToolName
  = WorkflowSubmit
  | WorkflowStatus
  | WorkflowCancel
  | WorkflowList
  | ArtifactGet
  | ArtifactDownloadUrl
  | ArtifactUploadUrl
  | ArtifactHide
  | ArtifactArchive
  | TenantInfo
  deriving (Eq, Ord, Show)

instance ToJSON ToolName where
  toJSON WorkflowSubmit = "workflow.submit"
  toJSON WorkflowStatus = "workflow.status"
  toJSON WorkflowCancel = "workflow.cancel"
  toJSON WorkflowList = "workflow.list"
  toJSON ArtifactGet = "artifact.get"
  toJSON ArtifactDownloadUrl = "artifact.download_url"
  toJSON ArtifactUploadUrl = "artifact.upload_url"
  toJSON ArtifactHide = "artifact.hide"
  toJSON ArtifactArchive = "artifact.archive"
  toJSON TenantInfo = "tenant.info"

instance FromJSON ToolName where
  parseJSON = withText "ToolName" $ \t ->
    case t of
      "workflow.submit" -> pure WorkflowSubmit
      "workflow.status" -> pure WorkflowStatus
      "workflow.cancel" -> pure WorkflowCancel
      "workflow.list" -> pure WorkflowList
      "artifact.get" -> pure ArtifactGet
      "artifact.download_url" -> pure ArtifactDownloadUrl
      "artifact.upload_url" -> pure ArtifactUploadUrl
      "artifact.hide" -> pure ArtifactHide
      "artifact.archive" -> pure ArtifactArchive
      "tenant.info" -> pure TenantInfo
      other -> fail $ "Unknown tool name: " <> T.unpack other

-- | All available tool names
allToolNames :: [ToolName]
allToolNames =
  [ WorkflowSubmit,
    WorkflowStatus,
    WorkflowCancel,
    WorkflowList,
    ArtifactGet,
    ArtifactDownloadUrl,
    ArtifactUploadUrl,
    ArtifactHide,
    ArtifactArchive,
    TenantInfo
  ]

-- | Tool execution errors
data ToolError
  = ToolNotFound Text
  | InvalidArguments Text
  | ExecutionFailed Text
  | AuthorizationFailed Text
  | ResourceNotFound Text
  | RateLimited
  deriving (Eq, Show)

-- | Get error code for tool errors
toolErrorCode :: ToolError -> Text
toolErrorCode (ToolNotFound _) = "tool-not-found"
toolErrorCode (InvalidArguments _) = "invalid-arguments"
toolErrorCode (ExecutionFailed _) = "execution-failed"
toolErrorCode (AuthorizationFailed _) = "authorization-failed"
toolErrorCode (ResourceNotFound _) = "resource-not-found"
toolErrorCode RateLimited = "rate-limited"

-- | Result of tool execution
data ToolResult
  = ToolSuccess CallToolResult
  | ToolFailure ToolError
  deriving (Eq, Show)

-- | Tool executor context
data ToolExecutor = ToolExecutor
  { teToolName :: ToolName,
    teTenantId :: TenantId,
    teSubjectId :: SubjectId,
    teArguments :: Maybe Value
  }
  deriving (Eq, Show)

-- | Internal state for tool catalog
data ToolCatalogState = ToolCatalogState
  { tcsExecutionCount :: Map.Map ToolName Int,
    tcsLastExecution :: Map.Map ToolName UTCTime,
    tcsRuns :: Map.Map Text WorkflowRunRecord
  }

data WorkflowRunRecord = WorkflowRunRecord
  { wrrRunId :: RunId,
    wrrTenantId :: TenantId,
    wrrSubmittedBy :: SubjectId,
    wrrStatus :: Text,
    wrrSubmittedAt :: UTCTime,
    wrrCompletedAt :: Maybe UTCTime
  }
  deriving (Eq, Show)

-- | Tool catalog service
data ToolCatalog = ToolCatalog
  { tcState :: TVar ToolCatalogState,
    tcExecutorAdapters :: Maybe ExecutorAdapters,
    tcRuntimeConfig :: Maybe RuntimeConfig,
    tcMinIOConfig :: Maybe MinIOConfig,
    tcTenantStorage :: TenantStorageService,
    tcGovernance :: GovernanceService,
    tcMetrics :: Maybe McpMetricsService
  }

newToolCatalogInternal ::
  Maybe ExecutorAdapters ->
  Maybe RuntimeConfig ->
  Maybe MinIOConfig ->
  TenantStorageService ->
  GovernanceService ->
  Maybe McpMetricsService ->
  IO ToolCatalog
newToolCatalogInternal maybeAdapters maybeRuntime maybeMinioConfig tenantStorage governance maybeMetrics = do
  stateVar <-
    newTVarIO
      ToolCatalogState
        { tcsExecutionCount = Map.empty,
          tcsLastExecution = Map.empty,
          tcsRuns = Map.empty
        }
  pure
    ToolCatalog
      { tcState = stateVar,
        tcExecutorAdapters = maybeAdapters,
        tcRuntimeConfig = maybeRuntime,
        tcMinIOConfig = maybeMinioConfig,
        tcTenantStorage = tenantStorage,
        tcGovernance = governance,
        tcMetrics = maybeMetrics
      }

-- | Create a new tool catalog backed by local in-memory services.
newToolCatalog :: IO ToolCatalog
newToolCatalog = do
  tenantStorage <- newTenantStorageService defaultTenantStorageConfig
  governance <- newGovernanceService defaultGovernancePolicy
  newToolCatalogInternal Nothing Nothing Nothing tenantStorage governance Nothing

-- | Create a new tool catalog with DAG executor and MinIO config
newToolCatalogWithExecutor :: ExecutorAdapters -> MinIOConfig -> IO ToolCatalog
newToolCatalogWithExecutor adapters minioConfig = do
  tenantStorage <- newTenantStorageService defaultTenantStorageConfig
  governance <- newGovernanceService defaultGovernancePolicy
  newToolCatalogInternal (Just adapters) Nothing (Just minioConfig) tenantStorage governance Nothing

-- | Create a new tool catalog that submits workflows through the full DAG runtime.
newToolCatalogWithRuntime ::
  RuntimeConfig ->
  TenantStorageService ->
  GovernanceService ->
  Maybe McpMetricsService ->
  IO ToolCatalog
newToolCatalogWithRuntime runtimeConfig tenantStorage governance maybeMetrics =
  newToolCatalogInternal Nothing (Just runtimeConfig) (Just (runtimeMinioConfig runtimeConfig)) tenantStorage governance maybeMetrics

-- | List all available tools
listTools :: ToolCatalog -> IO [ToolDefinition]
listTools _catalog =
  pure
    [ workflowSubmitTool,
      workflowStatusTool,
      workflowCancelTool,
      workflowListTool,
      artifactGetTool,
      artifactDownloadUrlTool,
      artifactUploadUrlTool,
      artifactHideTool,
      artifactArchiveTool,
      tenantInfoTool
    ]

-- | Call a tool with given parameters
callTool ::
  ToolCatalog ->
  TenantId ->
  SubjectId ->
  CallToolParams ->
  IO ToolResult
callTool catalog tenantId subjectId params = do
  let toolNameText = ctpName params
  case parseToolName toolNameText of
    Nothing -> pure $ ToolFailure $ ToolNotFound toolNameText
    Just toolName -> do
      startedAt <- getCurrentTime
      now <- getCurrentTime
      atomically $ modifyTVar' (tcState catalog) $ \s ->
        s
          { tcsExecutionCount = Map.insertWith (+) toolName 1 (tcsExecutionCount s),
            tcsLastExecution = Map.insert toolName now (tcsLastExecution s)
          }
      result <-
        executeTool
          catalog
          ToolExecutor
            { teToolName = toolName,
              teTenantId = tenantId,
              teSubjectId = subjectId,
              teArguments = ctpArguments params
            }
      endedAt <- getCurrentTime
      case tcMetrics catalog of
        Just metrics ->
          recordToolCall
            metrics
            toolNameText
            tenantId
            (realToFrac (diffUTCTime endedAt startedAt) * 1000.0)
            (isToolSuccess result)
        Nothing -> pure ()
      pure result

-- | Parse tool name from text
parseToolName :: Text -> Maybe ToolName
parseToolName "workflow.submit" = Just WorkflowSubmit
parseToolName "workflow.status" = Just WorkflowStatus
parseToolName "workflow.cancel" = Just WorkflowCancel
parseToolName "workflow.list" = Just WorkflowList
parseToolName "artifact.get" = Just ArtifactGet
parseToolName "artifact.download_url" = Just ArtifactDownloadUrl
parseToolName "artifact.upload_url" = Just ArtifactUploadUrl
parseToolName "artifact.hide" = Just ArtifactHide
parseToolName "artifact.archive" = Just ArtifactArchive
parseToolName "tenant.info" = Just TenantInfo
parseToolName _ = Nothing

-- | Execute a tool
executeTool :: ToolCatalog -> ToolExecutor -> IO ToolResult
executeTool catalog executor =
  case teToolName executor of
    WorkflowSubmit -> executeWorkflowSubmit catalog executor
    WorkflowStatus -> executeWorkflowStatus catalog executor
    WorkflowCancel -> executeWorkflowCancel catalog executor
    WorkflowList -> executeWorkflowList catalog executor
    ArtifactGet -> executeArtifactGet catalog executor
    ArtifactDownloadUrl -> executeArtifactDownloadUrl catalog executor
    ArtifactUploadUrl -> executeArtifactUploadUrl catalog executor
    ArtifactHide -> executeArtifactHide catalog executor
    ArtifactArchive -> executeArtifactArchive catalog executor
    TenantInfo -> executeTenantInfo catalog executor

-- | Execute workflow.submit tool
executeWorkflowSubmit :: ToolCatalog -> ToolExecutor -> IO ToolResult
executeWorkflowSubmit catalog executor =
  case teArguments executor >>= extractDagSpecArg of
    Nothing -> pure $ ToolFailure $ InvalidArguments "Missing dag_spec argument"
    Just (Left parseError) ->
      pure $ ToolFailure $ InvalidArguments parseError
    Just (Right dagSpec) -> do
      let TenantId tenantIdText = teTenantId executor
      now <- getCurrentTime
      runId <- generateRunId
      case tcRuntimeConfig catalog of
        Just runtimeConfig -> do
          upsertRunRecord
            catalog
            WorkflowRunRecord
              { wrrRunId = runId,
                wrrTenantId = teTenantId executor,
                wrrSubmittedBy = teSubjectId executor,
                wrrStatus = "running",
                wrrSubmittedAt = now,
                wrrCompletedAt = Nothing
              }
          _ <-
            forkIO $ do
              runtimeResult <- runDagSpecEndToEnd runtimeConfig runId dagSpec
              finishedAt <- getCurrentTime
              case runtimeResult of
                Left _failureDetail ->
                  upsertRunRecord
                    catalog
                    WorkflowRunRecord
                      { wrrRunId = runId,
                        wrrTenantId = teTenantId executor,
                        wrrSubmittedBy = teSubjectId executor,
                        wrrStatus = "failed",
                        wrrSubmittedAt = now,
                        wrrCompletedAt = Just finishedAt
                      }
                Right persistedRun ->
                  upsertRunRecord
                    catalog
                    WorkflowRunRecord
                      { wrrRunId = runId,
                        wrrTenantId = teTenantId executor,
                        wrrSubmittedBy = teSubjectId executor,
                        wrrStatus = T.pack . show . summaryStatus . reportSummary . persistedReport $ persistedRun,
                        wrrSubmittedAt = now,
                        wrrCompletedAt = Just finishedAt
                      }
          pure $
            toolResultWithData
              ("Workflow submitted for tenant " <> tenantIdText <> ". Run ID: " <> unRunId runId <> ". Status: running")
              (workflowRunRecordToJson
                WorkflowRunRecord
                  { wrrRunId = runId,
                    wrrTenantId = teTenantId executor,
                    wrrSubmittedBy = teSubjectId executor,
                    wrrStatus = "running",
                    wrrSubmittedAt = now,
                    wrrCompletedAt = Nothing
                  })
        Nothing ->
          case tcExecutorAdapters catalog of
            Nothing -> do
              let runRecord =
                    WorkflowRunRecord
                      { wrrRunId = runId,
                        wrrTenantId = teTenantId executor,
                        wrrSubmittedBy = teSubjectId executor,
                        wrrStatus = "accepted",
                        wrrSubmittedAt = now,
                        wrrCompletedAt = Nothing
                      }
              upsertRunRecord catalog runRecord
              pure $
                toolResultWithData
                  ("Workflow accepted for tenant " <> tenantIdText <> ". Run ID: " <> unRunId runId <> ". Status: accepted")
                  (workflowRunRecordToJson runRecord)
            Just adapters -> do
              result <- executeSequential adapters runId now dagSpec
              case result of
                Left failureDetail -> do
                  let runRecord =
                        WorkflowRunRecord
                          { wrrRunId = runId,
                            wrrTenantId = teTenantId executor,
                            wrrSubmittedBy = teSubjectId executor,
                            wrrStatus = "failed",
                            wrrSubmittedAt = now,
                            wrrCompletedAt = Just now
                          }
                  upsertRunRecord catalog runRecord
                  pure $ ToolFailure $ ExecutionFailed $ T.pack $ show failureDetail
                Right report -> do
                  let statusText = T.pack . show . summaryStatus $ StudioMCP.DAG.Executor.reportSummary report
                      runRecord =
                        WorkflowRunRecord
                          { wrrRunId = runId,
                            wrrTenantId = teTenantId executor,
                            wrrSubmittedBy = teSubjectId executor,
                            wrrStatus = statusText,
                            wrrSubmittedAt = now,
                            wrrCompletedAt = Just now
                          }
                  upsertRunRecord catalog runRecord
                  pure $
                    toolResultWithData
                      ("Workflow submitted for tenant " <> tenantIdText <> ". Run ID: " <> unRunId runId <> ". Status: " <> statusText)
                      (workflowRunRecordToJson runRecord)

-- | Execute workflow.status tool
executeWorkflowStatus :: ToolCatalog -> ToolExecutor -> IO ToolResult
executeWorkflowStatus catalog executor =
  case teArguments executor of
    Nothing -> pure $ ToolFailure $ InvalidArguments "Missing run_id argument"
    Just args ->
      case extractStringArg "run_id" args of
        Nothing -> pure $ ToolFailure $ InvalidArguments "run_id must be a string"
        Just runIdText -> do
          storedRuns <- readTVarIO (tcState catalog)
          case Map.lookup runIdText (tcsRuns storedRuns) of
            Just runRecord
              | wrrTenantId runRecord == teTenantId executor ->
                  pure $ toolResultWithData ("Run " <> runIdText <> " status: " <> wrrStatus runRecord) (workflowRunRecordToJson runRecord)
            _ ->
              case tcMinIOConfig catalog of
                Nothing ->
                  pure $ ToolFailure $ ResourceNotFound $ "Run not found: " <> runIdText
                Just minioConfig -> do
                  let runId = RunId runIdText
                      summaryRef = summaryRefForRun runId
                  result <- readSummary minioConfig summaryRef
                  case result of
                    Left _failureDetail ->
                      pure $ ToolFailure $ ResourceNotFound $ "Run not found: " <> runIdText
                    Right summary ->
                      let status = T.pack . show $ summaryStatus summary
                          runRecord =
                            WorkflowRunRecord
                              { wrrRunId = runId,
                                wrrTenantId = teTenantId executor,
                                wrrSubmittedBy = teSubjectId executor,
                                wrrStatus = status,
                                wrrSubmittedAt = summaryStartedAt summary,
                                wrrCompletedAt = summaryFinishedAt summary
                              }
                       in pure $
                            toolResultWithData
                              ("Run " <> runIdText <> " status: " <> status)
                              (workflowRunRecordToJson runRecord)

-- | Execute workflow.cancel tool
executeWorkflowCancel :: ToolCatalog -> ToolExecutor -> IO ToolResult
executeWorkflowCancel catalog executor =
  case teArguments executor of
    Nothing -> pure $ ToolFailure $ InvalidArguments "Missing run_id argument"
    Just args ->
      case extractStringArg "run_id" args of
        Nothing -> pure $ ToolFailure $ InvalidArguments "run_id must be a string"
        Just runIdText -> do
          now <- getCurrentTime
          state <- readTVarIO (tcState catalog)
          case Map.lookup runIdText (tcsRuns state) of
            Nothing ->
              pure $ ToolFailure $ ResourceNotFound $ "Run not found: " <> runIdText
            Just runRecord
              | wrrTenantId runRecord /= teTenantId executor ->
                  pure $ ToolFailure $ ResourceNotFound $ "Run not found: " <> runIdText
              | otherwise -> do
                  upsertRunRecord catalog runRecord {wrrStatus = "cancelled", wrrCompletedAt = Just now}
                  pure $
                    toolResultWithData
                      ("Run " <> runIdText <> " cancelled")
                      (workflowRunRecordToJson runRecord {wrrStatus = "cancelled", wrrCompletedAt = Just now})

-- | Execute workflow.list tool
executeWorkflowList :: ToolCatalog -> ToolExecutor -> IO ToolResult
executeWorkflowList catalog executor = do
  let TenantId tenantIdText = teTenantId executor
      maybeStatusFilter = teArguments executor >>= extractStringArg "status"
      limit = maybe 100 id (teArguments executor >>= extractIntArg "limit")
  state <- readTVarIO (tcState catalog)
  let runs =
        take limit
          . sortOn (Down . wrrSubmittedAt)
          . filter (\runRecord -> wrrTenantId runRecord == teTenantId executor)
          . filter (\runRecord -> maybe True (== wrrStatus runRecord) maybeStatusFilter)
          $ Map.elems (tcsRuns state)
      renderRun runRecord =
        "- " <> unRunId (wrrRunId runRecord) <> ": " <> wrrStatus runRecord
      body =
        if null runs
          then "Workflows for tenant " <> tenantIdText <> ":\n- none"
          else "Workflows for tenant " <> tenantIdText <> ":\n" <> T.intercalate "\n" (map renderRun runs)
  pure $ toolResultWithData body (toJSON (map workflowRunRecordToJson runs))

-- | Execute artifact.get tool
executeArtifactGet :: ToolCatalog -> ToolExecutor -> IO ToolResult
executeArtifactGet catalog executor =
  case teArguments executor of
    Nothing -> pure $ ToolFailure $ InvalidArguments "Missing artifact_id argument"
    Just args ->
      case extractStringArg "artifact_id" args of
        Nothing -> pure $ ToolFailure $ InvalidArguments "artifact_id must be a string"
        Just artifactId -> do
          artifactResult <- getTenantArtifact (tcTenantStorage catalog) (teTenantId executor) artifactId
          case artifactResult of
            Left err ->
              pure $ ToolFailure (tenantStorageErrorToToolError err)
            Right artifact -> do
              artifactState <- getArtifactState (tcGovernance catalog) artifactId
              pure $
                plainTextResult $
                  "Artifact "
                    <> artifactId
                    <> ":\n"
                    <> "  Content-Type: "
                    <> taContentType artifact
                    <> "\n"
                    <> "  Size: "
                    <> T.pack (show (taFileSize artifact))
                    <> " bytes\n"
                    <> "  Version: "
                    <> T.pack (show (taVersion artifact))
                    <> "\n"
                    <> "  State: "
                    <> renderArtifactState artifactState

-- | Execute artifact.download_url tool
executeArtifactDownloadUrl :: ToolCatalog -> ToolExecutor -> IO ToolResult
executeArtifactDownloadUrl catalog executor =
  case teArguments executor of
    Nothing -> pure $ ToolFailure $ InvalidArguments "Missing artifact_id argument"
    Just args ->
      case extractStringArg "artifact_id" args of
        Nothing -> pure $ ToolFailure $ InvalidArguments "artifact_id must be a string"
        Just artifactId -> do
          let maybeVersion = teArguments executor >>= extractIntArg "version"
          result <- generateDownloadUrl (tcTenantStorage catalog) (teTenantId executor) artifactId maybeVersion
          case result of
            Left err ->
              pure $ ToolFailure (tenantStorageErrorToToolError err)
            Right presigned ->
              pure $
                plainTextResult $
                  "Download URL for artifact "
                    <> artifactId
                    <> ":\n"
                    <> puUrl presigned
                    <> "\nMethod: "
                    <> puMethod presigned
                    <> "\nExpires At: "
                    <> T.pack (show (puExpiresAt presigned))

-- | Execute artifact.upload_url tool
executeArtifactUploadUrl :: ToolCatalog -> ToolExecutor -> IO ToolResult
executeArtifactUploadUrl catalog executor =
  case teArguments executor of
    Nothing -> pure $ ToolFailure $ InvalidArguments "Missing content_type argument"
    Just args ->
      case extractStringArg "content_type" args of
        Nothing -> pure $ ToolFailure $ InvalidArguments "content_type must be a string"
        Just contentType -> do
          let fileName = maybe "upload.bin" id (extractStringArg "file_name" args)
              fileSize = maybe 0 id (extractIntArg "file_size" args)
          artifactResult <-
            createTenantArtifact
              (tcTenantStorage catalog)
              (teTenantId executor)
              contentType
              fileName
              (fromIntegral fileSize)
              Map.empty
          case artifactResult of
            Left err ->
              pure $ ToolFailure (tenantStorageErrorToToolError err)
            Right artifact -> do
              urlResult <- generateUploadUrl (tcTenantStorage catalog) (teTenantId executor) (taArtifactId artifact) contentType
              case urlResult of
                Left err ->
                  pure $ ToolFailure (tenantStorageErrorToToolError err)
                Right presigned ->
                  pure $
                    plainTextResult $
                      "Upload URL generated for artifact "
                        <> taArtifactId artifact
                        <> ":\n"
                        <> puUrl presigned
                        <> "\nMethod: "
                        <> puMethod presigned
                        <> "\nHeaders: "
                        <> T.intercalate ", " [k <> "=" <> v | (k, v) <- Map.toList (puHeaders presigned)]

-- | Execute artifact.hide tool
executeArtifactHide :: ToolCatalog -> ToolExecutor -> IO ToolResult
executeArtifactHide catalog executor =
  case teArguments executor of
    Nothing -> pure $ ToolFailure $ InvalidArguments "Missing artifact_id argument"
    Just args ->
      case extractStringArg "artifact_id" args of
        Nothing -> pure $ ToolFailure $ InvalidArguments "artifact_id must be a string"
        Just artifactId -> do
          artifactResult <- getTenantArtifact (tcTenantStorage catalog) (teTenantId executor) artifactId
          case artifactResult of
            Left err ->
              pure $ ToolFailure (tenantStorageErrorToToolError err)
            Right _artifact -> do
              now <- getCurrentTime
              let reason = maybe "hidden via MCP tool" id (extractStringArg "reason" args)
              result <-
                hideArtifact
                  (tcGovernance catalog)
                  artifactId
                  (governanceMetadata executor reason now)
              case result of
                Left err ->
                  pure $ ToolFailure $ ExecutionFailed $ T.pack (show err)
                Right _ ->
                  pure $ plainTextResult $ "Artifact " <> artifactId <> " hidden successfully. State: hidden"

-- | Execute artifact.archive tool
executeArtifactArchive :: ToolCatalog -> ToolExecutor -> IO ToolResult
executeArtifactArchive catalog executor =
  case teArguments executor of
    Nothing -> pure $ ToolFailure $ InvalidArguments "Missing artifact_id argument"
    Just args ->
      case extractStringArg "artifact_id" args of
        Nothing -> pure $ ToolFailure $ InvalidArguments "artifact_id must be a string"
        Just artifactId -> do
          artifactResult <- getTenantArtifact (tcTenantStorage catalog) (teTenantId executor) artifactId
          case artifactResult of
            Left err ->
              pure $ ToolFailure (tenantStorageErrorToToolError err)
            Right _artifact -> do
              now <- getCurrentTime
              let reason = maybe "archived via MCP tool" id (extractStringArg "reason" args)
              result <-
                archiveArtifact
                  (tcGovernance catalog)
                  artifactId
                  (governanceMetadata executor reason now)
              case result of
                Left err ->
                  pure $ ToolFailure $ ExecutionFailed $ T.pack (show err)
                Right _ ->
                  pure $ plainTextResult $ "Artifact " <> artifactId <> " archived successfully. State: archived"

-- | Execute tenant.info tool
executeTenantInfo :: ToolCatalog -> ToolExecutor -> IO ToolResult
executeTenantInfo catalog executor = do
  let TenantId tenantIdText = teTenantId executor
      SubjectId subjectIdText = teSubjectId executor
  artifacts <- listTenantArtifacts (tcTenantStorage catalog) (teTenantId executor)
  let usedBytes = sum (map taFileSize artifacts)
  pure $
    plainTextResult $
      "Tenant Information:\n"
        <> "  Tenant ID: "
        <> tenantIdText
        <> "\n"
        <> "  Subject ID: "
        <> subjectIdText
        <> "\n"
        <> "  Storage Backend: platform-minio\n"
        <> "  Artifact Count: "
        <> T.pack (show (length artifacts))
        <> "\n"
        <> "  Quota: 10737418240 bytes\n"
        <> "  Used: "
        <> T.pack (show usedBytes)

-- | Extract string argument from JSON value
extractStringArg :: Text -> Value -> Maybe Text
extractStringArg key (Object obj) =
  case KeyMap.lookup (Key.fromText key) obj of
    Just (String s) -> Just s
    _ -> Nothing
extractStringArg _ _ = Nothing

extractIntArg :: Text -> Value -> Maybe Int
extractIntArg key (Object obj) =
  case KeyMap.lookup (Key.fromText key) obj of
    Just (Number n) -> Just (round n)
    _ -> Nothing
extractIntArg _ _ = Nothing

plainTextResult :: Text -> ToolResult
plainTextResult message =
  ToolSuccess
    CallToolResult
      { ctrContent =
          [ ToolContent
              { tcType = TextContent,
                tcText = Just message,
                tcData = Nothing,
                tcMimeType = Nothing,
                tcUri = Nothing
              }
          ],
        ctrIsError = Nothing
      }

toolResultWithData :: Text -> Value -> ToolResult
toolResultWithData message payload =
  ToolSuccess
    CallToolResult
      { ctrContent =
          [ ToolContent
              { tcType = TextContent,
                tcText = Just message,
                tcData = Just (TE.decodeUtf8 (LBS.toStrict (encode payload))),
                tcMimeType = Just "application/json",
                tcUri = Nothing
              }
          ],
        ctrIsError = Nothing
      }

upsertRunRecord :: ToolCatalog -> WorkflowRunRecord -> IO ()
upsertRunRecord catalog runRecord =
  atomically $
    modifyTVar' (tcState catalog) $ \state ->
      state
        { tcsRuns =
            Map.insert (unRunId (wrrRunId runRecord)) runRecord (tcsRuns state)
      }

listWorkflowRunsForTenant :: ToolCatalog -> TenantId -> IO [WorkflowRunRecord]
listWorkflowRunsForTenant catalog tenantIdValue = do
  state <- readTVarIO (tcState catalog)
  pure $
    sortOn (Down . wrrSubmittedAt) $
      filter ((== tenantIdValue) . wrrTenantId) (Map.elems (tcsRuns state))

lookupWorkflowRunRecord :: ToolCatalog -> TenantId -> RunId -> IO (Maybe WorkflowRunRecord)
lookupWorkflowRunRecord catalog tenantIdValue runIdValue = do
  state <- readTVarIO (tcState catalog)
  pure $ do
    runRecord <- Map.lookup (unRunId runIdValue) (tcsRuns state)
    if wrrTenantId runRecord == tenantIdValue
      then Just runRecord
      else Nothing

governanceMetadata :: ToolExecutor -> Text -> UTCTime -> GovernanceMetadata
governanceMetadata executor reason now =
  GovernanceMetadata
    { gmReason = reason,
      gmRequestedBy = teSubjectId executor,
      gmTenantId = teTenantId executor,
      gmTimestamp = now,
      gmRelatedArtifacts = []
    }

renderArtifactState :: ArtifactState -> Text
renderArtifactState Active = "active"
renderArtifactState Hidden = "hidden"
renderArtifactState Archived = "archived"
renderArtifactState (Superseded newArtifactId) = "superseded by " <> newArtifactId

tenantStorageErrorToToolError :: TenantStorageError -> ToolError
tenantStorageErrorToToolError err =
  case err of
    ArtifactNotFound artifactId -> ResourceNotFound artifactId
    ArtifactVersionNotFound artifactId version ->
      ResourceNotFound (artifactId <> " version " <> T.pack (show version))
    ArtifactTooLarge _ _ ->
      InvalidArguments "Artifact exceeds the configured size limit"
    InvalidContentType contentType ->
      InvalidArguments ("Unsupported content type: " <> contentType)
    StorageQuotaExceeded _ ->
      ExecutionFailed "Tenant storage quota exceeded"
    TenantNotConfigured _ ->
      ExecutionFailed "Tenant storage backend is not configured"
    StorageBackendError message ->
      ExecutionFailed message
    PresignedUrlGenerationFailed message ->
      ExecutionFailed message

-- | Generate a unique run ID
generateRunId :: IO RunId
generateRunId = do
  now <- getCurrentTime
  let timestamp = formatTime defaultTimeLocale "%Y%m%d%H%M%S%q" now
  pure $ RunId $ "run-" <> T.pack timestamp

isToolSuccess :: ToolResult -> Bool
isToolSuccess ToolSuccess {} = True
isToolSuccess ToolFailure {} = False

extractDagSpecArg :: Value -> Maybe (Either Text DagSpec)
extractDagSpecArg (Object obj) =
  case KeyMap.lookup (Key.fromText "dag_spec") obj of
    Nothing -> Nothing
    Just (String dagSpecText) ->
      Just $
        case decodeDagBytes (TE.encodeUtf8 dagSpecText) of
          Left parseError -> Left ("Invalid DAG spec: " <> T.pack parseError)
          Right dagSpec -> Right dagSpec
    Just dagSpecValue ->
      Just $
        case fromJSON dagSpecValue of
          Success dagSpec -> Right dagSpec
          Error err -> Left ("dag_spec must be a string or DAG object: " <> T.pack err)
extractDagSpecArg _ = Nothing

workflowRunRecordToJson :: WorkflowRunRecord -> Value
workflowRunRecordToJson runRecord =
  object
    [ "runId" .= wrrRunId runRecord,
      "tenantId" .= wrrTenantId runRecord,
      "submittedBy" .= wrrSubmittedBy runRecord,
      "status" .= wrrStatus runRecord,
      "submittedAt" .= wrrSubmittedAt runRecord,
      "completedAt" .= wrrCompletedAt runRecord
    ]

-- | Get required scopes for a tool
toolRequiredScopes :: ToolName -> [Text]
toolRequiredScopes WorkflowSubmit = ["workflow:write"]
toolRequiredScopes WorkflowStatus = ["workflow:read"]
toolRequiredScopes WorkflowCancel = ["workflow:write"]
toolRequiredScopes WorkflowList = ["workflow:read"]
toolRequiredScopes ArtifactGet = ["artifact:read"]
toolRequiredScopes ArtifactDownloadUrl = ["artifact:read"]
toolRequiredScopes ArtifactUploadUrl = ["artifact:write"]
toolRequiredScopes ArtifactHide = ["artifact:manage"]
toolRequiredScopes ArtifactArchive = ["artifact:manage"]
toolRequiredScopes TenantInfo = ["tenant:read"]

-- | Tool definitions

workflowSubmitTool :: ToolDefinition
workflowSubmitTool =
  ToolDefinition
    { tdName = "workflow.submit",
      tdDescription = Just "Submit a DAG workflow for execution",
      tdInputSchema =
        ToolInputSchema
          { tisType = "object",
            tisProperties =
              Just $
                object
                  [ "dag_spec"
                      .= object
                        [ "type" .= ("string" :: Text),
                          "description" .= ("YAML DAG specification" :: Text)
                        ],
                    "priority"
                      .= object
                        [ "type" .= ("string" :: Text),
                          "description" .= ("Execution priority: low, normal, high" :: Text),
                          "enum" .= (["low", "normal", "high"] :: [Text])
                        ]
                  ],
            tisRequired = Just ["dag_spec"]
          }
    }

workflowStatusTool :: ToolDefinition
workflowStatusTool =
  ToolDefinition
    { tdName = "workflow.status",
      tdDescription = Just "Get the status of a workflow run",
      tdInputSchema =
        ToolInputSchema
          { tisType = "object",
            tisProperties =
              Just $
                object
                  [ "run_id"
                      .= object
                        [ "type" .= ("string" :: Text),
                          "description" .= ("The workflow run ID" :: Text)
                        ]
                  ],
            tisRequired = Just ["run_id"]
          }
    }

workflowCancelTool :: ToolDefinition
workflowCancelTool =
  ToolDefinition
    { tdName = "workflow.cancel",
      tdDescription = Just "Cancel a running workflow",
      tdInputSchema =
        ToolInputSchema
          { tisType = "object",
            tisProperties =
              Just $
                object
                  [ "run_id"
                      .= object
                        [ "type" .= ("string" :: Text),
                          "description" .= ("The workflow run ID to cancel" :: Text)
                        ],
                    "reason"
                      .= object
                        [ "type" .= ("string" :: Text),
                          "description" .= ("Reason for cancellation" :: Text)
                        ]
                  ],
            tisRequired = Just ["run_id"]
          }
    }

workflowListTool :: ToolDefinition
workflowListTool =
  ToolDefinition
    { tdName = "workflow.list",
      tdDescription = Just "List workflow runs for the current tenant",
      tdInputSchema =
        ToolInputSchema
          { tisType = "object",
            tisProperties =
              Just $
                object
                  [ "status"
                      .= object
                        [ "type" .= ("string" :: Text),
                          "description" .= ("Filter by status" :: Text),
                          "enum" .= (["running", "completed", "failed", "cancelled"] :: [Text])
                        ],
                    "limit"
                      .= object
                        [ "type" .= ("integer" :: Text),
                          "description" .= ("Maximum number of results" :: Text),
                          "default" .= (100 :: Int)
                        ]
                  ],
            tisRequired = Nothing
          }
    }

artifactGetTool :: ToolDefinition
artifactGetTool =
  ToolDefinition
    { tdName = "artifact.get",
      tdDescription = Just "Get metadata for an artifact",
      tdInputSchema =
        ToolInputSchema
          { tisType = "object",
            tisProperties =
              Just $
                object
                  [ "artifact_id"
                      .= object
                        [ "type" .= ("string" :: Text),
                          "description" .= ("The artifact ID" :: Text)
                        ],
                    "version"
                      .= object
                        [ "type" .= ("integer" :: Text),
                          "description" .= ("Specific version (optional, defaults to latest)" :: Text)
                        ]
                  ],
            tisRequired = Just ["artifact_id"]
          }
    }

artifactDownloadUrlTool :: ToolDefinition
artifactDownloadUrlTool =
  ToolDefinition
    { tdName = "artifact.download_url",
      tdDescription = Just "Generate a presigned download URL for an artifact",
      tdInputSchema =
        ToolInputSchema
          { tisType = "object",
            tisProperties =
              Just $
                object
                  [ "artifact_id"
                      .= object
                        [ "type" .= ("string" :: Text),
                          "description" .= ("The artifact ID" :: Text)
                        ],
                    "version"
                      .= object
                        [ "type" .= ("integer" :: Text),
                          "description" .= ("Specific version (optional)" :: Text)
                        ]
                  ],
            tisRequired = Just ["artifact_id"]
          }
    }

artifactUploadUrlTool :: ToolDefinition
artifactUploadUrlTool =
  ToolDefinition
    { tdName = "artifact.upload_url",
      tdDescription = Just "Generate a presigned upload URL for a new artifact",
      tdInputSchema =
        ToolInputSchema
          { tisType = "object",
            tisProperties =
              Just $
                object
                  [ "content_type"
                      .= object
                        [ "type" .= ("string" :: Text),
                          "description" .= ("MIME content type" :: Text)
                        ],
                    "file_name"
                      .= object
                        [ "type" .= ("string" :: Text),
                          "description" .= ("Original file name" :: Text)
                        ],
                    "file_size"
                      .= object
                        [ "type" .= ("integer" :: Text),
                          "description" .= ("File size in bytes" :: Text)
                        ]
                  ],
            tisRequired = Just ["content_type"]
          }
    }

artifactHideTool :: ToolDefinition
artifactHideTool =
  ToolDefinition
    { tdName = "artifact.hide",
      tdDescription = Just "Hide an artifact from default listings (still accessible by ID)",
      tdInputSchema =
        ToolInputSchema
          { tisType = "object",
            tisProperties =
              Just $
                object
                  [ "artifact_id"
                      .= object
                        [ "type" .= ("string" :: Text),
                          "description" .= ("The artifact ID" :: Text)
                        ],
                    "reason"
                      .= object
                        [ "type" .= ("string" :: Text),
                          "description" .= ("Reason for hiding" :: Text)
                        ]
                  ],
            tisRequired = Just ["artifact_id"]
          }
    }

artifactArchiveTool :: ToolDefinition
artifactArchiveTool =
  ToolDefinition
    { tdName = "artifact.archive",
      tdDescription = Just "Archive an artifact (read-only, may be moved to cold storage)",
      tdInputSchema =
        ToolInputSchema
          { tisType = "object",
            tisProperties =
              Just $
                object
                  [ "artifact_id"
                      .= object
                        [ "type" .= ("string" :: Text),
                          "description" .= ("The artifact ID" :: Text)
                        ],
                    "reason"
                      .= object
                        [ "type" .= ("string" :: Text),
                          "description" .= ("Reason for archival" :: Text)
                        ]
                  ],
            tisRequired = Just ["artifact_id"]
          }
    }

tenantInfoTool :: ToolDefinition
tenantInfoTool =
  ToolDefinition
    { tdName = "tenant.info",
      tdDescription = Just "Get information about the current tenant",
      tdInputSchema =
        ToolInputSchema
          { tisType = "object",
            tisProperties = Nothing,
            tisRequired = Nothing
          }
    }

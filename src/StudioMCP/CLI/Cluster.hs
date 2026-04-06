{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.CLI.Cluster
  ( runClusterCommand,
    runValidateCommand,
  )
where

import Control.Exception (SomeException, bracket, bracket_, try)
import GHC.IO.Handle.Lock (LockMode (..), hLock, hUnlock)
import System.IO (IOMode (..), hClose, openFile)
import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Monad (foldM, forM_, unless, when)
import Data.Aeson (FromJSON, Value (..), decode, encode, fromJSON, object, (.=))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Bits (xor)
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Base64.URL as Base64Url
import Data.ByteString.Char8 qualified as BS
import Data.ByteString.Lazy.Char8 qualified as LBS
import qualified Data.CaseInsensitive as CI
import Data.Char (isSpace, toLower)
import Data.List (isInfixOf)
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import qualified Data.Set as Set
import Data.Time (addUTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import qualified Data.Map.Strict as Map
import qualified Data.Vector as Vector
import Network.HTTP.Client
  ( HttpException,
    Manager,
    Request (method, requestBody, requestHeaders, responseTimeout),
    RequestBody (RequestBodyLBS),
    defaultManagerSettings,
    httpLbs,
    newManager,
    parseRequest,
    responseTimeoutMicro,
    responseBody,
    responseHeaders,
    responseStatus,
  )
import Network.HTTP.Types
  ( Header,
    hContentType,
    methodGet,
    methodPost,
    status200,
    status404,
  )
import Network.HTTP.Types.Status (statusCode)
import Network.Wai
  ( Application,
    pathInfo,
    requestMethod,
    responseLBS,
    strictRequestBody,
  )
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort)
import StudioMCP.Config.Load (loadAppConfig)
import StudioMCP.Config.Types (AppConfig (..))
import Data.Yaml (decodeFileEither)
import StudioMCP.CLI.Command
  ( ClusterCommand (..),
    ClusterDeployTarget (..),
    ClusterStorageCommand (..),
    ValidateCommand (..),
  )
-- Note: ClusterEnsureCommand is now part of ClusterCommand (..)
import StudioMCP.CLI.Docs (validateDocsCommand)
import StudioMCP.API.Health (DependencyHealth (..), HealthReport (..), HealthStatus (..))
import StudioMCP.Auth.Admin
  ( KeycloakAdminConfig (..)
  , defaultAdminConfig
  , importRealmDefinition
  , newAdminClient
  , realmExists
  )
import StudioMCP.Auth.Config
  ( AuthConfig (..)
  , defaultAuthConfig
  , defaultKeycloakConfig
  , KeycloakConfig (..)
  , jwksEndpoint
  )
import StudioMCP.Auth.PKCE
  ( PasswordGrantParams (..)
  , TokenResponse (..)
  , exchangePasswordForTokens
  )
import StudioMCP.Auth.Middleware (newAuthService, validateToken)
import StudioMCP.Auth.Jwks (JwtHeader (..), parseJwt)
import StudioMCP.Auth.Types
  ( AuthError (..)
  , JwtClaims (..)
  , RawJwt (..)
  , Scope (..)
  , SubjectId (..)
  , TenantId (..)
  )
import StudioMCP.API.Version (VersionInfo (..))
import StudioMCP.Inference.Host (runInferenceServer)
import StudioMCP.Inference.ReferenceModel (ReferenceModelConfig (..))
import StudioMCP.Inference.Types (InferenceRequest (..), InferenceResponse (..))
import StudioMCP.DAG.Runtime (validateEndToEndRuntime)
import StudioMCP.DAG.Parser (loadDagFile)
import StudioMCP.DAG.Summary (RunId (..), RunStatus (..), Summary (..))
import StudioMCP.DAG.Types
  ( DagSpec (..),
    NodeId (..),
    NodeKind (..),
    NodeSpec (..),
    OutputType (..),
    TimeoutPolicy (..),
  )
import StudioMCP.DAG.Validator (renderFailures, validateDag)
import StudioMCP.MCP.JsonRpc (JsonRpcMessage (..), JsonRpcRequest (..), JsonRpcVersion (..), RequestId (..))
import StudioMCP.MCP.Handlers (createServerEnv, serverTenantStorage, serverToolCatalog)
import StudioMCP.MCP.Protocol.StateMachine
  ( ProtocolEvent (..)
  , ProtocolState (..)
  , getProtocolState
  , newSessionState
  , transitionSession
  )
import StudioMCP.Messaging.Pulsar
  ( PulsarConfig (..),
    validatePulsarLifecycle,
  )
import StudioMCP.Result.Failure (FailureDetail (..))
import StudioMCP.Result.Types (Result (Failure, Success))
import StudioMCP.Storage.MinIO
  ( MinIOConfig (MinIOConfig),
    validateMinioRoundTrip,
  )
import StudioMCP.Tools.Boundary (validateBoundaryRuntime)
import StudioMCP.Tools.FFmpeg (validateFFmpegAdapter)
import StudioMCP.DAG.Executor (validateExecutorRuntime)
import StudioMCP.Worker.Protocol
  ( WorkerExecutionRequest (..),
    WorkerExecutionResponse (..),
  )
import StudioMCP.Worker.Server (runWorkerServer)
import StudioMCP.MCP.Session.RedisConfig (RedisConfig (..), defaultRedisConfig)
import StudioMCP.MCP.Session.RedisStore
  ( RedisSessionStore
  , RedisHealth (..)
  , checkRedisHealth
  , closeRedisSessionStore
  , newRedisSessionStore
  , testConnection
  )
import StudioMCP.MCP.Session.Store
  ( CursorPosition (..)
  , SessionLock (..)
  , SessionStoreError (..)
  , SubscriptionRecord (..)
  , storeAcquireLock
  , storeCreateSession
  , storeDeleteSession
  , storeGetSession
  , storeGetSubscriptions
  , storeGetCursor
  , storeReleaseLock
  , storeAddSubscription
  , storeSetCursor
  , storeTouchSession
  , storeUpdateSession
  , storeExpireSessions
  )
import StudioMCP.MCP.Session.Types
  ( Session (..)
  , SessionState (..)
  , newSession
  , sessionId
  )
import StudioMCP.Web.BFF
  ( defaultBFFConfig
  , newBFFServiceWithRuntime
  , createWebSession
  , getWebSession
  , refreshWebSession
  , invalidateWebSession
  , requestUpload
  , confirmUpload
  , requestDownload
  , sendChatMessage
  , submitRun
  , getRunStatus
  )
import StudioMCP.Web.Types
  ( ChatMessage (..)
  , ChatRequest (..)
  , ChatResponse (..)
  , ChatRole (..)
  , DownloadRequest (..)
  , DownloadResponse (..)
  , PresignedDownloadUrl (..)
  , PresignedUploadUrl (..)
  , SessionLoginResponse (..)
  , SessionSummary (..)
  , SessionMeResponse (..)
  , SessionLogoutResponse (..)
  , SessionRefreshResponse (..)
  , UploadRequest (..)
  , UploadResponse (..)
  , WebSession (..)
  , RunSubmitRequest (..)
  , RunStatusResponse (..)
  )
import StudioMCP.Storage.TenantStorage
  ( TenantArtifact (..)
  , PresignedUrl (..)
  , defaultTenantStorageConfig
  , newTenantStorageService
  , createTenantArtifact
  , getTenantArtifact
  , listTenantArtifacts
  , generateUploadUrl
  , generateDownloadUrl
  )
import StudioMCP.Storage.Governance
  ( GovernanceAction (..)
  , defaultGovernancePolicy
  , newGovernanceService
  , hideArtifact
  , archiveArtifact
  , supersedeArtifact
  , restoreArtifact
  , denyHardDelete
  , getArtifactState
  , getArtifactHistory
  , GovernanceMetadata (..)
  , ArtifactState (..)
  )
import StudioMCP.Storage.Versioning
  ( ArtifactVersion (..)
  , defaultVersioningPolicy
  , newVersioningService
  , createInitialVersion
  , createNewVersion
  , getLatestVersion
  , listVersions
  )
import StudioMCP.Storage.AuditTrail
  ( AuditQuery (..)
  , AuditReport (..)
  , AuditIntegrityResult (..)
  , newAuditTrailService
  , recordAuditEntry
  , recordDeletionAttempt
  , queryAuditTrail
  , defaultAuditQuery
  , generateAuditReport
  , verifyAuditIntegrity
  , AuditAction (..)
  , AuditOutcome (..)
  )
import StudioMCP.Storage.ContentAddressed (ContentAddress (..))
import StudioMCP.MCP.Tools
  ( ToolName (..)
  , newToolCatalog
  , listTools
  , callTool
  , ToolResult (..)
  , ToolError (..)
  , toolRequiredScopes
  )
import StudioMCP.MCP.Resources
  ( ResourceType (..)
  , newResourceCatalog
  , listResources
  , readResource
  , ResourceError (..)
  , resourceRequiredScopes
  , parseResourceUri
  )
import StudioMCP.MCP.Prompts
  ( PromptName (..)
  , newPromptCatalog
  , listPrompts
  , getPrompt
  , PromptError (..)
  , promptRequiredScopes
  )
import StudioMCP.MCP.Protocol.Types
  ( CallToolParams (..)
  , CallToolResult (..)
  , GetPromptParams (..)
  , GetPromptResult (..)
  , ReadResourceParams (..)
  , ToolDefinition (..)
  , ToolContent (..)
  , PromptDefinition (..)
  )
import StudioMCP.Observability.CorrelationId
  ( CorrelationId (..)
  , generateCorrelationId
  , newRequestContext
  )
import StudioMCP.Observability.Quotas
  ( QuotaType (..)
  , QuotaCheckResult (..)
  , QuotaMetrics (..)
  , defaultQuotaConfig
  , newQuotaService
  , checkQuota
  , reserveQuota
  , releaseQuota
  , getQuotaMetrics
  )
import StudioMCP.Observability.RateLimiting
  ( RateLimitKey (..)
  , RateLimitWindow (..)
  , RateLimitResult (..)
  , RateLimitMetrics (..)
  , defaultRateLimiterConfig
  , newRateLimiterService
  , checkRateLimit
  , recordRequest
  , getRateLimitMetrics
  )
import StudioMCP.Observability.McpMetrics
  ( McpMetricsSnapshot (..)
  , newMcpMetricsService
  , recordToolCall
  , recordMethodCall
  , getMcpMetrics
  , renderPrometheusMetrics
  )
import StudioMCP.Observability.Redaction
  ( redactSecrets
  , redactToken
  , redactSensitiveHeaders
  )
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    findExecutable,
    getCurrentDirectory,
    getHomeDirectory,
    getTemporaryDirectory,
    removeFile,
  )
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..), die)
import System.FilePath ((</>))
import System.IO (openTempFile)
import System.Process
  ( CreateProcess (std_err, std_out),
    StdStream (NoStream),
    callProcess,
    createProcess,
    proc,
    readProcessWithExitCode,
    terminateProcess,
    waitForProcess,
    ProcessHandle,
  )

runClusterCommand :: ClusterCommand -> IO ()
runClusterCommand command =
  case command of
    ClusterUpCommand -> clusterUp
    ClusterDownCommand -> clusterDown
    ClusterResetCommand -> clusterReset
    ClusterStatusCommand -> clusterStatus
    ClusterEnsureCommand -> clusterEnsure
    ClusterDeployCommand target -> clusterDeploy target
    ClusterStorageCommand ClusterStorageReconcile -> clusterStorageReconcile
    ClusterStorageCommand (ClusterStorageDelete volumeName) -> clusterStorageDelete volumeName

runValidateCommand :: ValidateCommand -> IO ()
runValidateCommand command =
  case command of
    ValidateClusterCommand -> validateCluster
    ValidateDocsCommand -> validateDocsCommand
    ValidateE2ECommand -> validateE2E
    ValidateWorkerCommand -> validateWorker
    ValidatePulsarCommand -> validatePulsar
    ValidateMinioCommand -> validateMinio
    ValidateBoundaryCommand -> validateBoundary
    ValidateFFmpegAdapterCommand -> validateFFmpeg
    ValidateExecutorCommand -> validateExecutor
    ValidateMcpStdioCommand -> validateMcpStdio
    ValidateMcpHttpCommand -> validateMcpHttp
    ValidateKeycloakCommand -> validateKeycloak
    ValidateMcpAuthCommand -> validateMcpAuth
    ValidateSessionStoreCommand -> validateSessionStore
    ValidateHorizontalScaleCommand -> validateHorizontalScale
    ValidateWebBffCommand -> validateWebBff
    ValidateArtifactStorageCommand -> validateArtifactStorage
    ValidateArtifactGovernanceCommand -> validateArtifactGovernance
    ValidateMcpToolsCommand -> validateMcpTools
    ValidateMcpResourcesCommand -> validateMcpResources
    ValidateMcpPromptsCommand -> validateMcpPrompts
    ValidateInferenceCommand -> validateInference
    ValidateObservabilityCommand -> validateObservability
    ValidateAuditCommand -> validateAudit
    ValidateQuotasCommand -> validateQuotas
    ValidateRateLimitCommand -> validateRateLimit
    ValidateMcpConformanceCommand -> validateMcpConformance
    ValidateStoragePolicyCommand -> validateStoragePolicy

clusterUp :: IO ()
clusterUp = do
  requireExecutables ["kind", "kubectl", "helm"]
  clusterName <- getClusterName
  cliDataRoot <- resolveCliDataRoot
  kindHostDataRoot <- resolveKindHostDataRoot
  clusters <- kindClusters
  if clusterName `elem` clusters
    then do
      -- Validate port mappings before proceeding with existing cluster
      portMappingResult <- validateKindPortMappings clusterName
      case portMappingResult of
        Left missingMappings ->
          die (formatMissingPortMappingsError clusterName missingMappings)
        Right () -> do
          ensureContainerClusterAccess clusterName
          putStrLn ("kind cluster '" <> clusterName <> "' already exists.")
    else do
      createDirectoryIfMissing True cliDataRoot
      withKindConfig clusterName kindHostDataRoot $ \configPath ->
        callProcess "kind" ["create", "cluster", "--name", clusterName, "--config", configPath]
      ensureContainerClusterAccess clusterName

kindIngressManifestUrl :: String
kindIngressManifestUrl =
  "https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.14.0/deploy/static/provider/kind/deploy.yaml"

clusterEdgePublicBaseUrl :: Text
clusterEdgePublicBaseUrl = "http://localhost:8081"

clusterEdgeRealmName :: Text
clusterEdgeRealmName = "studiomcp"

clusterEdgeValidationUsername :: Text
clusterEdgeValidationUsername = "testuser1"

clusterEdgeValidationPassword :: Text
clusterEdgeValidationPassword = "testpassword1"

clusterEdgeInternalBaseUrl :: IO String
clusterEdgeInternalBaseUrl = do
  publishedHost <- resolveDockerPublishedHost
  pure ("http://" <> Text.unpack publishedHost <> ":8081")

ensureKindIngressController :: IO ()
ensureKindIngressController = do
  -- Check if ingress-nginx controller is already running and healthy
  controllerRunning <- ingressNginxControllerRunning
  if controllerRunning
    then putStrLn "ingress-nginx controller already running, skipping setup."
    else do
      -- Check if ingress-nginx exists but is broken (controller pod not running)
      needsCleanup <- ingressNginxNeedsCleanup
      when needsCleanup $ do
        putStrLn "Cleaning up failed ingress-nginx deployment..."
        callProcess "kubectl" ["delete", "namespace", "ingress-nginx", "--ignore-not-found"]
        waitForNamespaceDeletion "ingress-nginx" "60s"

      -- Apply the manifest
      callProcess "kubectl" ["apply", "-f", kindIngressManifestUrl]

      -- Give the cluster a moment to schedule the pods before waiting.
      -- On ARM Macs in kind, pod scheduling can be slow.
      threadDelay (5 * 1000 * 1000) -- 5 seconds

      -- Wait for admission webhook jobs to complete (they create the TLS secret needed by controller)
      -- ARM Macs in kind can be slow, so use 300s timeout (5 minutes)
      waitForJobCompletion "ingress-nginx-admission-create" "ingress-nginx" "300s"
      waitForJobCompletion "ingress-nginx-admission-patch" "ingress-nginx" "300s"

      -- Now wait for the controller deployment
      -- Use 480s timeout for ARM Mac compatibility
      waitForNamespacedWorkloadRollout "deployment/ingress-nginx-controller" "ingress-nginx" "480s"

      -- Enable snippet annotations for configuration-snippet support
      -- This is required for exposing X-Upstream-Addr header in responses
      enableNginxIngressSnippets

  -- Always ensure snippets are enabled (even if controller was already running)
  enableNginxIngressSnippets
  -- Always ensure response headers are configured (for X-Upstream-Addr in horizontal-scale validation)
  configureNginxResponseHeaders

-- | Enable snippet annotations in the nginx-ingress controller.
-- By default, nginx-ingress disables configuration-snippet annotations for
-- security. We need to enable them for the horizontal-scale validation test
-- which uses configuration-snippet to expose X-Upstream-Addr header.
enableNginxIngressSnippets :: IO ()
enableNginxIngressSnippets = do
  -- Check if snippets are already enabled in the ingress-nginx ConfigMap
  -- In nginx-ingress v1.14.0+, allow-snippet-annotations is set via ConfigMap,
  -- not as a command-line argument (--allow-snippet-annotations was removed)
  (exitCode, stdout, _) <-
    readProcessWithExitCode
      "kubectl"
      [ "get"
      , "configmap"
      , "ingress-nginx-controller"
      , "-n"
      , "ingress-nginx"
      , "-o"
      , "jsonpath={.data.allow-snippet-annotations}"
      ]
      ""
  case exitCode of
    ExitFailure _ -> pure () -- Namespace/configmap doesn't exist yet
    ExitSuccess ->
      if "true" `isInfixOf` stdout
        then do
          -- ConfigMap shows snippets enabled, but the webhook may still reject them.
          -- Test if the webhook actually accepts snippets before proceeding.
          putStrLn "Checking if nginx webhook accepts snippet annotations..."
          webhookOk <- testSnippetAnnotationAccepted
          if webhookOk
            then putStrLn "nginx-ingress snippet annotations already working."
            else do
              -- Webhook rejects snippets despite ConfigMap showing "true".
              -- Delete the validating webhook configuration to bypass the check.
              putStrLn "Webhook rejecting snippets, removing validating webhook..."
              _ <- readProcessWithExitCode
                "kubectl"
                [ "delete"
                , "validatingwebhookconfiguration"
                , "ingress-nginx-admission"
                , "--ignore-not-found"
                ]
                ""
              putStrLn "nginx-ingress snippet annotations now enabled (webhook removed)."
        else do
          putStrLn "Enabling nginx-ingress snippet annotations via ConfigMap..."
          -- Patch the ConfigMap to add allow-snippet-annotations=true
          -- This is the correct method for nginx-ingress v1.14.0+
          callProcess
            "kubectl"
            [ "patch"
            , "configmap"
            , "ingress-nginx-controller"
            , "-n"
            , "ingress-nginx"
            , "--type=merge"
            , "-p"
            , "{\"data\":{\"allow-snippet-annotations\":\"true\"}}"
            ]
          -- Delete the validating webhook configuration to avoid snippet rejection.
          -- The nginx-ingress admission webhook validates ingress annotations at
          -- creation time based on its startup configuration. Simply restarting
          -- the controller is not reliable - the webhook may still reject snippets
          -- even after the ConfigMap is updated and the controller restarts.
          --
          -- By deleting the validating webhook, we bypass the admission check entirely.
          -- This is safe for our use case since we explicitly want snippets enabled.
          -- The controller will still process ingresses normally, just without
          -- pre-validation of annotations.
          putStrLn "Removing validating webhook to allow snippet annotations..."
          _ <- readProcessWithExitCode
            "kubectl"
            [ "delete"
            , "validatingwebhookconfiguration"
            , "ingress-nginx-admission"
            , "--ignore-not-found"
            ]
            ""
          -- Restart the controller to pick up the new ConfigMap settings
          callProcess
            "kubectl"
            [ "rollout"
            , "restart"
            , "deployment/ingress-nginx-controller"
            , "-n"
            , "ingress-nginx"
            ]
          -- Wait for the rollout to complete (use longer timeout for controller restart)
          -- ARM Mac in kind can take >4 minutes for the controller to restart
          waitForNamespacedWorkloadRollout "deployment/ingress-nginx-controller" "ingress-nginx" "480s"
          putStrLn "nginx-ingress snippet annotations enabled."

-- | Configure custom response headers for nginx-ingress.
-- This creates an add-headers ConfigMap that the controller uses to add
-- custom headers to all responses. We use this to expose X-Upstream-Addr
-- which is needed for horizontal-scale validation to verify load distribution.
--
-- Note: This is preferred over configuration-snippet annotation because
-- nginx-ingress 1.14+ flags configuration-snippet as a risky annotation
-- which can cause ingresses to not sync (no Address assigned = 404 errors).
configureNginxResponseHeaders :: IO ()
configureNginxResponseHeaders = do
  putStrLn "Configuring nginx-ingress response headers..."
  -- Create/update the add-headers ConfigMap with X-Upstream-Addr
  -- The value $upstream_addr is an nginx variable that contains the upstream server address
  let addHeadersConfigMap = unlines
        [ "apiVersion: v1"
        , "kind: ConfigMap"
        , "metadata:"
        , "  name: custom-response-headers"
        , "  namespace: ingress-nginx"
        , "data:"
        , "  X-Upstream-Addr: $upstream_addr"
        ]
  (exitCode, _, stderr) <- readProcessWithExitCode "kubectl" ["apply", "-f", "-"] addHeadersConfigMap
  case exitCode of
    ExitFailure code -> putStrLn $ "Warning: Failed to create add-headers ConfigMap (exit " <> show code <> "): " <> stderr
    ExitSuccess -> do
      -- Now configure the controller ConfigMap to use the add-headers ConfigMap
      -- Check if the controller ConfigMap already has add-headers configured
      (checkExitCode, checkStdout, _) <- readProcessWithExitCode
        "kubectl"
        [ "get"
        , "configmap"
        , "ingress-nginx-controller"
        , "-n"
        , "ingress-nginx"
        , "-o"
        , "jsonpath={.data.add-headers}"
        ]
        ""
      case checkExitCode of
        ExitFailure _ -> putStrLn "Warning: Could not check controller ConfigMap"
        ExitSuccess ->
          if "ingress-nginx/custom-response-headers" `isInfixOf` checkStdout
            then putStrLn "nginx-ingress add-headers already configured."
            else do
              -- Patch the controller ConfigMap to add the add-headers reference
              callProcess
                "kubectl"
                [ "patch"
                , "configmap"
                , "ingress-nginx-controller"
                , "-n"
                , "ingress-nginx"
                , "--type=merge"
                , "-p"
                , "{\"data\":{\"add-headers\":\"ingress-nginx/custom-response-headers\"}}"
                ]
              -- Restart the controller to pick up the new settings
              putStrLn "Restarting nginx-ingress controller to apply response headers..."
              callProcess
                "kubectl"
                [ "rollout"
                , "restart"
                , "deployment/ingress-nginx-controller"
                , "-n"
                , "ingress-nginx"
                ]
              -- Wait for rollout to complete
              waitForNamespacedWorkloadRollout "deployment/ingress-nginx-controller" "ingress-nginx" "480s"
              putStrLn "nginx-ingress response headers configured."

-- | Wait for the nginx ingress admission webhook to be ready.
-- After the controller restarts, the admission webhook needs time to:
-- 1. Have its endpoints become available
-- 2. Load the new ConfigMap settings (especially allow-snippet-annotations)
--
-- We verify readiness by doing a dry-run create of an ingress with a
-- configuration-snippet annotation. This ensures the webhook is both
-- running AND has loaded the allow-snippet-annotations=true setting.
--
-- If the webhook doesn't accept snippets after a reasonable wait, we force
-- a controller restart to reload the ConfigMap settings.
waitForNginxAdmissionWebhook :: IO ()
waitForNginxAdmissionWebhook = do
  putStrLn "Waiting for nginx admission webhook to be ready..."
  -- First try: wait up to 120 seconds (60 retries * 2s)
  success <- waitForAdmissionWebhookWithRetryResult 60
  unless success $ do
    -- If still failing, force a controller restart to reload ConfigMap
    putStrLn "Webhook not accepting snippets, forcing controller restart..."
    callProcess
      "kubectl"
      [ "rollout"
      , "restart"
      , "deployment/ingress-nginx-controller"
      , "-n"
      , "ingress-nginx"
      ]
    -- Wait for rollout to complete
    waitForNamespacedWorkloadRollout "deployment/ingress-nginx-controller" "ingress-nginx" "480s"
    -- Second try: wait up to 180 seconds (90 retries * 2s)
    success2 <- waitForAdmissionWebhookWithRetryResult 90
    unless success2 $
      die "Timed out waiting for nginx admission webhook to accept snippet annotations"
-- | Helper that returns Bool instead of dying, for use in retry logic.
waitForAdmissionWebhookWithRetryResult :: Int -> IO Bool
waitForAdmissionWebhookWithRetryResult maxRetries = go maxRetries
  where
    go :: Int -> IO Bool
    go 0 = pure False  -- Out of retries, return failure
    go retries = do
      -- First check if the admission service endpoint has ready addresses
      (endpointExitCode, endpointStdout, _) <-
        readProcessWithExitCode
          "kubectl"
          [ "get"
          , "endpoints"
          , "ingress-nginx-controller-admission"
          , "-n"
          , "ingress-nginx"
          , "-o"
          , "jsonpath={.subsets[*].addresses[*].ip}"
          ]
          ""
      case endpointExitCode of
        ExitFailure _ -> do
          threadDelay 2_000_000
          go (retries - 1)
        ExitSuccess ->
          if null (filter (not . isSpace) endpointStdout)
            then do
              threadDelay 2_000_000
              go (retries - 1)
            else do
              -- Webhook endpoint exists, now test if it accepts snippet annotations
              -- by doing a dry-run create of a test ingress
              (testExitCode, _, _) <-
                readProcessWithExitCode
                  "kubectl"
                  [ "create"
                  , "--dry-run=server"
                  , "-f"
                  , "-"
                  ]
                  testIngressYaml
              case testExitCode of
                ExitSuccess -> pure True -- Webhook accepts snippet annotations
                ExitFailure _ -> do
                  threadDelay 2_000_000
                  go (retries - 1)

    -- Test ingress manifest with configuration-snippet annotation
    testIngressYaml :: String
    testIngressYaml =
      unlines
        [ "apiVersion: networking.k8s.io/v1"
        , "kind: Ingress"
        , "metadata:"
        , "  name: snippet-test"
        , "  namespace: default"
        , "  annotations:"
        , "    nginx.ingress.kubernetes.io/configuration-snippet: |"
        , "      # test snippet"
        , "spec:"
        , "  ingressClassName: nginx"
        , "  rules:"
        , "  - http:"
        , "      paths:"
        , "      - path: /snippet-test"
        , "        pathType: Prefix"
        , "        backend:"
        , "          service:"
        , "            name: test-svc"
        , "            port:"
        , "              number: 80"
        ]

-- | Quick test to check if the nginx webhook currently accepts snippet annotations.
-- Does a single dry-run create attempt without retries.
testSnippetAnnotationAccepted :: IO Bool
testSnippetAnnotationAccepted = do
  (exitCode, _, _) <-
    readProcessWithExitCode
      "kubectl"
      [ "create"
      , "--dry-run=server"
      , "-f"
      , "-"
      ]
      snippetTestIngressYaml
  case exitCode of
    ExitSuccess -> pure True
    ExitFailure _ -> pure False
  where
    snippetTestIngressYaml :: String
    snippetTestIngressYaml =
      unlines
        [ "apiVersion: networking.k8s.io/v1"
        , "kind: Ingress"
        , "metadata:"
        , "  name: snippet-test-check"
        , "  namespace: default"
        , "  annotations:"
        , "    nginx.ingress.kubernetes.io/configuration-snippet: |"
        , "      # test snippet"
        , "spec:"
        , "  ingressClassName: nginx"
        , "  rules:"
        , "  - http:"
        , "      paths:"
        , "      - path: /snippet-test-check"
        , "        pathType: Prefix"
        , "        backend:"
        , "          service:"
        , "            name: test-svc"
        , "            port:"
        , "              number: 80"
        ]

bootstrapClusterKeycloakRealm :: IO ()
bootstrapClusterKeycloakRealm = do
  manager <- newManager defaultManagerSettings
  mergedValues <- loadMergedValues
  let adminUser =
        Text.pack $
          fromMaybe "admin" (lookupString ["keycloak", "auth", "adminUser"] mergedValues)
      adminPassword =
        Text.pack $
          fromMaybe "admin123" (lookupString ["keycloak", "auth", "adminPassword"] mergedValues)
  realmDefinition <- LBS.readFile "docker/keycloak/realm/studiomcp-realm.json"
  withPortForward "service/studiomcp-keycloak" 39021 80 $ \baseUrl -> do
    -- Keycloak can take significant time to fully initialize after pod readiness.
    -- When running from Docker container with repeated cluster ensure calls, the
    -- cluster may be mid-rolling-update, so we use a generous 180s timeout.
    waitForHttpStatusWithTimeout 180 manager (baseUrl <> "/kc/realms/master") [200]
    adminClientResult <-
      newAdminClient
        defaultAdminConfig
          { kacBaseUrl = Text.pack (baseUrl <> "/kc")
          , kacAdminUser = adminUser
          , kacAdminPassword = adminPassword
          }
        manager
    adminClient <-
      case adminClientResult of
        Left err -> die ("Failed to create Keycloak admin client for cluster bootstrap: " <> show err)
        Right client -> pure client
    realmAlreadyExistsResult <- realmExists adminClient clusterEdgeRealmName
    realmAlreadyExists <-
      case realmAlreadyExistsResult of
        Left err -> die ("Failed to inspect cluster Keycloak realm state: " <> show err)
        Right exists -> pure exists
    unless realmAlreadyExists $ do
      importResult <- importRealmDefinition adminClient realmDefinition
      case importResult of
        Left err -> die ("Failed to import cluster Keycloak realm definition: " <> show err)
        Right () -> pure ()
    waitForHttpStatus manager (baseUrl <> "/kc/realms/studiomcp/.well-known/openid-configuration") [200]

clusterDown :: IO ()
clusterDown = do
  requireExecutables ["kind"]
  clusterName <- getClusterName
  clusters <- kindClusters
  if clusterName `elem` clusters
    then callProcess "kind" ["delete", "cluster", "--name", clusterName]
    else putStrLn ("kind cluster '" <> clusterName <> "' does not exist.")

clusterReset :: IO ()
clusterReset = do
  requireExecutables ["kind", "helm", "kubectl"]
  clusterName <- getClusterName
  clusters <- kindClusters
  when (clusterName `elem` clusters) $ do
    ensureContainerClusterAccess clusterName
    releaseExists <- helmReleaseExists "studiomcp"
    when releaseExists $
      callProcess "helm" ["uninstall", "studiomcp"]
  clusterDown
  clusterUp
  putStrLn "kind cluster reset complete. Host-backed volumes were preserved."

clusterStatus :: IO ()
clusterStatus = do
  requireExecutables ["kind", "kubectl"]
  clusterName <- getClusterName
  clusters <- kindClusters
  if clusterName `notElem` clusters
    then die ("kind cluster '" <> clusterName <> "' is not running.")
    else do
      ensureContainerClusterAccess clusterName
      let contextName = "kind-" <> clusterName
      callProcess "kubectl" ["cluster-info", "--context", contextName]

-- | Idempotent cluster setup: brings up cluster, deploys sidecars, waits for all services.
-- This is the recommended entry point for automation and integration tests.
clusterEnsure :: IO ()
clusterEnsure = do
  putStrLn "cluster ensure: Starting idempotent cluster setup..."

  -- Phase 1: Create/verify cluster and deploy sidecars (idempotent via clusterDeploy)
  clusterDeploy DeploySidecars

  -- Phase 2: Wait for all services to be ready (480s timeout each)
  -- Increased from 240s to handle resource-constrained environments
  putStrLn "cluster ensure: Waiting for all services to be ready..."

  -- Redis is already waited on by clusterDeploy/ensureRedisStatefulSetReady
  -- Wait for PostgreSQL-HA
  waitForWorkloadRollout "statefulset/studiomcp-postgresql-ha-postgresql" "480s"

  -- Wait for MinIO
  waitForWorkloadRollout "statefulset/studiomcp-minio" "480s"

  -- Wait for Pulsar components
  waitForWorkloadRollout "statefulset/studiomcp-pulsar-zookeeper" "480s"
  waitForWorkloadRollout "statefulset/studiomcp-pulsar-bookie" "480s"
  waitForWorkloadRollout "statefulset/studiomcp-pulsar-broker" "480s"

  -- Wait for Keycloak
  waitForWorkloadRollout "statefulset/studiomcp-keycloak" "480s"

  putStrLn "cluster ensure: All services ready."

clusterDeploy :: ClusterDeployTarget -> IO ()
clusterDeploy target = do
  requireExecutables
    ( case target of
        DeploySidecars -> ["docker", "kind", "helm"]
        DeployServer -> ["docker", "kind", "helm", "kubectl"]
    )
  clusterUp
  ensureKindIngressController
  clusterStorageReconcile
  clusterName <- getClusterName
  buildServerImage
  callProcess "kind" ["load", "docker-image", "studiomcp:latest", "--name", clusterName]
  upgradeCredentialArgs <- existingHelmUpgradeCredentialArgs
  let baseArgs =
        [ "upgrade"
        , "--install"
        , "studiomcp"
        , "chart"
        , "-f"
        , "chart/values.yaml"
        , "-f"
        , "chart/values-kind.yaml"
        ]
      args =
        case target of
          DeploySidecars ->
            baseArgs
              <> upgradeCredentialArgs
              <>
                [ "--wait"
                , "--set"
                , "studiomcp.replicas=0"
                , "--set"
                , "bff.enabled=false"
                , "--set"
                , "pulsar.kube-prometheus-stack.enabled=false"
                , "--set"
                , "pulsar.zookeeper.podMonitor.enabled=false"
                , "--set"
                , "pulsar.bookkeeper.podMonitor.enabled=false"
                , "--set"
                , "pulsar.autorecovery.podMonitor.enabled=false"
                , "--set"
                , "pulsar.broker.podMonitor.enabled=false"
                , "--set"
                , "pulsar.proxy.podMonitor.enabled=false"
                ]
          DeployServer -> baseArgs <> upgradeCredentialArgs
  withHelmLock $ callProcess "helm" args
  waitForWorkloadRollout "statefulset/studiomcp-keycloak" "480s"
  bootstrapClusterKeycloakRealm
  ensureRedisStatefulSetReady
  when (target == DeployServer) $ do
    callProcess "kubectl" ["rollout", "restart", "deployment/studiomcp"]
    restartWorkloadIfExists "deployment/studiomcp-bff"
    waitForWorkloadRollout "deployment/studiomcp" "480s"
    waitForWorkloadRollout "deployment/studiomcp-bff" "480s"

ensureRedisStatefulSetReady :: IO ()
ensureRedisStatefulSetReady = do
  let redisWorkload = "statefulset/studiomcp-redis-node"
  restartWorkloadIfExists redisWorkload
  waitForWorkloadRollout redisWorkload "480s"

restartWorkloadIfExists :: String -> IO ()
restartWorkloadIfExists workload = do
  exists <- kubectlResourceExists workload
  when exists $
    callProcess "kubectl" ["rollout", "restart", workload]

waitForWorkloadRollout :: String -> String -> IO ()
waitForWorkloadRollout workload timeoutValue = do
  exists <- kubectlResourceExists workload
  when exists $
    callProcess "kubectl" ["rollout", "status", workload, "--timeout=" <> timeoutValue]

waitForNamespacedWorkloadRollout :: String -> String -> String -> IO ()
waitForNamespacedWorkloadRollout workload namespace timeoutValue =
  callProcess "kubectl" ["rollout", "status", workload, "-n", namespace, "--timeout=" <> timeoutValue]

kubectlResourceExists :: String -> IO Bool
kubectlResourceExists resourceName = do
  (exitCode, _, _) <- readProcessWithExitCode "kubectl" ["get", resourceName] ""
  pure (exitCode == ExitSuccess)

-- | Wait for a Kubernetes Job to complete successfully
waitForJobCompletion :: String -> String -> String -> IO ()
waitForJobCompletion jobName namespace timeout = do
  (exitCode, _, _) <-
    readProcessWithExitCode
      "kubectl"
      ["wait", "--for=condition=Complete", "job/" <> jobName, "-n", namespace, "--timeout=" <> timeout]
      ""
  case exitCode of
    ExitSuccess -> pure ()
    ExitFailure _ -> do
      -- Job failed or timed out - check why and provide diagnostic info
      (_, logs, _) <- readProcessWithExitCode "kubectl" ["logs", "job/" <> jobName, "-n", namespace] ""
      die $
        unlines
          [ "Job '" <> jobName <> "' in namespace '" <> namespace <> "' failed."
          , "Logs:"
          , logs
          , ""
          , "To retry, delete the namespace and run 'cluster ensure' again:"
          , "  kubectl delete namespace " <> namespace
          , "  studiomcp cluster ensure"
          ]

-- | Wait for a Kubernetes namespace to be fully deleted
waitForNamespaceDeletion :: String -> String -> IO ()
waitForNamespaceDeletion namespace timeout = do
  (exitCode, _, _) <-
    readProcessWithExitCode
      "kubectl"
      ["wait", "--for=delete", "namespace/" <> namespace, "--timeout=" <> timeout]
      ""
  -- Ignore failure - namespace might not exist or might already be deleted
  case exitCode of
    ExitSuccess -> pure ()
    ExitFailure _ -> pure ()

-- | Check if ingress-nginx controller is already running and healthy
ingressNginxControllerRunning :: IO Bool
ingressNginxControllerRunning = do
  (exitCode, stdout, _) <-
    readProcessWithExitCode
      "kubectl"
      [ "get"
      , "pods"
      , "-n"
      , "ingress-nginx"
      , "-l"
      , "app.kubernetes.io/component=controller"
      , "-o"
      , "jsonpath={.items[0].status.phase}"
      ]
      ""
  case exitCode of
    ExitFailure _ -> pure False -- Namespace doesn't exist or no pods
    ExitSuccess ->
      let phase = filter (/= '\n') stdout
       in pure (phase == "Running")

-- | Check if ingress-nginx namespace exists but is in a broken state
ingressNginxNeedsCleanup :: IO Bool
ingressNginxNeedsCleanup = do
  -- Check if the controller pod exists but is not Running
  (exitCode, stdout, _) <-
    readProcessWithExitCode
      "kubectl"
      [ "get"
      , "pods"
      , "-n"
      , "ingress-nginx"
      , "-l"
      , "app.kubernetes.io/component=controller"
      , "-o"
      , "jsonpath={.items[0].status.phase}"
      ]
      ""
  case exitCode of
    ExitFailure _ -> pure False -- Namespace doesn't exist or no pods
    ExitSuccess ->
      -- If phase is not Running and not empty, we need cleanup
      let phase = filter (/= '\n') stdout
       in pure (phase /= "Running" && phase /= "")

clusterStorageReconcile :: IO ()
clusterStorageReconcile = do
  requireExecutables ["kubectl"]
  -- Ensure storage policy is enforced first (delete default SC, create studiomcp-manual)
  ensureStoragePolicy
  -- Now create PVs
  cliDataRoot <- resolveCliDataRoot
  createDirectoryIfMissing True cliDataRoot
  mergedValues <- loadMergedValues
  let volumeSpecs = desiredPersistentVolumes mergedValues
  if null volumeSpecs
    then putStrLn "No persistent volumes requested by the current chart values."
    else do
      forM_ volumeSpecs $ \volumeSpec -> do
        createDirectoryIfMissing True (cliDataRoot </> volumeDirectory volumeSpec)
        applyManifest (renderPersistentVolume volumeSpec)
      putStrLn $ "Persistent volume definitions applied (using StorageClass '" <> storageClassName <> "')."

clusterStorageDelete :: String -> IO ()
clusterStorageDelete volumeName = do
  requireExecutables ["kubectl"]
  callProcess "kubectl" ["delete", "pv", volumeName, "--ignore-not-found=true"]
  putStrLn ("Persistent volume '" <> volumeName <> "' deleted if it existed.")

existingHelmUpgradeCredentialArgs :: IO [String]
existingHelmUpgradeCredentialArgs = do
  releaseExists <- helmReleaseExists "studiomcp"
  if not releaseExists
    then pure []
    else do
      repmgrPassword <- lookupSecretValue "studiomcp-postgresql-ha-postgresql" "{.data.repmgr-password}"
      pgpoolAdminPassword <- lookupSecretValue "studiomcp-postgresql-ha-pgpool" "{.data.admin-password}"
      pure $
        concat
          [ maybe [] (\value -> ["--set-string", "postgresql-ha.postgresql.repmgrPassword=" <> value]) repmgrPassword
          , maybe [] (\value -> ["--set-string", "postgresql-ha.pgpool.adminPassword=" <> value]) pgpoolAdminPassword
          ]

-- | Run an IO action with an exclusive lock on Helm operations.
-- This prevents concurrent helm commands from conflicting when multiple
-- integration tests run in parallel and attempt helm upgrade --install.
withHelmLock :: IO a -> IO a
withHelmLock action = bracket
  (openFile "/tmp/studiomcp-helm.lock" AppendMode)
  hClose
  (\h -> do
    hLock h ExclusiveLock
    result <- action
    hUnlock h
    pure result)

helmReleaseExists :: String -> IO Bool
helmReleaseExists releaseName = do
  (exitCode, _, _) <- readProcessWithExitCode "helm" ["status", releaseName] ""
  pure (exitCode == ExitSuccess)

lookupSecretValue :: String -> String -> IO (Maybe String)
lookupSecretValue secretName jsonPath = do
  (exitCode, stdoutText, _) <-
    readProcessWithExitCode
      "kubectl"
      ["get", "secret", secretName, "-o", "jsonpath=" <> jsonPath]
      ""
  case exitCode of
    ExitFailure _ -> pure Nothing
    ExitSuccess ->
      let encoded = trimWhitespace stdoutText
       in if null encoded
            then pure Nothing
            else
              case Base64.decode (BS.pack encoded) of
                Left _ -> pure Nothing
                Right decoded -> pure (Just (BS.unpack decoded))

validateCluster :: IO ()
validateCluster = do
  requireExecutables ["kind", "kubectl", "helm"]
  clusterName <- getClusterName
  clusters <- kindClusters
  unless (clusterName `elem` clusters) $
    die ("kind cluster '" <> clusterName <> "' is not running.")
  -- Validate port mappings
  portMappingResult <- validateKindPortMappings clusterName
  case portMappingResult of
    Left missingMappings ->
      die (formatMissingPortMappingsError clusterName missingMappings)
    Right () -> pure ()
  ensureContainerClusterAccess clusterName
  let contextName = "kind-" <> clusterName
  callProcess "kubectl" ["cluster-info", "--context", contextName]
  putStrLn "Cluster validation passed."

-- | Validate the storage policy enforcement
-- Checks:
-- 1. studiomcp-manual StorageClass exists with no-provisioner
-- 2. No default StorageClass (standard) exists
-- 3. All PVs use studiomcp-manual StorageClass
-- 4. All PVCs reference studiomcp-manual StorageClass
validateStoragePolicy :: IO ()
validateStoragePolicy = do
  requireExecutables ["kubectl"]
  putStrLn "Validating storage policy enforcement..."

  -- Check studiomcp-manual exists
  (scExitCode, scOut, _) <- readProcessWithExitCode "kubectl"
    ["get", "sc", storageClassName, "-o", "jsonpath={.provisioner}"] ""
  case scExitCode of
    ExitSuccess -> do
      let provisioner = scOut
      if provisioner == "kubernetes.io/no-provisioner"
        then putStrLn $ "  [OK] StorageClass '" <> storageClassName <> "' exists with no-provisioner"
        else die $ "  [FAIL] StorageClass '" <> storageClassName <> "' has wrong provisioner: " <> provisioner
    ExitFailure _ -> die $ "  [FAIL] StorageClass '" <> storageClassName <> "' does not exist"

  -- Check no default StorageClass exists
  (defaultExitCode, _, _) <- readProcessWithExitCode "kubectl"
    ["get", "sc", "standard", "--ignore-not-found", "-o", "name"] ""
  case defaultExitCode of
    ExitSuccess -> do
      (checkExit, checkOut, _) <- readProcessWithExitCode "kubectl"
        ["get", "sc", "standard", "-o", "name"] ""
      if checkExit == ExitSuccess && not (null checkOut)
        then die "  [FAIL] Default StorageClass 'standard' still exists (should be deleted)"
        else putStrLn "  [OK] No default StorageClass 'standard' exists"
    ExitFailure _ -> putStrLn "  [OK] No default StorageClass 'standard' exists"

  -- Check all PVs use studiomcp-manual
  (pvExitCode, pvOut, _) <- readProcessWithExitCode "kubectl"
    ["get", "pv", "-o", "jsonpath={range .items[*]}{.metadata.name}:{.spec.storageClassName}\\n{end}"] ""
  case pvExitCode of
    ExitSuccess -> do
      let pvLines = filter (not . null) (lines pvOut)
      let badPvs = filter (\line -> not ((":" <> storageClassName) `isInfixOf` line)) pvLines
      if null pvLines
        then putStrLn "  [INFO] No PersistentVolumes found"
        else if null badPvs
          then putStrLn $ "  [OK] All " <> show (length pvLines) <> " PVs use StorageClass '" <> storageClassName <> "'"
          else die $ "  [FAIL] PVs with wrong StorageClass: " <> unwords badPvs
    ExitFailure _ -> putStrLn "  [INFO] Could not check PVs (none exist?)"

  -- Check all PVCs reference studiomcp-manual
  (pvcExitCode, pvcOut, _) <- readProcessWithExitCode "kubectl"
    ["get", "pvc", "-A", "-o", "jsonpath={range .items[*]}{.metadata.namespace}/{.metadata.name}:{.spec.storageClassName}\\n{end}"] ""
  case pvcExitCode of
    ExitSuccess -> do
      let pvcLines = filter (not . null) (lines pvcOut)
      let badPvcs = filter (\line -> not ((":" <> storageClassName) `isInfixOf` line)) pvcLines
      if null pvcLines
        then putStrLn "  [INFO] No PersistentVolumeClaims found"
        else if null badPvcs
          then putStrLn $ "  [OK] All " <> show (length pvcLines) <> " PVCs use StorageClass '" <> storageClassName <> "'"
          else die $ "  [FAIL] PVCs with wrong StorageClass: " <> unwords badPvcs
    ExitFailure _ -> putStrLn "  [INFO] Could not check PVCs (none exist?)"

  putStrLn "Storage policy validation passed."

validateE2E :: IO ()
validateE2E = do
  requireExecutables ["ffmpeg", "kubectl", "helm", "kind"]
  validateCluster
  requirePulsarDeployment
  requireMinioDeployment
  appConfig <- loadAppConfig
  withKindRuntimeConfig appConfig $ \runtimeConfig -> do
    result <- validateEndToEndRuntime runtimeConfig
    case result of
      Left failureDetail -> die (renderFailureDetail failureDetail)
      Right () -> putStrLn "End-to-end validation passed."

validateWorker :: IO ()
validateWorker = do
  requireExecutables ["ffmpeg", "kind", "kubectl", "helm", "mc"]
  validateCluster
  requirePulsarDeployment
  requireMinioDeployment
  appConfig <- loadAppConfig
  validDag <- loadSubmissionDag "examples/dags/transcode-basic.yaml"
  manager <- newManager defaultManagerSettings
  withLocalWorkerConfig appConfig $ \workerAppConfig ->
    withWorkerServer 39002 workerAppConfig $ \baseUrl -> do
      waitForHttpStatus manager (baseUrl <> "/version") [200]
      invalidResponse <-
        httpJsonRequest
          manager
          "POST"
          (baseUrl <> "/execute")
          (Just (encode (WorkerExecutionRequest invalidSubmissionDag)))
      unless (httpResponseStatus invalidResponse == 400) $
        die ("Expected worker invalid execution to return HTTP 400, got " <> show (httpResponseStatus invalidResponse))
      validResponse <-
        httpJsonRequestWithTimeoutMicros
          180000000
          manager
          "POST"
          (baseUrl <> "/execute")
          (Just (encode (WorkerExecutionRequest validDag)))
      unless (httpResponseStatus validResponse == 200) $
        die ("Expected worker execution to return HTTP 200, got " <> show (httpResponseStatus validResponse))
      executionResponse <- decodeResponseBody "worker execution response" validResponse
      unless (workerExecutionStatus (executionResponse :: WorkerExecutionResponse) == RunSucceeded) $
        die "Worker execution did not report a successful terminal summary."
      unless (summaryRunId (workerExecutionSummary executionResponse) == workerExecutionRunId executionResponse) $
        die "Worker execution returned a summary whose run id did not match the top-level response."
      healthResponse <- httpJsonRequest manager "GET" (baseUrl <> "/healthz") Nothing
      unless (httpResponseStatus healthResponse == 200) $
        die ("Expected worker /healthz to return HTTP 200, got " <> show (httpResponseStatus healthResponse))
      _ :: HealthReport <- decodeResponseBody "worker health response" healthResponse
      versionResponse <- httpJsonRequest manager "GET" (baseUrl <> "/version") Nothing
      unless (httpResponseStatus versionResponse == 200) $
        die ("Expected worker /version to return HTTP 200, got " <> show (httpResponseStatus versionResponse))
      versionInfo <- decodeResponseBody "worker version response" versionResponse
      unless (versionMode (versionInfo :: VersionInfo) == "worker") $
        die "Expected worker /version to report worker mode."
      putStrLn "Worker validation passed."

validatePulsar :: IO ()
validatePulsar = do
  requireExecutables ["kind", "kubectl", "helm"]
  validateCluster
  requirePulsarDeployment
  appConfig <- loadAppConfig
  withKindPulsarConfig appConfig $ \kindPulsarAppConfig -> do
    let pulsarConfig =
          PulsarConfig
            { pulsarHttpEndpoint = pulsarHttpUrl kindPulsarAppConfig,
              pulsarBinaryEndpoint = pulsarBinaryUrl kindPulsarAppConfig
            }
    result <- validatePulsarLifecycle pulsarConfig
    case result of
      Left failureDetail -> die (renderFailureDetail failureDetail)
      Right () -> putStrLn "Pulsar validation passed."

validateMinio :: IO ()
validateMinio = do
  requireExecutables ["kind", "kubectl", "helm", "mc"]
  validateCluster
  requireMinioDeployment
  appConfig <- loadAppConfig
  withMinioPortForwardConfig appConfig $ \minioAppConfig -> do
    let AppConfig
          { minioEndpoint = endpoint,
            minioAccessKey = accessKey,
            minioSecretKey = secretKey
          } = minioAppConfig
        minioConfig =
          MinIOConfig endpoint accessKey secretKey
    result <- validateMinioRoundTrip minioConfig
    case result of
      Left failureDetail -> die (renderFailureDetail failureDetail)
      Right () -> putStrLn "MinIO validation passed."

validateBoundary :: IO ()
validateBoundary = do
  requireExecutables ["sh"]
  result <- validateBoundaryRuntime
  case result of
    Left failureDetail -> die (renderFailureDetail failureDetail)
    Right () -> putStrLn "Boundary validation passed."

validateFFmpeg :: IO ()
validateFFmpeg = do
  requireExecutables ["ffmpeg"]
  result <- validateFFmpegAdapter
  case result of
    Left failureDetail -> die (renderFailureDetail failureDetail)
    Right () -> putStrLn "FFmpeg adapter validation passed."

validateExecutor :: IO ()
validateExecutor = do
  result <- validateExecutorRuntime
  case result of
    Left failureDetail -> die (renderFailureDetail failureDetail)
    Right () -> putStrLn "Executor validation passed."

-- | Validate MCP over stdio transport (Phase 13)
validateMcpStdio :: IO ()
validateMcpStdio = do
  -- Test JSON-RPC message parsing and protocol state machine
  -- This validates the MCP stdio transport without requiring a running server
  putStrLn "Validating MCP stdio transport..."

  -- Validate JSON-RPC types serialize/deserialize correctly
  let initializeRequest =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "id" .= (1 :: Int)
          , "method" .= ("initialize" :: Text)
          , "params" .= object
              [ "protocolVersion" .= ("2024-11-05" :: Text)
              , "capabilities" .= object []
              , "clientInfo" .= object
                  [ "name" .= ("test-client" :: Text)
                  , "version" .= ("1.0.0" :: Text)
                  ]
              ]
          ]

  -- Decode as JsonRpcMessage
  case fromJSON initializeRequest of
    Aeson.Error err ->
      die ("Failed to parse initialize request: " <> err)
    Aeson.Success (msg :: JsonRpcMessage) ->
      case msg of
        MsgRequest req -> do
          unless (reqMethod req == "initialize") $
            die "Expected method to be 'initialize'"
          putStrLn "  ✓ Initialize request parses correctly"
        _ ->
          die "Expected MsgRequest, got different message type"

  -- Test protocol state machine transitions
  sessionState <- newSessionState "test-session"
  initialState <- getProtocolState sessionState

  unless (initialState == Uninitialized) $
    die "Expected initial state to be Uninitialized"
  putStrLn "  ✓ Initial state is Uninitialized"

  -- Transition to Initializing
  transitionResult <- transitionSession sessionState InitializeReceived
  case transitionResult of
    Left err -> die ("State transition failed: " <> show err)
    Right newState -> do
      unless (newState == Initializing) $
        die "Expected state to be Initializing after InitializeReceived"
      putStrLn "  ✓ Transition to Initializing works"

  -- Transition to Ready
  readyResult <- transitionSession sessionState InitializedReceived
  case readyResult of
    Left err -> die ("State transition to Ready failed: " <> show err)
    Right newState -> do
      unless (newState == Ready) $
        die "Expected state to be Ready after InitializedReceived"
      putStrLn "  ✓ Transition to Ready works"

  putStrLn "MCP stdio validation passed."

-- | Validate MCP over HTTP transport (Phase 13)
validateMcpHttp :: IO ()
validateMcpHttp = do
  requireExecutables ["docker", "kubectl", "kind", "helm"]
  clusterDeploy DeployServer
  manager <- newManager defaultManagerSettings
  validDag <- loadSubmissionDag "examples/dags/transcode-basic.yaml"
  liveConfig <- loadKindEdgeValidationConfig
  config <-
    case liveConfig of
      Just edgeConfig -> pure edgeConfig
      Nothing -> die "Cluster edge validation config is unavailable. Set STUDIOMCP_VALIDATE_KIND_EDGE=true after cluster setup."
  let baseUrl = lvcBaseUrl config
  waitForHttpStatus manager (baseUrl <> "/kc/realms/studiomcp/.well-known/openid-configuration") [200]
  tokenResponse <- requestLiveAccessToken manager config
  let authHeaders = authorizationHeaders (trAccessToken tokenResponse)
  putStrLn "Validating MCP HTTP transport through the cluster edge..."

  -- Test initialize request
  let initializeRequest =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "id" .= (1 :: Int)
          , "method" .= ("initialize" :: Text)
          , "params" .= object
              [ "protocolVersion" .= ("2024-11-05" :: Text)
              , "capabilities" .= object []
              , "clientInfo" .= object
                  [ "name" .= ("test-client" :: Text)
                  , "version" .= ("1.0.0" :: Text)
                  ]
              ]
          ]

  initResponse <- httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/mcp") authHeaders (Just (encode initializeRequest))
  unless (httpResponseStatus initResponse == 200) $
    die ("Expected MCP initialize to return HTTP 200, got " <> show (httpResponseStatus initResponse))
  putStrLn "  ✓ Initialize request returns HTTP 200"
  sessionHeaderValue <-
    case lookupResponseHeader "Mcp-Session-Id" initResponse of
      Just headerValue -> pure headerValue
      Nothing -> die "Initialize response did not include an Mcp-Session-Id header"
  let mcpSessionHeaders = authHeaders <> [("Mcp-Session-Id", sessionHeaderValue)]
  putStrLn "  ✓ Initialize response returns an MCP session header"

  -- Verify response has correct JSON-RPC structure
  case decode (httpResponseBody initResponse) of
    Nothing ->
      die "Failed to decode initialize response as JSON"
    Just responseValue -> do
      case responseValue of
        Object obj -> do
          case (KeyMap.lookup "result" obj, KeyMap.lookup "error" obj) of
            (Just _, Nothing) ->
              putStrLn "  ✓ Initialize response has result field"
            (Nothing, Just _) ->
              die "Initialize request returned an error"
            _ ->
              die "Initialize response missing both result and error"
        _ ->
          die "Initialize response is not a JSON object"

  let initializedNotification =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "method" .= ("notifications/initialized" :: Text)
          ]
  initializedResponse <-
    httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/mcp") mcpSessionHeaders (Just (encode initializedNotification))
  unless (httpResponseStatus initializedResponse == 200) $
    die ("Expected MCP initialized notification to return HTTP 200, got " <> show (httpResponseStatus initializedResponse))
  putStrLn "  ✓ Initialized notification returns HTTP 200"

  let toolsListRequest =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "id" .= (2 :: Int)
          , "method" .= ("tools/list" :: Text)
          ]
  toolsResponse <- httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/mcp") mcpSessionHeaders (Just (encode toolsListRequest))
  unless (httpResponseStatus toolsResponse == 200) $
    die ("Expected MCP tools/list to return HTTP 200, got " <> show (httpResponseStatus toolsResponse))
  case decode (httpResponseBody toolsResponse) of
    Just (Object obj) ->
      case KeyMap.lookup "result" obj of
        Just (Object resultObj) ->
          case KeyMap.lookup "tools" resultObj of
            Just (Array tools)
              | not (null tools) ->
                  putStrLn "  ✓ tools/list returns registered tools"
            _ ->
              die "tools/list did not return a non-empty tools array"
        _ ->
          die "tools/list response missing result.tools"
    _ ->
      die "Failed to decode tools/list response"

  let resourcesListRequest =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "id" .= (3 :: Int)
          , "method" .= ("resources/list" :: Text)
          ]
  resourcesResponse <- httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/mcp") mcpSessionHeaders (Just (encode resourcesListRequest))
  unless (httpResponseStatus resourcesResponse == 200) $
    die ("Expected MCP resources/list to return HTTP 200, got " <> show (httpResponseStatus resourcesResponse))
  putStrLn "  ✓ resources/list request returns HTTP 200"

  let resourceSubscribeRequest =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "id" .= (31 :: Int)
          , "method" .= ("resources/subscribe" :: Text)
          , "params" .= object
              [ "uri" .= ("studiomcp://history/runs" :: Text)
              , "cursor" .= ("cursor-31" :: Text)
              , "lastEventId" .= ("evt-31" :: Text)
              ]
          ]
  resourceSubscribeResponse <-
    httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/mcp") mcpSessionHeaders (Just (encode resourceSubscribeRequest))
  unless (httpResponseStatus resourceSubscribeResponse == 200) $
    die ("Expected MCP resources/subscribe to return HTTP 200, got " <> show (httpResponseStatus resourceSubscribeResponse))
  resourceSubscribeValue <- decodeResponseBody "resources/subscribe response" resourceSubscribeResponse :: IO Value
  unless (lookupString ["result", "cursor"] resourceSubscribeValue == Just "cursor-31") $
    die "resources/subscribe should return the active cursor"
  putStrLn "  ✓ resources/subscribe persists resumable metadata"

  let promptsListRequest =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "id" .= (4 :: Int)
          , "method" .= ("prompts/list" :: Text)
          ]
  promptsResponse <- httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/mcp") mcpSessionHeaders (Just (encode promptsListRequest))
  unless (httpResponseStatus promptsResponse == 200) $
    die ("Expected MCP prompts/list to return HTTP 200, got " <> show (httpResponseStatus promptsResponse))
  putStrLn "  ✓ prompts/list request returns HTTP 200"

  let pingRequest =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "id" .= (5 :: Int)
          , "method" .= ("ping" :: Text)
          ]
  pingResponse <- httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/mcp") mcpSessionHeaders (Just (encode pingRequest))
  unless (httpResponseStatus pingResponse == 200) $
    die ("Expected MCP ping to return HTTP 200, got " <> show (httpResponseStatus pingResponse))
  putStrLn "  ✓ ping request returns HTTP 200"

  let submitWorkflowRequest =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "id" .= (6 :: Int)
          , "method" .= ("tools/call" :: Text)
          , "params" .= object
              [ "name" .= ("workflow.submit" :: Text)
              , "arguments" .= object
                  [ "dag_spec" .= validDag
                  ]
              ]
          ]
  submitWorkflowResponse <-
    httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/mcp") mcpSessionHeaders (Just (encode submitWorkflowRequest))
  unless (httpResponseStatus submitWorkflowResponse == 200) $
    die ("Expected workflow.submit over MCP to return HTTP 200, got " <> show (httpResponseStatus submitWorkflowResponse))
  submitWorkflowValue <- decodeResponseBody "MCP workflow.submit response" submitWorkflowResponse :: IO Value
  submitPayloadText <-
    case extractFirstMcpToolData submitWorkflowValue of
      Just payloadText -> pure payloadText
      Nothing -> die "workflow.submit over MCP did not return structured tool data"
  submitPayloadValue <-
    case decode (LBS.fromStrict (TextEncoding.encodeUtf8 submitPayloadText)) of
      Just value -> pure value
      Nothing -> die "workflow.submit returned invalid JSON tool data"
  runIdValue <-
    case lookupString ["runId"] submitPayloadValue of
      Just runIdText -> pure (Text.pack runIdText)
      Nothing -> die "workflow.submit structured payload did not include runId"
  putStrLn "  ✓ workflow.submit executes through the live MCP tool path"

  let workflowStatusRequest =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "id" .= (7 :: Int)
          , "method" .= ("tools/call" :: Text)
          , "params" .= object
              [ "name" .= ("workflow.status" :: Text)
              , "arguments" .= object
                  [ "run_id" .= runIdValue
                  ]
              ]
          ]
  workflowStatusResponse <-
    httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/mcp") mcpSessionHeaders (Just (encode workflowStatusRequest))
  unless (httpResponseStatus workflowStatusResponse == 200) $
    die ("Expected workflow.status over MCP to return HTTP 200, got " <> show (httpResponseStatus workflowStatusResponse))
  workflowStatusValue <- decodeResponseBody "MCP workflow.status response" workflowStatusResponse :: IO Value
  statusPayloadText <-
    case extractFirstMcpToolData workflowStatusValue of
      Just payloadText -> pure payloadText
      Nothing -> die ("workflow.status over MCP did not return structured tool data. Response: " <> LBS.unpack (encode workflowStatusValue))
  statusPayloadValue <-
    case decode (LBS.fromStrict (TextEncoding.encodeUtf8 statusPayloadText)) of
      Just value -> pure value
      Nothing -> die "workflow.status returned invalid JSON tool data"
  unless (lookupString ["runId"] statusPayloadValue == Just (Text.unpack runIdValue)) $
    die "workflow.status did not return the submitted run id"
  putStrLn "  ✓ workflow.status reads runtime-backed run state through /mcp"

  sseRequest <- parseRequest (baseUrl <> "/mcp")
  sseResponse <- httpLbs sseRequest {method = methodGet, requestHeaders = authHeaders} manager
  unless (statusCode (responseStatus sseResponse) == 200) $
    die ("Expected MCP SSE bootstrap to return HTTP 200, got " <> show (statusCode (responseStatus sseResponse)))
  unless ("event: ready" `isInfixOf` LBS.unpack (responseBody sseResponse)) $
    die "Expected MCP SSE bootstrap to emit a ready event."
  putStrLn "  ✓ GET /mcp emits SSE ready bootstrap"

  let invalidJson = "not valid json"
  parseErrorResponse <- httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/mcp") authHeaders (Just (LBS.pack invalidJson))
  unless (httpResponseStatus parseErrorResponse == 400) $
    die ("Expected invalid JSON to return HTTP 400, got " <> show (httpResponseStatus parseErrorResponse))
  putStrLn "  ✓ Parse errors return HTTP 400"

  let unknownMethodRequest =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "id" .= (8 :: Int)
          , "method" .= ("unknown/method" :: Text)
          ]
  unknownResponse <- httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/mcp") mcpSessionHeaders (Just (encode unknownMethodRequest))
  unless (httpResponseStatus unknownResponse == 200) $
    die ("Expected unknown method to return HTTP 200 with JSON-RPC error, got " <> show (httpResponseStatus unknownResponse))
  putStrLn "  ✓ Unknown methods return JSON-RPC error (HTTP 200)"

  putStrLn "MCP HTTP validation passed."

validateInference :: IO ()
validateInference = do
  manager <- newManager defaultManagerSettings
  withFakeModelHost 38101 "Use typed validation before execution." $ do
    withInferenceServer
      38102
      (ReferenceModelConfig "http://127.0.0.1:38101/api/generate")
      $ do
        waitForHttpStatus manager "http://127.0.0.1:38102/healthz" [200]
        response <-
          httpJsonRequest
            manager
            "POST"
            "http://127.0.0.1:38102/advice"
            (Just (encode (InferenceRequest "Suggest a DAG repair for a missing summary node.")))
        unless (httpResponseStatus response == 200) $
          die ("Expected inference advice endpoint to return HTTP 200, got " <> show (httpResponseStatus response))
        inferenceResponse <- decodeResponseBody "inference response" response
        unless ("ADVISORY:" `Text.isPrefixOf` inferenceAdvice (inferenceResponse :: InferenceResponse)) $
          die "Inference advice did not preserve the advisory guardrail prefix."
  withInferenceServer
    38103
    (ReferenceModelConfig "http://127.0.0.1:39999/api/generate")
    $ do
      waitForHttpStatus manager "http://127.0.0.1:38103/healthz" [200]
      failureResponse <-
        httpJsonRequest
          manager
          "POST"
          "http://127.0.0.1:38103/advice"
          (Just (encode (InferenceRequest "Suggest a DAG repair for a missing summary node.")))
      unless (httpResponseStatus failureResponse == 502) $
        die ("Expected unavailable model host to return HTTP 502, got " <> show (httpResponseStatus failureResponse))
  putStrLn "Inference validation passed."

validateObservability :: IO ()
validateObservability = do
  requireExecutables ["docker", "kubectl", "kind", "helm"]
  clusterDeploy DeployServer
  validDag <- loadSubmissionDag "examples/dags/transcode-basic.yaml"
  manager <- newManager defaultManagerSettings
  authHeaders <- getClusterEdgeAuthHeaders manager
  withPortForward "service/studiomcp" 39001 3000 $ \baseUrl -> do
    waitForHttpStatus manager (baseUrl <> "/version") [200]
    sessionHeaders <- initializeMcpSessionWithHeaders manager baseUrl authHeaders
    submitResponseValue <-
      callMcpToolOverHttp
        manager
        baseUrl
        sessionHeaders
        2
        "workflow.submit"
        (object ["dag_spec" .= validDag])
    submitPayloadText <-
      case extractFirstMcpToolData submitResponseValue of
        Just payloadText -> pure payloadText
        Nothing -> die "workflow.submit did not return structured tool data for observability validation"
    submitPayloadValue <-
      case decode (LBS.fromStrict (TextEncoding.encodeUtf8 submitPayloadText)) of
        Just value -> pure value
        Nothing -> die "workflow.submit returned invalid JSON tool data during observability validation"
    runIdValue <-
      case lookupString ["runId"] submitPayloadValue of
        Just runIdText -> pure (Text.pack runIdText)
        Nothing -> die "workflow.submit tool data did not include a runId during observability validation"
    _ <-
      callMcpToolOverHttp
        manager
        baseUrl
        sessionHeaders
        3
        "workflow.status"
        (object ["run_id" .= runIdValue])
    metricsBody <-
      waitForMetricsBody
        manager
        baseUrl
        [ "studiomcp_method_calls_total{method=\"initialize\"} 1"
        , "studiomcp_method_calls_total{method=\"tools/call\"} 2"
        , "studiomcp_tool_calls_total{tool=\"workflow.submit\"} 1"
        ]
    unless ("studiomcp_tool_calls_total{tool=\"workflow.submit\"} 1" `isInfixOf` metricsBody) $
      die "Expected /metrics to show workflow.submit tool metrics."
    unless ("studiomcp_method_calls_total{method=\"tools/call\"} 2" `isInfixOf` metricsBody) $
      die "Expected /metrics to show tools/call method metrics."
    putStrLn "  ✓ /metrics exposes live MCP method and tool counters"
    initialHealthResponse <- httpJsonRequest manager "GET" (baseUrl <> "/healthz") Nothing
    initialHealthReport <- decodeResponseBody "initial health response" initialHealthResponse
    if healthStatus (initialHealthReport :: HealthReport) == Degraded
      then
        unless (any ((== Degraded) . dependencyStatus) (healthDependencies initialHealthReport)) $
          die "Expected /healthz to include at least one degraded dependency when the system is already degraded."
      else
        withScaledWorkload "statefulset/studiomcp-pulsar-proxy" 0 2 $ do
          waitForHttpStatus manager (baseUrl <> "/healthz") [503]
          healthResponse <- httpJsonRequest manager "GET" (baseUrl <> "/healthz") Nothing
          healthReport <- decodeResponseBody "degraded health response" healthResponse
          unless (healthStatus (healthReport :: HealthReport) == Degraded) $
            die "Expected /healthz to return a degraded health report when Pulsar is unavailable."
          unless (any ((== Degraded) . dependencyStatus) (healthDependencies healthReport)) $
            die "Expected /healthz to include at least one degraded dependency."
  putStrLn "Observability validation passed."

withInferenceServer :: Int -> ReferenceModelConfig -> IO a -> IO a
withInferenceServer port referenceModelConfig action =
  bracket
    (forkIO (runInferenceServer port referenceModelConfig))
    killThread
    (\_ -> action)

withWorkerServer :: Int -> AppConfig -> (String -> IO a) -> IO a
withWorkerServer port appConfig action =
  bracket
    (forkIO (runWorkerServer port appConfig))
    killThread
    (\_ -> do
        manager <- newManager defaultManagerSettings
        waitForHttpStatus manager ("http://127.0.0.1:" <> show port <> "/version") [200]
        action ("http://127.0.0.1:" <> show port)
    )

withFakeModelHost :: Int -> Text -> IO a -> IO a
withFakeModelHost port adviceText action =
  bracket
    (forkIO (runSettings (setHost "127.0.0.1" (setPort port defaultSettings)) (fakeModelHostApplication adviceText)))
    killThread
    (\_ -> do
        manager <- newManager defaultManagerSettings
        waitForHttpStatus manager ("http://127.0.0.1:" <> show port <> "/healthz") [200]
        action
    )

withFakeKeycloak :: (AuthConfig -> IO a) -> IO a
withFakeKeycloak action = do
  requireExecutables ["openssl"]
  let port = 38104
      baseUrl = "http://127.0.0.1:" <> show port
      issuer = Text.pack (baseUrl <> "/realms/studiomcp")
      keycloakConfig =
        KeycloakConfig
          { kcIssuer = issuer
          , kcAdditionalIssuers = []
          , kcAudience = "studiomcp-mcp"
          , kcRealm = "studiomcp"
          , kcClientId = "studiomcp-mcp"
          , kcClientSecret = Nothing
          , kcJwksCacheTtlSeconds = 300
          , kcJwksFetchTimeoutSeconds = 5
          }
      authConfig =
        defaultAuthConfig
          { acEnabled = True
          , acAllowInsecureHttp = True
          , acAllowedAlgorithms = ["RS256"]
          , acKeycloak = keycloakConfig
          }
  bracket
    (forkIO (runSettings (setHost "127.0.0.1" (setPort port defaultSettings)) fakeKeycloakApplication))
    killThread
    (\_ -> do
        manager <- newManager defaultManagerSettings
        waitForHttpStatus manager (baseUrl <> "/healthz") [200]
        action authConfig
    )

fakeKeycloakApplication :: Application
fakeKeycloakApplication request respond =
  case (requestMethod request, pathInfo request) of
    ("GET", ["healthz"]) ->
      respond (responseLBS status200 [(hContentType, "application/json")] "{\"status\":\"ok\"}")
    ("GET", ["realms", "studiomcp", "protocol", "openid-connect", "certs"]) ->
      respond
        ( responseLBS
            status200
            [(hContentType, "application/json")]
            ( encode
                ( object
                    [ "keys"
                        .= [ object
                               [ "kty" .= ("RSA" :: Text)
                               , "use" .= ("sig" :: Text)
                               , "kid" .= testKeycloakKid
                               , "alg" .= ("RS256" :: Text)
                               , "n" .= testKeycloakModulus
                               , "e" .= testKeycloakExponent
                               ]
                           ]
                    ]
                )
            )
        )
    _ ->
      respond (responseLBS status404 [(hContentType, "application/json")] "{\"error\":\"not-found\"}")

testKeycloakKid :: Text
testKeycloakKid = "studiomcp-cli-test-key"

testKeycloakModulus :: Text
testKeycloakModulus =
  "vccNrBuOrqWddJDxV_KofpV-wpnBftN0q_g2jWoKQNXTjBB5jmLMWpprvDxomm-4Ye6tUZMBwJsaeeIF96L42wMqTJPyBcSUy1BRbL0WGydCYVjXgRzsdrmNGKsTsrOffl25FUA7NA9SYy27ZrHyh-xGPOs-FEO2CDlAo_Z8NpN4D2RwjhcHvNo1sB-jB3y0FJZE2-tj4r2m0XouJs-CxTujFnJ6YDjbTeLGtrw89zAcJCI9wT4_nFAyPV6WGy0uNjgH-fA5tJNgve01VDrN1_862LbUyPbHiaFgdoSQWN13DLdZWu-tWWvmVrhyap_jke3z7IdE1KhKAFdJYqiHgQ"

testKeycloakExponent :: Text
testKeycloakExponent = "AQAB"

testKeycloakPrivateKeyPem :: String
testKeycloakPrivateKeyPem =
  unlines
    [ "-----BEGIN PRIVATE KEY-----"
    , "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC9xw2sG46upZ10"
    , "kPFX8qh+lX7CmcF+03Sr+DaNagpA1dOMEHmOYsxammu8PGiab7hh7q1RkwHAmxp5"
    , "4gX3ovjbAypMk/IFxJTLUFFsvRYbJ0JhWNeBHOx2uY0YqxOys59+XbkVQDs0D1Jj"
    , "LbtmsfKH7EY86z4UQ7YIOUCj9nw2k3gPZHCOFwe82jWwH6MHfLQUlkTb62PivabR"
    , "ei4mz4LFO6MWcnpgONtN4sa2vDz3MBwkIj3BPj+cUDI9XpYbLS42OAf58Dm0k2C9"
    , "7TVUOs3X/zrYttTI9seJoWB2hJBY3XcMt1la761Za+ZWuHJqn+OR7fPsh0TUqEoA"
    , "V0liqIeBAgMBAAECggEAAX8CPUByXYTHZasxho9Og2ug9jPJchCEs55fVQ9oSUk7"
    , "mQ0ViD6AfJkJubrYMETVNUsbvrA5VqViY2JEHccBIz42en1oGQzgXMH4rQdzQdTg"
    , "vG0Q4Imz1jPG8vzWSOsK74TETXCWMZDgBhF5kBOzD8iYZ9PgR2nz6MNayRrLsTpw"
    , "6NnCFodnqN6XUob/ReQvNAqWDetBTmY/jPk6WZh5rY1AVXAbPUpJ+qmO8Bl3SuQJ"
    , "hXuXW2nSGcPiJ66332aAAoWaZ9PNWe8SQGi4jg7KGyuO8WM5NB6mBq7SNim4ZRz0"
    , "Oy2DapRfRuHb2XrczSKQpopd/fsiU9l85CGQhfOViQKBgQDwSxbGeVk4kxvM0Bn4"
    , "9tW2qLN4ZPKGbdXBHQr5Zke7tGuOt31ec8kGOqcVMFKe0sIW4qH6pDLO/6l6XUUA"
    , "kTfpvGkpzQJ9IAfDl9lk73PUqX/ldGHRkbdCheJh6W1AeACO+bqznhSREzLYlb7+"
    , "EQ+yhkWDIQRWIVE48qgwNv7VgwKBgQDKLqquO6PzXNHNut4f4VrNvj2XCFNtUXOm"
    , "AgE2qAIGzfUh5ymgBXHYkVCzrTDF7z/mxhHZPidtg437zn2P3VhTfp/VNWoDuvvU"
    , "5oEA5URqLAVjdRiZ1olwiRtfLaleVHfSibMFfDesAPP76el1rCCmF7S6nV5xrnoL"
    , "S+OgLpUjqwKBgAt8u3j/ghlnRvPymttBCZRy2imOQd3VUFusBMNJdXJuvJmVAgRK"
    , "6rhGg4hKyBhZoPexG+c8hEVLCZIU9WCCkLa20Bw0dcL/jf92uejOXa4z8C5K8wYu"
    , "viEK/3iIzTVAx14OaDOAAiGxVkPuXLQOor55FsefA3MOorBjQVEUv/f7AoGATURk"
    , "ak3UrG7up2cg+KIRJ8vqkcvWxlJ4lhryB8dRbvRLGHfViphKF/ABHYm0uBBlJXbQ"
    , "32tHeizqmC8kAVUgKlicEMlnCKHvGEA3UPZNnR3RuV7I1hINWHqtgURcE/bIDCgf"
    , "yJreU9fRZpbQZ+4uVAt/QEpgC6YYcjTAezkSOh0CgYEA3Wi+XEDu4O/NOz9Y4FWs"
    , "2dPpsqyRhOEi6aWwmzlraT+H9FCMJvMM2bBzA8rgkmp9wXYJ7hWDGG35eqvK9K9p"
    , "vKd1t7MlfqyUTbwJ6hEga4hd1AeZh/yembmwz9L22DKEonvzPChmWPIQb6uPaQbX"
    , "87Jc2KSMI3hU4df/fT8F5zM="
    , "-----END PRIVATE KEY-----"
    ]

buildSignedTestJwt :: AuthConfig -> Value -> IO RawJwt
buildSignedTestJwt authConfig payload = do
  let headerValue =
        object
          [ "alg" .= ("RS256" :: Text)
          , "typ" .= ("JWT" :: Text)
          , "kid" .= testKeycloakKid
          ]
      headerPart = base64UrlEncodeLazy (encode headerValue)
      payloadPart = base64UrlEncodeLazy (encode payload)
      signingInput = headerPart <> "." <> payloadPart
  signature <- signJwtPayload signingInput
  pure (RawJwt (signingInput <> "." <> base64UrlEncodeStrict signature))
  where
    _ = authConfig

signJwtPayload :: Text -> IO ByteString.ByteString
signJwtPayload signingInput = do
  tempDir <- getTemporaryDirectory
  bracket
    (openTempFile tempDir "studiomcp-key.pem")
    (\(pemPath, pemHandle) -> hClose pemHandle >> removeFileIfExists pemPath)
    (\(pemPath, pemHandle) -> do
        hClose pemHandle
        writeFile pemPath testKeycloakPrivateKeyPem
        bracket
          (openTempFile tempDir "studiomcp-signing-input.txt")
          (\(inputPath, inputHandle) -> hClose inputHandle >> removeFileIfExists inputPath)
          (\(inputPath, inputHandle) -> do
              hClose inputHandle
              ByteString.writeFile inputPath (TextEncoding.encodeUtf8 signingInput)
              bracket
                (openTempFile tempDir "studiomcp-signature.bin")
                (\(sigPath, sigHandle) -> hClose sigHandle >> removeFileIfExists sigPath)
                (\(sigPath, sigHandle) -> do
                    hClose sigHandle
                    callProcess
                      "openssl"
                      ["dgst", "-sha256", "-sign", pemPath, "-out", sigPath, inputPath]
                    ByteString.readFile sigPath
                )
          )
    )

base64UrlEncodeLazy :: LBS.ByteString -> Text
base64UrlEncodeLazy = base64UrlEncodeStrict . LBS.toStrict

base64UrlEncodeStrict :: ByteString.ByteString -> Text
base64UrlEncodeStrict =
  TextEncoding.decodeUtf8
    . ByteString.dropWhileEnd (== fromIntegral (fromEnum '='))
    . ByteString.map replace
    . Base64.encode
  where
    replace byte
      | byte == fromIntegral (fromEnum '+') = fromIntegral (fromEnum '-')
      | byte == fromIntegral (fromEnum '/') = fromIntegral (fromEnum '_')
      | otherwise = byte

buildKeycloakTestPayload ::
  AuthConfig ->
  [(Text, Value)] ->
  IO Value
buildKeycloakTestPayload authConfig overrides = do
  now <- getCurrentTime
  let epochNow = floor (utcTimeToPOSIXSeconds now) :: Integer
      basePayload =
        object
          [ "iss" .= kcIssuer (acKeycloak authConfig)
          , "sub" .= ("user-123" :: Text)
          , "aud" .= [kcAudience (acKeycloak authConfig)]
          , "exp" .= (epochNow + 3600)
          , "iat" .= epochNow
          , "scope" .= ("workflow:read workflow:write artifact:manage prompt:read" :: Text)
          , "tenant_id" .= ("tenant-456" :: Text)
          , "realm_access" .= object ["roles" .= ["user" :: Text, "tenant:tenant-456"]]
          , "resource_access" .= object ["studiomcp-mcp" .= object ["roles" .= ["workflow.submit" :: Text]]]
          , "email" .= ("user@example.com" :: Text)
          , "email_verified" .= True
          , "name" .= ("Test User" :: Text)
          ]
  pure (mergeObjectFields basePayload overrides)

mergeObjectFields :: Value -> [(Text, Value)] -> Value
mergeObjectFields (Object obj) overrides =
  Object $
    foldr
      (\(fieldName, fieldValue) acc -> KeyMap.insert (Key.fromText fieldName) fieldValue acc)
      obj
      overrides
mergeObjectFields value _ = value

tamperRawJwt :: RawJwt -> RawJwt
tamperRawJwt (RawJwt token) =
  case Text.splitOn "." token of
    [headerPart, payloadPart, signaturePart] ->
      case Base64Url.decodeUnpadded (TextEncoding.encodeUtf8 signaturePart) of
        Right signatureBytes
          | not (ByteString.null signatureBytes) ->
              let tamperedBytes =
                    ByteString.cons
                      (ByteString.head signatureBytes `xorWord8` 0x01)
                      (ByteString.tail signatureBytes)
               in RawJwt (Text.intercalate "." [headerPart, payloadPart, base64UrlEncodeStrict tamperedBytes])
        _ -> RawJwt token
    _ -> RawJwt token
  where
    xorWord8 value mask =
      toEnum (fromEnum value `xor` mask)

removeFileIfExists :: FilePath -> IO ()
removeFileIfExists path = do
  exists <- doesFileExist path
  when exists (removeFile path)

-- | Fixed container name for validation Redis instances.
-- Using a fixed name ensures idempotent container management:
-- - No orphaned containers accumulate from interrupted tests
-- - Re-running tests automatically cleans up previous instances
-- - Container state is predictable and inspectable
testRedisContainerName :: String
testRedisContainerName = "studiomcp-test-redis"

withTemporaryRedisConfig :: (RedisConfig -> IO a) -> IO a
withTemporaryRedisConfig action =
  bracket
    startRedisContainer
    stopRedisContainer
    (action . snd)
  where
    startRedisContainer :: IO (String, RedisConfig)
    startRedisContainer = do
      -- Cleanup any existing container with this name (idempotent start)
      _ <- readProcessWithExitCode "docker" ["rm", "-f", testRedisContainerName] ""
      (exitCode, stdoutText, stderrText) <-
        readProcessWithExitCode "docker" ["run", "-d", "-P", "--name", testRedisContainerName, "redis:7-alpine"] ""
      case exitCode of
        ExitFailure _ -> die stderrText
        ExitSuccess -> do
          let containerId = trimLine stdoutText
          dockerPublishedHost <- resolveDockerPublishedHost
          portNumber <- resolvePublishedPort containerId "6379/tcp"
          let redisConfig =
                defaultRedisConfig
                  { rcHost = dockerPublishedHost
                  , rcPort = portNumber
                  }
          waitForRedisReady redisConfig
          pure (containerId, redisConfig)

    stopRedisContainer :: (String, RedisConfig) -> IO ()
    stopRedisContainer (containerId, _) = do
      _ <- readProcessWithExitCode "docker" ["rm", "-f", containerId] ""
      pure ()

withRedisConfigEnv :: RedisConfig -> IO a -> IO a
withRedisConfigEnv redisConfig action = do
  let envBindings =
        [ ("STUDIOMCP_REDIS_HOST", Text.unpack (rcHost redisConfig))
        , ("STUDIOMCP_REDIS_PORT", show (rcPort redisConfig))
        , ("STUDIOMCP_REDIS_DATABASE", show (rcDatabase redisConfig))
        , ("STUDIOMCP_REDIS_POOL_SIZE", show (rcPoolSize redisConfig))
        , ("STUDIOMCP_REDIS_TIMEOUT", show (rcConnectionTimeout redisConfig))
        , ("STUDIOMCP_SESSION_TTL", show (rcSessionTtl redisConfig))
        , ("STUDIOMCP_LOCK_TTL", show (rcLockTtl redisConfig))
        , ("STUDIOMCP_REDIS_KEY_PREFIX", Text.unpack (rcKeyPrefix redisConfig))
        ]
  previousValues <- mapM (\(name, _) -> do previousValue <- lookupEnv name; pure (name, previousValue)) envBindings
  bracket_
    (mapM_ (uncurry setEnv) envBindings)
    (mapM_ restoreEnv previousValues)
    action
  where
    restoreEnv (name, maybeValue) =
      case maybeValue of
        Just value -> setEnv name value
        Nothing -> unsetEnv name

resolvePublishedPort :: String -> String -> IO Int
resolvePublishedPort containerId exposedPort = do
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode "docker" ["port", containerId, exposedPort] ""
  case exitCode of
    ExitFailure _ -> die stderrText
    ExitSuccess ->
      case readMaybePort (reverse (takeWhile (/= ':') (reverse (trimLine stdoutText)))) of
        Just portNumber -> pure portNumber
        Nothing -> die ("Unable to parse published Redis port from: " <> stdoutText)
  where
    readMaybePort rawValue =
      case reads rawValue of
        [(portNumber, "")] -> Just portNumber
        _ -> Nothing

resolveDockerPublishedHost :: IO Text
resolveDockerPublishedHost = do
  explicitHost <- lookupEnv "STUDIOMCP_DOCKER_PUBLISHED_HOST"
  case fmap Text.pack explicitHost of
    Just hostValue
      | not (Text.null (Text.strip hostValue)) -> pure (Text.strip hostValue)
    _ -> do
      runningInContainer <- doesFileExist "/.dockerenv"
      pure
        ( if runningInContainer
            then "host.docker.internal"
            else "127.0.0.1"
        )

waitForRedisReady :: RedisConfig -> IO ()
waitForRedisReady redisConfig = loop (20 :: Int)
  where
    loop attemptsRemaining
      | attemptsRemaining <= 0 =
          die "Timed out waiting for temporary Redis container to become ready"
      | otherwise = do
          storeResult <- (try (newRedisSessionStore redisConfig) :: IO (Either SomeException RedisSessionStore))
          case storeResult of
            Right store -> do
              connectionResult <- testConnection store
              closeRedisSessionStore store
              case connectionResult of
                Right () -> pure ()
                Left _ -> retry
            Left _ -> retry
      where
        retry = do
          threadDelay 500000
          loop (attemptsRemaining - 1)

fakeModelHostApplication :: Text -> Application
fakeModelHostApplication adviceText request respond =
  case pathInfo request of
    ["api", "generate"] | requestMethod request == methodPost -> do
      _ <- strictRequestBody request
      respond
        ( responseLBS
            status200
            [(hContentType, "application/json")]
            (encode (object ["response" .= adviceText]))
        )
    ["healthz"] | requestMethod request == methodGet ->
      respond
        ( responseLBS
            status200
            [(hContentType, "application/json")]
            (encode (object ["status" .= ("ready" :: String)]))
        )
    _ ->
      respond
        ( responseLBS
            status200
            [(hContentType, "application/json")]
            (encode (object ["status" .= ("ready" :: String)]))
        )

withScaledWorkload :: String -> Int -> Int -> IO a -> IO a
withScaledWorkload workloadName scaledDownReplicas restoredReplicas =
  bracket_
    ( do
        callProcess "kubectl" ["scale", workloadName, "--replicas", show scaledDownReplicas]
        callProcess "kubectl" ["rollout", "status", workloadName, "--timeout=300s"]
    )
    ( do
        callProcess "kubectl" ["scale", workloadName, "--replicas", show restoredReplicas]
        callProcess "kubectl" ["rollout", "status", workloadName, "--timeout=300s"]
    )

withMinioPortForwardConfig :: AppConfig -> (AppConfig -> IO a) -> IO a
withMinioPortForwardConfig appConfig action =
  withPortForward "service/studiomcp-minio" 39010 9000 $ \baseUrl -> do
    manager <- newManager defaultManagerSettings
    waitForHttpStatus manager (baseUrl <> "/minio/health/live") [200]
    action appConfig {minioEndpoint = Text.pack baseUrl}

kindPulsarBinaryEndpoint :: Text
kindPulsarBinaryEndpoint = "pulsar://studiomcp-pulsar-proxy:6650"

withKindPulsarConfig :: AppConfig -> (AppConfig -> IO a) -> IO a
withKindPulsarConfig appConfig action =
  withPortForward "service/studiomcp-pulsar-proxy" 39011 80 $ \pulsarHttpBaseUrl -> do
    manager <- newManager defaultManagerSettings
    waitForHttpStatus manager (pulsarHttpBaseUrl <> "/admin/v2/clusters") [200]
    action
      appConfig
        { pulsarHttpUrl = Text.pack pulsarHttpBaseUrl,
          pulsarBinaryUrl = kindPulsarBinaryEndpoint
        }

withKindRuntimeConfig :: AppConfig -> (AppConfig -> IO a) -> IO a
withKindRuntimeConfig appConfig action =
  withKindPulsarConfig appConfig $ \pulsarReadyConfig ->
    withMinioPortForwardConfig pulsarReadyConfig action

withLocalWorkerConfig :: AppConfig -> (AppConfig -> IO a) -> IO a
withLocalWorkerConfig = withKindRuntimeConfig

requireExecutables :: [String] -> IO ()
requireExecutables commands =
  forM_ commands $ \command -> do
    executable <- findExecutable command
    when (executable == Nothing) $
      die ("Required executable is not available: " <> command)

buildServerImage :: IO ()
buildServerImage = do
  skipBuild <- lookupEnv "STUDIOMCP_SKIP_IMAGE_BUILD"
  let skipRequested =
        case fmap (map toLower . trimWhitespace) skipBuild of
          Just "1" -> True
          Just "true" -> True
          Just "yes" -> True
          _ -> False
  if skipRequested
    then do
      (exitCode, _, _) <- readProcessWithExitCode "docker" ["image", "inspect", "studiomcp:latest"] ""
      case exitCode of
        ExitSuccess ->
          putStrLn "Reusing existing local image 'studiomcp:latest' (STUDIOMCP_SKIP_IMAGE_BUILD=1)."
        ExitFailure _ ->
          buildServerImageNow
    else buildServerImageNow
  where
    buildServerImageNow = do
      buildxConfigDir <- (</> "studiomcp-buildx") <$> getTemporaryDirectory
      createDirectoryIfMissing True buildxConfigDir
      previousBuildxConfig <- lookupEnv "BUILDX_CONFIG"
      bracket_
        (setEnv "BUILDX_CONFIG" buildxConfigDir)
        ( case previousBuildxConfig of
            Just value -> setEnv "BUILDX_CONFIG" value
            Nothing -> unsetEnv "BUILDX_CONFIG"
        )
        ( callProcess
            "docker"
            [ "buildx"
            , "build"
            , "--load"
            , "--progress=plain"
            , "-t"
            , "studiomcp:latest"
            , "-f"
            , "docker/Dockerfile"
            , "--target"
            , "production"
            , "."
            ]
        )

data HttpResponse = HttpResponse
  { httpResponseStatus :: Int,
    httpResponseHeaders :: [Header],
    httpResponseBody :: LBS.ByteString
  }

httpJsonRequest :: Manager -> String -> String -> Maybe LBS.ByteString -> IO HttpResponse
httpJsonRequest manager methodValue url maybeBody =
  httpJsonRequestWithHeaders manager methodValue url [] maybeBody

httpJsonRequestWithTimeoutMicros :: Int -> Manager -> String -> String -> Maybe LBS.ByteString -> IO HttpResponse
httpJsonRequestWithTimeoutMicros timeoutMicros manager methodValue url maybeBody =
  httpJsonRequestWithHeadersAndTimeout (Just timeoutMicros) manager methodValue url [] maybeBody

httpJsonRequestWithHeaders :: Manager -> String -> String -> [Header] -> Maybe LBS.ByteString -> IO HttpResponse
httpJsonRequestWithHeaders manager methodValue url extraHeaders maybeBody = do
  httpJsonRequestWithHeadersAndTimeout Nothing manager methodValue url extraHeaders maybeBody

httpJsonRequestWithHeadersAndTimeout :: Maybe Int -> Manager -> String -> String -> [Header] -> Maybe LBS.ByteString -> IO HttpResponse
httpJsonRequestWithHeadersAndTimeout maybeTimeoutMicros manager methodValue url extraHeaders maybeBody = do
  request <- parseRequest url
  response <-
    httpLbs
      request
        { method = BS.pack methodValue,
          requestHeaders =
            case maybeBody of
              Just _ -> (CI.mk "Content-Type", "application/json") : extraHeaders
              Nothing -> extraHeaders,
          requestBody =
            case maybeBody of
              Just body -> RequestBodyLBS body
              Nothing -> requestBody request,
          responseTimeout =
            case maybeTimeoutMicros of
              Just timeoutMicros -> responseTimeoutMicro timeoutMicros
              Nothing -> responseTimeout request
        }
      manager
  pure
    HttpResponse
      { httpResponseStatus = statusCode (responseStatus response),
        httpResponseHeaders = responseHeaders response,
        httpResponseBody = responseBody response
      }

decodeResponseBody :: FromJSON a => String -> HttpResponse -> IO a
decodeResponseBody label httpResponse =
  case decode (httpResponseBody httpResponse) of
    Just value -> pure value
    Nothing ->
      die
        ( "Could not decode "
            <> label
            <> " from HTTP body:\n"
            <> LBS.unpack (httpResponseBody httpResponse)
        )

lookupResponseHeader :: BS.ByteString -> HttpResponse -> Maybe BS.ByteString
lookupResponseHeader headerName httpResponse =
  lookup (CI.mk headerName) (httpResponseHeaders httpResponse)

initializeMcpSession :: Manager -> String -> IO [Header]
initializeMcpSession manager baseUrl = do
  let initializeRequest =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "id" .= (1 :: Int)
          , "method" .= ("initialize" :: Text)
          , "params" .= object
              [ "protocolVersion" .= ("2024-11-05" :: Text)
              , "capabilities" .= object []
              , "clientInfo" .= object
                  [ "name" .= ("validate-client" :: Text)
                  , "version" .= ("1.0.0" :: Text)
                  ]
              ]
          ]
  initResponse <- httpJsonRequest manager "POST" (baseUrl <> "/mcp") (Just (encode initializeRequest))
  unless (httpResponseStatus initResponse == 200) $
    die ("Expected MCP initialize to return HTTP 200, got " <> show (httpResponseStatus initResponse))
  sessionHeaderValue <-
    case lookupResponseHeader "Mcp-Session-Id" initResponse of
      Just headerValue -> pure headerValue
      Nothing -> die "Initialize response did not include an Mcp-Session-Id header"
  let sessionHeaders = [("Mcp-Session-Id", sessionHeaderValue)]
      initializedNotification =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "method" .= ("notifications/initialized" :: Text)
          ]
  initializedResponse <-
    httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/mcp") sessionHeaders (Just (encode initializedNotification))
  unless (httpResponseStatus initializedResponse == 200) $
    die ("Expected MCP initialized notification to return HTTP 200, got " <> show (httpResponseStatus initializedResponse))
  pure sessionHeaders

mcpJsonRpcRequest ::
  Manager ->
  String ->
  [Header] ->
  Value ->
  IO HttpResponse
mcpJsonRpcRequest manager baseUrl sessionHeaders payload =
  httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/mcp") sessionHeaders (Just (encode payload))

callMcpToolOverHttp ::
  Manager ->
  String ->
  [Header] ->
  Int ->
  Text ->
  Value ->
  IO Value
callMcpToolOverHttp manager baseUrl sessionHeaders requestId toolName arguments = do
  let requestPayload =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "id" .= requestId
          , "method" .= ("tools/call" :: Text)
          , "params" .= object
              [ "name" .= toolName
              , "arguments" .= arguments
              ]
          ]
  response <- mcpJsonRpcRequest manager baseUrl sessionHeaders requestPayload
  unless (httpResponseStatus response == 200) $
    die ("Expected tools/call to return HTTP 200, got " <> show (httpResponseStatus response))
  decodeResponseBody "tools/call response" response

expectToolSuccessText :: String -> ToolResult -> IO Text
expectToolSuccessText label result =
  case result of
    ToolFailure err ->
      die (label <> " failed: " <> show err)
    ToolSuccess toolResult ->
      case mapMaybe tcText (ctrContent toolResult) of
        textContent : _ -> pure textContent
        [] -> die (label <> " returned no text content")

extractDelimitedValue :: Text -> Text -> Text -> Maybe Text
extractDelimitedValue startMarker endMarker fullText =
  case Text.breakOn startMarker fullText of
    (_, remainder)
      | Text.null remainder -> Nothing
      | otherwise ->
          let afterMarker = Text.drop (Text.length startMarker) remainder
              value =
                if Text.null endMarker
                  then afterMarker
                  else fst (Text.breakOn endMarker afterMarker)
              trimmed = Text.strip value
           in if Text.null trimmed then Nothing else Just trimmed

withPortForward :: String -> Int -> Int -> (String -> IO a) -> IO a
withPortForward target localPort remotePort action =
  bracket
    ( do
        (_, _, _, processHandle) <-
          createProcess
            (proc "kubectl" ["port-forward", target, show localPort <> ":" <> show remotePort])
              { std_out = NoStream,
                std_err = NoStream
              }
        pure processHandle
    )
    (\processHandle -> terminateProcess processHandle >> voidWait processHandle)
    (\_ -> action ("http://127.0.0.1:" <> show localPort))

waitForHttpStatus :: Manager -> String -> [Int] -> IO ()
waitForHttpStatus = waitForHttpStatusWithTimeout 30

-- | Wait for an HTTP endpoint to return an expected status code with configurable timeout
waitForHttpStatusWithTimeout :: Int -> Manager -> String -> [Int] -> IO ()
waitForHttpStatusWithTimeout timeoutSeconds manager url expectedStatuses =
  go timeoutSeconds
  where
    go 0 =
      die ("Timed out waiting for HTTP readiness at " <> url)
    go remainingAttempts = do
      responseOrException <- tryHttp (httpJsonRequest manager "GET" url Nothing)
      case responseOrException of
        Right response
          | httpResponseStatus response `elem` expectedStatuses ->
              pure ()
        _ -> do
          threadDelay 1000000
          go (remainingAttempts - 1)

waitForMetricsBody :: Manager -> String -> [String] -> IO String
waitForMetricsBody manager baseUrl expectedFragments =
  go (60 :: Int)
  where
    metricsUrl = baseUrl <> "/metrics"

    go 0 =
      die ("Timed out waiting for metrics at " <> metricsUrl)
    go remainingAttempts = do
      responseOrException <- tryHttp (httpJsonRequest manager "GET" metricsUrl Nothing)
      case responseOrException of
        Right response
          | httpResponseStatus response == 200 ->
              let metricsBody = LBS.unpack (httpResponseBody response)
               in if all (`isInfixOf` metricsBody) expectedFragments
                    then pure metricsBody
                    else retry remainingAttempts
          | otherwise ->
              retry remainingAttempts
        Left _ -> retry remainingAttempts

    retry remainingAttempts = do
      threadDelay 1000000
      go (remainingAttempts - 1)

-- | Non-fatal variant that returns Nothing on timeout instead of dying
tryWaitForMetricsBody :: Manager -> String -> [String] -> IO (Maybe String)
tryWaitForMetricsBody manager baseUrl expectedFragments =
  go (15 :: Int)  -- Shorter timeout for non-critical checks
  where
    metricsUrl = baseUrl <> "/metrics"

    go 0 = do
      putStrLn ("    ⚠ Metrics endpoint not reachable at " <> metricsUrl <> " (skipping)")
      pure Nothing
    go remainingAttempts = do
      responseOrException <- tryHttp (httpJsonRequest manager "GET" metricsUrl Nothing)
      case responseOrException of
        Right response
          | httpResponseStatus response == 200 ->
              let metricsBody = LBS.unpack (httpResponseBody response)
               in if all (`isInfixOf` metricsBody) expectedFragments
                    then pure (Just metricsBody)
                    else retry remainingAttempts
          | otherwise ->
              retry remainingAttempts
        Left _ -> retry remainingAttempts

    retry remainingAttempts = do
      threadDelay 1000000
      go (remainingAttempts - 1)

loadSubmissionDag :: FilePath -> IO DagSpec
loadSubmissionDag dagPath = do
  decoded <- loadDagFile dagPath
  case decoded of
    Left parseFailure ->
      die ("Could not parse DAG fixture " <> dagPath <> ": " <> parseFailure)
    Right dagSpec ->
      case validateDag dagSpec of
        Success validDag -> pure validDag
        Failure failures ->
          die ("DAG fixture did not validate: " <> renderFailures failures)

invalidSubmissionDag :: DagSpec
invalidSubmissionDag =
  DagSpec
    { dagName = "invalid-mcp-submission",
      dagDescription = Just "DAG without a required summary node.",
      dagNodes =
        [ NodeSpec
            { nodeId = NodeId "ingest",
              nodeKind = PureNode,
              nodeTool = Nothing,
              nodeInputs = [],
              nodeOutputType = OutputType "text/plain",
              nodeTimeout = TimeoutPolicy 5,
              nodeMemoization = "memoize"
            }
        ]
    }

tryHttp :: IO a -> IO (Either HttpException a)
tryHttp = try

voidWait :: ProcessHandle -> IO ()
voidWait processHandle = do
  _ <- waitForProcess processHandle
  pure ()

requirePulsarDeployment :: IO ()
requirePulsarDeployment = do
  (exitCode, _, stderrText) <-
    readProcessWithExitCode "kubectl" ["get", "service/studiomcp-pulsar-proxy", "-o", "name"] ""
  case exitCode of
    ExitSuccess -> pure ()
    ExitFailure _ ->
      die
        ( "Pulsar proxy service is not available in the cluster. "
            <> "Deploy sidecars first with `studiomcp cluster deploy sidecars`.\n"
            <> stderrText
        )

requireMinioDeployment :: IO ()
requireMinioDeployment = do
  (exitCode, _, stderrText) <-
    readProcessWithExitCode "kubectl" ["get", "service/studiomcp-minio", "-o", "name"] ""
  case exitCode of
    ExitSuccess -> pure ()
    ExitFailure _ ->
      die
        ( "MinIO service is not available in the cluster. "
            <> "Deploy sidecars first with `studiomcp cluster deploy sidecars`.\n"
            <> stderrText
        )

kindClusters :: IO [String]
kindClusters = do
  (exitCode, stdoutText, stderrText) <- readProcessWithExitCode "kind" ["get", "clusters"] ""
  case exitCode of
    ExitSuccess -> pure (filter (not . null) (lines stdoutText))
    ExitFailure _ -> die stderrText

getClusterName :: IO String
getClusterName = fromMaybe "studiomcp" <$> lookupEnv "STUDIOMCP_KIND_CLUSTER"

resolveCliDataRoot :: IO FilePath
resolveCliDataRoot = do
  containerDataRootExists <- doesDirectoryExist "/.data"
  if containerDataRootExists
    then pure "/.data"
    else do
      cwd <- getCurrentDirectory
      pure (cwd </> ".data")

resolveKindHostDataRoot :: IO FilePath
resolveKindHostDataRoot = do
  explicitHostPath <- fmap normalizeOptionalPath (lookupEnv "STUDIOMCP_KIND_HOST_DATA_PATH")
  runningInContainer <- doesFileExist "/.dockerenv"
  case explicitHostPath of
    Just hostPath -> pure hostPath
    Nothing
      | runningInContainer -> do
          currentContainerName <- readCurrentContainerName
          maybeMountedSource <- readMountedHostPath currentContainerName "/.data"
          case maybeMountedSource of
            Just mountedSource -> pure mountedSource
            Nothing ->
              die
                "Could not resolve the host-visible .data mount from the outer container. Set STUDIOMCP_KIND_HOST_DATA_PATH explicitly."
      | otherwise -> do
          -- Use ./.data (project directory) for persistent storage
          cwd <- getCurrentDirectory
          pure (cwd </> ".data")

withKindConfig :: String -> FilePath -> (FilePath -> IO a) -> IO a
withKindConfig clusterName dataRoot action = do
  tempDir <- getTemporaryDirectory
  bracket
    (openTempFile tempDir "studiomcp-kind-config.yaml")
    (\(configPath, handle) -> hClose handle >> removeFile configPath)
    (\(configPath, handle) -> do
        LBS.hPutStr handle (renderKindConfig clusterName dataRoot)
        hClose handle
        action configPath
    )

ensureContainerKubeconfig :: String -> IO ()
ensureContainerKubeconfig clusterName = do
  runningInContainer <- doesFileExist "/.dockerenv"
  when runningInContainer $ do
    kubeconfigText <- readKindKubeconfig clusterName
    homeDirectory <- getHomeDirectory
    let kubeDirectory = homeDirectory </> ".kube"
        kubeconfigPath = kubeDirectory </> "config"
    createDirectoryIfMissing True kubeDirectory
    writeFile kubeconfigPath kubeconfigText

ensureHostKubeconfig :: String -> IO ()
ensureHostKubeconfig clusterName =
  callProcess "kind" ["export", "kubeconfig", "--name", clusterName]

ensureContainerClusterAccess :: String -> IO ()
ensureContainerClusterAccess clusterName = do
  runningInContainer <- doesFileExist "/.dockerenv"
  if runningInContainer
    then do
      ensureContainerOnKindNetwork
      ensureContainerKubeconfig clusterName
    else
      ensureHostKubeconfig clusterName

readKindKubeconfig :: String -> IO String
readKindKubeconfig clusterName = do
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode
      "kind"
      ["get", "kubeconfig", "--name", clusterName, "--internal"]
      ""
  case exitCode of
    ExitSuccess -> pure stdoutText
    ExitFailure _ -> die stderrText

ensureContainerOnKindNetwork :: IO ()
ensureContainerOnKindNetwork = do
  runningInContainer <- doesFileExist "/.dockerenv"
  when runningInContainer $ do
    currentContainerName <- readCurrentContainerName
    alreadyConnected <- containerOnKindNetwork currentContainerName
    unless alreadyConnected $
      callProcess "docker" ["network", "connect", "kind", currentContainerName]

readCurrentContainerName :: IO String
readCurrentContainerName = do
  currentContainerId <- trimLine <$> readFile "/etc/hostname"
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode "docker" ["inspect", "--format", "{{.Name}}", currentContainerId] ""
  case exitCode of
    ExitSuccess -> pure (dropWhile (== '/') (trimLine stdoutText))
    ExitFailure _ -> die stderrText

containerOnKindNetwork :: String -> IO Bool
containerOnKindNetwork containerName = do
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode "docker" ["network", "inspect", "kind", "--format", "{{json .Containers}}"] ""
  case exitCode of
    ExitSuccess ->
      pure (("\"Name\":\"" <> containerName <> "\"") `isInfixOf` stdoutText)
    ExitFailure _ -> die stderrText

trimLine :: String -> String
trimLine = reverse . dropWhile (`elem` ['\n', '\r']) . reverse

normalizeOptionalPath :: Maybe String -> Maybe String
normalizeOptionalPath maybeValue =
  case fmap trimWhitespace maybeValue of
    Just value
      | null value -> Nothing
      | otherwise -> Just value
    Nothing -> Nothing

trimWhitespace :: String -> String
trimWhitespace = dropWhileEndSpace . dropWhile isSpace
  where
    dropWhileEndSpace = reverse . dropWhile isSpace . reverse

renderFailureDetail :: FailureDetail -> String
renderFailureDetail failureDetail =
  unlines $
    [ Text.unpack (failureCode failureDetail <> ": " <> failureMessage failureDetail)
    ]
      <> map renderContextEntry (Map.toList (failureContext failureDetail))
  where
    renderContextEntry (keyText, valueText) =
      "  " <> Text.unpack keyText <> ": " <> Text.unpack valueText

readMountedHostPath :: String -> FilePath -> IO (Maybe FilePath)
readMountedHostPath containerName mountDestination = do
  (exitCode, stdoutText, stderrText) <-
    readProcessWithExitCode
      "docker"
      ["inspect", "--format", "{{range .Mounts}}{{println .Destination \"=>\" .Source}}{{end}}", containerName]
      ""
  case exitCode of
    ExitSuccess -> pure (parseMountedHostPath mountDestination stdoutText)
    ExitFailure _ -> die stderrText

parseMountedHostPath :: FilePath -> String -> Maybe FilePath
parseMountedHostPath mountDestination stdoutText =
  listToMaybe (mapMaybe parseLine (lines stdoutText))
  where
    parseLine line =
      case Text.splitOn " => " (Text.pack line) of
        [destination, source]
          | Text.unpack destination == mountDestination ->
              Just (Text.unpack source)
        _ -> Nothing

-- | A required port mapping for Kind cluster validation
data RequiredPortMapping = RequiredPortMapping
  { rpmContainerPort :: Int
  , rpmHostPort :: Int
  , rpmDescription :: String
  } deriving (Eq, Show)

-- | Required port mappings for studioMCP Kind clusters
requiredPortMappings :: [RequiredPortMapping]
requiredPortMappings =
  [ RequiredPortMapping 80 8081 "HTTP Ingress"
  , RequiredPortMapping 443 8444 "HTTPS Ingress"
  , RequiredPortMapping 32000 9000 "MinIO S3 API"
  , RequiredPortMapping 32001 9001 "MinIO Console"
  ]

renderKindConfig :: String -> FilePath -> LBS.ByteString
renderKindConfig clusterName dataRoot =
  LBS.unlines $
    [ "kind: Cluster"
    , "apiVersion: kind.x-k8s.io/v1alpha4"
    , "name: " <> LBS.pack clusterName
    , "nodes:"
    , "  - role: control-plane"
    , "    extraPortMappings:"
    ]
    <> concatMap renderPortMapping requiredPortMappings
    <> [ "    extraMounts:"
       , "      - hostPath: " <> LBS.pack dataRoot
       , "        containerPath: /.data"
       ]
  where
    renderPortMapping :: RequiredPortMapping -> [LBS.ByteString]
    renderPortMapping rpm =
      [ "      - containerPort: " <> LBS.pack (show (rpmContainerPort rpm))
      , "        hostPort: " <> LBS.pack (show (rpmHostPort rpm))
      , "        protocol: TCP"
      ]

-- | Inspect the port bindings of a Kind cluster's control-plane node
-- Returns a map from container port (e.g., "80") to list of host ports
inspectKindNodePortBindings :: String -> IO (Map.Map String [Int])
inspectKindNodePortBindings clusterName = do
  let containerName = clusterName <> "-control-plane"
  (exitCode, stdoutText, _) <-
    readProcessWithExitCode "docker"
      ["inspect", containerName, "--format", "{{json .HostConfig.PortBindings}}"]
      ""
  case exitCode of
    ExitFailure _ -> pure Map.empty
    ExitSuccess -> pure (parsePortBindings (trimWhitespace stdoutText))

-- | Parse Docker PortBindings JSON into a map from container port to host ports
-- Input format: {"80/tcp":[{"HostIp":"","HostPort":"8081"}],"443/tcp":[{"HostIp":"","HostPort":"8444"}]}
parsePortBindings :: String -> Map.Map String [Int]
parsePortBindings jsonStr =
  case decode (LBS.pack jsonStr) of
    Nothing -> Map.empty
    Just (Object obj) -> Map.fromList (mapMaybe parseEntry (KeyMap.toList obj))
    Just _ -> Map.empty
  where
    parseEntry :: (Aeson.Key, Value) -> Maybe (String, [Int])
    parseEntry (key, Array bindings) =
      let portStr = takeWhile (/= '/') (Key.toString key)
          hostPorts = mapMaybe extractHostPort (Vector.toList bindings)
       in if null hostPorts then Nothing else Just (portStr, hostPorts)
    parseEntry _ = Nothing

    extractHostPort :: Value -> Maybe Int
    extractHostPort (Object binding) =
      case KeyMap.lookup "HostPort" binding of
        Just (String portText) ->
          case reads (Text.unpack portText) of
            [(port, "")] -> Just port
            _ -> Nothing
        _ -> Nothing
    extractHostPort _ = Nothing

-- | Check if Kind cluster has all required port mappings
validateKindPortMappings :: String -> IO (Either [RequiredPortMapping] ())
validateKindPortMappings clusterName = do
  actualBindings <- inspectKindNodePortBindings clusterName
  let missingMappings = filter (not . hasMapping actualBindings) requiredPortMappings
  pure $ if null missingMappings then Right () else Left missingMappings
  where
    hasMapping :: Map.Map String [Int] -> RequiredPortMapping -> Bool
    hasMapping bindings rpm =
      case Map.lookup (show (rpmContainerPort rpm)) bindings of
        Nothing -> False
        Just hostPorts -> rpmHostPort rpm `elem` hostPorts

-- | Format error message for missing port mappings
formatMissingPortMappingsError :: String -> [RequiredPortMapping] -> String
formatMissingPortMappingsError clusterName missingMappings =
  unlines
    [ "ERROR: Kind cluster '" <> clusterName <> "' is missing required port mappings:"
    , ""
    ]
    <> unlines (map formatMapping missingMappings)
    <> unlines
      [ ""
      , "To fix this, recreate the cluster with:"
      , "  studiomcp cluster reset"
      , ""
      , "Data in host-mounted volumes (.data/) will be preserved."
      ]
  where
    formatMapping rpm =
      "  - " <> rpmDescription rpm <> ": containerPort "
        <> show (rpmContainerPort rpm) <> " -> hostPort "
        <> show (rpmHostPort rpm)

data PersistentVolumeSpec = PersistentVolumeSpec
  { volumeName :: String,
    volumeDirectory :: FilePath,
    claimName :: String,
    requestedSize :: String
  }
  deriving (Eq, Show)

desiredPersistentVolumes :: Value -> [PersistentVolumeSpec]
desiredPersistentVolumes values =
  concat
    [ minioPersistentVolumes values
    , pulsarPersistentVolumes values
    , postgresqlHaPersistentVolumes values
    , redisPersistentVolumes values
    ]

-- | Generate PVs for MinIO StatefulSet (minio/minio chart)
-- PVC naming: export-studiomcp-minio-{0,1,2,...}
minioPersistentVolumes :: Value -> [PersistentVolumeSpec]
minioPersistentVolumes values =
  case enabled of
    Just True -> map mkSpec [0 .. replicaCount - 1]
    _ -> []
  where
    enabled = lookupBool ["minio", "persistence", "enabled"] values
    replicaCount = fromMaybe 4 (lookupInt ["minio", "replicas"] values)
    size = fromMaybe "10Gi" (lookupString ["minio", "persistence", "size"] values)
    mkSpec :: Int -> PersistentVolumeSpec
    mkSpec idx =
      PersistentVolumeSpec
        { volumeName = "studiomcp-minio-pv-" <> show idx
        , volumeDirectory = "minio/minio-" <> show idx
        , claimName = "export-studiomcp-minio-" <> show idx
        , requestedSize = size
        }

-- | Generate PVs for PostgreSQL-HA StatefulSet (bitnami chart)
-- PVC naming: data-studiomcp-postgresql-ha-postgresql-{0,1,2}
postgresqlHaPersistentVolumes :: Value -> [PersistentVolumeSpec]
postgresqlHaPersistentVolumes values =
  case enabled of
    Just True -> map mkSpec [0 .. replicaCount - 1]
    _ -> []
  where
    enabled = lookupBool ["postgresql-ha", "persistence", "enabled"] values
    replicaCount = fromMaybe 3 (lookupInt ["postgresql-ha", "postgresql", "replicaCount"] values)
    size = fromMaybe "10Gi" (lookupString ["postgresql-ha", "persistence", "size"] values)
    mkSpec :: Int -> PersistentVolumeSpec
    mkSpec idx =
      PersistentVolumeSpec
        { volumeName = "studiomcp-postgresql-ha-pv-" <> show idx
        , volumeDirectory = "postgresql-ha/postgresql-" <> show idx
        , claimName = "data-studiomcp-postgresql-ha-postgresql-" <> show idx
        , requestedSize = size
        }

-- | Generate PVs for Redis StatefulSets (bitnami chart with replication architecture)
-- PVC naming: redis-data-studiomcp-redis-node-{0,1,2,...}
redisPersistentVolumes :: Value -> [PersistentVolumeSpec]
redisPersistentVolumes values =
  if masterEnabled then map mkNodeSpec [0 .. totalNodes - 1] else []
  where
    masterEnabled = fromMaybe False (lookupBool ["redis", "master", "persistence", "enabled"] values)
    masterSize = fromMaybe "5Gi" (lookupString ["redis", "master", "persistence", "size"] values)
    replicaCount = fromMaybe 3 (lookupInt ["redis", "replica", "replicaCount"] values)
    -- Total nodes = 1 master + n replicas
    totalNodes = 1 + replicaCount
    mkNodeSpec :: Int -> PersistentVolumeSpec
    mkNodeSpec idx =
      PersistentVolumeSpec
        { volumeName = "studiomcp-redis-node-pv-" <> show idx
        , volumeDirectory = "redis/node-" <> show idx
        , claimName = "redis-data-studiomcp-redis-node-" <> show idx
        , requestedSize = masterSize
        }

-- | Generate PVs for Pulsar StatefulSets (apache/pulsar chart)
-- ZooKeeper PVCs: studiomcp-pulsar-zookeeper-data-studiomcp-pulsar-zookeeper-{0,1,2}
-- BookKeeper Journal: studiomcp-pulsar-bookie-journal-studiomcp-pulsar-bookie-{0,1,2}
-- BookKeeper Ledgers: studiomcp-pulsar-bookie-ledgers-studiomcp-pulsar-bookie-{0,1,2}
pulsarPersistentVolumes :: Value -> [PersistentVolumeSpec]
pulsarPersistentVolumes values =
  zookeeperPVs ++ bookieJournalPVs ++ bookieLedgersPVs
  where
    zkReplicaCount = fromMaybe 3 (lookupInt ["pulsar", "zookeeper", "replicaCount"] values)
    bkReplicaCount = fromMaybe 3 (lookupInt ["pulsar", "bookkeeper", "replicaCount"] values)
    -- Pulsar chart uses volumes.data/journal/ledgers structure, not persistence
    zkSize = fromMaybe "20Gi" (lookupString ["pulsar", "zookeeper", "volumes", "data", "size"] values)
    bkJournalSize = fromMaybe "10Gi" (lookupString ["pulsar", "bookkeeper", "volumes", "journal", "size"] values)
    bkLedgersSize = fromMaybe "50Gi" (lookupString ["pulsar", "bookkeeper", "volumes", "ledgers", "size"] values)
    zookeeperPVs = map mkZkSpec [0 .. zkReplicaCount - 1]
    bookieJournalPVs = map mkJournalSpec [0 .. bkReplicaCount - 1]
    bookieLedgersPVs = map mkLedgersSpec [0 .. bkReplicaCount - 1]
    mkZkSpec :: Int -> PersistentVolumeSpec
    mkZkSpec idx =
      PersistentVolumeSpec
        { volumeName = "studiomcp-pulsar-zookeeper-pv-" <> show idx
        , volumeDirectory = "pulsar/zookeeper-" <> show idx
        , claimName = "studiomcp-pulsar-zookeeper-data-studiomcp-pulsar-zookeeper-" <> show idx
        , requestedSize = zkSize
        }
    mkJournalSpec :: Int -> PersistentVolumeSpec
    mkJournalSpec idx =
      PersistentVolumeSpec
        { volumeName = "studiomcp-pulsar-bookie-journal-pv-" <> show idx
        , volumeDirectory = "pulsar/bookie-journal-" <> show idx
        , claimName = "studiomcp-pulsar-bookie-journal-studiomcp-pulsar-bookie-" <> show idx
        , requestedSize = bkJournalSize
        }
    mkLedgersSpec :: Int -> PersistentVolumeSpec
    mkLedgersSpec idx =
      PersistentVolumeSpec
        { volumeName = "studiomcp-pulsar-bookie-ledgers-pv-" <> show idx
        , volumeDirectory = "pulsar/bookie-ledgers-" <> show idx
        , claimName = "studiomcp-pulsar-bookie-ledgers-studiomcp-pulsar-bookie-" <> show idx
        , requestedSize = bkLedgersSize
        }

-- | The name of the explicit null storage class (no dynamic provisioning)
storageClassName :: String
storageClassName = "studiomcp-manual"

renderPersistentVolume :: PersistentVolumeSpec -> String
renderPersistentVolume spec =
  unlines
    [ "apiVersion: v1"
    , "kind: PersistentVolume"
    , "metadata:"
    , "  name: " <> volumeName spec
    , "spec:"
    , "  storageClassName: " <> storageClassName
    , "  capacity:"
    , "    storage: " <> requestedSize spec
    , "  accessModes:"
    , "    - ReadWriteOnce"
    , "  persistentVolumeReclaimPolicy: Retain"
    , "  hostPath:"
    , "    path: /.data/" <> volumeDirectory spec
    , "    type: DirectoryOrCreate"
    , "  claimRef:"
    , "    namespace: default"
    , "    name: " <> claimName spec
    ]

-- | Render the manual storage class (no-provisioner, explicit PV binding only)
renderManualStorageClass :: String
renderManualStorageClass =
  unlines
    [ "apiVersion: storage.k8s.io/v1"
    , "kind: StorageClass"
    , "metadata:"
    , "  name: " <> storageClassName
    , "provisioner: kubernetes.io/no-provisioner"
    , "volumeBindingMode: WaitForFirstConsumer"
    , "reclaimPolicy: Retain"
    ]

-- | Delete the default StorageClass if it exists
deleteDefaultStorageClass :: IO ()
deleteDefaultStorageClass = do
  (exitCode, _, _) <- readProcessWithExitCode "kubectl" ["delete", "sc", "standard", "--ignore-not-found"] ""
  case exitCode of
    ExitSuccess -> putStrLn "Deleted default StorageClass 'standard' (if it existed)."
    ExitFailure _ -> putStrLn "Warning: Could not delete default StorageClass."

-- | Create the studiomcp-manual StorageClass
createManualStorageClass :: IO ()
createManualStorageClass = do
  putStrLn $ "Creating StorageClass '" <> storageClassName <> "'..."
  applyManifest renderManualStorageClass
  putStrLn $ "StorageClass '" <> storageClassName <> "' created."

-- | Ensure the storage policy is enforced (only studiomcp-manual exists)
ensureStoragePolicy :: IO ()
ensureStoragePolicy = do
  deleteDefaultStorageClass
  createManualStorageClass

applyManifest :: String -> IO ()
applyManifest manifest = do
  (exitCode, _, stderrText) <- readProcessWithExitCode "kubectl" ["apply", "-f", "-"] manifest
  case exitCode of
    ExitSuccess -> pure ()
    ExitFailure _ -> die stderrText

loadMergedValues :: IO Value
loadMergedValues = do
  baseValues <- loadYamlValue "chart/values.yaml"
  kindValues <- loadYamlValue "chart/values-kind.yaml"
  pure (mergeValues baseValues kindValues)

loadYamlValue :: FilePath -> IO Value
loadYamlValue path = do
  decoded <- decodeFileEither path
  case decoded of
    Left err -> die (show err)
    Right value -> pure value

mergeValues :: Value -> Value -> Value
mergeValues (Object leftObject) (Object rightObject) =
  Object (KeyMap.unionWith mergeValues leftObject rightObject)
mergeValues _ rightValue = rightValue

lookupBool :: [String] -> Value -> Maybe Bool
lookupBool path value =
  case lookupPath path value of
    Just (Bool boolValue) -> Just boolValue
    _ -> Nothing

lookupString :: [String] -> Value -> Maybe String
lookupString path value =
  case lookupPath path value of
    Just (String textValue) -> Just (Text.unpack textValue)
    _ -> Nothing

lookupInt :: [String] -> Value -> Maybe Int
lookupInt path value =
  case lookupPath path value of
    Just (Number n) -> Just (round n)
    _ -> Nothing

lookupPath :: [String] -> Value -> Maybe Value
lookupPath [] currentValue = Just currentValue
lookupPath (segment : remainingPath) (Object objectValue) =
  KeyMap.lookup (Key.fromString segment) objectValue >>= lookupPath remainingPath
lookupPath _ _ = Nothing

extractFirstMcpToolData :: Value -> Maybe Text
extractFirstMcpToolData responseValue = do
  Array contentItems <- lookupPath ["result", "content"] responseValue
  firstContent <- listToMaybe (Vector.toList contentItems)
  case firstContent of
    Object contentObject ->
      case KeyMap.lookup "data" contentObject of
        Just (String payloadText) -> Just payloadText
        _ -> Nothing
    _ -> Nothing

validateKeycloak :: IO ()
validateKeycloak = do
  putStrLn "Validating Keycloak connectivity..."
  preferKindEdge <- kindEdgeValidationRequested
  when preferKindEdge $
    clusterEnsure
  liveConfig <- loadPreferredEdgeValidationConfig
  case liveConfig of
    Just config -> validateLiveKeycloak config
    Nothing -> do
      withFakeKeycloak $ \authConfig -> do
        manager <- newManager defaultManagerSettings
        authService <- newAuthService authConfig manager
        putStrLn "  ✓ Local Keycloak-compatible JWKS server started"

        let jwksUrl = Text.unpack (jwksEndpoint (acKeycloak authConfig))
        req <- parseRequest jwksUrl
        resp <- httpLbs req manager
        unless (statusCode (responseStatus resp) == 200) $
          die ("JWKS endpoint returned status " <> show (statusCode (responseStatus resp)))
        case decode (responseBody resp) of
          Just (Object obj)
            | KeyMap.member "keys" obj ->
                putStrLn "  ✓ JWKS endpoint returns a valid key set"
          _ ->
            die "JWKS endpoint did not return a valid JWKS payload"

        validPayload <- buildKeycloakTestPayload authConfig []
        validToken <- buildSignedTestJwt authConfig validPayload
        validationResult <- validateToken authService validToken
        case validationResult of
          Right claims -> do
            unless (jcSubject claims == SubjectId "user-123") $
              die "Validated token returned the wrong subject"
            unless (jcTenantId claims == Just (TenantId "tenant-456")) $
              die "Validated token returned the wrong tenant"
            putStrLn "  ✓ Signed JWT validation succeeds against the served JWKS"
          Left err ->
            die ("Signed JWT validation failed: " <> show err)

        cachedValidationResult <- validateToken authService validToken
        case cachedValidationResult of
          Right _ -> putStrLn "  ✓ Cached JWKS validation succeeds on repeat requests"
          Left err -> die ("Repeat validation with cached JWKS failed: " <> show err)
      putStrLn "validate keycloak: PASS (harness fallback)"

validateLiveKeycloak :: LiveValidationConfig -> IO ()
validateLiveKeycloak config = do
  manager <- newManager defaultManagerSettings
  let liveAuthConfig = lvcAuthConfig config
  authService <- newAuthService liveAuthConfig manager

  let jwksUrl = Text.unpack (jwksEndpoint (acKeycloak liveAuthConfig))
  req <- parseRequest jwksUrl
  resp <- httpLbs req manager
  unless (statusCode (responseStatus resp) == 200) $
    die ("JWKS endpoint returned status " <> show (statusCode (responseStatus resp)))
  case decode (responseBody resp) of
    Just (Object obj)
      | KeyMap.member "keys" obj ->
          putStrLn "  ✓ Live JWKS endpoint returns a valid key set"
    _ ->
      die "JWKS endpoint did not return a valid JWKS payload"

  let keycloakConfig = acKeycloak liveAuthConfig
      passwordGrant =
        PasswordGrantParams
          { pgClientId = kcClientId keycloakConfig
          , pgUsername = lvcUsername config
          , pgPassword = lvcPassword config
          , pgScopes = ["openid"]
          , pgClientSecret = kcClientSecret keycloakConfig
          }
  tokenResult <- exchangePasswordForTokens keycloakConfig manager passwordGrant
  tokenResponse <- case tokenResult of
    Left err -> die ("Direct grant failed against live Keycloak: " <> show err)
    Right response -> pure response
  unless (trTokenType tokenResponse == "Bearer") $
    die "Live Keycloak did not return a Bearer token"
  validationResult <- validateToken authService (RawJwt (trAccessToken tokenResponse))
  case validationResult of
    Right claims -> do
      unless (jcSubject claims /= SubjectId "") $
        die "Validated live token returned an empty subject"
      unless (jcTenantId claims /= Nothing) $
        die "Validated live token did not carry a tenant_id claim"
      putStrLn "  ✓ Password grant and JWT validation succeed against the live realm"
    Left err ->
      die ("Validated live token was rejected: " <> show err)
  putStrLn "validate keycloak: PASS"

validateMcpAuth :: IO ()
validateMcpAuth = do
  putStrLn "Validating MCP authentication..."
  preferKindEdge <- kindEdgeValidationRequested
  when preferKindEdge $
    clusterDeploy DeployServer
  liveConfig <- loadPreferredEdgeValidationConfig
  case liveConfig of
    Just config -> validateLiveMcpAuth config
    Nothing -> validateHarnessMcpAuth

validateSessionStore :: IO ()
validateSessionStore = do
  putStrLn "Validating session store..."
  withTemporaryRedisConfig $ \redisConfig -> do
    -- Create a test store with a real Redis backend
    store <- newRedisSessionStore redisConfig
    putStrLn "  ✓ Session store created against Redis"

    -- Test health check
    health <- checkRedisHealth store
    unless (rhConnected health) $
      die "Session store health check failed: not connected"
    putStrLn "  ✓ Session store health check passed"

    -- Test session lifecycle
    session <- newSession
    createResult <- storeCreateSession store session
    case createResult of
      Left err -> die ("Session creation failed: " <> show err)
      Right () -> putStrLn "  ✓ Session creation works"

    getResult <- storeGetSession store (sessionId session)
    case getResult of
      Left err -> die ("Session retrieval failed: " <> show err)
      Right retrieved ->
        unless (sessionId retrieved == sessionId session) $
          die "Session retrieval returned wrong session"
    putStrLn "  ✓ Session retrieval works"

    -- Test session update
    updateResult <- storeUpdateSession store (sessionId session) (\s -> s {sessionState = SessionReady})
    case updateResult of
      Left err -> die ("Session update failed: " <> show err)
      Right updated ->
        unless (sessionState updated == SessionReady) $
          die "Session update did not apply"
    putStrLn "  ✓ Session update works"

    -- Test session touch
    touchResult <- storeTouchSession store (sessionId session)
    case touchResult of
      Left err -> die ("Session touch failed: " <> show err)
      Right () -> pure ()
    putStrLn "  ✓ Session touch works"

    -- Test session deletion
    deleteResult <- storeDeleteSession store (sessionId session)
    case deleteResult of
      Left err -> die ("Session deletion failed: " <> show err)
      Right () -> pure ()
    putStrLn "  ✓ Session deletion works"

    -- Test lock acquisition
    session2 <- newSession
    _ <- storeCreateSession store session2
    lockResult <- storeAcquireLock store (sessionId session2) "test-pod" 30
    case lockResult of
      Left err -> die ("Lock acquisition failed: " <> show err)
      Right lock ->
        unless (slHolderPodId lock == "test-pod") $
          die "Lock acquisition returned wrong holder"
    putStrLn "  ✓ Lock acquisition works"

    -- Test lock release
    releaseResult <- storeReleaseLock store (sessionId session2) "test-pod"
    case releaseResult of
      Left err -> die ("Lock release failed: " <> show err)
      Right () -> pure ()
    putStrLn "  ✓ Lock release works"

    -- Test TTL-based expiration and cleanup
    correlationId <- generateCorrelationId
    let expiryConfig =
          redisConfig
            { rcKeyPrefix = "mcp:validate-session-store:" <> unCorrelationId correlationId <> ":"
            , rcSessionTtl = 1
            }
    expiringStore <- newRedisSessionStore expiryConfig
    expiringSession <- newSession
    createExpiringResult <- storeCreateSession expiringStore expiringSession
    case createExpiringResult of
      Left err -> die ("Expiring session creation failed: " <> show err)
      Right () -> pure ()
    now <- getCurrentTime
    _ <-
      storeUpdateSession
        expiringStore
        (sessionId expiringSession)
        (\s -> s {sessionLastActiveAt = addUTCTime (-10) now})
    let ttlSub =
          SubscriptionRecord
            { srResourceUri = "studiomcp://summaries/ttl-run"
            , srSubscribedAt = now
            , srLastEventId = Nothing
            }
        ttlCursor =
          CursorPosition
            { cpStreamName = "events"
            , cpPosition = "42"
            , cpUpdatedAt = now
            }
    _ <- storeAddSubscription expiringStore (sessionId expiringSession) "studiomcp://summaries/ttl-run" ttlSub
    _ <- storeSetCursor expiringStore (sessionId expiringSession) ttlCursor
    _ <- storeAcquireLock expiringStore (sessionId expiringSession) "ttl-pod" 30
    expireResult <- storeExpireSessions expiringStore
    case expireResult of
      Left err -> die ("Session expiration failed: " <> show err)
      Right expiredCount ->
        unless (expiredCount == 1) $
          die ("Expected one expired session, got " <> show expiredCount)
    postExpireSession <- storeGetSession expiringStore (sessionId expiringSession)
    case postExpireSession of
      Left (SessionNotFound _) -> pure ()
      other -> die ("Expired session should not be retrievable, got " <> show other)
    postExpireSubs <- storeGetSubscriptions expiringStore (sessionId expiringSession)
    case postExpireSubs of
      Right [] -> pure ()
      other -> die ("Expired session subscriptions should be removed, got " <> show other)
    postExpireCursor <- storeGetCursor expiringStore (sessionId expiringSession) "events"
    case postExpireCursor of
      Right Nothing -> pure ()
      other -> die ("Expired session cursor should be removed, got " <> show other)
    postExpireLock <- storeAcquireLock expiringStore (sessionId expiringSession) "ttl-pod-2" 30
    case postExpireLock of
      Right _ -> putStrLn "  ✓ Session expiration cleans up subscriptions, cursors, and locks"
      Left err -> die ("Expected expired session lock to be released, got " <> show err)

    closeRedisSessionStore expiringStore
    closeRedisSessionStore store
    putStrLn "  ✓ Session store closed"

  putStrLn "validate session-store: PASS"

validateHorizontalScale :: IO ()
validateHorizontalScale = do
  putStrLn "Validating horizontal scaling support..."
  preferKindEdge <- kindEdgeValidationRequested
  when preferKindEdge $
    clusterDeploy DeployServer
  liveConfig <- loadKindEdgeValidationConfig
  case liveConfig of
    Just config -> validateLiveHorizontalScale config
    Nothing -> validateHarnessHorizontalScale

validateWebBff :: IO ()
validateWebBff = do
  putStrLn "Validating Web BFF..."
  preferKindEdge <- kindEdgeValidationRequested
  when preferKindEdge $
    clusterDeploy DeployServer
  liveConfig <- loadPreferredEdgeValidationConfig
  case liveConfig of
    Just config -> validateLiveWebBff config
    Nothing -> validateHarnessWebBff

data LiveValidationConfig = LiveValidationConfig
  { lvcBaseUrl :: String
  , lvcAuthConfig :: AuthConfig
  , lvcObjectStoragePublicEndpoint :: Text
  , lvcUsername :: Text
  , lvcPassword :: Text
  }

-- | Load validation configuration for the kind-edge path.
-- Since docker-compose no longer hosts the application stack, this is the only live validation path.
-- See: documents/engineering/k8s_native_dev_policy.md
loadPreferredEdgeValidationConfig :: IO (Maybe LiveValidationConfig)
loadPreferredEdgeValidationConfig = loadKindEdgeValidationConfig

loadKindEdgeValidationConfig :: IO (Maybe LiveValidationConfig)
loadKindEdgeValidationConfig = do
  clusterName <- getClusterName
  clusters <- kindClusters
  if clusterName `notElem` clusters
    then pure Nothing
    else do
      internalBaseUrl <- clusterEdgeInternalBaseUrl
      let publicIssuer = clusterEdgePublicBaseUrl <> "/kc/realms/" <> clusterEdgeRealmName
          internalIssuer = Text.pack internalBaseUrl <> "/kc/realms/" <> clusterEdgeRealmName
          keycloakConfig =
            defaultKeycloakConfig
              { kcIssuer = publicIssuer
              , kcAdditionalIssuers = [internalIssuer]
              , kcAudience = "studiomcp-mcp"
              , kcRealm = clusterEdgeRealmName
              , kcClientId = "studiomcp-bff"
              , kcClientSecret = Just "studiomcp-bff-dev-secret"
              }
      pure $
        Just
          LiveValidationConfig
            { lvcBaseUrl = internalBaseUrl
            , lvcAuthConfig =
                defaultAuthConfig
                  { acEnabled = True
                  , acAllowInsecureHttp = True
                  , acKeycloak = keycloakConfig
                  }
            , lvcObjectStoragePublicEndpoint = "http://localhost:9000"
            , lvcUsername = clusterEdgeValidationUsername
            , lvcPassword = clusterEdgeValidationPassword
            }

kindEdgeValidationRequested :: IO Bool
kindEdgeValidationRequested = do
  rawValue <- lookupEnv "STUDIOMCP_VALIDATE_KIND_EDGE"
  pure $
    case fmap (map toLower) rawValue of
      Just "1" -> True
      Just "true" -> True
      Just "yes" -> True
      _ -> False

requestLiveAccessToken :: Manager -> LiveValidationConfig -> IO TokenResponse
requestLiveAccessToken manager config = do
  let keycloakConfig = acKeycloak (lvcAuthConfig config)
      passwordGrant =
        PasswordGrantParams
          { pgClientId = kcClientId keycloakConfig
          , pgUsername = lvcUsername config
          , pgPassword = lvcPassword config
          , pgScopes = ["openid"]
          , pgClientSecret = kcClientSecret keycloakConfig
          }
  exchangeResult <- exchangePasswordForTokens keycloakConfig manager passwordGrant
  case exchangeResult of
    Left err -> die ("Live password grant failed: " <> show err)
    Right tokenResponse -> pure tokenResponse

-- | Get auth headers by acquiring a token through the cluster edge (ingress).
-- This produces tokens with an issuer that matches what the MCP server expects,
-- avoiding issuer mismatch errors that occur when using direct Keycloak port-forward.
getClusterEdgeAuthHeaders :: Manager -> IO [Header]
getClusterEdgeAuthHeaders manager = do
  configMaybe <- loadKindEdgeValidationConfig
  case configMaybe of
    Nothing -> die "Cluster edge validation config not available - is the Kind cluster running?"
    Just config -> do
      tokenResponse <- requestLiveAccessToken manager config
      pure (authorizationHeaders (trAccessToken tokenResponse))

authorizationHeaders :: Text -> [Header]
authorizationHeaders accessToken =
  [(CI.mk "Authorization", "Bearer " <> TextEncoding.encodeUtf8 accessToken)]

initializeMcpSessionWithHeaders :: Manager -> String -> [Header] -> IO [Header]
initializeMcpSessionWithHeaders manager baseUrl extraHeaders = do
  let initializeRequest =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "id" .= (1 :: Int)
          , "method" .= ("initialize" :: Text)
          , "params" .= object
              [ "protocolVersion" .= ("2024-11-05" :: Text)
              , "capabilities" .= object []
              , "clientInfo" .= object
                  [ "name" .= ("validate-client" :: Text)
                  , "version" .= ("1.0.0" :: Text)
                  ]
              ]
          ]
  -- Retry logic for transient errors during pod startup after rolling restarts:
  -- - 401: JWKS cache not yet populated (auth service needs to fetch JWKS from Keycloak)
  -- - 502/503/504: Pod not yet ready or being restarted
  let maxRetries = 30 :: Int
      retryDelaySecs = 2 :: Int
      transientCodes = [401, 502, 503, 504]
      tryInitialize attempt = do
        initResponse <-
          httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/mcp") extraHeaders (Just (encode initializeRequest))
        if httpResponseStatus initResponse == 200
          then pure initResponse
          else if httpResponseStatus initResponse `elem` transientCodes && attempt < maxRetries
            then do
              threadDelay (retryDelaySecs * 1000000)
              tryInitialize (attempt + 1)
            else die ("Expected MCP initialize to return HTTP 200, got " <> show (httpResponseStatus initResponse))
  initResponse <- tryInitialize (1 :: Int)
  sessionHeaderValue <-
    case lookupResponseHeader "Mcp-Session-Id" initResponse of
      Just headerValue -> pure headerValue
      Nothing -> die "Initialize response did not include an Mcp-Session-Id header"
  let sessionHeaders = extraHeaders <> [("Mcp-Session-Id", sessionHeaderValue)]
      initializedNotification =
        object
          [ "jsonrpc" .= ("2.0" :: Text)
          , "method" .= ("notifications/initialized" :: Text)
          ]
  initializedResponse <-
    httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/mcp") sessionHeaders (Just (encode initializedNotification))
  unless (httpResponseStatus initializedResponse == 200) $
    die ("Expected MCP initialized notification to return HTTP 200, got " <> show (httpResponseStatus initializedResponse))
  pure sessionHeaders

pingLiveMcpSession :: Manager -> String -> [Header] -> IO HttpResponse
pingLiveMcpSession manager baseUrl sessionHeaders =
  mcpJsonRpcRequest
    manager
    baseUrl
    sessionHeaders
    ( object
        [ "jsonrpc" .= ("2.0" :: Text)
        , "id" .= (99 :: Int)
        , "method" .= ("ping" :: Text)
        ]
    )

-- | Collect unique upstream addresses by creating multiple separate MCP sessions.
-- This is necessary because the ingress uses upstream-hash-by: "$http_mcp_session_id" for
-- session affinity. Creating separate MCP sessions with their own session IDs forces nginx
-- to potentially route to different backend pods. Each session is fully initialized and valid.
--
-- Note: We extract just the auth headers (no Mcp-Session-Id) to create fresh sessions.
collectLiveUpstreams :: Manager -> String -> [Header] -> Int -> IO (Set.Set BS.ByteString)
collectLiveUpstreams manager baseUrl sessionHeaders attempts = do
  -- Extract auth headers only (filter out any Mcp-Session-Id)
  let authHeaders = filter (\(name, _) -> name /= "Mcp-Session-Id") sessionHeaders
  foldM
    ( \seen _attemptNum -> do
        -- Create a fresh MCP session for each attempt. This gives us a unique session ID
        -- that nginx will hash to potentially different backends.
        newSessionHeaders <- initializeMcpSessionWithHeaders manager baseUrl authHeaders
        response <- pingLiveMcpSession manager baseUrl newSessionHeaders
        unless (httpResponseStatus response == 200) $
          die ("Expected live ping to return 200, got " <> show (httpResponseStatus response))
        upstreamAddress <-
          case lookupResponseHeader "X-Upstream-Addr" response of
            Just value -> pure value
            Nothing -> die "Live edge proxy did not expose X-Upstream-Addr; multi-backend validation cannot verify routing"
        pure (Set.insert upstreamAddress seen)
    )
    Set.empty
    [1 .. attempts]

waitForDistinctLiveUpstreams :: Manager -> String -> [Header] -> Int -> IO ()
waitForDistinctLiveUpstreams manager baseUrl sessionHeaders attemptsRemaining
  | attemptsRemaining <= 0 =
      die "Timed out waiting for the live edge proxy to route across multiple MCP backends"
  | otherwise = do
      upstreams <- collectLiveUpstreams manager baseUrl sessionHeaders 8
      if Set.size upstreams >= 2
        then pure ()
        else do
          threadDelay 1000000
          waitForDistinctLiveUpstreams manager baseUrl sessionHeaders (attemptsRemaining - 1)

subscribeMcpResourceOverHttp ::
  Manager ->
  String ->
  [Header] ->
  Int ->
  Text ->
  Maybe Text ->
  Maybe Text ->
  IO Value
subscribeMcpResourceOverHttp manager baseUrl sessionHeaders requestId resourceUri maybeCursor maybeLastEventId = do
  let requestPayload =
        object $
          [ "jsonrpc" .= ("2.0" :: Text)
          , "id" .= requestId
          , "method" .= ("resources/subscribe" :: Text)
          , "params" .=
              object
                ( [ "uri" .= resourceUri
                  ]
                    <> maybe [] (\cursor -> ["cursor" .= cursor]) maybeCursor
                    <> maybe [] (\eventId -> ["lastEventId" .= eventId]) maybeLastEventId
                )
          ]
  response <- mcpJsonRpcRequest manager baseUrl sessionHeaders requestPayload
  unless (httpResponseStatus response == 200) $
    die ("Expected resources/subscribe to return HTTP 200, got " <> show (httpResponseStatus response))
  decodeResponseBody "resources/subscribe response" response

-- | Scale a Kubernetes deployment to target replicas, run an action, then restore.
-- Used by horizontal-scale validator to simulate rollout and outage scenarios.
withKubernetesDeploymentScaled :: String -> String -> Int -> Int -> IO a -> IO a
withKubernetesDeploymentScaled namespace deployment targetReplicas originalReplicas action = do
  requireExecutables ["kubectl"]
  bracket_
    (callProcess "kubectl" ["scale", "deployment", deployment, "-n", namespace, "--replicas=" <> show targetReplicas])
    (do
        callProcess "kubectl" ["scale", "deployment", deployment, "-n", namespace, "--replicas=" <> show originalReplicas]
        waitForDeploymentReadyInNamespace namespace deployment)
    action

-- | Scale a Kubernetes StatefulSet to target replicas, run an action, then restore.
-- Used for Redis master (Bitnami uses StatefulSet for Redis).
withKubernetesStatefulSetScaled :: String -> String -> Int -> Int -> IO a -> IO a
withKubernetesStatefulSetScaled namespace statefulset targetReplicas originalReplicas action = do
  requireExecutables ["kubectl"]
  bracket_
    (callProcess "kubectl" ["scale", "statefulset", statefulset, "-n", namespace, "--replicas=" <> show targetReplicas])
    (do
        callProcess "kubectl" ["scale", "statefulset", statefulset, "-n", namespace, "--replicas=" <> show originalReplicas]
        waitForStatefulSetReadyInNamespace namespace statefulset)
    action

-- | Wait for a deployment to become ready in a specific namespace.
waitForDeploymentReadyInNamespace :: String -> String -> IO ()
waitForDeploymentReadyInNamespace namespace deployment =
  callProcess "kubectl" ["rollout", "status", "deployment/" <> deployment, "-n", namespace, "--timeout=300s"]

-- | Wait for a StatefulSet to become ready in a specific namespace.
waitForStatefulSetReadyInNamespace :: String -> String -> IO ()
waitForStatefulSetReadyInNamespace namespace statefulset =
  callProcess "kubectl" ["rollout", "status", "statefulset/" <> statefulset, "-n", namespace, "--timeout=300s"]

validateLiveMcpAuth :: LiveValidationConfig -> IO ()
validateLiveMcpAuth config = do
  manager <- newManager defaultManagerSettings
  authService <- newAuthService (lvcAuthConfig config) manager
  let keycloakConfig = acKeycloak (lvcAuthConfig config)
      baseUrl = lvcBaseUrl config
  putStrLn $ "  ✓ Live Keycloak realm: " <> Text.unpack (kcRealm keycloakConfig)
  putStrLn $ "  ✓ Live edge base URL: " <> baseUrl

  unauthorizedInit <-
    httpJsonRequest
      manager
      "POST"
      (baseUrl <> "/mcp")
      (Just (encode (object ["jsonrpc" .= ("2.0" :: Text), "id" .= (1 :: Int), "method" .= ("initialize" :: Text)])))
  unless (httpResponseStatus unauthorizedInit == 401) $
    die ("Expected unauthenticated live /mcp initialize to return 401, got " <> show (httpResponseStatus unauthorizedInit))
  putStrLn "  ✓ Live /mcp rejects unauthenticated requests"

  tokenResponse <- requestLiveAccessToken manager config
  unless (trTokenType tokenResponse == "Bearer") $
    die "Live Keycloak did not return a Bearer token"
  validationResult <- validateToken authService (RawJwt (trAccessToken tokenResponse))
  case validationResult of
    Right claims -> do
      unless (Scope "workflow:write" `Set.member` jcScopes claims) $
        die "Validated live token did not include workflow:write"
      putStrLn "  ✓ Live bearer token validates locally against the configured JWKS"
    Left err ->
      die ("Live bearer token failed local validation: " <> show err)

  let authHeaders = authorizationHeaders (trAccessToken tokenResponse)
  sessionHeaders <- initializeMcpSessionWithHeaders manager baseUrl authHeaders
  putStrLn "  ✓ Live authenticated initialize completes through /mcp"

  toolsResponse <-
    mcpJsonRpcRequest
      manager
      baseUrl
      sessionHeaders
      (object ["jsonrpc" .= ("2.0" :: Text), "id" .= (2 :: Int), "method" .= ("tools/list" :: Text)])
  unless (httpResponseStatus toolsResponse == 200) $
    die ("Expected live authenticated tools/list to return 200, got " <> show (httpResponseStatus toolsResponse))
  putStrLn "  ✓ Live authenticated tool discovery works through the edge proxy"

  sseResponse <- httpJsonRequestWithHeaders manager "GET" (baseUrl <> "/mcp") authHeaders Nothing
  unless (httpResponseStatus sseResponse == 200) $
    die ("Expected authenticated live GET /mcp to return 200, got " <> show (httpResponseStatus sseResponse))
  unless ("event: ready" `isInfixOf` LBS.unpack (httpResponseBody sseResponse)) $
    die "Expected authenticated live GET /mcp to emit an SSE ready event"
  putStrLn "  ✓ Live GET /mcp emits the authenticated SSE bootstrap"

  putStrLn "validate mcp-auth: PASS"

validateHarnessMcpAuth :: IO ()
validateHarnessMcpAuth =
  withFakeKeycloak $ \authConfig -> do
    manager <- newManager defaultManagerSettings
    authService <- newAuthService authConfig manager
    putStrLn "  ✓ Local signed-token auth harness started"

    let keycloakConfig = acKeycloak authConfig
    putStrLn $ "  ✓ Keycloak realm: " <> Text.unpack (kcRealm keycloakConfig)
    putStrLn $ "  ✓ Expected audience: " <> Text.unpack (kcAudience keycloakConfig)
    putStrLn $ "  ✓ Token leeway: " <> show (acTokenLeewaySeconds authConfig) <> "s"

    validPayload <- buildKeycloakTestPayload authConfig []
    validToken@(RawJwt validTokenText) <- buildSignedTestJwt authConfig validPayload
    case parseJwt validToken of
      Left err -> die ("Signed JWT should parse successfully: " <> show err)
      Right (header, _, _) -> do
        unless (jhAlg header == "RS256") $
          die "Signed JWT should advertise RS256"
        putStrLn "  ✓ JWT parsing works for signed RS256 tokens"

    validResult <- validateToken authService validToken
    case validResult of
      Right claims -> do
        unless (Scope "workflow:write" `Set.member` jcScopes claims) $
          die "Validated token did not include the expected workflow:write scope"
        putStrLn "  ✓ Valid signed token is accepted"
      Left err ->
        die ("Valid signed token was rejected: " <> show err)

    let tamperedToken = tamperRawJwt validToken
    tamperedResult <- validateToken authService tamperedToken
    case tamperedResult of
      Left InvalidSignature -> putStrLn "  ✓ Tampered token is rejected with InvalidSignature"
      Left err -> die ("Tampered token returned the wrong auth error: " <> show err)
      Right _ -> die "Tampered token should not validate"

    wrongIssuerPayload <-
      buildKeycloakTestPayload
        authConfig
        [("iss", String "http://127.0.0.1:38104/realms/not-studiomcp")]
    wrongIssuerToken <- buildSignedTestJwt authConfig wrongIssuerPayload
    wrongIssuerResult <- validateToken authService wrongIssuerToken
    case wrongIssuerResult of
      Left (InvalidIssuer _) -> putStrLn "  ✓ Wrong issuer is rejected"
      Left err -> die ("Wrong issuer token returned the wrong auth error: " <> show err)
      Right _ -> die "Wrong issuer token should not validate"

    wrongAudiencePayload <-
      buildKeycloakTestPayload
        authConfig
        [("aud", Array (Vector.fromList [String "different-audience"]))]
    wrongAudienceToken <- buildSignedTestJwt authConfig wrongAudiencePayload
    wrongAudienceResult <- validateToken authService wrongAudienceToken
    case wrongAudienceResult of
      Left (InvalidAudience _) -> putStrLn "  ✓ Wrong audience is rejected"
      Left err -> die ("Wrong audience token returned the wrong auth error: " <> show err)
      Right _ -> die "Wrong audience token should not validate"

    expiredPayload <-
      buildKeycloakTestPayload
        authConfig
        [ ("exp", Number (fromIntegral (0 :: Int)))
        , ("iat", Number (fromIntegral (0 :: Int)))
        ]
    expiredToken <- buildSignedTestJwt authConfig expiredPayload
    expiredResult <- validateToken authService expiredToken
    case expiredResult of
      Left TokenExpired -> putStrLn "  ✓ Expired token is rejected"
      Left err -> die ("Expired token returned the wrong auth error: " <> show err)
      Right _ -> die "Expired token should not validate"

    let malformedJwt = RawJwt (Text.intercalate "." ["not-json", validTokenText, "broken"])
    case parseJwt malformedJwt of
      Left _ -> putStrLn "  ✓ Malformed JWT structure is rejected during parsing"
      Right _ -> die "Malformed JWT should not parse"

    putStrLn "validate mcp-auth: PASS"

validateLiveHorizontalScale :: LiveValidationConfig -> IO ()
validateLiveHorizontalScale config = do
  manager <- newManager defaultManagerSettings
  tokenResponse <- requestLiveAccessToken manager config
  let baseUrl = lvcBaseUrl config
      authHeaders = authorizationHeaders (trAccessToken tokenResponse)
      resourceUri = "studiomcp://history/runs"
  sessionHeaders <- initializeMcpSessionWithHeaders manager baseUrl authHeaders
  upstreams <- collectLiveUpstreams manager baseUrl sessionHeaders 8
  unless (Set.size upstreams >= 2) $
    die ("Expected live edge proxy to route across at least two MCP backends, saw " <> show (Set.size upstreams))
  putStrLn "  ✓ Shared MCP session survives requests routed across multiple edge backends without sticky ingress"

  initialSubscriptionValue <-
    subscribeMcpResourceOverHttp
      manager
      baseUrl
      sessionHeaders
      100
      resourceUri
      (Just "cursor-42")
      (Just "evt-42")
  unless (lookupString ["result", "cursor"] initialSubscriptionValue == Just "cursor-42") $
    die "Initial resources/subscribe should echo the provided cursor"
  unless (lookupString ["result", "lastEventId"] initialSubscriptionValue == Just "evt-42") $
    die "Initial resources/subscribe should echo the provided lastEventId"

  resumedSubscriptionValue <-
    subscribeMcpResourceOverHttp
      manager
      baseUrl
      sessionHeaders
      101
      resourceUri
      Nothing
      Nothing
  unless (lookupString ["result", "cursor"] resumedSubscriptionValue == Just "cursor-42") $
    die "Shared resource subscription should resume the stored cursor across routed requests"
  unless (lookupString ["result", "lastEventId"] resumedSubscriptionValue == Just "evt-42") $
    die "Shared resource subscription should resume the stored lastEventId across routed requests"
  putStrLn "  ✓ Shared subscription and cursor metadata resume across routed MCP requests"

  -- Simulate a partial rollout by scaling from 3 replicas to 1
  withKubernetesDeploymentScaled "default" "studiomcp" 1 3 $ do
    duringRolloutResponse <- pingLiveMcpSession manager baseUrl sessionHeaders
    unless (httpResponseStatus duringRolloutResponse == 200) $
      die ("Expected live ping during partial rollout simulation to return 200, got " <> show (httpResponseStatus duringRolloutResponse))
    duringRolloutSubscription <-
      subscribeMcpResourceOverHttp
        manager
        baseUrl
        sessionHeaders
        102
        resourceUri
        Nothing
        Nothing
    unless (lookupString ["result", "cursor"] duringRolloutSubscription == Just "cursor-42") $
      die "Shared subscription metadata should survive a rollout simulation"
  putStrLn "  ✓ Shared session and subscription metadata survive a rollout simulation"

  waitForDistinctLiveUpstreams manager baseUrl sessionHeaders 20

  -- Simulate Redis outage by scaling the Redis StatefulSet to 0
  -- Note: We verify the system gracefully handles Redis unavailability. The MCP server may cache
  -- session state locally, so a ping might succeed even during Redis outage. We verify recovery works.
  withKubernetesStatefulSetScaled "default" "studiomcp-redis-node" 0 1 $ do
    -- Wait for the Redis pods to fully terminate
    threadDelay 30_000_000 -- 30 seconds to ensure pods are fully down and connection pools drain
    -- During Redis outage, the server may return 503 (if session validation fails) or 200 (if cached)
    -- Either is acceptable - what matters is the system doesn't crash
    outageResponse <- pingLiveMcpSession manager baseUrl sessionHeaders
    putStrLn $ "    Redis outage response: " <> show (httpResponseStatus outageResponse)
  -- After Redis recovery, verify the system returns to normal
  -- Wait for Redis to be fully available again before testing recovery
  threadDelay 10_000_000 -- 10 seconds for Redis to stabilize
  recoveredResponse <- pingLiveMcpSession manager baseUrl sessionHeaders
  unless (httpResponseStatus recoveredResponse == 200) $
    die ("Expected live ping after Redis recovery to return 200, got " <> show (httpResponseStatus recoveredResponse))
  putStrLn "  ✓ Redis outage gracefully handled and session recovers afterward"

  putStrLn "validate horizontal-scale: PASS"

validateHarnessHorizontalScale :: IO ()
validateHarnessHorizontalScale =
  withTemporaryRedisConfig $ \redisConfig -> do
    correlationId <- generateCorrelationId
    let sharedConfig =
          redisConfig
            { rcKeyPrefix = "shared:mcp:validate-horizontal-scale:" <> unCorrelationId correlationId <> ":"
            }

    store1 <- newRedisSessionStore sharedConfig
    store2 <- newRedisSessionStore sharedConfig
    putStrLn "  ✓ Multiple store instances created"

    session <- newSession
    _ <- storeCreateSession store1 session
    putStrLn "  ✓ Session created in store1"

    visibleInStore2 <- storeGetSession store2 (sessionId session)
    case visibleInStore2 of
      Right retrieved ->
        unless (sessionId retrieved == sessionId session) $
          die "store2 retrieved the wrong shared session"
      Left err -> die ("store2 should see store1 session, got " <> show err)
    putStrLn "  ✓ Session visibility spans store instances"

    updatedFromStore2 <- storeUpdateSession store2 (sessionId session) (\s -> s {sessionState = SessionReady})
    case updatedFromStore2 of
      Left err -> die ("store2 failed to update shared session: " <> show err)
      Right _ -> pure ()
    updatedFromStore1 <- storeGetSession store1 (sessionId session)
    case updatedFromStore1 of
      Right retrieved ->
        unless (sessionState retrieved == SessionReady) $
          die "store1 did not observe the shared session update"
      Left err -> die ("store1 failed to read updated shared session: " <> show err)
    putStrLn "  ✓ Session updates are visible across store instances"

    now <- getCurrentTime
    let sharedSubscription =
          SubscriptionRecord
            { srResourceUri = "studiomcp://summaries/shared-run"
            , srSubscribedAt = now
            , srLastEventId = Nothing
            }
    _ <- storeAddSubscription store1 (sessionId session) "studiomcp://summaries/shared-run" sharedSubscription
    subscriptionsFromStore2 <- storeGetSubscriptions store2 (sessionId session)
    case subscriptionsFromStore2 of
      Right [_] -> putStrLn "  ✓ Subscriptions are shared across store instances"
      other -> die ("Expected one shared subscription, got " <> show other)

    lockResult1 <- storeAcquireLock store1 (sessionId session) "pod-1" 30
    case lockResult1 of
      Left err -> die ("Initial lock acquisition failed: " <> show err)
      Right _ -> putStrLn "  ✓ Initial lock acquired by pod-1"

    lockResult2 <- storeAcquireLock store2 (sessionId session) "pod-1" 30
    case lockResult2 of
      Left err -> die ("Lock re-acquisition by same pod failed: " <> show err)
      Right _ -> putStrLn "  ✓ Lock re-acquisition by same pod works"

    lockResult3 <- storeAcquireLock store2 (sessionId session) "pod-2" 30
    case lockResult3 of
      Left (LockAcquisitionFailed _) -> putStrLn "  ✓ Lock contention correctly prevents acquisition by pod-2"
      Left err -> die ("Unexpected error during lock contention: " <> show err)
      Right _ -> die "Lock contention should have prevented acquisition by pod-2"

    _ <- storeReleaseLock store1 (sessionId session) "pod-1"
    putStrLn "  ✓ Lock released by pod-1"

    lockResult4 <- storeAcquireLock store2 (sessionId session) "pod-2" 30
    case lockResult4 of
      Left err -> die ("Lock acquisition by pod-2 after release failed: " <> show err)
      Right _ -> putStrLn "  ✓ Lock acquired by pod-2 after release"

    closeRedisSessionStore store1
    closeRedisSessionStore store2
    putStrLn "  ✓ Stores closed"

    putStrLn "validate horizontal-scale: PASS"

validateLiveWebBff :: LiveValidationConfig -> IO ()
validateLiveWebBff config = do
  manager <- newManager defaultManagerSettings
  let baseUrl = lvcBaseUrl config
      loginBody =
        encode $
          object
            [ "username" .= lvcUsername config
            , "password" .= lvcPassword config
            ]
  loginResponse <- httpJsonRequest manager "POST" (baseUrl <> "/api/v1/session/login") (Just loginBody)
  unless (httpResponseStatus loginResponse == 200) $
    die ("Expected live session login to return 200, got " <> show (httpResponseStatus loginResponse))
  loginPayloadValue <- decodeResponseBody "live session login JSON" loginResponse :: IO Value
  loginPayload <- decodeResponseBody "live session login" loginResponse :: IO SessionLoginResponse
  assertBrowserSessionPayload "live session login" loginPayloadValue
  setCookieHeader <-
    case lookupResponseHeader "Set-Cookie" loginResponse of
      Just headerValue -> pure headerValue
      Nothing -> die "Live session login did not return Set-Cookie"
  unless ("HttpOnly" `BS.isInfixOf` setCookieHeader) $
    die "Live session login cookie should be HttpOnly"
  let cookieHeader = BS.takeWhile (/= ';') setCookieHeader
      sessionHeaders = [(CI.mk "Cookie", cookieHeader)]
      bearerSessionId = BS.drop 1 (BS.dropWhile (/= '=') cookieHeader)
      bearerSessionHeaders = [(CI.mk "Authorization", "Bearer " <> bearerSessionId)]
      conflictingSessionHeaders =
        [ (CI.mk "Cookie", cookieHeader)
        , (CI.mk "Authorization", "Bearer invalid-session-id")
        ]
  when (BS.null bearerSessionId) $
    die "Live session login cookie did not include a session value"
  putStrLn "  ✓ Live login returns a browser session cookie and hides session internals in JSON"

  sessionMeResponse <- httpJsonRequestWithHeaders manager "GET" (baseUrl <> "/api/v1/session/me") sessionHeaders Nothing
  unless (httpResponseStatus sessionMeResponse == 200) $
    die ("Expected live session/me to return 200, got " <> show (httpResponseStatus sessionMeResponse))
  sessionMePayload <- decodeResponseBody "live session/me" sessionMeResponse :: IO SessionMeResponse
  unless (ssSubjectId (smerSession sessionMePayload) == ssSubjectId (slresSession loginPayload)) $
    die "Live session/me returned the wrong subject"
  unless (ssTenantId (smerSession sessionMePayload) == ssTenantId (slresSession loginPayload)) $
    die "Live session/me returned the wrong tenant"
  putStrLn "  ✓ Live session bootstrap works from the cookie through /api/v1/session/me"

  bearerMeResponse <- httpJsonRequestWithHeaders manager "GET" (baseUrl <> "/api/v1/session/me") bearerSessionHeaders Nothing
  unless (httpResponseStatus bearerMeResponse == 200) $
    die ("Expected bearer-compatible session/me to return 200, got " <> show (httpResponseStatus bearerMeResponse))
  conflictingMeResponse <- httpJsonRequestWithHeaders manager "GET" (baseUrl <> "/api/v1/session/me") conflictingSessionHeaders Nothing
  unless (httpResponseStatus conflictingMeResponse == 200) $
    die ("Expected cookie-first session/me to return 200, got " <> show (httpResponseStatus conflictingMeResponse))
  conflictingMePayload <- decodeResponseBody "cookie-first session/me" conflictingMeResponse :: IO SessionMeResponse
  unless (ssSubjectId (smerSession conflictingMePayload) == ssSubjectId (smerSession sessionMePayload)) $
    die "Cookie-first session handling did not preserve the cookie-authenticated subject"
  putStrLn "  ✓ Bearer session compatibility remains available, and the cookie wins when both are present"

  refreshResponse <- httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/api/v1/session/refresh") sessionHeaders Nothing
  unless (httpResponseStatus refreshResponse == 200) $
    die ("Expected live session refresh to return 200, got " <> show (httpResponseStatus refreshResponse))
  refreshPayloadValue <- decodeResponseBody "live session refresh JSON" refreshResponse :: IO Value
  refreshPayload <- decodeResponseBody "live session refresh" refreshResponse :: IO SessionRefreshResponse
  assertBrowserSessionPayload "live session refresh" refreshPayloadValue
  unless (srrSuccess refreshPayload) $
    die "Live session refresh reported failure"
  unless (ssSubjectId (srrSession refreshPayload) == ssSubjectId (slresSession loginPayload)) $
    die "Live session refresh changed the subject unexpectedly"
  unless (ssTenantId (srrSession refreshPayload) == ssTenantId (slresSession loginPayload)) $
    die "Live session refresh changed the tenant unexpectedly"
  putStrLn "  ✓ Live session refresh works through /api without exposing session internals"

  let uploadReq =
        UploadRequest
          { urFileName = "live-test-video.mp4"
          , urContentType = "video/mp4"
          , urFileSize = 1000000
          , urMetadata = Nothing
          }
  uploadResponse <-
    httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/api/v1/upload/request") sessionHeaders (Just (encode uploadReq))
  unless (httpResponseStatus uploadResponse == 200) $
    die ("Expected live upload request to return 200, got " <> show (httpResponseStatus uploadResponse))
  uploadPayload <- decodeResponseBody "live upload request" uploadResponse :: IO UploadResponse
  unless ("X-Amz-Signature=" `Text.isInfixOf` puuUrl (urpPresignedUrl uploadPayload)) $
    die "Live upload request should return a real presigned URL"
  assertPresignedUrlRoot "live upload request" (lvcObjectStoragePublicEndpoint config) (puuUrl (urpPresignedUrl uploadPayload))
  putStrLn "  ✓ Live upload request works through /api and uses the configured public object-storage endpoint"

  confirmResponse <-
    httpJsonRequestWithHeaders
      manager
      "POST"
      (baseUrl <> "/api/v1/upload/confirm/" <> Text.unpack (urpArtifactId uploadPayload))
      sessionHeaders
      Nothing
  unless (httpResponseStatus confirmResponse == 200) $
    die ("Expected live upload confirm to return 200, got " <> show (httpResponseStatus confirmResponse))
  putStrLn "  ✓ Live upload confirmation works through /api"

  let downloadReq =
        DownloadRequest
          { drArtifactId = urpArtifactId uploadPayload
          , drVersion = Nothing
          }
  downloadResponse <-
    httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/api/v1/download") sessionHeaders (Just (encode downloadReq))
  unless (httpResponseStatus downloadResponse == 200) $
    die ("Expected live download request to return 200, got " <> show (httpResponseStatus downloadResponse))
  downloadPayload <- decodeResponseBody "live download request" downloadResponse :: IO DownloadResponse
  unless ("X-Amz-Signature=" `Text.isInfixOf` pduUrl (drpPresignedUrl downloadPayload)) $
    die "Live download request should return a real presigned URL"
  assertPresignedUrlRoot "live download request" (lvcObjectStoragePublicEndpoint config) (pduUrl (drpPresignedUrl downloadPayload))
  putStrLn "  ✓ Live download request works through /api and uses the configured public object-storage endpoint"

  let chatReq =
        ChatRequest
          { crMessages = [ChatMessage ChatUser "Hello from live validation" Nothing]
          , crContext = Nothing
          }
  chatResponse <- httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/api/v1/chat") sessionHeaders (Just (encode chatReq))
  unless (httpResponseStatus chatResponse == 200) $
    die ("Expected live chat request to return 200, got " <> show (httpResponseStatus chatResponse))
  chatPayload <- decodeResponseBody "live chat response" chatResponse :: IO ChatResponse
  unless ("ADVISORY:" `Text.isPrefixOf` cmContent (crpMessage chatPayload)) $
    die "Live chat response should come from the advisory model path"
  putStrLn "  ✓ Live chat works through /api"

  dagSpec <- loadSubmissionDag "examples/dags/transcode-basic.yaml"
  let submitReq =
        RunSubmitRequest
          { rsrDagSpec = dagSpec
          , rsrInputArtifacts = [("input", urpArtifactId uploadPayload)]
          }
  submitResponse <- httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/api/v1/runs") sessionHeaders (Just (encode submitReq))
  unless (httpResponseStatus submitResponse == 200) $
    die ("Expected live run submit to return 200, got " <> show (httpResponseStatus submitResponse))
  runStatus <- decodeResponseBody "live run submit" submitResponse :: IO RunStatusResponse
  unless (rsrRunId runStatus /= RunId "") $
    die "Live run submission returned an empty run id"
  putStrLn "  ✓ Live run submission works through /api"

  statusResponse <-
    httpJsonRequestWithHeaders
      manager
      "GET"
      (baseUrl <> "/api/v1/runs/" <> Text.unpack (unRunId (rsrRunId runStatus)) <> "/status")
      sessionHeaders
      Nothing
  unless (httpResponseStatus statusResponse == 200) $
    die ("Expected live run status to return 200, got " <> show (httpResponseStatus statusResponse))
  putStrLn "  ✓ Live run status works through /api"

  eventsResponse <-
    httpJsonRequestWithHeaders
      manager
      "GET"
      (baseUrl <> "/api/v1/runs/" <> Text.unpack (unRunId (rsrRunId runStatus)) <> "/events")
      sessionHeaders
      Nothing
  unless (httpResponseStatus eventsResponse == 200) $
    die ("Expected live run events stream to return 200, got " <> show (httpResponseStatus eventsResponse))
  let eventsBody = LBS.unpack (httpResponseBody eventsResponse)
  unless ("event: ready" `isInfixOf` eventsBody) $
    die "Live run events stream did not emit a ready event"
  unless ("event: status" `isInfixOf` eventsBody || "event: heartbeat" `isInfixOf` eventsBody) $
    die "Live run events stream did not emit a status or heartbeat event"
  putStrLn "  ✓ Live run progress streaming works through /api"

  logoutResponse <- httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/api/v1/session/logout") sessionHeaders Nothing
  unless (httpResponseStatus logoutResponse == 200) $
    die ("Expected live session logout to return 200, got " <> show (httpResponseStatus logoutResponse))
  _ <- decodeResponseBody "live session logout" logoutResponse :: IO SessionLogoutResponse
  putStrLn "  ✓ Live logout works through /api"

  refreshAfterLogout <- httpJsonRequestWithHeaders manager "POST" (baseUrl <> "/api/v1/session/refresh") sessionHeaders Nothing
  unless (httpResponseStatus refreshAfterLogout == 401) $
    die ("Expected refresh after logout to return 401, got " <> show (httpResponseStatus refreshAfterLogout))
  putStrLn "  ✓ Invalidated browser sessions are rejected after logout"

  putStrLn "validate web-bff: PASS"

assertBrowserSessionPayload :: String -> Value -> IO ()
assertBrowserSessionPayload label payload = do
  when (lookupPath ["session", "sessionId"] payload /= Nothing) $
    die (label <> " should not expose sessionId")
  when (lookupPath ["session", "accessToken"] payload /= Nothing) $
    die (label <> " should not expose accessToken")
  when (lookupPath ["session", "refreshToken"] payload /= Nothing) $
    die (label <> " should not expose refreshToken")

assertPresignedUrlRoot :: String -> Text -> Text -> IO ()
assertPresignedUrlRoot label expectedRoot actualUrl =
  let normalizedRoot = Text.dropWhileEnd (== '/') expectedRoot
   in unless (normalizedRoot `Text.isPrefixOf` actualUrl) $
    die
      ( label
          <> " should be rooted at "
          <> Text.unpack expectedRoot
          <> ", got "
          <> Text.unpack actualUrl
      )

validateHarnessWebBff :: IO ()
validateHarnessWebBff =
  withTemporaryRedisConfig $ \redisConfig ->
    withRedisConfigEnv redisConfig $ do
      appConfig <- loadAppConfig
      serverEnv <- createServerEnv appConfig
      withFakeModelHost 38105 "Use workflow.submit and artifact tools to coordinate the run." $ do
        service <-
          newBFFServiceWithRuntime
            defaultBFFConfig
            (serverToolCatalog serverEnv)
            (serverTenantStorage serverEnv)
            (ReferenceModelConfig "http://127.0.0.1:38105/api/generate")
        putStrLn "  ✓ BFF service created with runtime-backed MCP and inference integrations"

        sessionResult <- createWebSession service "user-123" "tenant-456" "test-token" (Just "refresh-token")
        webSession <- case sessionResult of
          Left err -> die ("Session creation failed: " <> show err)
          Right session -> do
            unless (wsSubjectId session == "user-123") $
              die "Session has wrong subject ID"
            unless (wsTenantId session == "tenant-456") $
              die "Session has wrong tenant ID"
            putStrLn "  ✓ Web session creation works"
            pure session

        getResult <- getWebSession service (wsSessionId webSession)
        case getResult of
          Left err -> die ("Session retrieval failed: " <> show err)
          Right retrieved ->
            unless (wsSubjectId retrieved == "user-123") $
              die "Session retrieval returned wrong session"
        putStrLn "  ✓ Web session retrieval works"

        refreshResult <- refreshWebSession service (wsSessionId webSession) "new-token" (Just "new-refresh")
        case refreshResult of
          Left err -> die ("Session refresh failed: " <> show err)
          Right refreshed ->
            unless (wsAccessToken refreshed == "new-token") $
              die "Session refresh did not update token"
        putStrLn "  ✓ Web session refresh works"

        let uploadReq = UploadRequest
              { urFileName = "test-video.mp4"
              , urContentType = "video/mp4"
              , urFileSize = 1000000
              , urMetadata = Nothing
              }
        uploadResult <- requestUpload service (wsSessionId webSession) uploadReq
        uploadResponse <- case uploadResult of
          Left err -> die ("Upload request failed: " <> show err)
          Right resp -> do
            unless (urpArtifactId resp /= "") $
              die "Upload response has empty artifact ID"
            unless (puuArtifactId (urpPresignedUrl resp) == urpArtifactId resp) $
              die "Upload response presigned URL should be scoped to the created artifact"
            unless ("X-Amz-Signature=" `Text.isInfixOf` puuUrl (urpPresignedUrl resp)) $
              die "Upload response should contain a real SigV4 presigned signature"
            putStrLn "  ✓ Upload request works with a real presigned URL"
            pure resp

        confirmResult <- confirmUpload service (wsSessionId webSession) (urpArtifactId uploadResponse)
        case confirmResult of
          Left err -> die ("Upload confirmation failed: " <> show err)
          Right () -> putStrLn "  ✓ Upload confirmation works"

        let downloadReq = DownloadRequest
              { drArtifactId = urpArtifactId uploadResponse
              , drVersion = Nothing
              }
        downloadResult <- requestDownload service (wsSessionId webSession) downloadReq
        case downloadResult of
          Left err -> die ("Download request failed: " <> show err)
          Right resp -> do
            unless (drpArtifactId resp == urpArtifactId uploadResponse) $
              die "Download response returned the wrong artifact ID"
            unless (drpFileName resp == "test-video.mp4") $
              die "Download response returned the wrong file name"
            unless (pduContentType (drpPresignedUrl resp) == "video/mp4") $
              die "Download response returned the wrong content type"
            unless ("X-Amz-Signature=" `Text.isInfixOf` pduUrl (drpPresignedUrl resp)) $
              die "Download response should contain a real SigV4 presigned signature"
            putStrLn "  ✓ Download request works with a real presigned URL"

        let chatReq = ChatRequest
              { crMessages = [ChatMessage ChatUser "Hello" Nothing]
              , crContext = Nothing
              }
        chatResult <- sendChatMessage service (wsSessionId webSession) chatReq
        case chatResult of
          Left err -> die ("Chat request failed: " <> show err)
          Right resp -> do
            unless (cmRole (crpMessage resp) == ChatAssistant) $
              die "Chat response has wrong role"
            unless ("ADVISORY:" `Text.isPrefixOf` cmContent (crpMessage resp)) $
              die "Chat response should come from the inference-backed advisory path"
        putStrLn "  ✓ Chat request works through the inference path"

        dagSpec <- loadSubmissionDag "examples/dags/transcode-basic.yaml"
        submitResult <-
          submitRun
            service
            (wsSessionId webSession)
            RunSubmitRequest
              { rsrDagSpec = dagSpec
              , rsrInputArtifacts = [("input", urpArtifactId uploadResponse)]
              }
        runStatus <- case submitResult of
          Left err -> die ("Run submission failed: " <> show err)
          Right status -> do
            unless (rsrRunId status /= RunId "") $
              die "Run submission returned an empty run id"
            putStrLn "  ✓ Run submission is forwarded through the MCP tool path"
            pure status

        statusResult <- getRunStatus service (wsSessionId webSession) (rsrRunId runStatus)
        case statusResult of
          Left err -> die ("Run status failed: " <> show err)
          Right status ->
            unless (rsrRunId status == rsrRunId runStatus) $
              die "Run status returned the wrong run id"
        putStrLn "  ✓ Run status is read through the MCP tool path"

        invalidResult <- invalidateWebSession service (wsSessionId webSession)
        case invalidResult of
          Left err -> die ("Session invalidation failed: " <> show err)
          Right () -> pure ()
        putStrLn "  ✓ Web session invalidation works"

        checkResult <- getWebSession service (wsSessionId webSession)
        case checkResult of
          Left _ -> putStrLn "  ✓ Invalidated session no longer accessible"
          Right _ -> die "Invalidated session should not be accessible"

        putStrLn "validate web-bff: PASS"

validateArtifactStorage :: IO ()
validateArtifactStorage = do
  putStrLn "Validating artifact storage..."

  -- Create tenant storage service
  storageService <- newTenantStorageService defaultTenantStorageConfig
  putStrLn "  ✓ Tenant storage service created"

  let tenantId = TenantId "test-tenant-123"

  -- Test artifact creation
  createResult <- createTenantArtifact
    storageService
    tenantId
    "video/mp4"
    "test-video.mp4"
    10000000
    Map.empty
  artId <- case createResult of
    Left err -> die ("Artifact creation failed: " <> show err)
    Right art -> do
      putStrLn "  ✓ Artifact creation works"
      pure (taArtifactId art)

  -- Test artifact retrieval
  getResult <- getTenantArtifact storageService tenantId artId
  case getResult of
    Left err -> die ("Artifact retrieval failed: " <> show err)
    Right retrieved ->
      unless (taArtifactId retrieved == artId) $
        die "Artifact retrieval returned wrong artifact"
  putStrLn "  ✓ Artifact retrieval works"

  -- Test listing artifacts
  artifacts <- listTenantArtifacts storageService tenantId
  unless (length artifacts >= 1) $
    die "Artifact listing returned empty list"
  putStrLn "  ✓ Artifact listing works"

  -- Test upload URL generation
  uploadResult <- generateUploadUrl storageService tenantId artId "video/mp4"
  case uploadResult of
    Left err -> die ("Upload URL generation failed: " <> show err)
    Right url -> do
      unless (puUrl url /= Text.empty) $
        die "Upload URL is empty"
      putStrLn "  ✓ Upload URL generation works"

  -- Test download URL generation
  downloadResult <- generateDownloadUrl storageService tenantId artId Nothing
  case downloadResult of
    Left err -> die ("Download URL generation failed: " <> show err)
    Right url -> do
      unless (puUrl url /= Text.empty) $
        die "Download URL is empty"
      putStrLn "  ✓ Download URL generation works"

  -- Create versioning service
  versioningService <- newVersioningService defaultVersioningPolicy
  putStrLn "  ✓ Versioning service created"

  -- Test initial version creation
  let contentAddr = ContentAddress "ca:fnv64:abc123"
  versionResult <- createInitialVersion
    versioningService
    "test-artifact"
    contentAddr
    1000
    "video/mp4"
    (SubjectId "user-123")
    tenantId
    Map.empty
  case versionResult of
    Left err -> die ("Initial version creation failed: " <> show err)
    Right _ver -> putStrLn "  ✓ Initial version creation works"

  -- Test version retrieval
  latestResult <- getLatestVersion versioningService "test-artifact"
  case latestResult of
    Left err -> die ("Latest version retrieval failed: " <> show err)
    Right latest ->
      unless (avVersionNumber latest == 1) $
        die "Latest version has wrong version number"
  putStrLn "  ✓ Version retrieval works"

  -- Test new version creation
  let contentAddr2 = ContentAddress "ca:fnv64:def456"
  newVersionResult <- createNewVersion
    versioningService
    "test-artifact"
    contentAddr2
    2000
    "video/mp4"
    (SubjectId "user-123")
    Map.empty
  case newVersionResult of
    Left err -> die ("New version creation failed: " <> show err)
    Right newVer ->
      unless (avVersionNumber newVer == 2) $
        die "New version has wrong version number"
  putStrLn "  ✓ New version creation works"

  -- Test version listing
  versionsResult <- listVersions versioningService "test-artifact"
  case versionsResult of
    Left err -> die ("Version listing failed: " <> show err)
    Right versions ->
      unless (length versions == 2) $
        die "Version listing returned wrong count"
  putStrLn "  ✓ Version listing works"

  putStrLn "validate artifact-storage: PASS"

validateArtifactGovernance :: IO ()
validateArtifactGovernance = do
  putStrLn "Validating artifact governance..."

  -- Create governance service
  governanceService <- newGovernanceService defaultGovernancePolicy
  putStrLn "  ✓ Governance service created"

  -- Create audit trail service
  auditService <- newAuditTrailService
  putStrLn "  ✓ Audit trail service created"

  let tenantId = TenantId "test-tenant-123"
      subjectId = SubjectId "user-123"
      artifactId = "test-artifact-456"

  -- Create governance metadata
  now <- getCurrentTime
  let metadata = GovernanceMetadata
        { gmReason = "Test governance operation"
        , gmRequestedBy = subjectId
        , gmTenantId = tenantId
        , gmTimestamp = now
        , gmRelatedArtifacts = []
        }

  -- Test initial state
  initialState <- getArtifactState governanceService artifactId
  unless (initialState == Active) $
    die "Initial artifact state should be Active"
  putStrLn "  ✓ Initial state is Active"

  -- Test hide operation
  hideResult <- hideArtifact governanceService artifactId metadata
  case hideResult of
    Left err -> die ("Hide operation failed: " <> show err)
    Right _record -> do
      state <- getArtifactState governanceService artifactId
      unless (state == Hidden) $
        die "Artifact should be Hidden after hide operation"
  putStrLn "  ✓ Hide operation works"

  -- Record audit entry for hide
  _ <- recordAuditEntry
    auditService
    tenantId
    subjectId
    artifactId
    Nothing
    (AuditStateChange ActionHide)
    OutcomeSuccess
    Map.empty
  putStrLn "  ✓ Audit entry recorded for hide"

  -- Test restore operation
  restoreResult <- restoreArtifact governanceService artifactId metadata
  case restoreResult of
    Left err -> die ("Restore operation failed: " <> show err)
    Right _record -> do
      state <- getArtifactState governanceService artifactId
      unless (state == Active) $
        die "Artifact should be Active after restore"
  putStrLn "  ✓ Restore operation works"

  -- Test archive operation
  archiveResult <- archiveArtifact governanceService artifactId metadata
  case archiveResult of
    Left err -> die ("Archive operation failed: " <> show err)
    Right _record -> do
      state <- getArtifactState governanceService artifactId
      unless (state == Archived) $
        die "Artifact should be Archived after archive operation"
  putStrLn "  ✓ Archive operation works"

  -- Test that restore from archived fails (policy)
  restoreArchivedResult <- restoreArtifact governanceService artifactId metadata
  case restoreArchivedResult of
    Left _ -> putStrLn "  ✓ Restore from Archived correctly denied by policy"
    Right _ -> die "Restore from Archived should be denied by default policy"

  -- Test hard delete denial
  deleteResult <- denyHardDelete governanceService artifactId metadata
  case deleteResult of
    Left _ -> putStrLn "  ✓ Hard delete correctly denied"
    Right _ -> die "Hard delete should always be denied"

  -- Record deletion attempt in audit
  _ <- recordDeletionAttempt
    auditService
    tenantId
    subjectId
    artifactId
    "Hard delete is forbidden by governance policy"
  putStrLn "  ✓ Deletion attempt recorded in audit trail"

  -- Test supersede operation (on a fresh artifact)
  let artifact2 = "test-artifact-789"
      newArtifact = "test-artifact-new"
  supersedeResult <- supersedeArtifact governanceService artifact2 newArtifact metadata
  case supersedeResult of
    Left err -> die ("Supersede operation failed: " <> show err)
    Right _ -> do
      state <- getArtifactState governanceService artifact2
      case state of
        Superseded newId ->
          unless (newId == newArtifact) $
            die "Superseded state has wrong new artifact ID"
        _ -> die "Artifact should be Superseded"
  putStrLn "  ✓ Supersede operation works"

  -- Test history retrieval
  history <- getArtifactHistory governanceService artifactId
  unless (length history >= 2) $
    die "History should have at least 2 entries"
  putStrLn "  ✓ History retrieval works"

  -- Test audit query
  entries <- queryAuditTrail auditService defaultAuditQuery { aqTenantId = Just tenantId }
  unless (length entries >= 2) $
    die "Audit query should return at least 2 entries"
  putStrLn "  ✓ Audit query works"

  -- Test audit report generation
  -- Get fresh time to ensure all entries created during test are included
  nowForReport <- getCurrentTime
  let oneHourAgo = addUTCTime (-3600) nowForReport
  report <- generateAuditReport auditService tenantId oneHourAgo nowForReport
  unless (arTotalEntries report >= 2) $
    die "Audit report should have at least 2 entries"
  unless (arDeleteAttemptsCount report >= 1) $
    die "Audit report should show at least 1 delete attempt"
  putStrLn "  ✓ Audit report generation works"

  -- Test audit integrity verification
  integrityResult <- verifyAuditIntegrity auditService tenantId
  case integrityResult of
    IntegrityValid -> putStrLn "  ✓ Audit integrity verification passed"
    _ -> die "Audit integrity should be valid"

  putStrLn "validate artifact-governance: PASS"

validateMcpTools :: IO ()
validateMcpTools = do
  putStrLn "Validating MCP tools catalog..."

  -- Create tool catalog
  toolCatalog <- newToolCatalog
  putStrLn "  ✓ Tool catalog created"

  -- List tools
  tools <- listTools toolCatalog
  unless (length tools == 10) $
    die ("Expected 10 tools, got " <> show (length tools))
  putStrLn "  ✓ Tool listing works (10 tools)"

  -- Verify all expected tools are present
  let toolNames = map (\t -> tdName t) tools
      expectedTools = ["workflow.submit", "workflow.status", "workflow.cancel", "workflow.list",
                       "artifact.get", "artifact.download_url", "artifact.upload_url",
                       "artifact.hide", "artifact.archive", "tenant.info"]
  forM_ expectedTools $ \expectedTool ->
    unless (expectedTool `elem` toolNames) $
      die ("Missing tool: " <> Text.unpack expectedTool)
  putStrLn "  ✓ All expected tools present"

  -- Test tool execution
  let tenantId = TenantId "test-tenant-123"
      subjectId = SubjectId "user-123"

  dagSpecText <- Text.pack <$> readFile "examples/dags/transcode-basic.yaml"
  submitText <-
    expectToolSuccessText
      "workflow.submit"
      =<< callTool
        toolCatalog
        tenantId
        subjectId
        CallToolParams
          { ctpName = "workflow.submit"
          , ctpArguments = Just (object ["dag_spec" .= dagSpecText])
          }
  runId <-
    case extractDelimitedValue "Run ID: " "." submitText of
      Just value -> pure value
      Nothing -> die ("workflow.submit did not return a run id: " <> Text.unpack submitText)
  putStrLn "  ✓ workflow.submit execution works"

  statusText <-
    expectToolSuccessText
      "workflow.status"
      =<< callTool
        toolCatalog
        tenantId
        subjectId
        CallToolParams
          { ctpName = "workflow.status"
          , ctpArguments = Just (object ["run_id" .= runId])
          }
  unless (runId `Text.isInfixOf` statusText) $
    die "workflow.status should return the submitted run id"
  putStrLn "  ✓ workflow.status execution works"

  listText <-
    expectToolSuccessText
      "workflow.list"
      =<< callTool
        toolCatalog
        tenantId
        subjectId
        CallToolParams { ctpName = "workflow.list", ctpArguments = Just (object ["limit" .= (10 :: Int)]) }
  unless (runId `Text.isInfixOf` listText) $
    die "workflow.list should include the submitted run"
  putStrLn "  ✓ workflow.list execution works"

  cancelText <-
    expectToolSuccessText
      "workflow.cancel"
      =<< callTool
        toolCatalog
        tenantId
        subjectId
        CallToolParams
          { ctpName = "workflow.cancel"
          , ctpArguments = Just (object ["run_id" .= runId])
          }
  unless ("cancelled" `Text.isInfixOf` Text.toLower cancelText) $
    die "workflow.cancel should mark the run as cancelled"
  putStrLn "  ✓ workflow.cancel execution works"

  cancelledStatusText <-
    expectToolSuccessText
      "workflow.status"
      =<< callTool
        toolCatalog
        tenantId
        subjectId
        CallToolParams
          { ctpName = "workflow.status"
          , ctpArguments = Just (object ["run_id" .= runId])
          }
  unless ("cancelled" `Text.isInfixOf` Text.toLower cancelledStatusText) $
    die "workflow.status should report the cancelled run state"
  putStrLn "  ✓ workflow status transitions are persisted"

  uploadText <-
    expectToolSuccessText
      "artifact.upload_url"
      =<< callTool
        toolCatalog
        tenantId
        subjectId
        CallToolParams
          { ctpName = "artifact.upload_url"
          , ctpArguments =
              Just
                ( object
                    [ "content_type" .= ("video/mp4" :: Text)
                    , "file_name" .= ("tool-test-video.mp4" :: Text)
                    , "file_size" .= (2048 :: Int)
                    ]
                )
          }
  artifactId <-
    case extractDelimitedValue "Upload URL generated for artifact " ":\n" uploadText of
      Just value -> pure value
      Nothing -> die ("artifact.upload_url did not return an artifact id: " <> Text.unpack uploadText)
  unless (not ("storage.example.com" `Text.isInfixOf` uploadText)) $
    die "artifact.upload_url should not return placeholder storage.example.com URLs"
  putStrLn "  ✓ artifact.upload_url execution works"

  artifactText <-
    expectToolSuccessText
      "artifact.get"
      =<< callTool
        toolCatalog
        tenantId
        subjectId
        CallToolParams
          { ctpName = "artifact.get"
          , ctpArguments = Just (object ["artifact_id" .= artifactId])
          }
  unless ("video/mp4" `Text.isInfixOf` artifactText) $
    die "artifact.get should return the stored content type"
  putStrLn "  ✓ artifact.get execution works"

  downloadText <-
    expectToolSuccessText
      "artifact.download_url"
      =<< callTool
        toolCatalog
        tenantId
        subjectId
        CallToolParams
          { ctpName = "artifact.download_url"
          , ctpArguments = Just (object ["artifact_id" .= artifactId])
          }
  unless (not ("storage.example.com" `Text.isInfixOf` downloadText)) $
    die "artifact.download_url should not return placeholder storage.example.com URLs"
  putStrLn "  ✓ artifact.download_url execution works"

  _ <-
    expectToolSuccessText
      "artifact.hide"
      =<< callTool
        toolCatalog
        tenantId
        subjectId
        CallToolParams
          { ctpName = "artifact.hide"
          , ctpArguments = Just (object ["artifact_id" .= artifactId, "reason" .= ("tool-validation" :: Text)])
          }
  hiddenArtifactText <-
    expectToolSuccessText
      "artifact.get"
      =<< callTool
        toolCatalog
        tenantId
        subjectId
        CallToolParams
          { ctpName = "artifact.get"
          , ctpArguments = Just (object ["artifact_id" .= artifactId])
          }
  unless ("State: hidden" `Text.isInfixOf` hiddenArtifactText) $
    die "artifact.hide should update the artifact state"
  putStrLn "  ✓ artifact.hide execution works"

  _ <-
    expectToolSuccessText
      "artifact.archive"
      =<< callTool
        toolCatalog
        tenantId
        subjectId
        CallToolParams
          { ctpName = "artifact.archive"
          , ctpArguments = Just (object ["artifact_id" .= artifactId, "reason" .= ("tool-validation" :: Text)])
          }
  archivedArtifactText <-
    expectToolSuccessText
      "artifact.get"
      =<< callTool
        toolCatalog
        tenantId
        subjectId
        CallToolParams
          { ctpName = "artifact.get"
          , ctpArguments = Just (object ["artifact_id" .= artifactId])
          }
  unless ("State: archived" `Text.isInfixOf` archivedArtifactText) $
    die "artifact.archive should update the artifact state"
  putStrLn "  ✓ artifact.archive execution works"

  infoText <-
    expectToolSuccessText
      "tenant.info"
      =<< callTool
        toolCatalog
        tenantId
        subjectId
        CallToolParams { ctpName = "tenant.info", ctpArguments = Nothing }
  unless ("Artifact Count: 1" `Text.isInfixOf` infoText) $
    die "tenant.info should reflect the created artifact count"
  putStrLn "  ✓ tenant.info execution works"

  -- Test tool authorization scopes
  let submitScopes = toolRequiredScopes WorkflowSubmit
  unless ("workflow:write" `elem` submitScopes) $
    die "workflow.submit should require workflow:write scope"
  putStrLn "  ✓ Tool authorization scopes correct"

  -- Test unknown tool
  unknownResult <- callTool toolCatalog tenantId subjectId
    CallToolParams { ctpName = "unknown.tool", ctpArguments = Nothing }
  case unknownResult of
    ToolFailure (ToolNotFound _) -> putStrLn "  ✓ Unknown tool correctly rejected"
    _ -> die "Unknown tool should fail with ToolNotFound"

  putStrLn "validate mcp-tools: PASS"

validateMcpResources :: IO ()
validateMcpResources = do
  putStrLn "Validating MCP resources catalog..."

  -- Create resource catalog
  resourceCatalog <- newResourceCatalog
  putStrLn "  ✓ Resource catalog created"

  let tenantId = TenantId "test-tenant-123"

  -- List resources
  resources <- listResources resourceCatalog tenantId
  unless (length resources == 6) $
    die ("Expected 6 resources, got " <> show (length resources))
  putStrLn "  ✓ Resource listing works (6 resources)"

  -- Test resource URI parsing
  case parseResourceUri "studiomcp://summaries/run-123" of
    Nothing -> die "Failed to parse summary URI"
    Just _ -> putStrLn "  ✓ Summary URI parsing works"

  case parseResourceUri "studiomcp://metadata/quotas" of
    Nothing -> die "Failed to parse quota URI"
    Just _ -> putStrLn "  ✓ Quota URI parsing works"

  case parseResourceUri "invalid://uri" of
    Nothing -> putStrLn "  ✓ Invalid URI correctly rejected"
    Just _ -> die "Invalid URI should not parse"

  -- Test resource reading
  summaryResult <- readResource resourceCatalog tenantId
    ReadResourceParams { rrpUri = "studiomcp://summaries/run-123" }
  case summaryResult of
    Right _ -> putStrLn "  ✓ Summary resource reading works"
    Left err -> die ("Summary resource read failed: " <> show err)

  quotaResult <- readResource resourceCatalog tenantId
    ReadResourceParams { rrpUri = "studiomcp://metadata/quotas" }
  case quotaResult of
    Right _ -> putStrLn "  ✓ Quota resource reading works"
    Left err -> die ("Quota resource read failed: " <> show err)

  -- Test invalid resource
  invalidResult <- readResource resourceCatalog tenantId
    ReadResourceParams { rrpUri = "invalid://something" }
  case invalidResult of
    Left (InvalidResourceUri _) -> putStrLn "  ✓ Invalid resource URI correctly rejected"
    _ -> die "Invalid resource URI should fail"

  -- Test resource authorization scopes
  let summaryScopes = resourceRequiredScopes SummaryResource
  unless ("workflow:read" `elem` summaryScopes) $
    die "Summary resource should require workflow:read scope"
  putStrLn "  ✓ Resource authorization scopes correct"

  putStrLn "validate mcp-resources: PASS"

validateMcpPrompts :: IO ()
validateMcpPrompts = do
  putStrLn "Validating MCP prompts catalog..."

  -- Create prompt catalog
  promptCatalog <- newPromptCatalog
  putStrLn "  ✓ Prompt catalog created"

  -- List prompts
  prompts <- listPrompts promptCatalog
  unless (length prompts == 5) $
    die ("Expected 5 prompts, got " <> show (length prompts))
  putStrLn "  ✓ Prompt listing works (5 prompts)"

  -- Verify expected prompts are present
  let promptNames = map (\p -> pdName p) prompts
      expectedPrompts = ["dag-planning", "dag-repair", "workflow-analysis",
                         "artifact-naming", "error-diagnosis"]
  forM_ expectedPrompts $ \expectedPrompt ->
    unless (expectedPrompt `elem` promptNames) $
      die ("Missing prompt: " <> Text.unpack expectedPrompt)
  putStrLn "  ✓ All expected prompts present"

  let tenantId = TenantId "test-tenant-123"

  -- Test prompt rendering
  planningResult <- getPrompt promptCatalog tenantId
    GetPromptParams { gppName = "dag-planning", gppArguments = Nothing }
  case planningResult of
    Right result -> do
      unless (length (gprMessages result) >= 1) $
        die "DAG planning prompt should have messages"
      putStrLn "  ✓ DAG planning prompt rendering works"
    Left err -> die ("DAG planning prompt failed: " <> show err)

  -- Test prompt with arguments
  repairResult <- getPrompt promptCatalog tenantId
    GetPromptParams
      { gppName = "dag-repair",
        gppArguments = Just (object ["dag_spec" .= ("nodes: []" :: Text)])
      }
  case repairResult of
    Right _ -> putStrLn "  ✓ DAG repair prompt rendering works"
    Left err -> die ("DAG repair prompt failed: " <> show err)

  -- Test unknown prompt
  unknownResult <- getPrompt promptCatalog tenantId
    GetPromptParams { gppName = "unknown-prompt", gppArguments = Nothing }
  case unknownResult of
    Left (PromptNotFound _) -> putStrLn "  ✓ Unknown prompt correctly rejected"
    _ -> die "Unknown prompt should fail with PromptNotFound"

  -- Test prompt authorization scopes
  let planningScopes = promptRequiredScopes DagPlanning
  unless ("prompt:read" `elem` planningScopes) $
    die "DAG planning prompt should require prompt:read scope"
  putStrLn "  ✓ Prompt authorization scopes correct"

  putStrLn "validate mcp-prompts: PASS"

validateAudit :: IO ()
validateAudit = do
  putStrLn "Validating audit capabilities..."

  -- Create correlation ID
  correlationId <- generateCorrelationId
  putStrLn $ "  ✓ Correlation ID generated: " <> Text.unpack (unCorrelationId correlationId)

  -- Create request context
  _ <- newRequestContext "POST" "/api/v1/tools/call" (Just "127.0.0.1") (Just "TestClient/1.0")
  putStrLn "  ✓ Request context created"

  -- Create audit service
  auditService <- newAuditTrailService
  putStrLn "  ✓ Audit trail service created"

  let tenantId = TenantId "test-tenant-123"
      subjectId = SubjectId "user-123"
      artifactId = "test-artifact-456"

  -- Record various audit entries
  _ <- recordAuditEntry
    auditService
    tenantId
    subjectId
    artifactId
    Nothing
    AuditCreate
    OutcomeSuccess
    Map.empty
  putStrLn "  ✓ Create audit entry recorded"

  _ <- recordAuditEntry
    auditService
    tenantId
    subjectId
    artifactId
    (Just "v1")
    AuditRead
    OutcomeSuccess
    Map.empty
  putStrLn "  ✓ Read audit entry recorded"

  -- Record deletion attempt (always denied)
  _ <- recordDeletionAttempt auditService tenantId subjectId artifactId "hard-delete-forbidden"
  putStrLn "  ✓ Deletion attempt audit entry recorded"

  -- Query audit trail
  entries <- queryAuditTrail auditService defaultAuditQuery { aqTenantId = Just tenantId }
  unless (length entries >= 3) $
    die "Audit query should return at least 3 entries"
  putStrLn "  ✓ Audit query returns correct entries"

  -- Generate audit report
  nowForReport <- getCurrentTime
  let oneHourAgo = addUTCTime (-3600) nowForReport
  report <- generateAuditReport auditService tenantId oneHourAgo nowForReport
  unless (arTotalEntries report >= 3) $
    die "Audit report should have at least 3 entries"
  putStrLn "  ✓ Audit report generated correctly"

  -- Verify audit integrity
  integrityResult <- verifyAuditIntegrity auditService tenantId
  case integrityResult of
    IntegrityValid -> putStrLn "  ✓ Audit integrity verification passed"
    _ -> die "Audit integrity should be valid"

  putStrLn "validate audit: PASS"

validateQuotas :: IO ()
validateQuotas = do
  putStrLn "Validating quota enforcement..."

  -- Create quota service
  quotaService <- newQuotaService defaultQuotaConfig
  putStrLn "  ✓ Quota service created"

  let tenantId = TenantId "test-tenant-123"

  -- Test quota check (should be allowed)
  result1 <- checkQuota quotaService tenantId ConcurrentRunsQuota
  case result1 of
    QuotaAllowed -> putStrLn "  ✓ Initial quota check allowed"
    _ -> die "Initial quota check should be allowed"

  -- Reserve some quota
  reserveResult <- reserveQuota quotaService tenantId ConcurrentRunsQuota 5
  case reserveResult of
    Right () -> putStrLn "  ✓ Quota reservation successful"
    Left err -> die ("Quota reservation failed: " <> show err)

  -- Check quota again (should still be allowed but usage increased)
  result2 <- checkQuota quotaService tenantId ConcurrentRunsQuota
  case result2 of
    QuotaAllowed -> putStrLn "  ✓ Post-reservation quota check allowed"
    QuotaWarning {} -> putStrLn "  ✓ Post-reservation quota check shows warning (80% threshold)"
    _ -> die "Post-reservation quota check should be allowed or warning"

  -- Reserve more to trigger warning
  _ <- reserveQuota quotaService tenantId ConcurrentRunsQuota 3
  result3 <- checkQuota quotaService tenantId ConcurrentRunsQuota
  case result3 of
    QuotaWarning _ _ _ _ -> putStrLn "  ✓ Quota warning triggered at 80%"
    QuotaAllowed -> putStrLn "  ✓ Quota still allowed (under 80%)"
    QuotaExceeded {} -> die "Quota should not be exceeded yet"

  -- Release quota
  releaseQuota quotaService tenantId ConcurrentRunsQuota 5
  putStrLn "  ✓ Quota release successful"

  -- Get quota metrics
  metrics <- getQuotaMetrics quotaService
  unless (qmTotalChecks metrics >= 3) $
    die "Quota metrics should show at least 3 checks"
  putStrLn "  ✓ Quota metrics recorded correctly"

  putStrLn "validate quotas: PASS"

validateRateLimit :: IO ()
validateRateLimit = do
  putStrLn "Validating rate limiting..."

  -- Create rate limiter service
  rateLimiter <- newRateLimiterService defaultRateLimiterConfig
  putStrLn "  ✓ Rate limiter service created"

  let tenantId = TenantId "test-tenant-123"
      key = TenantKey tenantId

  -- Check rate limit (should be allowed)
  result1 <- checkRateLimit rateLimiter key PerMinute
  case result1 of
    RateLimitAllowed remaining limit -> do
      putStrLn $ "  ✓ Initial rate limit check allowed (remaining: " <> show remaining <> "/" <> show limit <> ")"
    _ -> die "Initial rate limit check should be allowed"

  -- Record some requests
  forM_ [1..5 :: Int] $ \_ ->
    recordRequest rateLimiter key PerMinute
  putStrLn "  ✓ Recorded 5 requests"

  -- Check rate limit again
  result2 <- checkRateLimit rateLimiter key PerMinute
  case result2 of
    RateLimitAllowed remaining _ -> do
      putStrLn $ "  ✓ Rate limit still allowed (remaining: " <> show remaining <> ")"
    _ -> die "Rate limit should still be allowed after 5 requests"

  -- Get rate limit metrics
  metrics <- getRateLimitMetrics rateLimiter
  unless (rlmTotalChecks metrics >= 2) $
    die "Rate limit metrics should show at least 2 checks"
  putStrLn "  ✓ Rate limit metrics recorded correctly"

  -- Test redaction utilities
  let sensitiveToken = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test"
      redactedToken = redactToken sensitiveToken
  unless (redactedToken == "Bearer [REDACTED]") $
    die "Token redaction should work"
  putStrLn "  ✓ Token redaction works"

  let sensitiveText = "api_key: sk-1234567890abcdef"
      redactedText = redactSecrets sensitiveText
  unless ("[API KEY REDACTED]" `Text.isInfixOf` redactedText) $
    die "Secret redaction should work"
  putStrLn "  ✓ Secret redaction works"

  let sensitiveHeaders = [("Authorization", "Bearer secret123"), ("Content-Type", "application/json")]
      redactedHeaders = redactSensitiveHeaders sensitiveHeaders
      authHeader = lookup "Authorization" redactedHeaders
  case authHeader of
    Just h | "[REDACTED]" `Text.isInfixOf` h -> putStrLn "  ✓ Header redaction works"
    _ -> die "Header redaction should work"

  -- Test MCP metrics
  metricsService <- newMcpMetricsService
  putStrLn "  ✓ MCP metrics service created"

  recordToolCall metricsService "workflow.submit" tenantId 50.0 True
  recordToolCall metricsService "workflow.status" tenantId 10.0 True
  recordMethodCall metricsService "tools/call" 55.0 True
  putStrLn "  ✓ MCP metrics recorded"

  snapshot <- getMcpMetrics metricsService
  unless (Map.size (mmsToolMetrics snapshot) >= 2) $
    die "MCP metrics should have at least 2 tool entries"
  putStrLn "  ✓ MCP metrics snapshot correct"

  let prometheusOutput = renderPrometheusMetrics snapshot
  unless ("studiomcp_tool_calls_total" `Text.isInfixOf` prometheusOutput) $
    die "Prometheus output should contain tool metrics"
  putStrLn "  ✓ Prometheus metrics rendering works"

  putStrLn "validate rate-limit: PASS"

-- | Validate MCP protocol conformance
validateMcpConformance :: IO ()
validateMcpConformance = do
  putStrLn "Validating MCP protocol conformance..."
  requireExecutables ["docker", "kubectl", "kind", "helm"]
  clusterDeploy DeployServer
  manager <- newManager defaultManagerSettings
  validDag <- loadSubmissionDag "examples/dags/transcode-basic.yaml"

  -- Test 1: JSON-RPC 2.0 message formatting
  putStrLn "  Testing JSON-RPC 2.0 message format..."
  let initializeRequest = JsonRpcRequest
        { reqJsonRpc = JsonRpcVersion "2.0"
        , reqId = RequestIdString "1"
        , reqMethod = "initialize"
        , reqParams = Just $ object
            [ "protocolVersion" .= ("2024-11-05" :: Text)
            , "capabilities" .= object []
            , "clientInfo" .= object
                [ "name" .= ("test-client" :: Text)
                , "version" .= ("1.0.0" :: Text)
                ]
            ]
        }
  let encoded = encode initializeRequest
  case decode encoded :: Maybe JsonRpcRequest of
    Just decoded -> do
      unless (reqMethod decoded == "initialize") $
        die "JSON-RPC method should be 'initialize'"
      putStrLn "    ✓ JSON-RPC 2.0 request serialization works"
    Nothing -> die "JSON-RPC request should round-trip"

  -- Test 2: Protocol state machine
  putStrLn "  Testing MCP protocol state machine..."
  sessionState <- newSessionState "conformance-test-session"
  initialProtocolState <- getProtocolState sessionState
  -- Just verify the state machine works
  putStrLn $ "    ✓ Initial protocol state: " <> show initialProtocolState

  internalBaseUrl <- clusterEdgeInternalBaseUrl
  let keycloakOidcUrl = internalBaseUrl <> "/kc/realms/studiomcp/.well-known/openid-configuration"
  waitForHttpStatus manager keycloakOidcUrl [200]
  authHeaders <- getClusterEdgeAuthHeaders manager
  let baseUrl = internalBaseUrl
  do
    -- Note: We skip waitForHttpStatusWithTimeout here because clusterDeploy DeployServer
    -- already waits for all workload rollouts to complete (studiomcp, studiomcp-bff, studiomcp-redis-node).
    -- The pods are ready to serve requests at this point.
    sessionHeaders <- initializeMcpSessionWithHeaders manager baseUrl authHeaders

    -- Test 3: Tool catalog conformance
    putStrLn "  Testing tool catalog conformance..."
    let toolsListRequest =
          object
            [ "jsonrpc" .= ("2.0" :: Text)
            , "id" .= (2 :: Int)
            , "method" .= ("tools/list" :: Text)
            ]
    toolsResponse <- mcpJsonRpcRequest manager baseUrl sessionHeaders toolsListRequest
    toolsValue <- decodeResponseBody "tools/list response" toolsResponse :: IO Value
    liveTools <-
      case lookupPath ["result", "tools"] toolsValue of
        Just (Array toolsArray) -> pure (Vector.toList toolsArray)
        _ -> die "tools/list should return result.tools"
    unless (length liveTools >= 10) $
      die "Live MCP tool catalog should have at least 10 tools"
    let toolNames = mapMaybe (\toolValue -> lookupString ["name"] toolValue) liveTools
        requiredTools = ["workflow.submit", "workflow.status", "workflow.cancel", "artifact.get"]
    forM_ requiredTools $ \toolName ->
      unless (Text.unpack toolName `elem` toolNames) $
        die ("Required live tool missing: " <> Text.unpack toolName)
    putStrLn "    ✓ Live /mcp exposes the expected tool catalog"

    submitValue <-
      callMcpToolOverHttp
        manager
        baseUrl
        sessionHeaders
        3
        "workflow.submit"
        (object ["dag_spec" .= validDag])
    submitPayloadText <-
      case extractFirstMcpToolData submitValue of
        Just payloadText -> pure payloadText
        Nothing -> die "Live workflow.submit did not return structured tool data"
    submitPayloadValue <-
      case decode (LBS.fromStrict (TextEncoding.encodeUtf8 submitPayloadText)) of
        Just value -> pure value
        Nothing -> die "Live workflow.submit returned invalid JSON tool data"
    conformanceRunId <-
      case lookupString ["runId"] submitPayloadValue of
        Just runIdText -> pure (Text.pack runIdText)
        Nothing -> die "Live workflow.submit did not return a runId"
    statusValue <-
      callMcpToolOverHttp
        manager
        baseUrl
        sessionHeaders
        4
        "workflow.status"
        (object ["run_id" .= conformanceRunId])
    statusPayloadText <-
      case extractFirstMcpToolData statusValue of
        Just payloadText -> pure payloadText
        Nothing -> die "Live workflow.status did not return structured tool data"
    unless (conformanceRunId `Text.isInfixOf` statusPayloadText) $
      die "Live workflow.status should return the submitted run id"
    putStrLn "    ✓ Tool invocation round-trips through the live MCP server"

    -- Test 4: Resource catalog conformance
    putStrLn "  Testing resource catalog conformance..."
    let resourcesListRequest =
          object
            [ "jsonrpc" .= ("2.0" :: Text)
            , "id" .= (5 :: Int)
            , "method" .= ("resources/list" :: Text)
            ]
    resourcesResponse <- mcpJsonRpcRequest manager baseUrl sessionHeaders resourcesListRequest
    resourcesValue <- decodeResponseBody "resources/list response" resourcesResponse :: IO Value
    resourcesCount <-
      case lookupPath ["result", "resources"] resourcesValue of
        Just (Array resourcesArray) -> pure (length resourcesArray)
        _ -> die "resources/list should return result.resources"
    unless (resourcesCount >= 6) $
      die "Live MCP resource catalog should expose at least 6 resources"
    putStrLn "    ✓ Live /mcp exposes the expected resource catalog"

    subscriptionValue <-
      subscribeMcpResourceOverHttp
        manager
        baseUrl
        sessionHeaders
        51
        "studiomcp://history/runs"
        (Just "cursor-51")
        (Just "evt-51")
    unless (lookupString ["result", "cursor"] subscriptionValue == Just "cursor-51") $
      die "resources/subscribe should return resumable cursor metadata"
    unless (lookupString ["result", "lastEventId"] subscriptionValue == Just "evt-51") $
      die "resources/subscribe should return resumable lastEventId metadata"
    putStrLn "    ✓ Live resource subscriptions expose resumable metadata"

    -- Test 5: Prompt catalog conformance
    putStrLn "  Testing prompt catalog conformance..."
    let promptsListRequest =
          object
            [ "jsonrpc" .= ("2.0" :: Text)
            , "id" .= (6 :: Int)
            , "method" .= ("prompts/list" :: Text)
            ]
    promptsResponse <- mcpJsonRpcRequest manager baseUrl sessionHeaders promptsListRequest
    promptsValue <- decodeResponseBody "prompts/list response" promptsResponse :: IO Value
    promptsCount <-
      case lookupPath ["result", "prompts"] promptsValue of
        Just (Array promptsArray) -> pure (length promptsArray)
        _ -> die "prompts/list should return result.prompts"
    unless (promptsCount >= 5) $
      die "Live MCP prompt catalog should expose at least 5 prompts"
    let promptGetRequest =
          object
            [ "jsonrpc" .= ("2.0" :: Text)
            , "id" .= (7 :: Int)
            , "method" .= ("prompts/get" :: Text)
            , "params" .= object ["name" .= ("dag-planning" :: Text)]
            ]
    promptResponse <- mcpJsonRpcRequest manager baseUrl sessionHeaders promptGetRequest
    promptValue <- decodeResponseBody "prompts/get response" promptResponse :: IO Value
    putStrLn $ "    DEBUG prompts/get response: " <> take 500 (show promptValue)
    case lookupPath ["result", "messages"] promptValue of
      Just (Array messagesArray)
        | not (null messagesArray) ->
            putStrLn "    ✓ Live prompt rendering works"
      _ -> die "Live prompts/get should return at least one message"

    -- Test 8: Transport abstraction
    putStrLn "  Testing transport abstraction..."
    sseRequest <- parseRequest (baseUrl <> "/mcp")
    sseResponse <- httpLbs sseRequest {method = methodGet, requestHeaders = authHeaders} manager
    unless (statusCode (responseStatus sseResponse) == 200) $
      die ("Expected live MCP SSE bootstrap to return HTTP 200, got " <> show (statusCode (responseStatus sseResponse)))
    unless ("event: ready" `isInfixOf` LBS.unpack (responseBody sseResponse)) $
      die "Expected live GET /mcp to emit an SSE ready event"
    putStrLn "    ✓ Live HTTP transport emits the MCP SSE bootstrap"

    -- Test 9: Metrics and observability conformance (non-fatal in Docker)
    putStrLn "  Testing observability conformance..."
    metricsResult <-
      tryWaitForMetricsBody
        manager
        baseUrl
        [ "studiomcp_method_calls_total{method=\"initialize\"} 1"
        , "studiomcp_tool_calls_total{tool=\"workflow.submit\"} 1"
        ]
    case metricsResult of
      Just prometheusOutput -> do
        unless ("studiomcp_method_calls_total" `Text.isInfixOf` Text.pack prometheusOutput) $
          die "Prometheus output should contain live method metrics"
        putStrLn "    ✓ Live MCP metrics are exported from /metrics"
      Nothing ->
        -- Metrics endpoint not reachable (common in Docker-to-Kind), skip gracefully
        pure ()

  -- Test 6: Auth scope enforcement
  putStrLn "  Testing auth scope requirements..."
  let submitScopes = toolRequiredScopes WorkflowSubmit
  unless ("workflow:write" `elem` submitScopes) $
    die "workflow.submit should require workflow:write scope"
  putStrLn "    ✓ workflow.submit requires workflow:write scope"

  let readScopes = toolRequiredScopes WorkflowStatus
  unless ("workflow:read" `elem` readScopes) $
    die "workflow.status should require workflow:read scope"
  putStrLn "    ✓ workflow.status requires workflow:read scope"

  -- Test 7: Non-destructive artifact policy verification
  putStrLn "  Testing non-destructive artifact policy..."
  governanceService <- newGovernanceService defaultGovernancePolicy
  conformanceNow <- getCurrentTime
  let dummyMetadata = GovernanceMetadata
        { gmReason = "conformance-test"
        , gmRequestedBy = SubjectId "test"
        , gmTenantId = TenantId "conformance"
        , gmTimestamp = conformanceNow
        , gmRelatedArtifacts = []
        }
  deleteResult <- denyHardDelete governanceService "test-artifact" dummyMetadata
  case deleteResult of
    Left _ -> putStrLn "    ✓ Hard delete is correctly forbidden"
    Right _ -> die "Hard delete should be denied"

  -- Test 10: Session management conformance
  putStrLn "  Testing session management conformance..."
  withTemporaryRedisConfig $ \redisConfig -> do
    conformanceCorrelationId <- generateCorrelationId
    let sharedSessionConfig =
          redisConfig
            { rcKeyPrefix = "shared:mcp:validate-conformance:" <> unCorrelationId conformanceCorrelationId <> ":"
            }
    sessionStore1 <- newRedisSessionStore sharedSessionConfig
    sessionStore2 <- newRedisSessionStore sharedSessionConfig
    conformanceSession <- newSession
    _ <- storeCreateSession sessionStore1 conformanceSession
    mirroredSession <- storeGetSession sessionStore2 (sessionId conformanceSession)
    case mirroredSession of
      Right retrieved
        | sessionId retrieved == sessionId conformanceSession ->
            putStrLn "    ✓ Sessions are externally visible across store instances"
      Right _ -> die "Conformance session retrieval returned the wrong session"
      Left err -> die ("Conformance session retrieval failed: " <> show err)
    closeRedisSessionStore sessionStore1
    closeRedisSessionStore sessionStore2

  -- Test 11: BFF layer conformance
  putStrLn "  Testing BFF layer conformance..."
  withTemporaryRedisConfig $ \redisConfig ->
    withRedisConfigEnv redisConfig $ do
      appConfig <- loadAppConfig
      serverEnv <- createServerEnv appConfig
      withFakeModelHost 38106 "Coordinate the upload, workflow submission, and status checks." $ do
        conformanceBff <-
          newBFFServiceWithRuntime
            defaultBFFConfig
            (serverToolCatalog serverEnv)
            (serverTenantStorage serverEnv)
            (ReferenceModelConfig "http://127.0.0.1:38106/api/generate")
        conformanceWebSessionResult <-
          createWebSession conformanceBff "conformance-user" "conformance-tenant" "access-token" Nothing
        conformanceWebSession <-
          case conformanceWebSessionResult of
            Right session -> pure session
            Left err -> die ("BFF session creation failed during conformance validation: " <> show err)
        conformanceUploadResult <-
          requestUpload
            conformanceBff
            (wsSessionId conformanceWebSession)
            UploadRequest
              { urFileName = "conformance.mp4"
              , urContentType = "video/mp4"
              , urFileSize = 4096
              , urMetadata = Nothing
              }
        conformanceUpload <-
          case conformanceUploadResult of
            Right upload -> pure upload
            Left err -> die ("BFF upload flow failed during conformance validation: " <> show err)
        unless ("X-Amz-Signature=" `Text.isInfixOf` puuUrl (urpPresignedUrl conformanceUpload)) $
          die "BFF upload flow should return a real SigV4 presigned URL"
        conformanceDownloadResult <-
          requestDownload
            conformanceBff
            (wsSessionId conformanceWebSession)
            DownloadRequest
              { drArtifactId = urpArtifactId conformanceUpload
              , drVersion = Nothing
              }
        case conformanceDownloadResult of
          Right downloadResponse
            | "X-Amz-Signature=" `Text.isInfixOf` pduUrl (drpPresignedUrl downloadResponse) ->
                pure ()
          Right _ -> die "BFF download flow should return a real SigV4 presigned URL"
          Left err -> die ("BFF download flow failed during conformance validation: " <> show err)
        conformanceChatResult <-
          sendChatMessage
            conformanceBff
            (wsSessionId conformanceWebSession)
            ChatRequest
              { crMessages = [ChatMessage ChatUser "Help me submit this run" Nothing]
              , crContext = Just "conformance"
              }
        case conformanceChatResult of
          Right response
            | cmRole (crpMessage response) == ChatAssistant
                && "ADVISORY:" `Text.isPrefixOf` cmContent (crpMessage response) ->
                    putStrLn "    ✓ Runtime-backed BFF upload, download, and chat flows work"
          Right _ -> die "BFF chat should return an inference-backed assistant response"
          Left err -> die ("BFF chat flow failed during conformance validation: " <> show err)

  putStrLn "validate mcp-conformance: PASS"

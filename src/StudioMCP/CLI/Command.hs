module StudioMCP.CLI.Command
  ( Command (..),
    DagCommand (..),
    ClusterCommand (..),
    ClusterDeployTarget (..),
    ClusterStorageCommand (..),
    ValidateCommand (..),
    TestCommand (..),
    parseCommand,
    usageText,
  )
where

data Command
  = ServerCommand
  | StdioCommand
  | BffCommand
  | InferenceCommand
  | WorkerCommand
  | ValidateDagCommand FilePath
  | DagCommand DagCommand
  | ValidateCommand ValidateCommand
  | ClusterCommand ClusterCommand
  | TestCommand TestCommand
  deriving (Eq, Show)

data DagCommand
  = DagValidateFixturesCommand
  deriving (Eq, Show)

data ValidateCommand
  = ValidateAllCommand -- Run all validators
  | ValidateDocsCommand
  | ValidateClusterCommand
  | ValidateE2ECommand
  | ValidateWorkerCommand
  | ValidatePulsarCommand
  | ValidateMinioCommand
  | ValidateBoundaryCommand
  | ValidateFFmpegAdapterCommand
  | ValidateExecutorCommand
  | ValidateMcpStdioCommand -- Phase 13: MCP over stdio transport
  | ValidateMcpHttpCommand -- Phase 13: MCP over HTTP transport
  | ValidateKeycloakCommand -- Phase 14: Keycloak connectivity
  | ValidateMcpAuthCommand -- Phase 14: MCP auth validation
  | ValidateSessionStoreCommand -- Phase 15: Session store validation
  | ValidateHorizontalScaleCommand -- Phase 15: Horizontal scaling validation
  | ValidateWebBffCommand -- Phase 16: Web BFF validation
  | ValidateArtifactStorageCommand -- Phase 17: Artifact storage validation
  | ValidateArtifactGovernanceCommand -- Phase 17: Artifact governance validation
  | ValidateMcpToolsCommand -- Phase 18: MCP tools validation
  | ValidateMcpResourcesCommand -- Phase 18: MCP resources validation
  | ValidateMcpPromptsCommand -- Phase 18: MCP prompts validation
  | ValidateInferenceCommand
  | ValidateObservabilityCommand
  | ValidateAuditCommand -- Phase 19: Audit validation
  | ValidateQuotasCommand -- Phase 19: Quota validation
  | ValidateRateLimitCommand -- Phase 19: Rate limit validation
  | ValidateMcpConformanceCommand -- Phase 21: MCP protocol conformance
  | ValidateStoragePolicyCommand -- Storage policy enforcement validation
  deriving (Eq, Show)

data ClusterCommand
  = ClusterUpCommand
  | ClusterDownCommand
  | ClusterResetCommand
  | ClusterStatusCommand
  | ClusterEnsureCommand
  | ClusterDeployCommand ClusterDeployTarget
  | ClusterStorageCommand ClusterStorageCommand
  deriving (Eq, Show)

data ClusterDeployTarget
  = DeploySidecars
  | DeployServer
  deriving (Eq, Show)

data ClusterStorageCommand
  = ClusterStorageReconcile
  | ClusterStorageDelete String
  deriving (Eq, Show)

data TestCommand
  = TestAllCommand
  | TestUnitCommand
  | TestIntegrationCommand
  deriving (Eq, Show)

parseCommand :: [String] -> Either String Command
parseCommand args =
  case args of
    ["server"] -> Right ServerCommand
    ["stdio"] -> Right StdioCommand
    ["bff"] -> Right BffCommand
    ["inference"] -> Right InferenceCommand
    ["worker"] -> Right WorkerCommand
    ["validate-dag", dagPath] -> Right (ValidateDagCommand dagPath)
    ["dag", "validate", dagPath] -> Right (ValidateDagCommand dagPath)
    ["dag", "validate-fixtures"] -> Right (DagCommand DagValidateFixturesCommand)
    ["validate", "all"] -> Right (ValidateCommand ValidateAllCommand)
    ["validate", "docs"] -> Right (ValidateCommand ValidateDocsCommand)
    ["validate", "cluster"] -> Right (ValidateCommand ValidateClusterCommand)
    ["validate", "e2e"] -> Right (ValidateCommand ValidateE2ECommand)
    ["validate", "worker"] -> Right (ValidateCommand ValidateWorkerCommand)
    ["validate", "pulsar"] -> Right (ValidateCommand ValidatePulsarCommand)
    ["validate", "minio"] -> Right (ValidateCommand ValidateMinioCommand)
    ["validate", "boundary"] -> Right (ValidateCommand ValidateBoundaryCommand)
    ["validate", "ffmpeg-adapter"] -> Right (ValidateCommand ValidateFFmpegAdapterCommand)
    ["validate", "executor"] -> Right (ValidateCommand ValidateExecutorCommand)
    ["validate", "mcp-stdio"] -> Right (ValidateCommand ValidateMcpStdioCommand)
    ["validate", "mcp-http"] -> Right (ValidateCommand ValidateMcpHttpCommand)
    ["validate", "keycloak"] -> Right (ValidateCommand ValidateKeycloakCommand)
    ["validate", "mcp-auth"] -> Right (ValidateCommand ValidateMcpAuthCommand)
    ["validate", "session-store"] -> Right (ValidateCommand ValidateSessionStoreCommand)
    ["validate", "mcp-session-store"] -> Right (ValidateCommand ValidateSessionStoreCommand)
    ["validate", "horizontal-scale"] -> Right (ValidateCommand ValidateHorizontalScaleCommand)
    ["validate", "mcp-horizontal-scale"] -> Right (ValidateCommand ValidateHorizontalScaleCommand)
    ["validate", "web-bff"] -> Right (ValidateCommand ValidateWebBffCommand)
    ["validate", "artifact-storage"] -> Right (ValidateCommand ValidateArtifactStorageCommand)
    ["validate", "artifact-governance"] -> Right (ValidateCommand ValidateArtifactGovernanceCommand)
    ["validate", "mcp-tools"] -> Right (ValidateCommand ValidateMcpToolsCommand)
    ["validate", "mcp-resources"] -> Right (ValidateCommand ValidateMcpResourcesCommand)
    ["validate", "mcp-prompts"] -> Right (ValidateCommand ValidateMcpPromptsCommand)
    ["validate", "inference"] -> Right (ValidateCommand ValidateInferenceCommand)
    ["validate", "observability"] -> Right (ValidateCommand ValidateObservabilityCommand)
    ["validate", "audit"] -> Right (ValidateCommand ValidateAuditCommand)
    ["validate", "quotas"] -> Right (ValidateCommand ValidateQuotasCommand)
    ["validate", "rate-limit"] -> Right (ValidateCommand ValidateRateLimitCommand)
    ["validate", "mcp-conformance"] -> Right (ValidateCommand ValidateMcpConformanceCommand)
    ["validate", "storage-policy"] -> Right (ValidateCommand ValidateStoragePolicyCommand)
    ["cluster", "up"] -> Right (ClusterCommand ClusterUpCommand)
    ["cluster", "down"] -> Right (ClusterCommand ClusterDownCommand)
    ["cluster", "reset"] -> Right (ClusterCommand ClusterResetCommand)
    ["cluster", "status"] -> Right (ClusterCommand ClusterStatusCommand)
    ["cluster", "ensure"] -> Right (ClusterCommand ClusterEnsureCommand)
    ["cluster", "deploy", "sidecars"] -> Right (ClusterCommand (ClusterDeployCommand DeploySidecars))
    ["cluster", "deploy", "server"] -> Right (ClusterCommand (ClusterDeployCommand DeployServer))
    ["cluster", "storage", "reconcile"] -> Right (ClusterCommand (ClusterStorageCommand ClusterStorageReconcile))
    ["cluster", "storage", "delete", name] -> Right (ClusterCommand (ClusterStorageCommand (ClusterStorageDelete name)))
    ["test"] -> Right (TestCommand TestAllCommand)
    ["test", "all"] -> Right (TestCommand TestAllCommand)
    ["test", "unit"] -> Right (TestCommand TestUnitCommand)
    ["test", "integration"] -> Right (TestCommand TestIntegrationCommand)
    _ -> Left usageText

usageText :: String
usageText =
  unlines
    [ "usage:"
    , "  studiomcp server"
    , "  studiomcp stdio"
    , "  studiomcp bff"
    , "  studiomcp inference"
    , "  studiomcp worker"
    , "  studiomcp validate-dag <path>"
    , "  studiomcp dag validate <path>"
    , "  studiomcp dag validate-fixtures"
    , "  studiomcp validate all             # Run all validators"
    , "  studiomcp validate docs"
    , "  studiomcp validate cluster"
    , "  studiomcp validate e2e"
    , "  studiomcp validate worker"
    , "  studiomcp validate pulsar"
    , "  studiomcp validate minio"
    , "  studiomcp validate boundary"
    , "  studiomcp validate ffmpeg-adapter"
    , "  studiomcp validate executor"
    , "  studiomcp validate mcp-stdio        # MCP over stdio transport"
    , "  studiomcp validate mcp-http         # MCP over HTTP transport"
    , "  studiomcp validate keycloak         # Keycloak connectivity"
    , "  studiomcp validate mcp-auth         # MCP auth validation"
    , "  studiomcp validate session-store    # Session store validation"
    , "  studiomcp validate mcp-session-store # Session store validation (alias)"
    , "  studiomcp validate horizontal-scale # Horizontal scaling validation"
    , "  studiomcp validate mcp-horizontal-scale # Horizontal scaling validation (alias)"
    , "  studiomcp validate web-bff          # Web BFF validation"
    , "  studiomcp validate artifact-storage # Artifact storage validation"
    , "  studiomcp validate artifact-governance # Artifact governance validation"
    , "  studiomcp validate mcp-tools        # MCP tools catalog validation"
    , "  studiomcp validate mcp-resources    # MCP resources catalog validation"
    , "  studiomcp validate mcp-prompts      # MCP prompts catalog validation"
    , "  studiomcp validate inference"
    , "  studiomcp validate observability"
    , "  studiomcp validate audit            # Audit trail validation"
    , "  studiomcp validate quotas           # Quota enforcement validation"
    , "  studiomcp validate rate-limit       # Rate limiting validation"
    , "  studiomcp validate mcp-conformance # MCP protocol conformance"
    , "  studiomcp validate storage-policy # Storage policy enforcement"
    , "  studiomcp cluster up"
    , "  studiomcp cluster down"
    , "  studiomcp cluster reset"
    , "  studiomcp cluster status"
    , "  studiomcp cluster ensure            # Idempotent: up + sidecars + wait for all services"
    , "  studiomcp cluster deploy sidecars"
    , "  studiomcp cluster deploy server"
    , "  studiomcp cluster storage reconcile"
    , "  studiomcp cluster storage delete <name>"
    , "  studiomcp test                     # Run all tests (unit + integration)"
    , "  studiomcp test all                 # Run all tests (unit + integration)"
    , "  studiomcp test unit                # Run unit tests only"
    , "  studiomcp test integration         # Run integration tests only"
    ]

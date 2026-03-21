module StudioMCP.CLI.Command
  ( Command (..),
    DagCommand (..),
    ClusterCommand (..),
    ClusterDeployTarget (..),
    ClusterStorageCommand (..),
    ValidateCommand (..),
    parseCommand,
    usageText,
  )
where

data Command
  = ServerCommand
  | InferenceCommand
  | WorkerCommand
  | ValidateDagCommand FilePath
  | DagCommand DagCommand
  | ValidateCommand ValidateCommand
  | ClusterCommand ClusterCommand
  deriving (Eq, Show)

data DagCommand
  = DagValidateFixturesCommand
  deriving (Eq, Show)

data ValidateCommand
  = ValidateDocsCommand
  | ValidateClusterCommand
  | ValidateE2ECommand
  | ValidateWorkerCommand
  | ValidatePulsarCommand
  | ValidateMinioCommand
  | ValidateBoundaryCommand
  | ValidateFFmpegAdapterCommand
  | ValidateExecutorCommand
  | ValidateMcpCommand
  | ValidateInferenceCommand
  | ValidateObservabilityCommand
  deriving (Eq, Show)

data ClusterCommand
  = ClusterUpCommand
  | ClusterDownCommand
  | ClusterStatusCommand
  | ClusterDeployCommand ClusterDeployTarget
  | ClusterStorageCommand ClusterStorageCommand
  deriving (Eq, Show)

data ClusterDeployTarget
  = DeploySidecars
  | DeployServer
  deriving (Eq, Show)

data ClusterStorageCommand
  = ClusterStorageReconcile
  deriving (Eq, Show)

parseCommand :: [String] -> Either String Command
parseCommand args =
  case args of
    ["server"] -> Right ServerCommand
    ["inference"] -> Right InferenceCommand
    ["worker"] -> Right WorkerCommand
    ["validate-dag", dagPath] -> Right (ValidateDagCommand dagPath)
    ["dag", "validate", dagPath] -> Right (ValidateDagCommand dagPath)
    ["dag", "validate-fixtures"] -> Right (DagCommand DagValidateFixturesCommand)
    ["validate", "docs"] -> Right (ValidateCommand ValidateDocsCommand)
    ["validate", "cluster"] -> Right (ValidateCommand ValidateClusterCommand)
    ["validate", "e2e"] -> Right (ValidateCommand ValidateE2ECommand)
    ["validate", "worker"] -> Right (ValidateCommand ValidateWorkerCommand)
    ["validate", "pulsar"] -> Right (ValidateCommand ValidatePulsarCommand)
    ["validate", "minio"] -> Right (ValidateCommand ValidateMinioCommand)
    ["validate", "boundary"] -> Right (ValidateCommand ValidateBoundaryCommand)
    ["validate", "ffmpeg-adapter"] -> Right (ValidateCommand ValidateFFmpegAdapterCommand)
    ["validate", "executor"] -> Right (ValidateCommand ValidateExecutorCommand)
    ["validate", "mcp"] -> Right (ValidateCommand ValidateMcpCommand)
    ["validate", "inference"] -> Right (ValidateCommand ValidateInferenceCommand)
    ["validate", "observability"] -> Right (ValidateCommand ValidateObservabilityCommand)
    ["cluster", "up"] -> Right (ClusterCommand ClusterUpCommand)
    ["cluster", "down"] -> Right (ClusterCommand ClusterDownCommand)
    ["cluster", "status"] -> Right (ClusterCommand ClusterStatusCommand)
    ["cluster", "deploy", "sidecars"] -> Right (ClusterCommand (ClusterDeployCommand DeploySidecars))
    ["cluster", "deploy", "server"] -> Right (ClusterCommand (ClusterDeployCommand DeployServer))
    ["cluster", "storage", "reconcile"] -> Right (ClusterCommand (ClusterStorageCommand ClusterStorageReconcile))
    _ -> Left usageText

usageText :: String
usageText =
  unlines
    [ "usage:"
    , "  studiomcp server"
    , "  studiomcp inference"
    , "  studiomcp worker"
    , "  studiomcp validate-dag <path>"
    , "  studiomcp dag validate <path>"
    , "  studiomcp dag validate-fixtures"
    , "  studiomcp validate docs"
    , "  studiomcp validate cluster"
    , "  studiomcp validate e2e"
    , "  studiomcp validate worker"
    , "  studiomcp validate pulsar"
    , "  studiomcp validate minio"
    , "  studiomcp validate boundary"
    , "  studiomcp validate ffmpeg-adapter"
    , "  studiomcp validate executor"
    , "  studiomcp validate mcp"
    , "  studiomcp validate inference"
    , "  studiomcp validate observability"
    , "  studiomcp cluster up"
    , "  studiomcp cluster down"
    , "  studiomcp cluster status"
    , "  studiomcp cluster deploy sidecars"
    , "  studiomcp cluster deploy server"
    , "  studiomcp cluster storage reconcile"
    ]

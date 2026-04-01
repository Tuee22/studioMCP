module Main (main) where

import BFFMode (runBffMode)
import StudioMCP.CLI.Cluster (runClusterCommand, runValidateCommand)
import StudioMCP.CLI.Command
  ( Command (..),
    parseCommand,
    usageText,
  )
import StudioMCP.CLI.Dag (runDagCommand, validateDagFileCommand)
import StudioMCP.Inference.Host (runInferenceMode)
import StudioMCP.MCP.Server (runServer)
import StudioMCP.Worker.Server (runWorkerMode)
import System.Environment (getArgs)
import System.Exit (die)

main :: IO ()
main = do
  args <- getArgs
  case parseCommand args of
    Left _ -> die usageText
    Right command ->
      case command of
        ServerCommand -> runServer
        BffCommand -> runBffMode
        InferenceCommand -> runInferenceMode
        WorkerCommand -> runWorkerMode
        ValidateDagCommand dagPath -> validateDagFileCommand dagPath
        DagCommand dagCommand -> runDagCommand dagCommand
        ValidateCommand validateCommand -> runValidateCommand validateCommand
        ClusterCommand clusterCommand -> runClusterCommand clusterCommand

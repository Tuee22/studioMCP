module Main (main) where

import BFFMode (runBffMode)
import StudioMCP.CLI.Cluster (runClusterCommand, runValidateCommand)
import StudioMCP.CLI.Command
  ( Command (..),
    parseCommand,
    usageText,
  )
import StudioMCP.CLI.Dag (runDagCommand, validateDagFileCommand)
import StudioMCP.CLI.Test (runTestCommand)
import StudioMCP.Inference.Host (runInferenceMode)
import StudioMCP.MCP.Server (runServer, runServerStdio)
import StudioMCP.Worker.Server (runWorkerMode)
import System.Environment (getArgs)
import System.Exit (die, exitSuccess)

main :: IO ()
main = do
  args <- getArgs
  case parseCommand args of
    Left _ -> die usageText
    Right command ->
      case command of
        HelpCommand -> putStrLn usageText >> exitSuccess
        ServerCommand -> runServer
        StdioCommand -> runServerStdio
        BffCommand -> runBffMode
        InferenceCommand -> runInferenceMode
        WorkerCommand -> runWorkerMode
        ValidateDagCommand dagPath -> validateDagFileCommand dagPath
        DagCommand dagCommand -> runDagCommand dagCommand
        ValidateCommand validateCommand -> runValidateCommand validateCommand
        ClusterCommand clusterCommand -> runClusterCommand clusterCommand
        TestCommand testCommand -> runTestCommand testCommand

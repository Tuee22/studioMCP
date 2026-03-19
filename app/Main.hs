module Main (main) where

import StudioMCP.DAG.Parser (loadDagFile)
import StudioMCP.DAG.Validator (renderFailures, validateDag)
import StudioMCP.Inference.Host (runInferenceMode)
import StudioMCP.MCP.Server (runServer)
import StudioMCP.Result.Types (Result (Failure, Success))
import StudioMCP.Tools.Process (runWorkerMode)
import System.Environment (getArgs)
import System.Exit (die)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["server"] -> runServer
    ["inference"] -> runInferenceMode
    ["worker"] -> runWorkerMode
    ["validate-dag", dagPath] -> validateDagFile dagPath
    _ ->
      die
        "usage: studiomcp {server|inference|worker|validate-dag <path>}"

validateDagFile :: FilePath -> IO ()
validateDagFile dagPath = do
  decoded <- loadDagFile dagPath
  dagSpec <- either die pure decoded
  case validateDag dagSpec of
    Success _ -> putStrLn "DAG is valid."
    Failure failures -> die (renderFailures failures)

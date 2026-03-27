{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Tools.Boundary
  ( BoundaryCommand (..),
    BoundaryResult (..),
    runBoundaryCommand,
    validateBoundaryRuntime,
  )
where

import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (IOException, SomeException, evaluate, try)
import Control.Monad (void)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import StudioMCP.Result.Failure
  ( FailureCategory (TimeoutFailure, ToolProcessFailure),
    FailureDetail (..),
    failureCode,
  )
import System.Exit (ExitCode (..))
import System.IO (Handle, hClose, hGetContents)
import System.Process
  ( CreateProcess (create_group, std_err, std_in, std_out),
    ProcessHandle,
    StdStream (CreatePipe),
    getPid,
    getProcessExitCode,
    proc,
    terminateProcess,
    withCreateProcess,
  )
import System.Posix.Signals (sigKILL, sigTERM, signalProcessGroup)

data BoundaryCommand = BoundaryCommand
  { boundaryExecutable :: FilePath,
    boundaryArguments :: [String],
    boundaryStdin :: Text,
    boundaryTimeoutSeconds :: Int
  }
  deriving (Eq, Show)

data BoundaryResult = BoundaryResult
  { boundaryStdout :: Text,
    boundaryStderr :: Text,
    boundaryExitCode :: Int
  }
  deriving (Eq, Show)

runBoundaryCommand :: BoundaryCommand -> IO (Either FailureDetail BoundaryResult)
runBoundaryCommand command =
  do
    commandResult <- try (runBoundaryCommandUnchecked command) :: IO (Either IOException (Either FailureDetail BoundaryResult))
    case commandResult of
      Left ioException ->
        pure
          ( Left
              FailureDetail
                { failureCategory = ToolProcessFailure,
                  failureCode = "boundary-launch-failed",
                  failureMessage = "The boundary process could not be launched.",
                  failureRetryable = False,
                  failureContext =
                    Map.fromList
                      [ ("executable", Text.pack (boundaryExecutable command)),
                        ("arguments", renderArguments (boundaryArguments command)),
                        ("ioException", Text.pack (show ioException))
                      ]
                }
          )
      Right result -> pure result

validateBoundaryRuntime :: IO (Either FailureDetail ())
validateBoundaryRuntime = do
  successResult <- runBoundaryCommand successCommand
  case successResult of
    Left failureDetail -> pure (Left failureDetail)
    Right boundaryResult
      | boundaryResult
          /= BoundaryResult
            { boundaryStdout = "boundary-success-stdout",
              boundaryStderr = "boundary-success-stderr",
              boundaryExitCode = 0
            } ->
          pure
            ( Left
                FailureDetail
                  { failureCategory = ToolProcessFailure,
                    failureCode = "boundary-success-mismatch",
                    failureMessage = "The successful boundary helper did not preserve stdout, stderr, and exit code as expected.",
                    failureRetryable = False,
                    failureContext =
                      Map.fromList
                        [ ("stdout", boundaryStdout boundaryResult),
                          ("stderr", boundaryStderr boundaryResult),
                          ("exitCode", Text.pack (show (boundaryExitCode boundaryResult)))
                        ]
                  }
            )
      | otherwise -> do
          failureResult <- runBoundaryCommand failureCommand
          case failureResult of
            Left processFailure
              | failureCode processFailure /= "boundary-process-failed" ->
                  pure (Left (unexpectedFailureCode "boundary-process-failed" processFailure))
              | Map.lookup "stdoutSnippet" (failureContext processFailure) /= Just "boundary-failure-stdout"
                  || Map.lookup "stderrSnippet" (failureContext processFailure) /= Just "boundary-failure-stderr" ->
                  pure
                    ( Left
                        FailureDetail
                          { failureCategory = ToolProcessFailure,
                            failureCode = "boundary-failure-capture-mismatch",
                            failureMessage = "The failing boundary helper did not preserve stdout and stderr in the failure context.",
                            failureRetryable = False,
                            failureContext = failureContext processFailure
                          }
                    )
              | otherwise -> do
                  timeoutResult <- runBoundaryCommand timeoutCommand
                  case timeoutResult of
                    Left timeoutFailure
                      | failureCode timeoutFailure /= "boundary-timeout" ->
                          pure (Left (unexpectedFailureCode "boundary-timeout" timeoutFailure))
                      | Map.lookup "stdoutSnippet" (failureContext timeoutFailure) /= Just "boundary-timeout-stdout"
                          || Map.lookup "stderrSnippet" (failureContext timeoutFailure) /= Just "boundary-timeout-stderr" ->
                          pure
                            ( Left
                                FailureDetail
                                  { failureCategory = TimeoutFailure,
                                    failureCode = "boundary-timeout-capture-mismatch",
                                    failureMessage = "The timed-out boundary helper did not preserve stdout and stderr in the failure context.",
                                    failureRetryable = True,
                                    failureContext = failureContext timeoutFailure
                                  }
                            )
                      | otherwise -> pure (Right ())
                    Right timeoutSuccess ->
                      pure
                        ( Left
                            FailureDetail
                              { failureCategory = TimeoutFailure,
                                failureCode = "boundary-timeout-unexpected-success",
                                failureMessage = "The timed boundary helper unexpectedly succeeded.",
                                failureRetryable = False,
                                failureContext =
                                  Map.fromList
                                    [ ("stdout", boundaryStdout timeoutSuccess),
                                      ("stderr", boundaryStderr timeoutSuccess),
                                      ("exitCode", Text.pack (show (boundaryExitCode timeoutSuccess)))
                                    ]
                              }
                        )
            Right processSuccess ->
              pure
                ( Left
                    FailureDetail
                      { failureCategory = ToolProcessFailure,
                        failureCode = "boundary-failure-unexpected-success",
                        failureMessage = "The failing boundary helper unexpectedly succeeded.",
                        failureRetryable = False,
                        failureContext =
                          Map.fromList
                            [ ("stdout", boundaryStdout processSuccess),
                              ("stderr", boundaryStderr processSuccess),
                              ("exitCode", Text.pack (show (boundaryExitCode processSuccess)))
                            ]
                      }
                )

runBoundaryCommandUnchecked :: BoundaryCommand -> IO (Either FailureDetail BoundaryResult)
runBoundaryCommandUnchecked command =
  withCreateProcess
    (proc (boundaryExecutable command) (boundaryArguments command))
      { create_group = True,
        std_in = CreatePipe,
        std_out = CreatePipe,
        std_err = CreatePipe
      }
    (\maybeStdin maybeStdout maybeStderr processHandle ->
        case (maybeStdin, maybeStdout, maybeStderr) of
          (Just stdinHandle, Just stdoutHandle, Just stderrHandle) -> do
            writeBoundaryInput stdinHandle
            stdoutMVar <- newEmptyMVar
            stderrMVar <- newEmptyMVar
            _ <- forkIO (readFully stdoutHandle >>= putMVar stdoutMVar)
            _ <- forkIO (readFully stderrHandle >>= putMVar stderrMVar)
            let timeoutMicroseconds = boundaryTimeoutSeconds command * 1000000
            exitCodeOrTimeout <- awaitProcessExit processHandle timeoutMicroseconds
            case exitCodeOrTimeout of
              Just exitCodeValue -> do
                stdoutText <- takeMVar stdoutMVar
                stderrText <- takeMVar stderrMVar
                pure (projectBoundaryExit command stdoutText stderrText exitCodeValue)
              Nothing -> do
                terminateBoundaryProcess processHandle
                _ <- awaitProcessExit processHandle 1000000
                stdoutText <- takeMVar stdoutMVar
                stderrText <- takeMVar stderrMVar
                pure (Left (projectBoundaryTimeout command stdoutText stderrText))
          _ ->
            pure
              ( Left
                  FailureDetail
                    { failureCategory = ToolProcessFailure,
                      failureCode = "boundary-process-plumbing-failed",
                      failureMessage = "The boundary process did not expose stdin, stdout, and stderr pipes as expected.",
                      failureRetryable = False,
                      failureContext =
                        Map.fromList
                          [ ("executable", Text.pack (boundaryExecutable command)),
                            ("arguments", renderArguments (boundaryArguments command))
                          ]
                    }
              )
    )
  where
    writeBoundaryInput stdinHandle = do
      if Text.null (boundaryStdin command)
        then pure ()
        else TextIO.hPutStr stdinHandle (boundaryStdin command)
      hClose stdinHandle

terminateBoundaryProcess :: ProcessHandle -> IO ()
terminateBoundaryProcess processHandle = do
  maybePid <- getPid processHandle
  case maybePid of
    Just pid -> do
      void (try (signalProcessGroup sigTERM pid) :: IO (Either SomeException ()))
      threadDelay 100000
      exitCode <- getProcessExitCode processHandle
      case exitCode of
        Just _ -> pure ()
        Nothing -> void (try (signalProcessGroup sigKILL pid) :: IO (Either SomeException ()))
    Nothing ->
      void (try (terminateProcess processHandle) :: IO (Either SomeException ()))

awaitProcessExit :: ProcessHandle -> Int -> IO (Maybe ExitCode)
awaitProcessExit processHandle timeoutMicroseconds =
  go timeoutMicroseconds
  where
    pollIntervalMicroseconds = 100000

    go remainingMicroseconds = do
      exitCode <- getProcessExitCode processHandle
      case exitCode of
        Just exitCodeValue -> pure (Just exitCodeValue)
        Nothing
          | remainingMicroseconds <= 0 ->
              pure Nothing
          | otherwise -> do
              let sleepMicroseconds = min pollIntervalMicroseconds remainingMicroseconds
              threadDelay sleepMicroseconds
              go (remainingMicroseconds - sleepMicroseconds)

readFully :: Handle -> IO Text
readFully handle = do
  contents <- hGetContents handle
  _ <- evaluate (length contents)
  pure (trimTrailingNewlines (Text.pack contents))

trimTrailingNewlines :: Text -> Text
trimTrailingNewlines = Text.dropWhileEnd (`elem` ['\n', '\r'])

projectBoundaryExit :: BoundaryCommand -> Text -> Text -> ExitCode -> Either FailureDetail BoundaryResult
projectBoundaryExit _ stdoutText stderrText ExitSuccess =
  Right
    BoundaryResult
      { boundaryStdout = stdoutText,
        boundaryStderr = stderrText,
        boundaryExitCode = 0
      }
projectBoundaryExit command stdoutText stderrText (ExitFailure exitCodeValue) =
  Left
    FailureDetail
      { failureCategory = ToolProcessFailure,
        failureCode = "boundary-process-failed",
        failureMessage = "The boundary process exited with a non-zero status.",
        failureRetryable = False,
        failureContext =
          Map.fromList
            [ ("executable", Text.pack (boundaryExecutable command)),
              ("arguments", renderArguments (boundaryArguments command)),
              ("exitCode", Text.pack (show exitCodeValue)),
              ("stdoutSnippet", stdoutText),
              ("stderrSnippet", stderrText)
            ]
      }

projectBoundaryTimeout :: BoundaryCommand -> Text -> Text -> FailureDetail
projectBoundaryTimeout command stdoutText stderrText =
  FailureDetail
    { failureCategory = TimeoutFailure,
      failureCode = "boundary-timeout",
      failureMessage = "The boundary process exceeded its timeout budget.",
      failureRetryable = True,
      failureContext =
        Map.fromList
          [ ("executable", Text.pack (boundaryExecutable command)),
            ("arguments", renderArguments (boundaryArguments command)),
            ("timeoutSeconds", Text.pack (show (boundaryTimeoutSeconds command))),
            ("stdoutSnippet", stdoutText),
            ("stderrSnippet", stderrText)
          ]
    }

unexpectedFailureCode :: Text -> FailureDetail -> FailureDetail
unexpectedFailureCode expectedCode observedFailure =
  FailureDetail
    { failureCategory = ToolProcessFailure,
      failureCode = "boundary-failure-code-mismatch",
      failureMessage = "Boundary validation returned an unexpected failure code.",
      failureRetryable = False,
      failureContext =
        Map.fromList
          [ ("expectedFailureCode", expectedCode),
            ("observedFailureCode", failureCode observedFailure)
          ]
            <> failureContext observedFailure
    }

renderArguments :: [String] -> Text
renderArguments = Text.unwords . map Text.pack

successCommand :: BoundaryCommand
successCommand =
  BoundaryCommand
    { boundaryExecutable = "sh",
      boundaryArguments =
        [ "-c",
          "printf 'boundary-success-stdout'; printf 'boundary-success-stderr' 1>&2; exit 0"
        ],
      boundaryStdin = "",
      boundaryTimeoutSeconds = 2
    }

failureCommand :: BoundaryCommand
failureCommand =
  BoundaryCommand
    { boundaryExecutable = "sh",
      boundaryArguments =
        [ "-c",
          "printf 'boundary-failure-stdout'; printf 'boundary-failure-stderr' 1>&2; exit 7"
        ],
      boundaryStdin = "",
      boundaryTimeoutSeconds = 2
    }

timeoutCommand :: BoundaryCommand
timeoutCommand =
  BoundaryCommand
    { boundaryExecutable = "sh",
      boundaryArguments =
        [ "-c",
          "printf 'boundary-timeout-stdout'; printf 'boundary-timeout-stderr' 1>&2; sleep 2"
        ],
      boundaryStdin = "",
      boundaryTimeoutSeconds = 1
    }

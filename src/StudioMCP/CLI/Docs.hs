{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.CLI.Docs
  ( DocProblem,
    markdownFilesToCheck,
    renderProblems,
    validateDocText,
    validateDocsCommand,
  )
where

import Control.Monad (forM, unless)
import qualified Data.ByteString as BS
import Data.List (isPrefixOf, sort)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8')
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.Exit (die)
import System.FilePath ((</>), takeExtension)

type DocProblem = Text

markdownFilesToCheck :: [FilePath]
markdownFilesToCheck =
  [ "README.md"
  , "STUDIOMCP_DEVELOPMENT_PLAN.md"
  ]

validateDocsCommand :: IO ()
validateDocsCommand = do
  docFiles <- findMarkdownFiles "documents"
  let requiredFiles =
        [ "documents/README.md"
        , "documents/documentation_standards.md"
        , "documents/architecture/cli_architecture.md"
        , "documents/architecture/parallel_scheduling.md"
        , "documents/engineering/docker_policy.md"
        , "documents/engineering/k8s_native_dev_policy.md"
        , "documents/engineering/k8s_storage.md"
        , "documents/operations/runbook_local_debugging.md"
        , "documents/reference/cli_surface.md"
        , "documents/reference/mcp_surface.md"
        , "documents/adr/0001_mcp_transport.md"
        , "documents/adr/0002_parallel_scheduling.md"
        ]
  requiredProblems <- fmap concat $
    forM requiredFiles $ \path -> do
      exists <- doesFileExist path
      pure $
        [ "Missing required documentation file: " <> Text.pack path
        | not exists
        ]
  docProblems <- fmap concat $
    forM docFiles $ \path -> do
      fileBytes <- BS.readFile path
      case decodeUtf8' fileBytes of
        Left _ ->
          pure ["Documentation file is not valid UTF-8: " <> Text.pack path]
        Right content ->
          pure (validateDocText path content)
  rootProblems <- fmap concat $
    forM markdownFilesToCheck $ \path -> do
      exists <- doesFileExist path
      pure $
        [ "Missing expected root markdown file: " <> Text.pack path
        | not exists
        ]
  let problems = requiredProblems <> docProblems <> rootProblems
  unless (null problems) $
    die (Text.unpack (renderProblems problems))
  putStrLn "Documentation checks passed."

validateDocText :: FilePath -> Text -> [DocProblem]
validateDocText path content =
  headerProblems
    <> statusProblems
    <> referenceProblems
    <> crossRefProblems
  where
    linesOfText = Text.lines content
    hasLinePrefix prefix = any (prefix `Text.isPrefixOf`) linesOfText
    hasLineContaining needle = any (needle `Text.isInfixOf`) linesOfText
    isDocumentsPath = "documents/" `isPrefixOf` path
    statusLine = findLineWithPrefix "**Status**: "

    headerProblems =
      [ "Missing file header in " <> packedPath
      | isDocumentsPath && not (hasLinePrefix "# File: documents/")
      ]
        <> [ "Missing status header in " <> packedPath
           | isDocumentsPath && not (hasLinePrefix "**Status**: ")
           ]
        <> [ "Missing supersedes header in " <> packedPath
           | isDocumentsPath && not (hasLinePrefix "**Supersedes**: ")
           ]
        <> [ "Missing referenced-by header in " <> packedPath
           | isDocumentsPath && not (hasLinePrefix "**Referenced by**: ")
           ]
        <> [ "Missing purpose block in " <> packedPath
           | isDocumentsPath && not (hasLinePrefix "> **Purpose**: ")
           ]

    statusProblems =
      case statusLine of
        Nothing -> []
        Just "Authoritative source" -> []
        Just "Reference only" -> []
        Just "Deprecated" -> []
        Just other -> ["Unsupported documentation status in " <> packedPath <> ": " <> other]

    referenceProblems =
      case statusLine of
        Just "Reference only" ->
          [ "Reference-only doc missing authoritative reference: " <> packedPath
          | not (hasLineContaining "Authoritative Reference")
          ]
        _ -> []

    crossRefProblems =
      case statusLine of
        Just "Authoritative source" ->
          [ "Authoritative doc missing cross-references section: " <> packedPath
          | not (hasLinePrefix "## Cross-References")
          ]
        _ -> []

    packedPath = Text.pack path
    findLineWithPrefix prefix =
      case filter (Text.isPrefixOf (Text.pack prefix)) linesOfText of
        [] -> Nothing
        (match : _) -> Just (Text.drop (Text.length (Text.pack prefix)) match)

renderProblems :: [DocProblem] -> Text
renderProblems problems =
  Text.unlines ("Documentation validation failed:" : fmap ("- " <>) (sort problems))

findMarkdownFiles :: FilePath -> IO [FilePath]
findMarkdownFiles root = do
  rootExists <- doesDirectoryExist root
  if not rootExists
    then pure []
    else go root
  where
    go current = do
      entries <- sort <$> listDirectory current
      fmap concat $
        forM entries $ \entry -> do
          let path = current </> entry
          isDirectory <- doesDirectoryExist path
          if isDirectory
            then go path
            else pure [path | takeExtension path == ".md"]

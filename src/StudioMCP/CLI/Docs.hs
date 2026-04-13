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
  ["README.md"]

validateDocsCommand :: IO ()
validateDocsCommand = do
  docFiles <- findMarkdownFiles "documents"
  planFiles <- findMarkdownFiles "DEVELOPMENT_PLAN"
  let requiredFiles =
        [ "documents/README.md"
        , "documents/documentation_standards.md"
        , "documents/architecture/overview.md"
        , "documents/architecture/mcp_protocol_architecture.md"
        , "documents/architecture/cli_architecture.md"
        , "documents/architecture/server_mode.md"
        , "documents/architecture/multi_tenant_saas_mcp_auth_architecture.md"
        , "documents/architecture/artifact_storage_architecture.md"
        , "documents/architecture/parallel_scheduling.md"
        , "documents/engineering/security_model.md"
        , "documents/engineering/session_scaling.md"
        , "documents/engineering/docker_policy.md"
        , "documents/engineering/k8s_native_dev_policy.md"
        , "documents/engineering/k8s_storage.md"
        , "documents/development/testing_strategy.md"
        , "documents/operations/runbook_local_debugging.md"
        , "documents/operations/keycloak_realm_bootstrap_runbook.md"
        , "documents/reference/cli_surface.md"
        , "documents/reference/mcp_surface.md"
        , "documents/reference/mcp_tool_catalog.md"
        , "documents/reference/web_portal_surface.md"
        -- ADR files removed per documentation_standards.md (no ADRs in documents/)
        ]
      requiredPlanFiles =
        [ "DEVELOPMENT_PLAN/README.md"
        , "DEVELOPMENT_PLAN/development_plan_standards.md"
        , "DEVELOPMENT_PLAN/00-overview.md"
        , "DEVELOPMENT_PLAN/system-components.md"
        , "DEVELOPMENT_PLAN/phase-1-repository-dag-runtime-foundations.md"
        , "DEVELOPMENT_PLAN/phase-2-mcp-surface-catalog-artifact-governance.md"
        , "DEVELOPMENT_PLAN/phase-3-keycloak-auth-shared-sessions.md"
        , "DEVELOPMENT_PLAN/phase-4-control-plane-data-plane-contract.md"
        , "DEVELOPMENT_PLAN/phase-5-browser-session-contract.md"
        , "DEVELOPMENT_PLAN/phase-6-cluster-control-plane-parity.md"
        , "DEVELOPMENT_PLAN/phase-7-keycloak-realm-bootstrap.md"
        , "DEVELOPMENT_PLAN/phase-8-final-closure-regression-gate.md"
        , "DEVELOPMENT_PLAN/phase-9-cli-test-validate-consolidation.md"
        , "DEVELOPMENT_PLAN/phase-10-build-artifact-isolation.md"
        , "DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md"
        ]
  requiredProblems <- fmap concat $
    forM requiredFiles $ \path -> do
      exists <- doesFileExist path
      pure $
        [ "Missing required documentation file: " <> Text.pack path
        | not exists
        ]
  requiredPlanProblems <- fmap concat $
    forM requiredPlanFiles $ \path -> do
      exists <- doesFileExist path
      pure $
        [ "Missing required development plan file: " <> Text.pack path
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
  planProblems <- fmap concat $
    forM planFiles $ \path -> do
      fileBytes <- BS.readFile path
      case decodeUtf8' fileBytes of
        Left _ ->
          pure ["Development plan file is not valid UTF-8: " <> Text.pack path]
        Right content ->
          pure (validateDocText path content)
  rootProblems <- fmap concat $
    forM markdownFilesToCheck $ \path -> do
      exists <- doesFileExist path
      pure $
        [ "Missing expected root markdown file: " <> Text.pack path
        | not exists
        ]
  let problems = requiredProblems <> requiredPlanProblems <> docProblems <> planProblems <> rootProblems
  unless (null problems) $
    die (Text.unpack (renderProblems problems))
  putStrLn "Documentation checks passed."

validateDocText :: FilePath -> Text -> [DocProblem]
validateDocText path content =
  headerProblems
    <> statusProblems
    <> referenceProblems
    <> crossRefProblems
    <> mermaidProblems
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

    isPlanPath = "DEVELOPMENT_PLAN/" `isPrefixOf` path

    statusProblems =
      case statusLine of
        Nothing -> []
        Just status
          | isDocumentsPath -> validateDocStatus status
          | isPlanPath -> validatePlanStatus status
          | otherwise -> []

    validateDocStatus :: Text -> [DocProblem]
    validateDocStatus "Authoritative source" = []
    validateDocStatus "Reference only" = []
    validateDocStatus "Deprecated" = []
    validateDocStatus other = ["Unsupported documentation status in " <> packedPath <> ": " <> other]

    validatePlanStatus :: Text -> [DocProblem]
    validatePlanStatus "Done" = []
    validatePlanStatus "Active" = []
    validatePlanStatus "Planned" = []
    validatePlanStatus "Blocked" = []
    validatePlanStatus "Authoritative source" = []  -- For standards docs in DEVELOPMENT_PLAN
    validatePlanStatus other = ["Unsupported plan status in " <> packedPath <> ": " <> other]

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

    mermaidProblems =
      concatMap validateMermaidBlock (extractMermaidBlocks linesOfText)

    packedPath = Text.pack path
    findLineWithPrefix prefix =
      case filter (Text.isPrefixOf (Text.pack prefix)) linesOfText of
        [] -> Nothing
        (match : _) -> Just (Text.drop (Text.length (Text.pack prefix)) match)

renderProblems :: [DocProblem] -> Text
renderProblems problems =
  Text.unlines ("Documentation validation failed:" : fmap ("- " <>) (sort problems))

extractMermaidBlocks :: [Text] -> [[Text]]
extractMermaidBlocks = go False []
  where
    go _ current [] =
      [reverse current | not (null current)]
    go False current (line : rest)
      | Text.strip line == "```mermaid" = go True [] rest
      | otherwise = go False current rest
    go True current (line : rest)
      | Text.strip line == "```" = reverse current : go False [] rest
      | otherwise = go True (line : current) rest

validateMermaidBlock :: [Text] -> [DocProblem]
validateMermaidBlock mermaidLines =
  concatMap forbiddenProblem forbiddenPatterns
  where
    blockText = Text.unlines mermaidLines
    forbiddenPatterns =
      [ ("subgraph", "Mermaid block uses forbidden `subgraph` syntax")
      , ("-.->", "Mermaid block uses forbidden dotted arrows")
      , ("==>", "Mermaid block uses forbidden thick arrows")
      , (":::", "Mermaid block uses forbidden class syntax")
      , ("%%", "Mermaid block uses forbidden Mermaid comments")
      , ("stateDiagram", "Mermaid block uses forbidden state diagrams")
      , ("sequenceDiagram", "Mermaid block uses forbidden sequence diagrams")
      , ("flowchart RL", "Mermaid block uses forbidden right-to-left flowcharts")
      , ("graph LR", "Mermaid block uses forbidden `graph LR` syntax")
      , ("graph RL", "Mermaid block uses forbidden `graph RL` syntax")
      ]
    forbiddenProblem (patternText, message) =
      [message | patternText `Text.isInfixOf` blockText]

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

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module StudioMCP.MCP.Prompts
  ( -- * Prompt Catalog
    PromptCatalog (..),
    newPromptCatalog,
    listPrompts,
    getPrompt,

    -- * Prompt Names
    PromptName (..),
    allPromptNames,
    parsePromptName,

    -- * Prompt Errors
    PromptError (..),
    promptErrorCode,

    -- * Prompt Authorization
    promptRequiredScopes,

    -- * Prompt Definitions
    dagPlanningPrompt,
    dagRepairPrompt,
    workflowAnalysisPrompt,
    artifactNamingPrompt,
    errorDiagnosisPrompt,
  )
where

import Control.Concurrent.STM (TVar, atomically, modifyTVar', newTVarIO, readTVarIO)
import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    Value (..),
    withText,
  )
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (UTCTime, getCurrentTime)
import StudioMCP.Auth.Types (TenantId (..))
import StudioMCP.MCP.Protocol.Types
  ( ContentType (..),
    GetPromptParams (..),
    GetPromptResult (..),
    PromptArgument (..),
    PromptDefinition (..),
    PromptMessage (..),
    PromptRole (..),
    ToolContent (..),
  )

-- | Prompt names in the catalog
data PromptName
  = DagPlanning
  | DagRepair
  | WorkflowAnalysis
  | ArtifactNaming
  | ErrorDiagnosis
  deriving (Eq, Ord, Show)

instance ToJSON PromptName where
  toJSON DagPlanning = "dag-planning"
  toJSON DagRepair = "dag-repair"
  toJSON WorkflowAnalysis = "workflow-analysis"
  toJSON ArtifactNaming = "artifact-naming"
  toJSON ErrorDiagnosis = "error-diagnosis"

instance FromJSON PromptName where
  parseJSON = withText "PromptName" $ \t ->
    case t of
      "dag-planning" -> pure DagPlanning
      "dag-repair" -> pure DagRepair
      "workflow-analysis" -> pure WorkflowAnalysis
      "artifact-naming" -> pure ArtifactNaming
      "error-diagnosis" -> pure ErrorDiagnosis
      other -> fail $ "Unknown prompt name: " <> T.unpack other

-- | All available prompt names
allPromptNames :: [PromptName]
allPromptNames =
  [ DagPlanning,
    DagRepair,
    WorkflowAnalysis,
    ArtifactNaming,
    ErrorDiagnosis
  ]

-- | Parse prompt name from text
parsePromptName :: Text -> Maybe PromptName
parsePromptName "dag-planning" = Just DagPlanning
parsePromptName "dag-repair" = Just DagRepair
parsePromptName "workflow-analysis" = Just WorkflowAnalysis
parsePromptName "artifact-naming" = Just ArtifactNaming
parsePromptName "error-diagnosis" = Just ErrorDiagnosis
parsePromptName _ = Nothing

-- | Prompt errors
data PromptError
  = PromptNotFound Text
  | InvalidPromptArguments Text
  | PromptRenderFailed Text
  deriving (Eq, Show)

-- | Get error code for prompt errors
promptErrorCode :: PromptError -> Text
promptErrorCode (PromptNotFound _) = "prompt-not-found"
promptErrorCode (InvalidPromptArguments _) = "invalid-arguments"
promptErrorCode (PromptRenderFailed _) = "render-failed"

-- | Internal state for prompt catalog
data PromptCatalogState = PromptCatalogState
  { pcsUsageCount :: Map.Map PromptName Int,
    pcsLastUsed :: Map.Map PromptName UTCTime
  }

-- | Prompt catalog service
data PromptCatalog = PromptCatalog
  { pcState :: TVar PromptCatalogState
  }

-- | Create a new prompt catalog
newPromptCatalog :: IO PromptCatalog
newPromptCatalog = do
  stateVar <-
    newTVarIO
      PromptCatalogState
        { pcsUsageCount = Map.empty,
          pcsLastUsed = Map.empty
        }
  pure PromptCatalog {pcState = stateVar}

-- | List all available prompts
listPrompts :: PromptCatalog -> IO [PromptDefinition]
listPrompts _catalog =
  pure
    [ dagPlanningPrompt,
      dagRepairPrompt,
      workflowAnalysisPrompt,
      artifactNamingPrompt,
      errorDiagnosisPrompt
    ]

-- | Get a prompt by name with rendered arguments
getPrompt ::
  PromptCatalog ->
  TenantId ->
  GetPromptParams ->
  IO (Either PromptError GetPromptResult)
getPrompt catalog tenantId params = do
  let promptNameText = gppName params
  case parsePromptName promptNameText of
    Nothing -> pure $ Left $ PromptNotFound promptNameText
    Just promptName -> do
      now <- getCurrentTime
      atomically $ modifyTVar' (pcState catalog) $ \s ->
        s
          { pcsUsageCount = Map.insertWith (+) promptName 1 (pcsUsageCount s),
            pcsLastUsed = Map.insert promptName now (pcsLastUsed s)
          }
      renderPrompt tenantId promptName (gppArguments params)

-- | Render a prompt with arguments
renderPrompt ::
  TenantId ->
  PromptName ->
  Maybe Value ->
  IO (Either PromptError GetPromptResult)
renderPrompt tenantId promptName args =
  case promptName of
    DagPlanning -> renderDagPlanningPrompt tenantId args
    DagRepair -> renderDagRepairPrompt tenantId args
    WorkflowAnalysis -> renderWorkflowAnalysisPrompt tenantId args
    ArtifactNaming -> renderArtifactNamingPrompt tenantId args
    ErrorDiagnosis -> renderErrorDiagnosisPrompt tenantId args

-- | Render DAG planning prompt
renderDagPlanningPrompt :: TenantId -> Maybe Value -> IO (Either PromptError GetPromptResult)
renderDagPlanningPrompt _tenantId args = do
  let description = extractStringArg "description" args
      inputFormat = extractStringArg "input_format" args
      outputFormat = extractStringArg "output_format" args

  let systemMessage =
        "You are an expert media workflow planner for studioMCP. Your task is to help users design "
          <> "efficient DAG workflows for media processing tasks.\n\n"
          <> "Key principles:\n"
          <> "1. Each node in the DAG should represent a single, well-defined processing step\n"
          <> "2. Use appropriate node types: source (for inputs), pure (for stateless transforms), "
          <> "boundary (for FFmpeg operations)\n"
          <> "3. Ensure proper dependency ordering\n"
          <> "4. Consider memoization opportunities for expensive operations\n"
          <> "5. Output YAML DAG specifications that can be directly submitted to workflow.submit"

  let userMessage =
        "Please help me plan a DAG workflow.\n\n"
          <> maybe "" (\d -> "Description: " <> d <> "\n") description
          <> maybe "" (\i -> "Input format: " <> i <> "\n") inputFormat
          <> maybe "" (\o -> "Output format: " <> o <> "\n") outputFormat
          <> "\nProvide a complete DAG specification in YAML format."

  pure $
    Right
      GetPromptResult
        { gprDescription = Just "Helps plan a DAG workflow for media processing",
          gprMessages =
            [ PromptMessage
                { pmRole = AssistantRole,
                  pmContent =
                    ToolContent
                      { tcType = TextContent,
                        tcText = Just systemMessage,
                        tcData = Nothing,
                        tcMimeType = Nothing,
                        tcUri = Nothing
                      }
                },
              PromptMessage
                { pmRole = UserRole,
                  pmContent =
                    ToolContent
                      { tcType = TextContent,
                        tcText = Just userMessage,
                        tcData = Nothing,
                        tcMimeType = Nothing,
                        tcUri = Nothing
                      }
                }
            ]
        }

-- | Render DAG repair prompt
renderDagRepairPrompt :: TenantId -> Maybe Value -> IO (Either PromptError GetPromptResult)
renderDagRepairPrompt _tenantId args = do
  let dagSpec = extractStringArg "dag_spec" args
      errorMessage = extractStringArg "error_message" args

  case dagSpec of
    Nothing -> pure $ Left $ InvalidPromptArguments "dag_spec is required"
    Just spec -> do
      let systemMessage =
            "You are an expert at debugging and repairing studioMCP DAG specifications. "
              <> "Analyze the provided DAG and error message, then suggest corrections.\n\n"
              <> "Common issues to check:\n"
              <> "1. Cyclic dependencies\n"
              <> "2. Invalid node types or missing required fields\n"
              <> "3. Tool binding errors for pure nodes\n"
              <> "4. Invalid input/output references\n"
              <> "5. Timeout policy misconfigurations\n"
              <> "6. YAML syntax errors"

      let userMessage =
            "Please help me fix this DAG specification:\n\n"
              <> "```yaml\n"
              <> spec
              <> "\n```\n\n"
              <> maybe "The DAG is failing validation." (\e -> "Error: " <> e) errorMessage
              <> "\n\nProvide the corrected DAG specification."

      pure $
        Right
          GetPromptResult
            { gprDescription = Just "Helps repair a failing DAG specification",
              gprMessages =
                [ PromptMessage
                    { pmRole = AssistantRole,
                      pmContent =
                        ToolContent
                          { tcType = TextContent,
                            tcText = Just systemMessage,
                            tcData = Nothing,
                            tcMimeType = Nothing,
                            tcUri = Nothing
                          }
                    },
                  PromptMessage
                    { pmRole = UserRole,
                      pmContent =
                        ToolContent
                          { tcType = TextContent,
                            tcText = Just userMessage,
                            tcData = Nothing,
                            tcMimeType = Nothing,
                            tcUri = Nothing
                          }
                    }
                ]
            }

-- | Render workflow analysis prompt
renderWorkflowAnalysisPrompt :: TenantId -> Maybe Value -> IO (Either PromptError GetPromptResult)
renderWorkflowAnalysisPrompt _tenantId args = do
  let runId = extractStringArg "run_id" args
      summaryJson = extractStringArg "summary" args

  let systemMessage =
        "You are an expert at analyzing studioMCP workflow executions. "
          <> "Examine the provided run summary and identify:\n\n"
          <> "1. Performance bottlenecks\n"
          <> "2. Failed or slow nodes\n"
          <> "3. Resource utilization patterns\n"
          <> "4. Optimization opportunities\n"
          <> "5. Potential issues for future runs"

  let userMessage =
        "Please analyze this workflow run:\n\n"
          <> maybe "" (\r -> "Run ID: " <> r <> "\n\n") runId
          <> maybe "Summary not provided." (\s -> "Summary:\n```json\n" <> s <> "\n```") summaryJson
          <> "\n\nProvide insights and recommendations."

  pure $
    Right
      GetPromptResult
        { gprDescription = Just "Analyzes a workflow run and provides insights",
          gprMessages =
            [ PromptMessage
                { pmRole = AssistantRole,
                  pmContent =
                    ToolContent
                      { tcType = TextContent,
                        tcText = Just systemMessage,
                        tcData = Nothing,
                        tcMimeType = Nothing,
                        tcUri = Nothing
                      }
                },
              PromptMessage
                { pmRole = UserRole,
                  pmContent =
                    ToolContent
                      { tcType = TextContent,
                        tcText = Just userMessage,
                        tcData = Nothing,
                        tcMimeType = Nothing,
                        tcUri = Nothing
                      }
                }
            ]
        }

-- | Render artifact naming prompt
renderArtifactNamingPrompt :: TenantId -> Maybe Value -> IO (Either PromptError GetPromptResult)
renderArtifactNamingPrompt _tenantId args = do
  let contentType = extractStringArg "content_type" args
      context = extractStringArg "context" args

  let systemMessage =
        "You are helping users organize their media artifacts in studioMCP. "
          <> "Suggest clear, descriptive file names that follow best practices:\n\n"
          <> "1. Use lowercase with hyphens for separation\n"
          <> "2. Include relevant metadata (resolution, format, date)\n"
          <> "3. Avoid special characters\n"
          <> "4. Keep names concise but descriptive"

  let userMessage =
        "Please suggest a good file name for:\n\n"
          <> maybe "" (\c -> "Content type: " <> c <> "\n") contentType
          <> maybe "" (\c -> "Context: " <> c <> "\n") context
          <> "\nProvide 3 naming suggestions."

  pure $
    Right
      GetPromptResult
        { gprDescription = Just "Suggests artifact naming conventions",
          gprMessages =
            [ PromptMessage
                { pmRole = AssistantRole,
                  pmContent =
                    ToolContent
                      { tcType = TextContent,
                        tcText = Just systemMessage,
                        tcData = Nothing,
                        tcMimeType = Nothing,
                        tcUri = Nothing
                      }
                },
              PromptMessage
                { pmRole = UserRole,
                  pmContent =
                    ToolContent
                      { tcType = TextContent,
                        tcText = Just userMessage,
                        tcData = Nothing,
                        tcMimeType = Nothing,
                        tcUri = Nothing
                      }
                }
            ]
        }

-- | Render error diagnosis prompt
renderErrorDiagnosisPrompt :: TenantId -> Maybe Value -> IO (Either PromptError GetPromptResult)
renderErrorDiagnosisPrompt _tenantId args = do
  let errorType = extractStringArg "error_type" args
      errorMessage = extractStringArg "error_message" args
      context = extractStringArg "context" args

  let systemMessage =
        "You are an expert at diagnosing studioMCP errors. "
          <> "Analyze the provided error and suggest:\n\n"
          <> "1. Root cause analysis\n"
          <> "2. Immediate remediation steps\n"
          <> "3. Long-term fixes\n"
          <> "4. Prevention strategies"

  let userMessage =
        "Please help diagnose this error:\n\n"
          <> maybe "" (\e -> "Error type: " <> e <> "\n") errorType
          <> maybe "" (\e -> "Error message: " <> e <> "\n") errorMessage
          <> maybe "" (\c -> "Context: " <> c <> "\n") context
          <> "\nProvide diagnosis and recommendations."

  pure $
    Right
      GetPromptResult
        { gprDescription = Just "Diagnoses errors and suggests fixes",
          gprMessages =
            [ PromptMessage
                { pmRole = AssistantRole,
                  pmContent =
                    ToolContent
                      { tcType = TextContent,
                        tcText = Just systemMessage,
                        tcData = Nothing,
                        tcMimeType = Nothing,
                        tcUri = Nothing
                      }
                },
              PromptMessage
                { pmRole = UserRole,
                  pmContent =
                    ToolContent
                      { tcType = TextContent,
                        tcText = Just userMessage,
                        tcData = Nothing,
                        tcMimeType = Nothing,
                        tcUri = Nothing
                      }
                }
            ]
        }

-- | Extract string argument from JSON value
extractStringArg :: Text -> Maybe Value -> Maybe Text
extractStringArg key (Just (Object obj)) =
  case KeyMap.lookup (Key.fromText key) obj of
    Just (String s) -> Just s
    _ -> Nothing
extractStringArg _ _ = Nothing

-- | Get required scopes for a prompt
promptRequiredScopes :: PromptName -> [Text]
promptRequiredScopes DagPlanning = ["prompt:read"]
promptRequiredScopes DagRepair = ["prompt:read"]
promptRequiredScopes WorkflowAnalysis = ["prompt:read", "workflow:read"]
promptRequiredScopes ArtifactNaming = ["prompt:read"]
promptRequiredScopes ErrorDiagnosis = ["prompt:read"]

-- | Prompt definitions

dagPlanningPrompt :: PromptDefinition
dagPlanningPrompt =
  PromptDefinition
    { pdName = "dag-planning",
      pdDescription = Just "Helps plan a DAG workflow for media processing tasks",
      pdArguments =
        Just
          [ PromptArgument
              { paName = "description",
                paDescription = Just "Description of the desired workflow",
                paRequired = Just False
              },
            PromptArgument
              { paName = "input_format",
                paDescription = Just "Input media format (e.g., video/mp4)",
                paRequired = Just False
              },
            PromptArgument
              { paName = "output_format",
                paDescription = Just "Desired output format",
                paRequired = Just False
              }
          ],
      pdRequiredScopes = ["prompt:read"]
    }

dagRepairPrompt :: PromptDefinition
dagRepairPrompt =
  PromptDefinition
    { pdName = "dag-repair",
      pdDescription = Just "Helps fix errors in DAG specifications",
      pdArguments =
        Just
          [ PromptArgument
              { paName = "dag_spec",
                paDescription = Just "The YAML DAG specification that needs repair",
                paRequired = Just True
              },
            PromptArgument
              { paName = "error_message",
                paDescription = Just "The error message from validation or execution",
                paRequired = Just False
              }
          ],
      pdRequiredScopes = ["prompt:read"]
    }

workflowAnalysisPrompt :: PromptDefinition
workflowAnalysisPrompt =
  PromptDefinition
    { pdName = "workflow-analysis",
      pdDescription = Just "Analyzes a workflow run and provides insights",
      pdArguments =
        Just
          [ PromptArgument
              { paName = "run_id",
                paDescription = Just "The workflow run ID to analyze",
                paRequired = Just False
              },
            PromptArgument
              { paName = "summary",
                paDescription = Just "JSON summary of the workflow run",
                paRequired = Just False
              }
          ],
      pdRequiredScopes = ["prompt:read", "workflow:read"]
    }

artifactNamingPrompt :: PromptDefinition
artifactNamingPrompt =
  PromptDefinition
    { pdName = "artifact-naming",
      pdDescription = Just "Suggests naming conventions for media artifacts",
      pdArguments =
        Just
          [ PromptArgument
              { paName = "content_type",
                paDescription = Just "MIME type of the artifact",
                paRequired = Just False
              },
            PromptArgument
              { paName = "context",
                paDescription = Just "Context about the artifact's purpose",
                paRequired = Just False
              }
          ],
      pdRequiredScopes = ["prompt:read"]
    }

errorDiagnosisPrompt :: PromptDefinition
errorDiagnosisPrompt =
  PromptDefinition
    { pdName = "error-diagnosis",
      pdDescription = Just "Diagnoses errors and suggests remediation",
      pdArguments =
        Just
          [ PromptArgument
              { paName = "error_type",
                paDescription = Just "Type of error (e.g., validation, execution, storage)",
                paRequired = Just False
              },
            PromptArgument
              { paName = "error_message",
                paDescription = Just "The error message",
                paRequired = Just False
              },
            PromptArgument
              { paName = "context",
                paDescription = Just "Additional context about when the error occurred",
                paRequired = Just False
              }
          ],
      pdRequiredScopes = ["prompt:read"]
    }

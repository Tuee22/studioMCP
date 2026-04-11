module Main (main) where

import qualified API.HealthSpec
import qualified API.MetricsSpec
import qualified Auth.ClaimsSpec
import qualified Auth.ConfigSpec
import qualified Auth.JwksSpec
import qualified Auth.MiddlewareSpec
import qualified Auth.PassthroughGuardSpec
import qualified Auth.ScopesSpec
import qualified Auth.TypesSpec
import qualified CLI.CommandSpec
import qualified CLI.DocsSpec
import qualified DAG.ExecutorSpec
import qualified DAG.MemoizationSpec
import qualified DAG.ParserSpec
import qualified DAG.RailwaySpec
import qualified DAG.SchedulerSpec
import qualified DAG.SummarySpec
import qualified DAG.TimeoutSpec
import qualified DAG.ValidatorSpec
import qualified Inference.GuardrailsSpec
import qualified Inference.PromptsSpec
import qualified MCP.JsonRpcSpec
import qualified MCP.ProtocolSpec
import qualified MCP.StateMachineSpec
import qualified MCP.CoreSpec
import qualified MCP.ConformanceSpec
import qualified DAG.ProvenanceSpec
import qualified Messaging.ExecutionStateSpec
import qualified Messaging.EventsSpec
import qualified Messaging.PulsarSpec
import qualified Messaging.TopicsSpec
import qualified Session.RedisConfigSpec
import qualified Session.RedisStoreSpec
import qualified Session.StoreSpec
import qualified Storage.AuditTrailSpec
import qualified Storage.ContentAddressedSpec
import qualified Storage.GovernanceSpec
import qualified Storage.KeysSpec
import qualified Storage.ManifestsSpec
import qualified Storage.MinIOSpec
import qualified Storage.TenantStorageSpec
import qualified Tools.BoundarySpec
import qualified Web.BFFSpec
import qualified Web.HandlersSpec
import qualified Web.TypesSpec
import qualified Worker.ProtocolSpec
import qualified API.VersionSpec
import qualified CLI.DagSpec
import qualified Config.EnvSpec
import qualified Config.LoadSpec
import qualified Config.TypesSpec
import qualified DAG.HashingSpec
import qualified DAG.TypesSpec
import qualified Inference.HostSpec
import qualified Inference.ReferenceModelSpec
import qualified Inference.TypesSpec
import qualified MCP.ContextSpec
import qualified MCP.HandlersSpec
import qualified MCP.PromptsSpec
import qualified MCP.ResourcesSpec
import qualified MCP.ServerSpec
import qualified MCP.ToolsSpec
import qualified MCP.TransportSpec
import qualified MCP.TypesSpec
import qualified Observability.CorrelationIdSpec
import qualified Observability.McpMetricsSpec
import qualified Observability.QuotasSpec
import qualified Observability.RateLimitingSpec
import qualified Observability.RedactionSpec
import qualified Result.FailureSpec
import qualified Result.SummaryFailureSpec
import qualified Result.TypesSpec
import qualified Storage.VersioningSpec
import qualified Tools.FFmpegSpec
import qualified Tools.RegistrySpec
import qualified Tools.TypesSpec
import qualified Util.ExceptionsSpec
import qualified Util.JsonSpec
import qualified Util.LoggingSpec
import qualified Util.StartupSpec
import qualified Util.TimeSpec
import qualified Worker.ServerSpec
import Test.Hspec (hspec)

main :: IO ()
main =
  hspec $ do
    API.HealthSpec.spec
    API.MetricsSpec.spec
    Auth.TypesSpec.spec
    Auth.ConfigSpec.spec
    Auth.ClaimsSpec.spec
    Auth.ScopesSpec.spec
    Auth.JwksSpec.spec
    Auth.MiddlewareSpec.spec
    Auth.PassthroughGuardSpec.spec
    CLI.CommandSpec.spec
    CLI.DocsSpec.spec
    DAG.ParserSpec.spec
    DAG.ValidatorSpec.spec
    DAG.RailwaySpec.spec
    DAG.TimeoutSpec.spec
    DAG.MemoizationSpec.spec
    DAG.SchedulerSpec.spec
    DAG.ExecutorSpec.spec
    DAG.SummarySpec.spec
    Inference.GuardrailsSpec.spec
    Inference.PromptsSpec.spec
    MCP.JsonRpcSpec.spec
    MCP.ProtocolSpec.spec
    MCP.StateMachineSpec.spec
    MCP.CoreSpec.spec
    MCP.ConformanceSpec.spec
    DAG.ProvenanceSpec.spec
    Messaging.ExecutionStateSpec.spec
    Messaging.EventsSpec.spec
    Messaging.PulsarSpec.spec
    Messaging.TopicsSpec.spec
    Storage.ContentAddressedSpec.spec
    Storage.KeysSpec.spec
    Storage.ManifestsSpec.spec
    Storage.MinIOSpec.spec
    Storage.GovernanceSpec.spec
    Storage.AuditTrailSpec.spec
    Storage.TenantStorageSpec.spec
    Session.StoreSpec.spec
    Session.RedisConfigSpec.spec
    Session.RedisStoreSpec.spec
    Web.TypesSpec.spec
    Web.BFFSpec.spec
    Web.HandlersSpec.spec
    Tools.BoundarySpec.spec
    Worker.ProtocolSpec.spec
    API.VersionSpec.spec
    CLI.DagSpec.spec
    Config.EnvSpec.spec
    Config.LoadSpec.spec
    Config.TypesSpec.spec
    DAG.HashingSpec.spec
    DAG.TypesSpec.spec
    Inference.HostSpec.spec
    Inference.ReferenceModelSpec.spec
    Inference.TypesSpec.spec
    MCP.ContextSpec.spec
    MCP.HandlersSpec.spec
    MCP.PromptsSpec.spec
    MCP.ResourcesSpec.spec
    MCP.ServerSpec.spec
    MCP.ToolsSpec.spec
    MCP.TransportSpec.spec
    MCP.TypesSpec.spec
    Observability.CorrelationIdSpec.spec
    Observability.McpMetricsSpec.spec
    Observability.QuotasSpec.spec
    Observability.RateLimitingSpec.spec
    Observability.RedactionSpec.spec
    Result.FailureSpec.spec
    Result.SummaryFailureSpec.spec
    Result.TypesSpec.spec
    Storage.VersioningSpec.spec
    Tools.FFmpegSpec.spec
    Tools.RegistrySpec.spec
    Tools.TypesSpec.spec
    Util.ExceptionsSpec.spec
    Util.JsonSpec.spec
    Util.LoggingSpec.spec
    Util.StartupSpec.spec
    Util.TimeSpec.spec
    Worker.ServerSpec.spec

module Main (main) where

import qualified API.HealthSpec
import qualified API.MetricsSpec
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
import qualified MCP.ProtocolSpec
import qualified Messaging.ExecutionStateSpec
import qualified Messaging.EventsSpec
import qualified Messaging.PulsarSpec
import qualified Messaging.TopicsSpec
import qualified Storage.ContentAddressedSpec
import qualified Storage.KeysSpec
import qualified Storage.ManifestsSpec
import qualified Storage.MinIOSpec
import qualified Tools.BoundarySpec
import qualified Worker.ProtocolSpec
import Test.Hspec (hspec)

main :: IO ()
main =
  hspec $ do
    API.HealthSpec.spec
    API.MetricsSpec.spec
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
    MCP.ProtocolSpec.spec
    Messaging.ExecutionStateSpec.spec
    Messaging.EventsSpec.spec
    Messaging.PulsarSpec.spec
    Messaging.TopicsSpec.spec
    Storage.ContentAddressedSpec.spec
    Storage.KeysSpec.spec
    Storage.ManifestsSpec.spec
    Storage.MinIOSpec.spec
    Tools.BoundarySpec.spec
    Worker.ProtocolSpec.spec

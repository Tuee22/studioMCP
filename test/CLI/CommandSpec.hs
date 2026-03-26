module CLI.CommandSpec
  ( spec,
  )
where

import StudioMCP.CLI.Command
  ( ClusterCommand (..),
    ClusterDeployTarget (..),
    ClusterStorageCommand (..),
    Command (..),
    DagCommand (..),
    ValidateCommand (..),
    parseCommand,
    usageText,
  )
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec =
  describe "parseCommand" $ do
    it "parses validate docs" $
      parseCommand ["validate", "docs"]
        `shouldBe` Right (ValidateCommand ValidateDocsCommand)

    it "parses validate pulsar" $
      parseCommand ["validate", "pulsar"]
        `shouldBe` Right (ValidateCommand ValidatePulsarCommand)

    it "parses validate e2e" $
      parseCommand ["validate", "e2e"]
        `shouldBe` Right (ValidateCommand ValidateE2ECommand)

    it "parses validate worker" $
      parseCommand ["validate", "worker"]
        `shouldBe` Right (ValidateCommand ValidateWorkerCommand)

    it "parses validate minio" $
      parseCommand ["validate", "minio"]
        `shouldBe` Right (ValidateCommand ValidateMinioCommand)

    it "parses validate boundary" $
      parseCommand ["validate", "boundary"]
        `shouldBe` Right (ValidateCommand ValidateBoundaryCommand)

    it "parses validate ffmpeg-adapter" $
      parseCommand ["validate", "ffmpeg-adapter"]
        `shouldBe` Right (ValidateCommand ValidateFFmpegAdapterCommand)

    it "parses validate executor" $
      parseCommand ["validate", "executor"]
        `shouldBe` Right (ValidateCommand ValidateExecutorCommand)

    it "parses validate mcp" $
      parseCommand ["validate", "mcp"]
        `shouldBe` Right (ValidateCommand ValidateMcpCommand)

    it "parses validate mcp-session-store" $
      parseCommand ["validate", "mcp-session-store"]
        `shouldBe` Right (ValidateCommand ValidateSessionStoreCommand)

    it "parses validate mcp-horizontal-scale" $
      parseCommand ["validate", "mcp-horizontal-scale"]
        `shouldBe` Right (ValidateCommand ValidateHorizontalScaleCommand)

    it "parses validate inference" $
      parseCommand ["validate", "inference"]
        `shouldBe` Right (ValidateCommand ValidateInferenceCommand)

    it "parses validate observability" $
      parseCommand ["validate", "observability"]
        `shouldBe` Right (ValidateCommand ValidateObservabilityCommand)

    it "parses validate storage-policy" $
      parseCommand ["validate", "storage-policy"]
        `shouldBe` Right (ValidateCommand ValidateStoragePolicyCommand)

    it "parses cluster up" $
      parseCommand ["cluster", "up"]
        `shouldBe` Right (ClusterCommand ClusterUpCommand)

    it "parses cluster deploy sidecars" $
      parseCommand ["cluster", "deploy", "sidecars"]
        `shouldBe` Right (ClusterCommand (ClusterDeployCommand DeploySidecars))

    it "parses cluster deploy server" $
      parseCommand ["cluster", "deploy", "server"]
        `shouldBe` Right (ClusterCommand (ClusterDeployCommand DeployServer))

    it "parses cluster storage reconcile" $
      parseCommand ["cluster", "storage", "reconcile"]
        `shouldBe` Right (ClusterCommand (ClusterStorageCommand ClusterStorageReconcile))

    it "parses dag validate path" $
      parseCommand ["dag", "validate", "examples/dags/transcode-basic.yaml"]
        `shouldBe` Right (ValidateDagCommand "examples/dags/transcode-basic.yaml")

    it "parses dag validate-fixtures" $
      parseCommand ["dag", "validate-fixtures"]
        `shouldBe` Right (DagCommand DagValidateFixturesCommand)

    it "returns usage text on invalid input" $
      parseCommand ["cluster", "deploy"] `shouldBe` Left usageText

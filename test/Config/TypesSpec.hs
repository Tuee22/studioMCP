{-# LANGUAGE OverloadedStrings #-}

module Config.TypesSpec (spec) where

import StudioMCP.Config.Types
import Test.Hspec

spec :: Spec
spec = do
  describe "AppMode" $ do
    it "can compare ServerMode equality" $ do
      ServerMode `shouldBe` ServerMode

    it "can compare InferenceMode equality" $ do
      InferenceMode `shouldBe` InferenceMode

    it "can compare WorkerMode equality" $ do
      WorkerMode `shouldBe` WorkerMode

    it "distinguishes different modes" $ do
      ServerMode `shouldNotBe` InferenceMode
      ServerMode `shouldNotBe` WorkerMode
      InferenceMode `shouldNotBe` WorkerMode

    it "can be shown" $ do
      show ServerMode `shouldBe` "ServerMode"
      show InferenceMode `shouldBe` "InferenceMode"
      show WorkerMode `shouldBe` "WorkerMode"

  describe "AppConfig" $ do
    it "can be created with all fields" $ do
      let config = AppConfig
            { appMode = ServerMode
            , pulsarHttpUrl = "http://localhost:8080"
            , pulsarBinaryUrl = "pulsar://localhost:6650"
            , minioEndpoint = "http://localhost:9000"
            , minioPublicEndpoint = "http://localhost:9000"
            , minioAccessKey = "access"
            , minioSecretKey = "secret"
            }
      appMode config `shouldBe` ServerMode
      pulsarHttpUrl config `shouldBe` "http://localhost:8080"
      pulsarBinaryUrl config `shouldBe` "pulsar://localhost:6650"
      minioEndpoint config `shouldBe` "http://localhost:9000"
      minioPublicEndpoint config `shouldBe` "http://localhost:9000"
      minioAccessKey config `shouldBe` "access"
      minioSecretKey config `shouldBe` "secret"

    it "can be compared for equality" $ do
      let config1 = AppConfig ServerMode "http" "pulsar" "minio" "minio-public" "key" "secret"
          config2 = AppConfig ServerMode "http" "pulsar" "minio" "minio-public" "key" "secret"
          config3 = AppConfig InferenceMode "http" "pulsar" "minio" "minio-public" "key" "secret"
      config1 `shouldBe` config2
      config1 `shouldNotBe` config3

    it "can be shown" $ do
      let config = AppConfig ServerMode "http" "pulsar" "minio" "minio-public" "key" "secret"
      show config `shouldContain` "AppConfig"

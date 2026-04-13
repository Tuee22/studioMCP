{-# LANGUAGE OverloadedStrings #-}

module Auth.ConfigSpec (spec) where

import Data.Aeson (decode, encode)
import StudioMCP.Auth.Config
import Test.Hspec

spec :: Spec
spec = do
  describe "defaultKeycloakConfig" $ do
    it "has localhost issuer" $ do
      kcIssuer defaultKeycloakConfig `shouldBe` "http://localhost:8080/kc/realms/studiomcp"

    it "has no additional issuers by default" $ do
      kcAdditionalIssuers defaultKeycloakConfig `shouldBe` []

    it "has studiomcp-mcp audience" $ do
      kcAudience defaultKeycloakConfig `shouldBe` "studiomcp-mcp"

    it "has studiomcp realm" $ do
      kcRealm defaultKeycloakConfig `shouldBe` "studiomcp"

    it "has 5 minute JWKS cache TTL" $ do
      kcJwksCacheTtlSeconds defaultKeycloakConfig `shouldBe` 300

    it "has 5 second JWKS fetch timeout" $ do
      kcJwksFetchTimeoutSeconds defaultKeycloakConfig `shouldBe` 5

  describe "defaultAuthConfig" $ do
    it "has auth disabled by default" $ do
      acEnabled defaultAuthConfig `shouldBe` False

    it "allows insecure HTTP by default" $ do
      acAllowInsecureHttp defaultAuthConfig `shouldBe` True

    it "has RS256 in allowed algorithms" $ do
      acAllowedAlgorithms defaultAuthConfig `shouldSatisfy` elem "RS256"

    it "has ES256 in allowed algorithms" $ do
      acAllowedAlgorithms defaultAuthConfig `shouldSatisfy` elem "ES256"

    it "has 60 second token leeway" $ do
      acTokenLeewaySeconds defaultAuthConfig `shouldBe` 60

  describe "jwksEndpoint" $ do
    it "builds correct JWKS URL" $ do
      jwksEndpoint defaultKeycloakConfig
        `shouldBe` "http://localhost:8080/kc/realms/studiomcp/protocol/openid-connect/certs"

    it "uses first additional issuer when present" $ do
      jwksEndpoint defaultKeycloakConfig {kcAdditionalIssuers = ["http://keycloak-loopback-proxy:8080/kc/realms/studiomcp"]}
        `shouldBe` "http://keycloak-loopback-proxy:8080/kc/realms/studiomcp/protocol/openid-connect/certs"

  describe "tokenEndpoint" $ do
    it "builds correct token URL" $ do
      tokenEndpoint defaultKeycloakConfig
        `shouldBe` "http://localhost:8080/kc/realms/studiomcp/protocol/openid-connect/token"

  describe "authorizeEndpoint" $ do
    it "builds correct authorize URL" $ do
      authorizeEndpoint defaultKeycloakConfig
        `shouldBe` "http://localhost:8080/kc/realms/studiomcp/protocol/openid-connect/auth"

  describe "userinfoEndpoint" $ do
    it "builds correct userinfo URL" $ do
      userinfoEndpoint defaultKeycloakConfig
        `shouldBe` "http://localhost:8080/kc/realms/studiomcp/protocol/openid-connect/userinfo"

  describe "validateKeycloakConfig" $ do
    it "returns no errors for valid config" $ do
      validateKeycloakConfig defaultAuthConfig `shouldBe` []

    it "detects empty issuer" $ do
      let config = defaultAuthConfig {acKeycloak = defaultKeycloakConfig {kcIssuer = ""}}
      validateKeycloakConfig config `shouldSatisfy` elem EmptyIssuer

    it "detects empty audience" $ do
      let config = defaultAuthConfig {acKeycloak = defaultKeycloakConfig {kcAudience = ""}}
      validateKeycloakConfig config `shouldSatisfy` elem EmptyAudience

    it "detects empty realm" $ do
      let config = defaultAuthConfig {acKeycloak = defaultKeycloakConfig {kcRealm = ""}}
      validateKeycloakConfig config `shouldSatisfy` elem EmptyRealm

    it "detects empty client ID" $ do
      let config = defaultAuthConfig {acKeycloak = defaultKeycloakConfig {kcClientId = ""}}
      validateKeycloakConfig config `shouldSatisfy` elem EmptyClientId

    it "detects insecure HTTP when not allowed" $ do
      let config =
            defaultAuthConfig
              { acAllowInsecureHttp = False,
                acKeycloak = defaultKeycloakConfig {kcIssuer = "http://auth.example.com/realms/test"}
              }
      validateKeycloakConfig config `shouldSatisfy` elem InsecureHttpNotAllowed

    it "allows HTTPS when insecure not allowed" $ do
      let config =
            defaultAuthConfig
              { acAllowInsecureHttp = False,
                acKeycloak = defaultKeycloakConfig {kcIssuer = "https://auth.example.com/realms/test"}
              }
      validateKeycloakConfig config `shouldSatisfy` notElem InsecureHttpNotAllowed

    it "detects invalid cache TTL" $ do
      let config = defaultAuthConfig {acKeycloak = defaultKeycloakConfig {kcJwksCacheTtlSeconds = 0}}
          isInvalidCacheTtl (InvalidCacheTtl _) = True
          isInvalidCacheTtl _ = False
      validateKeycloakConfig config `shouldSatisfy` any isInvalidCacheTtl

    it "detects invalid fetch timeout" $ do
      let config = defaultAuthConfig {acKeycloak = defaultKeycloakConfig {kcJwksFetchTimeoutSeconds = -1}}
          isInvalidFetchTimeout (InvalidFetchTimeout _) = True
          isInvalidFetchTimeout _ = False
      validateKeycloakConfig config `shouldSatisfy` any isInvalidFetchTimeout

  describe "KeycloakConfig JSON" $ do
    it "round-trips through JSON" $ do
      let config = defaultKeycloakConfig
          encoded = encode config
          decoded = decode encoded :: Maybe KeycloakConfig
      decoded `shouldBe` Just config

  describe "AuthConfig JSON" $ do
    it "round-trips through JSON" $ do
      let config = defaultAuthConfig
          encoded = encode config
          decoded = decode encoded :: Maybe AuthConfig
      decoded `shouldBe` Just config

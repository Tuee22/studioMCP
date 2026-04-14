{-# LANGUAGE OverloadedStrings #-}

module Integration.EmailFlowsSpec (spec) where

import Control.Concurrent (forkIO, killThread, threadDelay)
import Network.HTTP.Types (status202)
import Network.Wai (Application, responseLBS, strictRequestBody)
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort, setTimeout)
import StudioMCP.Email.SES (SESConfig (..), sendRenderedEmail)
import StudioMCP.Email.Templates
  ( EmailTemplateData (..),
    EmailTemplateName (PasswordResetTemplate),
    renderEmailTemplate,
  )
import Test.Hspec

spec :: Spec
spec =
  describe "email flows" $ do
    it "sends a rendered password reset email through a fake SES endpoint" $ do
      renderedEmailResult <-
        renderEmailTemplate
          PasswordResetTemplate
          EmailTemplateData
            { etdRecipientName = "Jordan",
              etdPrimaryUrl = "https://example.com/reset",
              etdSupportEmail = "support@example.com"
            }
      renderedEmail <-
        case renderedEmailResult of
          Left failureDetail -> expectationFailure (show failureDetail) >> fail "unreachable"
          Right value -> pure value
      let sesConfig =
            SESConfig
              { sesRegion = "us-east-1",
                sesAccessKeyId = "test-access-key",
                sesSecretAccessKey = "test-secret-key",
                sesSenderAddress = "no-reply@resolvefintech.com",
                sesEndpoint = "http://127.0.0.1:38241/v2/email/outbound-emails"
              }
      threadId <-
        forkIO
          ( runSettings
              (setHost "127.0.0.1" (setPort 38241 (setTimeout 0 defaultSettings)))
              fakeSesApplication
          )
      threadDelay 100000
      result <- sendRenderedEmail sesConfig "user@example.com" renderedEmail
      killThread threadId
      result `shouldSatisfy` either (const False) (const True)

fakeSesApplication :: Application
fakeSesApplication request respond = do
  _ <- strictRequestBody request
  respond (responseLBS status202 [("Content-Type", "application/json")] "{\"messageId\":\"test-message\"}")

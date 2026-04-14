{-# LANGUAGE OverloadedStrings #-}

module Email.TemplatesSpec (spec) where

import qualified Data.Text as Text
import StudioMCP.Email.Templates
import Test.Hspec

spec :: Spec
spec = do
  describe "renderEmailTemplate" $ do
    it "renders the email verification template with substitutions" $ do
      renderedEmailResult <-
        renderEmailTemplate
          EmailVerificationTemplate
          EmailTemplateData
            { etdRecipientName = "Taylor",
              etdPrimaryUrl = "https://example.com/verify",
              etdSupportEmail = "support@example.com"
            }
      case renderedEmailResult of
        Left failureDetail -> expectationFailure (show failureDetail)
        Right renderedEmail -> do
          Text.unpack (reSubject renderedEmail) `shouldContain` "Verify"
          Text.unpack (reHtmlBody renderedEmail) `shouldContain` "Taylor"
          Text.unpack (reTextBody renderedEmail) `shouldContain` "https://example.com/verify"

    it "renders the password changed template" $ do
      renderedEmailResult <-
        renderEmailTemplate
          PasswordChangedTemplate
          EmailTemplateData
            { etdRecipientName = "Morgan",
              etdPrimaryUrl = "https://example.com/unused",
              etdSupportEmail = "support@example.com"
            }
      case renderedEmailResult of
        Left failureDetail -> expectationFailure (show failureDetail)
        Right renderedEmail ->
          Text.unpack (reTextBody renderedEmail) `shouldContain` "support@example.com"

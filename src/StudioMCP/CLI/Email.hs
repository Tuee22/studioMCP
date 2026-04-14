{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.CLI.Email
  ( runEmailCommand,
  )
where

import qualified Data.Text as Text
import StudioMCP.CLI.Command (EmailCommand (..))
import StudioMCP.Email.SES (loadSESConfigFromEnv, sendRenderedEmail, sesSenderAddress)
import StudioMCP.Email.Templates
  ( EmailTemplateData (..),
    EmailTemplateName (EmailVerificationTemplate),
    renderEmailTemplate,
  )
import System.Environment (lookupEnv)
import System.Exit (die)

runEmailCommand :: EmailCommand -> IO ()
runEmailCommand command =
  case command of
    EmailSendTestCommand -> do
      sesConfig <- loadSESConfigFromEnv
      maybeRecipient <- lookupEnv "STUDIOMCP_TEST_EMAIL_TO"
      let recipient = maybe (sesSenderAddress sesConfig) Text.pack maybeRecipient
      renderedEmailResult <-
        renderEmailTemplate
          EmailVerificationTemplate
          EmailTemplateData
            { etdRecipientName = "studioMCP Operator",
              etdPrimaryUrl = "https://resolvefintech.com/studiomcp/verify?token=test-token",
              etdSupportEmail = "support@resolvefintech.com"
            }
      case renderedEmailResult of
        Left failureDetail -> die (show failureDetail)
        Right renderedEmail -> do
          sendResult <- sendRenderedEmail sesConfig recipient renderedEmail
          case sendResult of
            Left failureDetail -> die (show failureDetail)
            Right responseText -> do
              putStrLn ("Sent test email to " <> Text.unpack recipient)
              putStrLn (Text.unpack (Text.take 240 responseText))

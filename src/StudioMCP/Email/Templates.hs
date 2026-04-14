{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Email.Templates
  ( EmailTemplateData (..),
    EmailTemplateName (..),
    RenderedEmail (..),
    renderEmailTemplate,
  )
where

import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import StudioMCP.Result.Failure (FailureDetail)

data EmailTemplateName
  = EmailVerificationTemplate
  | PasswordResetTemplate
  | PasswordChangedTemplate
  deriving (Eq, Show)

data EmailTemplateData = EmailTemplateData
  { etdRecipientName :: Text,
    etdPrimaryUrl :: Text,
    etdSupportEmail :: Text
  }
  deriving (Eq, Show)

data RenderedEmail = RenderedEmail
  { reSubject :: Text,
    reHtmlBody :: Text,
    reTextBody :: Text
  }
  deriving (Eq, Show)

renderEmailTemplate :: EmailTemplateName -> EmailTemplateData -> IO (Either FailureDetail RenderedEmail)
renderEmailTemplate templateName templateData = do
  htmlTemplate <- TextIO.readFile (templatePath templateName "html")
  textTemplate <- TextIO.readFile (templatePath templateName "txt")
  pure $
    Right
      RenderedEmail
        { reSubject = templateSubject templateName,
          reHtmlBody = renderTemplate htmlTemplate templateData,
          reTextBody = renderTemplate textTemplate templateData
        }

templateSubject :: EmailTemplateName -> Text
templateSubject EmailVerificationTemplate = "Verify your studioMCP email address"
templateSubject PasswordResetTemplate = "Reset your studioMCP password"
templateSubject PasswordChangedTemplate = "Your studioMCP password was changed"

templatePath :: EmailTemplateName -> String -> FilePath
templatePath templateName extension =
  "templates/email/" <> templateSlug templateName <> "." <> extension

templateSlug :: EmailTemplateName -> String
templateSlug EmailVerificationTemplate = "email-verification"
templateSlug PasswordResetTemplate = "password-reset"
templateSlug PasswordChangedTemplate = "password-changed"

renderTemplate :: Text -> EmailTemplateData -> Text
renderTemplate templateText templateData =
  foldl replaceToken templateText replacementPairs
  where
    replacementPairs =
      [ ("{{recipient_name}}", etdRecipientName templateData),
        ("{{primary_url}}", etdPrimaryUrl templateData),
        ("{{support_email}}", etdSupportEmail templateData)
      ]
    replaceToken currentText (needle, replacement) =
      Text.replace needle replacement currentText

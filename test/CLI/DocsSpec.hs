{-# LANGUAGE OverloadedStrings #-}

module CLI.DocsSpec
  ( spec,
  )
where

import qualified Data.Text as Text
import StudioMCP.CLI.Docs (validateDocText)
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec =
  describe "validateDocText" $ do
    it "accepts a minimal authoritative document with cross references" $
      validateDocText "documents/example.md" authoritativeDoc `shouldBe` []

    it "rejects a reference-only document without an authoritative reference" $
      validateDocText "documents/example.md" referenceOnlyDoc
        `shouldSatisfy` any (Text.isInfixOf "Reference-only doc missing authoritative reference")

    it "rejects an authoritative document without cross references" $
      validateDocText "documents/example.md" authoritativeWithoutCrossRefs
        `shouldSatisfy` any (Text.isInfixOf "Authoritative doc missing cross-references section")

    it "rejects forbidden Mermaid constructs inside Mermaid blocks" $
      validateDocText "documents/example.md" mermaidWithSequenceDiagram
        `shouldSatisfy` any (Text.isInfixOf "Mermaid block uses forbidden sequence diagrams")

  where
    authoritativeDoc =
      Text.unlines
        [ "# File: documents/example.md"
        , "# Example"
        , ""
        , "**Status**: Authoritative source"
        , "**Supersedes**: N/A"
        , "**Referenced by**: other.md"
        , ""
        , "> **Purpose**: Example doc."
        , ""
        , "## Cross-References"
        ]

    referenceOnlyDoc =
      Text.unlines
        [ "# File: documents/example.md"
        , "# Example"
        , ""
        , "**Status**: Reference only"
        , "**Supersedes**: N/A"
        , "**Referenced by**: other.md"
        , ""
        , "> **Purpose**: Example doc."
        ]

    authoritativeWithoutCrossRefs =
      Text.unlines
        [ "# File: documents/example.md"
        , "# Example"
        , ""
        , "**Status**: Authoritative source"
        , "**Supersedes**: N/A"
        , "**Referenced by**: other.md"
        , ""
        , "> **Purpose**: Example doc."
        ]

    mermaidWithSequenceDiagram =
      Text.unlines
        [ "# File: documents/example.md"
        , "# Example"
        , ""
        , "**Status**: Authoritative source"
        , "**Supersedes**: N/A"
        , "**Referenced by**: other.md"
        , ""
        , "> **Purpose**: Example doc."
        , ""
        , "```mermaid"
        , "sequenceDiagram"
        , "  A->>B: bad"
        , "```"
        , ""
        , "## Cross-References"
        ]

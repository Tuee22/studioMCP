{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Inference.Prompts
  ( planningPromptHeader,
  )
where

import Data.Text (Text)

planningPromptHeader :: Text
planningPromptHeader = "studioMCP planning prompt"

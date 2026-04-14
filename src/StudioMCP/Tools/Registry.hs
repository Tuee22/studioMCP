{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Tools.Registry
  ( ToolRegistry (..),
    defaultToolRegistry,
    emptyToolRegistry,
    lookupToolExecutable,
  )
where

import qualified Data.Map.Strict as Map
import Data.Map.Strict (Map)
import StudioMCP.Tools.Types (ToolName (..))

newtype ToolRegistry = ToolRegistry
  { unToolRegistry :: Map ToolName FilePath
  }
  deriving (Eq, Show)

emptyToolRegistry :: ToolRegistry
emptyToolRegistry = ToolRegistry Map.empty

defaultToolRegistry :: ToolRegistry
defaultToolRegistry =
  ToolRegistry $
    Map.fromList
      [ (ToolName "ffmpeg", "ffmpeg"),
        (ToolName "sox", "sox"),
        (ToolName "demucs", "demucs"),
        (ToolName "whisper", "whisper"),
        (ToolName "basicpitch", "basic-pitch"),
        (ToolName "fluidsynth", "fluidsynth"),
        (ToolName "rubberband", "rubberband"),
        (ToolName "imagemagick", "convert"),
        (ToolName "mediainfo", "mediainfo")
      ]

lookupToolExecutable :: ToolName -> ToolRegistry -> Maybe FilePath
lookupToolExecutable toolName (ToolRegistry registryEntries) =
  Map.lookup toolName registryEntries

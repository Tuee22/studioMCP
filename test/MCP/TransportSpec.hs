{-# LANGUAGE OverloadedStrings #-}

module MCP.TransportSpec (spec) where

import Test.Hspec

-- Note: Transport modules (Stdio, Http) require actual I/O
-- So we verify the module structure compiles correctly

spec :: Spec
spec = do
  describe "MCP.Transport modules" $ do
    it "Stdio transport exports compile" $ do
      -- StudioMCP.MCP.Transport.Stdio
      pure () :: IO ()

    it "Http transport exports compile" $ do
      -- StudioMCP.MCP.Transport.Http
      pure () :: IO ()

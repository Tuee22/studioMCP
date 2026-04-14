# File: documents/tools/imagemagick.md
# ImageMagick

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../reference/mcp_tool_catalog.md](../reference/mcp_tool_catalog.md#workflow-boundary-tool-registry), [../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md](../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md#cross-references)

> **Purpose**: Canonical tool note for the ImageMagick boundary adapter in `studioMCP`.

## Summary

`src/StudioMCP/Tools/ImageMagick.hs` wraps `convert` for deterministic image resizing and thumbnail
generation.

## Validation Contract

`studiomcp validate imagemagick-adapter` resizes the PNG test pattern to a bounded JPEG output,
checks that the file is non-empty, and confirms missing-input failure projection.

## Cross-References

- [Test Fixtures](../development/test_fixtures.md#test-fixtures)
- [CLI Reference](../reference/cli_reference.md#studiomcp-cli-reference)

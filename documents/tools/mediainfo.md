# File: documents/tools/mediainfo.md
# MediaInfo

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../reference/mcp_tool_catalog.md](../reference/mcp_tool_catalog.md#workflow-boundary-tool-registry), [../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md](../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md#cross-references)

> **Purpose**: Canonical tool note for the MediaInfo inspection adapter in `studioMCP`.

## Summary

`src/StudioMCP/Tools/MediaInfo.hs` wraps `mediainfo` for JSON-based media inspection.

## Validation Contract

`studiomcp validate mediainfo-adapter` runs `mediainfo --Output=JSON` on the deterministic video
fixture, checks for a JSON payload containing `media`, and confirms missing-input failure
projection.

## Cross-References

- [Test Fixtures](../development/test_fixtures.md#test-fixtures)
- [CLI Reference](../reference/cli_reference.md#studiomcp-cli-reference)

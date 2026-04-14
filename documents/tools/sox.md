# File: documents/tools/sox.md
# SoX

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../reference/mcp_tool_catalog.md](../reference/mcp_tool_catalog.md#workflow-boundary-tool-registry), [../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md](../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md#cross-references)

> **Purpose**: Canonical tool note for the SoX boundary adapter in `studioMCP`.

## Summary

The repo exposes a Haskell SoX adapter in `src/StudioMCP/Tools/SoX.hs` for deterministic audio
effects, trims, fades, and format-normalization checks.

## Validation Contract

`studiomcp validate sox-adapter` seeds the tone fixture, renders a trimmed and normalized output,
checks that the output file is non-empty, and confirms missing-input failure projection.

## Cross-References

- [Test Fixtures](../development/test_fixtures.md#test-fixtures)
- [CLI Reference](../reference/cli_reference.md#studiomcp-cli-reference)

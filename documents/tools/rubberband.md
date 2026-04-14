# File: documents/tools/rubberband.md
# Rubberband

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../reference/mcp_tool_catalog.md](../reference/mcp_tool_catalog.md#workflow-boundary-tool-registry), [../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md](../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md#cross-references)

> **Purpose**: Canonical tool note for the Rubberband time-stretch and pitch-shift adapter in `studioMCP`.

## Summary

`src/StudioMCP/Tools/Rubberband.hs` uses `rubberband` for deterministic timing and pitch
transformations on generated audio fixtures.

## Validation Contract

`studiomcp validate rubberband-adapter` stretches the tone fixture, checks for a non-empty output,
and confirms missing-input failure projection.

## Cross-References

- [Test Fixtures](../development/test_fixtures.md#test-fixtures)
- [CLI Reference](../reference/cli_reference.md#studiomcp-cli-reference)

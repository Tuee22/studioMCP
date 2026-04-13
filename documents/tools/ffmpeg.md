# File: documents/tools/ffmpeg.md
# FFmpeg

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite)

> **Purpose**: Canonical tool note for FFmpeg as an early high-leverage boundary target in `studioMCP`.

## Why It Matters

FFmpeg covers a large part of the initial media-boundary surface:

- transcoding
- stream inspection
- extraction
- muxing and demuxing
- format normalization

## Current Maturity

The repo now includes a production Haskell FFmpeg adapter on top of the generic boundary runtime. `studiomcp validate ffmpeg-adapter` seeds the deterministic `examples/assets/audio/tone.wav` fixture, verifies reseeding repeatability, runs one successful transcode, and asserts the structured failure projection for a missing input. Current implementation status is tracked in [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/00-overview.md#current-repo-assessment-against-this-plan).

## Boundary Rule

FFmpeg is always an impure process boundary. The Haskell layer must:

- normalize inputs
- enforce timeout policy
- capture stdout and stderr
- project process failures into typed failure values

## Cross-References

- [Architecture Overview](../architecture/overview.md#architecture-overview)
- [Testing Strategy](../development/testing_strategy.md#testing-strategy)
- [MCP Surface Reference](../reference/mcp_surface.md#mcp-surface-reference)

# File: documents/tools/demucs.md
# Demucs

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../engineering/model_storage.md](../engineering/model_storage.md#cross-references), [../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md](../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md#cross-references)

> **Purpose**: Canonical tool note for the Demucs-compatible adapter surface in `studioMCP`.

## Summary

`src/StudioMCP/Tools/Demucs.hs` wraps the `demucs` CLI name behind the generic boundary runtime.
On the supported local image the command is provided by a deterministic repository shim so the
adapter surface stays stable even when upstream Python packaging is not.

## Model Contract

The adapter resolves model ID `demucs-htdemucs` through the MinIO-backed model registry when model
autoload is enabled.

## Validation Contract

`studiomcp validate demucs-adapter` verifies `demucs --help` and confirms structured failure
projection for a missing input path.

## Cross-References

- [Model Storage](../engineering/model_storage.md#model-storage)
- [CLI Reference](../reference/cli_reference.md#studiomcp-cli-reference)

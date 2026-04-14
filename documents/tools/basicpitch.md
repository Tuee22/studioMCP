# File: documents/tools/basicpitch.md
# Basic Pitch

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../engineering/model_storage.md](../engineering/model_storage.md#cross-references), [../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md](../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md#cross-references)

> **Purpose**: Canonical tool note for the Basic Pitch-compatible adapter surface in `studioMCP`.

## Summary

`src/StudioMCP/Tools/BasicPitch.hs` wraps the `basic-pitch` CLI name. The supported local image
ships a deterministic compatibility shim for that command so adapter validation and DAG examples do
not depend on unstable TensorFlow packaging in the outer container.

## Model Contract

The adapter uses model ID `basic-pitch` when autoload is enabled. Operators must provide a source
override because the registry intentionally has no baked-in download URL for this model.

## Validation Contract

`studiomcp validate basic-pitch-adapter` checks command availability and optional model-cache
resolution.

## Cross-References

- [Model Storage](../engineering/model_storage.md#model-storage)
- [CLI Reference](../reference/cli_reference.md#studiomcp-cli-reference)

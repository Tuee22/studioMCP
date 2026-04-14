# File: documents/tools/whisper.md
# Whisper

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../engineering/model_storage.md](../engineering/model_storage.md#cross-references), [../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md](../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md#cross-references)

> **Purpose**: Canonical tool note for the `whisper.cpp` adapter surface in `studioMCP`.

## Summary

`src/StudioMCP/Tools/Whisper.hs` wraps the `whisper` CLI name. The repository image builds the
binary from `whisper.cpp`, installs `libwhisper.so.1` plus the required `libggml*.so` companions
under `/usr/local/lib`, runs `ldconfig`, and keeps model bytes externalized through MinIO-backed
cache files.

## Model Contract

The current validator targets `whisper-base-en` and uses the MinIO cache only when
`STUDIOMCP_MODEL_AUTOLOAD` is enabled.

## Validation Contract

`docker compose run --rm studiomcp whisper --help` is expected to succeed in the outer container
without manual loader fixes. `studiomcp validate whisper-adapter` confirms the installed runtime is
present and that model autoload can resolve the registered model when storage config is available.

## Cross-References

- [Model Storage](../engineering/model_storage.md#model-storage)
- [CLI Reference](../reference/cli_reference.md#studiomcp-cli-reference)

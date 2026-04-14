# File: documents/engineering/model_storage.md
# Model Storage

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../tools/demucs.md](../tools/demucs.md#cross-references), [../tools/whisper.md](../tools/whisper.md#cross-references), [../tools/basicpitch.md](../tools/basicpitch.md#cross-references), [../tools/fluidsynth.md](../tools/fluidsynth.md#cross-references), [../../DEVELOPMENT_PLAN/phase-16-minio-model-storage.md](../../DEVELOPMENT_PLAN/phase-16-minio-model-storage.md#cross-references)

> **Purpose**: Define the MinIO-backed model registry, sync workflow, and runtime cache behavior for model-backed adapters in `studioMCP`.

## Summary

Model weights do not live in the repository image. `studioMCP` stores model bytes in the
`studiomcp-models` bucket, syncs them from configured public sources, and copies them to a local
cache only when an adapter or operator command needs them.

## Bucket Layout

| Model ID | Object Key | Default Source |
|----------|------------|----------------|
| `demucs-htdemucs` | `models/demucs/htdemucs.th` | Meta public checkpoint URL |
| `whisper-base-en` | `models/whisper/base.en.bin` | Hugging Face `whisper.cpp` artifact |
| `whisper-small-en` | `models/whisper/small.en.bin` | Hugging Face `whisper.cpp` artifact |
| `basic-pitch` | `models/basicpitch/model.npz` | no default; operator must provide override |
| `generaluser-gs` | `models/soundfonts/GeneralUser-GS.sf2` | no default; operator must provide override |

## CLI Workflow

The supported model-management entrypoints are:

```bash
docker compose run --rm studiomcp studiomcp models sync
docker compose run --rm studiomcp studiomcp models list
docker compose run --rm studiomcp studiomcp models verify
```

- `models sync` ensures the bucket exists and writes missing objects
- `models list` reports whether each registered model is present
- `models verify` re-downloads the configured source bytes and compares checksums against MinIO

## Configuration

Each model source can be overridden independently with an environment variable of the form:

```text
STUDIOMCP_MODEL_SOURCE_<NORMALIZED_MODEL_ID>
```

Examples:

- `STUDIOMCP_MODEL_SOURCE_BASIC_PITCH`
- `STUDIOMCP_MODEL_SOURCE_GENERALUSER_GS`
- `STUDIOMCP_MODEL_SOURCE_WHISPER_BASE_EN`

Runtime cache behavior uses:

- `STUDIOMCP_MODEL_CACHE_DIR` to override the local cache root
- `STUDIOMCP_MODEL_AUTOLOAD=true` to let adapter validators opportunistically cache models before validation

## Runtime Loading

`src/StudioMCP/Models/Loader.hs` resolves cached paths under `.data/studiomcp/model-cache/` by
default. The loader reads the object from MinIO exactly once per missing cache entry and then
reuses the cached bytes for subsequent adapter calls in the same workspace.

## Cross-References

- [MinIO](../tools/minio.md#minio)
- [CLI Reference](../reference/cli_reference.md#studiomcp-cli-reference)
- [Demucs](../tools/demucs.md#demucs)
- [Whisper](../tools/whisper.md#whisper)
- [Basic Pitch](../tools/basicpitch.md#basic-pitch)
- [FluidSynth](../tools/fluidsynth.md#fluidsynth)

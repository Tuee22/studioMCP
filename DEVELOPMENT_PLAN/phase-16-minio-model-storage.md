# Phase 16: MinIO Model Storage Infrastructure

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Provide the repository-owned model registry, MinIO sync surface, and local cache
> contract used by model-backed boundary adapters.

## Phase Summary

**Status**: Done
**Implementation**: `src/StudioMCP/Models/Registry.hs`, `src/StudioMCP/Models/Sync.hs`, `src/StudioMCP/Models/Loader.hs`, `src/StudioMCP/CLI/Models.hs`
**Blocked by**: Phase 15 (Done)
**Docs to update**: `system-components.md`, `documents/engineering/model_storage.md`

### Goal

Keep model weights out of containers while giving the repo a concrete model-management surface:

- a canonical registry of supported model artifacts
- idempotent sync and verification commands against MinIO bucket `studiomcp-models`
- an on-disk cache for runtime adapter use
- environment-variable overrides for source URLs and cache location

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Model registry and object-key inventory | `src/StudioMCP/Models/Registry.hs` | Done |
| Idempotent MinIO sync and checksum verification | `src/StudioMCP/Models/Sync.hs` | Done |
| Cache loader for runtime consumption | `src/StudioMCP/Models/Loader.hs` | Done |
| CLI `models sync`, `models list`, and `models verify` commands | `src/StudioMCP/CLI/Models.hs`, `src/StudioMCP/CLI/Command.hs`, `app/Main.hs` | Done |
| Governed storage documentation | `documents/engineering/model_storage.md`, `DEVELOPMENT_PLAN/system-components.md` | Done |

### Validation

| Check | Command | Expected |
|-------|---------|----------|
| Model registry and loader unit coverage | `docker compose run --rm studiomcp studiomcp test unit` | PASS |
| Full suite regression gate | `docker compose run --rm studiomcp studiomcp test` | PASS |
| Docs validation | `docker compose run --rm studiomcp studiomcp validate docs` | PASS |

### Remaining Work

None within the original registry, sync, and cache scope. The repository-owned model registry is
implemented and documented. [Phase 25](phase-25-auth-storage-and-runtime-contract-realignment.md)
records the later runtime alignment that makes MinIO-backed SoundFonts authoritative in practice.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/model_storage.md` - model bucket, overrides, and cache contract

**Product docs to create/update:**
- None

**Cross-references to add:**
- keep [system-components.md](system-components.md) aligned with the model-storage inventory

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-25-auth-storage-and-runtime-contract-realignment.md](phase-25-auth-storage-and-runtime-contract-realignment.md)

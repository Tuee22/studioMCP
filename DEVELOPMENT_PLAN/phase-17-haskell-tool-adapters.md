# Phase 17: Haskell Tool Adapters - Audio Foundation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Implement boundary adapters, registry entries, and validator hooks for the expanded
> tool inventory.

## Phase Summary

**Status**: Done
**Implementation**: `src/StudioMCP/Tools/*.hs`, `src/StudioMCP/CLI/Cluster.hs`, `src/StudioMCP/Tools/Registry.hs`
**Blocked by**: Phase 16 (Done)
**Docs to update**: `system-components.md`, `documents/reference/mcp_tool_catalog.md`, `documents/tools/*.md`

### Goal

Close the adapter layer between DAG `tool:` names and the outer-image executables. Each adapter now
has a repository-owned validation entrypoint, deterministic fixture support where needed, and a
stable registry mapping used by DAG validation and workflow examples. The later Phase 24 follow-on
closed the outer-container Whisper runtime repair, so the supported adapter path is runnable again
through the installed `whisper` executable.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Shared adapter helper utilities | `src/StudioMCP/Tools/AdapterSupport.hs` | Done |
| SoX adapter | `src/StudioMCP/Tools/SoX.hs` | Done |
| Demucs adapter | `src/StudioMCP/Tools/Demucs.hs` | Done |
| Whisper adapter | `src/StudioMCP/Tools/Whisper.hs` | Done |
| BasicPitch adapter | `src/StudioMCP/Tools/BasicPitch.hs` | Done |
| FluidSynth adapter | `src/StudioMCP/Tools/FluidSynth.hs` | Done |
| Rubberband adapter | `src/StudioMCP/Tools/Rubberband.hs` | Done |
| ImageMagick adapter | `src/StudioMCP/Tools/ImageMagick.hs` | Done |
| MediaInfo adapter | `src/StudioMCP/Tools/MediaInfo.hs` | Done |
| Expanded runtime tool registry | `src/StudioMCP/Tools/Registry.hs` | Done |
| CLI validator dispatch for each adapter | `src/StudioMCP/CLI/Command.hs`, `src/StudioMCP/CLI/Cluster.hs` | Done |

### Validation

| Check | Command | Expected |
|-------|---------|----------|
| Unit-level adapter coverage | `docker compose run --rm studiomcp studiomcp test unit` | PASS |
| SoX validator | `docker compose run --rm studiomcp studiomcp validate sox-adapter` | PASS |
| Demucs validator | `docker compose run --rm studiomcp studiomcp validate demucs-adapter` | PASS |
| Whisper validator | `docker compose run --rm studiomcp studiomcp validate whisper-adapter` | PASS |
| BasicPitch validator | `docker compose run --rm studiomcp studiomcp validate basic-pitch-adapter` | PASS |
| FluidSynth validator | `docker compose run --rm studiomcp studiomcp validate fluidsynth-adapter` | PASS |
| Rubberband validator | `docker compose run --rm studiomcp studiomcp validate rubberband-adapter` | PASS |
| ImageMagick validator | `docker compose run --rm studiomcp studiomcp validate imagemagick-adapter` | PASS |
| MediaInfo validator | `docker compose run --rm studiomcp studiomcp validate mediainfo-adapter` | PASS |

### Current Validation State

- The adapter modules, runtime registry entries, and validator command surface remain implemented in
  the current source tree.
- `docker compose run --rm studiomcp studiomcp validate whisper-adapter` passes on April 15, 2026,
  and the repaired outer-container runtime now executes the installed `whisper` binary without
  loader failures.
- [phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md) records the closed
  follow-on that restored the runnable Whisper adapter path.

### Remaining Work

None. This baseline adapter phase remains closed, and
[phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md) now records the
completed Whisper runtime follow-on.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/tools/sox.md`
- `documents/tools/demucs.md`
- `documents/tools/whisper.md`
- `documents/tools/basicpitch.md`
- `documents/tools/fluidsynth.md`
- `documents/tools/rubberband.md`
- `documents/tools/imagemagick.md`
- `documents/tools/mediainfo.md`

**Product docs to create/update:**
- `documents/reference/mcp_tool_catalog.md`

**Cross-references to add:**
- keep [system-components.md](system-components.md) aligned with the registry inventory
- keep [phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md) aligned as the closed follow-on record for the Whisper runtime repair

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-16-minio-model-storage.md](phase-16-minio-model-storage.md)
- [phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md)

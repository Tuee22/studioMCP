# Phase 15: Monocontainer Tool Expansion - Audio Foundation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Expand the outer development image with the boundary-tool inventory required for the
> current audio, image, and metadata workflow surface without baking model weights into containers.

## Phase Summary

**Status**: Done
**Implementation**: `docker/Dockerfile`, `docker/tool-shims/demucs.py`, `docker/tool-shims/basic_pitch.py`
**Blocked by**: Phase 14 (Done)
**Docs to update**: `system-components.md`, `documents/engineering/docker_policy.md`

### Goal

The single-stage outer image now ships the executables needed for boundary validation and example
workflow coverage. Native tools are installed where practical, `whisper` is built from
`whisper.cpp`, and the current local image uses deterministic compatibility shims for `demucs` and
`basic-pitch` so the boundary contracts can be exercised without pulling heavyweight runtime stacks
into the repository image. The later Phase 24 follow-on closed the Whisper shared-library runtime
repair, so the supported outer image now exposes a runnable `whisper` CLI without manual loader
fixes.

### Tool Inventory Closed By This Phase

| Tool | Delivery | Notes |
|------|----------|-------|
| `sox` | distro package | audio trim, fade, normalize, and format work |
| `whisper` | built from `whisper.cpp` | CLI binary only; model files remain externalized |
| `demucs` | local shim | deterministic compatibility surface for adapter validation |
| `basic-pitch` | local shim | deterministic compatibility surface for adapter validation |
| `fluidsynth` | distro package plus bundled SoundFont | uses system SoundFont fallback when no cached model is supplied |
| `rubberband` | distro package | time-stretch and pitch-shift |
| `imagemagick` (`convert`) | distro package | image resize and format conversion |
| `mediainfo` | distro package | media inspection |
| `exiftool` | distro package | metadata extraction support |

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Expand the single-stage Dockerfile tool inventory | `docker/Dockerfile` | Done |
| Build and install `whisper` from `whisper.cpp` | `docker/Dockerfile` | Done |
| Install deterministic local shims for `demucs` and `basic-pitch` | `docker/tool-shims/*.py` | Done |
| Update the system inventory and container policy docs | `DEVELOPMENT_PLAN/system-components.md`, `documents/engineering/docker_policy.md` | Done |

### Validation

| Check | Command | Expected |
|-------|---------|----------|
| Container build | `docker compose build` | Success |
| Demucs surface available | `docker compose run --rm studiomcp demucs --help` | Help output |
| Whisper surface available | `docker compose run --rm studiomcp whisper --help` | Help output |
| Basic Pitch surface available | `docker compose run --rm studiomcp basic-pitch --help` | Help output |
| FluidSynth available | `docker compose run --rm studiomcp fluidsynth --help` | Help output |
| Rubberband available | `docker compose run --rm studiomcp rubberband --help` | Help output |
| MediaInfo available | `docker compose run --rm studiomcp mediainfo --Version` | Version output |

### Current Validation State

- The current source tree still carries the expanded tool inventory and `whisper.cpp` build hooks.
- `docker compose run --rm studiomcp whisper --help` passes on April 14, 2026 after the rebuilt
  outer image installs loader-visible `libwhisper.so.1` and companion `libggml*.so` files under
  `/usr/local/lib`.
- [phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md) records the closed
  follow-on that restored the runnable Whisper surface.

### Remaining Work

None. This baseline image-expansion phase remains closed, and
[phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md) now records the
completed Whisper runtime follow-on.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/docker_policy.md` - document the image-owned tool inventory

**Product docs to create/update:**
- None

**Cross-references to add:**
- keep [system-components.md](system-components.md) aligned with the actual tool inventory
- keep [phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md) aligned as the closed follow-on record for the Whisper runtime repair

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md)

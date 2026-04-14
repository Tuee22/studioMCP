# File: documents/tools/fluidsynth.md
# FluidSynth

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../engineering/model_storage.md](../engineering/model_storage.md#cross-references), [../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md](../../DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md#cross-references)

> **Purpose**: Canonical tool note for the FluidSynth boundary adapter in `studioMCP`.

## Summary

`src/StudioMCP/Tools/FluidSynth.hs` renders deterministic MIDI fixtures to audio through
`fluidsynth`.

## SoundFont Contract

Validation resolves a SoundFont in this order:

1. `STUDIOMCP_FLUIDSYNTH_SOUNDFONT`
2. cached model `generaluser-gs`
3. system SoundFonts installed in the container image

## Validation Contract

`studiomcp validate fluidsynth-adapter` renders the `simple-melody` fixture to WAV and verifies the
output is non-empty.

## Cross-References

- [Model Storage](../engineering/model_storage.md#model-storage)
- [Test Fixtures](../development/test_fixtures.md#test-fixtures)

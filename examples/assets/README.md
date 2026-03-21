# Example Assets

This directory now contains deterministic fixtures owned by the native Haskell validation workflow.

Current assets:

- `audio/tone.wav`: a one-second 440 Hz WAV fixture seeded by `studiomcp validate ffmpeg-adapter`

Rules:

- fixtures here must be deterministic and safe to reseed
- fixture seeding must stay in Haskell, not shell scripts
- validation commands may overwrite and regenerate these files when proving repeatability

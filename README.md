# studioMCP

## Project Vision
`studioMCP` is a Haskell-first MCP platform for DAG-based studio workflows with typed DAG execution, a live MCP surface, Keycloak-backed auth, a browser-facing BFF, and a Kubernetes-forward local edge deployment path.

## Why This Could Replace Large Parts of DAW / Photo / Video Toolchains
Most studio workflows are long chains of deterministic transforms wrapped around a smaller number of impure boundaries. `studioMCP` treats those chains as typed DAGs instead of opaque editor sessions. That creates room for repeatability, memoization, better summaries, and safer automation.

## Why Haskell Is a Fit
Haskell is the ownership layer for:

- DAG types and validation
- railway-oriented result handling
- timeout semantics
- summary construction
- memoization-key derivation
- storage and messaging contracts
- the MCP-facing protocol and execution plane

The point is not novelty. The point is to make the orchestration semantics hard to accidentally weaken.

## Pure DAG Execution Model
Every executable node is one of:

- `PureNode`: typed and deterministic from the interpreter’s point of view
- `BoundaryNode`: wraps an impure tool or service behind a typed contract
- `SummaryNode`: derives the final immutable run summary

The server accepts only validated DAG definitions. Callers do not bypass the Haskell model.

## Railway-Oriented Result Handling
Node execution returns `Result success failure`. Success values may be memoized. Failure values are explicit, structured, and user-presentable. The system never relies on hidden exceptional control flow as its public execution model.

## Timeout Semantics
Every node has a timeout policy. A timeout is modeled as a real failure outcome, not an infrastructure footnote. The final `Summary` must show timeouts distinctly from semantic tool failures.

## Memoization Semantics
Successful pure results are addressed by content-oriented keys derived from normalized inputs and execution semantics. Immutable outputs go to MinIO. Changing semantics must produce a new key, not overwrite an old one.

## Pulsar vs MinIO
- Pulsar is the source of truth for in-flight execution state.
- MinIO is the immutable store for memoized outputs, manifests, summaries, and durable artifacts.

They are intentionally separate systems because they solve different problems.

## Repository Architecture
Early structure:

```text
app/               executable entrypoints
src/               Haskell library modules
test/              unit and integration tests
docker/            Dockerfile and container assets
docker-compose.yaml  one-off outer development container launcher
chart/             Helm deployment source of truth
kind/              local kind cluster configuration
skaffold.yaml      Kubernetes-native development loop config
documents/         governed architecture, development, domain, and tool docs
examples/          sample DAGs and fixtures
.data/             local persistent cluster data ignored by git and Docker builds
```

## Documentation Suite
The repository uses `documents/`, not `docs/`, for the governed documentation suite. Start with [documents/README.md](/Users/matthewnowak/studioMCP/documents/README.md) for the index and [documents/documentation_standards.md](/Users/matthewnowak/studioMCP/documents/documentation_standards.md) for the SSoT rules, Mermaid constraints, and metadata requirements.

Current documentation categories:

- `architecture/`
- `development/`
- `domain/`
- `engineering/` for engineering standards such as Kubernetes-native development policy
- `operations/`
- `reference/`
- `tools/`

The governed suite is current-state declarative documentation. Historical decision trails live in git history, not an ADR folder.

## Server Mode
`server` mode owns DAG submission, validation, execution orchestration, run-state progression, and summary retrieval. This is the authoritative execution path.

## Inference Mode
`inference` mode is a local reference-LLM path for DAG drafting, repair suggestions, documentation Q&A, and operator assistance. It is advisory only. It must not bypass typed validation or mutate persisted results directly.

## Cluster Management CLI
Supported operational commands live in the Haskell `studiomcp` CLI, not in checked-in shell helpers. The intended control-plane workflow is `docker compose run --rm studiomcp studiomcp <subcommand...>`. See [documents/reference/cli_reference.md](/Users/matthewnowak/studioMCP/documents/reference/cli_reference.md), [documents/architecture/cli_architecture.md](/Users/matthewnowak/studioMCP/documents/architecture/cli_architecture.md), and [documents/engineering/docker_policy.md](/Users/matthewnowak/studioMCP/documents/engineering/docker_policy.md).

## Docker Strategy
The repo uses one single-stage Dockerfile at [docker/Dockerfile](/Users/matthewnowak/studioMCP/docker/Dockerfile). The resulting image includes the Haskell toolchain, cluster-management tools, `tini`, and the `studiomcp` binary. Compose uses it only for one-off outer-container commands, while Helm owns explicit in-cluster startup for the server, BFF, and worker workloads.

## Kubernetes-Native Development
The repo is Kubernetes-forward. Helm under [chart/](/Users/matthewnowak/studioMCP/chart) defines service topology, [skaffold.yaml](/Users/matthewnowak/studioMCP/skaffold.yaml) remains part of the image-build and deploy toolchain, and [kind/kind_config.yaml](/Users/matthewnowak/studioMCP/kind/kind_config.yaml) defines the local cluster target. Compose at [docker-compose.yaml](/Users/matthewnowak/studioMCP/docker-compose.yaml) launches one-off outer `studiomcp` containers for individual commands only; all application services (MCP server, BFF, Keycloak, Redis, MinIO, Pulsar, PostgreSQL-HA) run inside the kind cluster via Helm. The control plane is exposed through ingress-nginx at `http://localhost:8081` with `/mcp`, `/api`, `/kc`, and `/minio`; object-storage data-plane URLs remain rooted at `http://localhost:9000`. The canonical policies are [documents/engineering/k8s_native_dev_policy.md](/Users/matthewnowak/studioMCP/documents/engineering/k8s_native_dev_policy.md), [documents/engineering/docker_policy.md](/Users/matthewnowak/studioMCP/documents/engineering/docker_policy.md), and [documents/engineering/k8s_storage.md](/Users/matthewnowak/studioMCP/documents/engineering/k8s_storage.md).

## FOSS Ecosystem Survey
The project leans on existing tools instead of rebuilding them:

- FFmpeg and SoX for audio/video transforms
- GStreamer for pipeline-oriented media handling
- ImageMagick and OpenCV for image processing
- Blender for rendering/compositing boundaries
- Pulsar for in-flight execution state
- MinIO for immutable object persistence
- a local LLM host such as Ollama or `llama.cpp` for inference mode

## Future Music Workflow Expansion
The current repository already proves the boundary-adapter pattern against media tooling, but the
longer-term plan is to expand `studioMCP` into a broader music and notation workflow platform. The
items in this section are planned future workflows, not claims about the current runtime surface.

Two platform rules shape this expansion:

- Linux + CUDA is a first-class production stack, deployed through containerized workers with the
  NVIDIA Container Runtime.
- Apple Silicon + Metal is a first-class local and workstation stack, deployed natively on macOS
  without virtualization or containerization.

The intended future workflow families are:

### Speech, Transcript, and Localization Workflows
- `Speech transcript and subtitle extraction`: ingest audio or video, normalize with `ffmpeg`,
  transcribe with Whisper-family models, and emit transcript, `srt`, and `vtt` artifacts.
- `Podcast cleanup and transcript preparation`: separate stems where useful, denoise and master with
  `sox`/`ffmpeg`, generate transcripts, and package mastered audio plus text artifacts together.
- `Video localization and caption republishing`: extract speech, transcribe it, align subtitles,
  and republish captioned or localized video derivatives.
- `Meeting and rehearsal logs`: ingest rehearsal-room recordings, generate searchable transcripts,
  and attach run summaries and artifact references for later retrieval.

### Audio DSP and Stem Workflows
- `Stem separation`: split mixed music into vocals, drums, bass, and accompaniment stems using
  ANN-backed source-separation models.
- `Stem cleanup and remix packaging`: branch separated stems into cleanup nodes, then remix and
  republish alternate vocal/instrumental packages.
- `Karaoke preparation`: build instrumental, vocal-only, and lyric-timed deliverables from a single
  source mix.
- `Tempo-safe practice tracks`: stretch or compress tempo with `rubberband` while preserving pitch,
  then master the result for rehearsal use.
- `Pitch-shifted practice tracks`: transpose accompaniment into player-friendly keys without
  re-recording source material.
- `Reference mastering and delivery normalization`: normalize loudness, trim silence, inspect media
  metadata, and package stable output formats for downstream workflows.

### Automatic Music Transcription and MIR Workflows
- `Baseline audio-to-MIDI transcription`: convert solo or simple polyphonic audio into MIDI for
  quick symbolic capture.
- `Multi-instrument transcription`: separate stems first, then transcribe multiple instruments and
  merge symbolic outputs into a common score-oriented representation.
- `Vocal melody transcription`: extract note-level or contour-level vocal melody from songs or
  rehearsal takes.
- `Drum-event transcription`: produce drum-event timelines suitable for charts, beat-aware editing,
  or practice loops.
- `Chord, key, beat, and tempo analysis`: derive harmonic and temporal descriptors that can feed
  arrangement, search, and cataloging workflows.
- `Section and similarity analysis`: compute structural fingerprints and descriptors for search,
  duplicate detection, cover-song analysis, and library indexing.
- `Lead-sheet extraction from audio`: combine melody transcription with chord analysis to produce a
  first-pass lead sheet from a recording.

### Symbolic Arrangement and Transformation Workflows
- `Transcription cleanup`: quantize note starts and durations, split voices, normalize measures, and
  repair symbolic artifacts before arrangement or engraving.
- `Automatic transposition`: transpose a score for different keys or transposing instruments while
  preserving symbolic semantics.
- `Part extraction`: derive per-instrument parts from a full score and publish them as independent
  artifacts.
- `Piano reduction and condensed score generation`: reduce larger ensemble material into a playable
  piano or condensed conductor score.
- `Ensemble arrangement generation`: map symbolic material into SATB, string, wind, rhythm-section,
  or other target ensembles.
- `Difficulty reduction`: simplify rhythms, ranges, densities, and textures for student or amateur
  performers.
- `Harmonic annotation`: produce Roman numeral, chord-symbol, and structural annotations for theory,
  rehearsal, and pedagogy workflows.
- `Round-trip audition`: render symbolic outputs back to audio using `fluidsynth` so arrangement
  changes can be reviewed without leaving the workflow system.

### Notation, Engraving, and Publishing Workflows
- `Deterministic engraving`: convert `MusicXML` or other symbolic sources into engraved `pdf`, `svg`,
  and `png` score artifacts through deterministic notation backends.
- `Browser score preview`: render `MusicXML` directly in the web surface for lightweight review,
  approval, and artifact inspection.
- `Score package publishing`: bundle full score, extracted parts, rehearsal audio, click tracks, and
  metadata into a single publishable artifact set.
- `Format normalization`: convert between `MIDI`, `MusicXML`, score-editor formats, and preview
  assets so downstream consumers work against a canonical representation.
- `Playback proofing`: render engraved or converted scores back to audio and compare them against the
  symbolic source to catch notation and export regressions.

### OMR, Archive, and Library Workflows
- `Scan and PDF to editable score`: ingest sheet-music images or PDFs through OMR and convert them
  into editable symbolic notation.
- `OMR review loop`: pair machine recognition with browser or desktop score review so operators can
  repair low-confidence output before publishing.
- `Archive normalization of mixed catalogs`: ingest legacy combinations of scanned PDFs, notation
  files, MIDI, and audio, then normalize them into canonical symbolic and preview artifacts.
- `Music library indexing`: extract descriptors, symbolic summaries, and searchable metadata for
  large music collections.
- `Version and cover comparison`: compare recordings or scores for key, tempo, arrangement, and
  structure drift across versions.

## Future ANN Inference Strategy
The future music stack includes several ANN-backed tools and models. We want Linux + CUDA and Apple
Silicon + Metal to be first-class citizens, but they should not be forced into the same deployment
shape.

- Linux + CUDA should prefer containerized workers with NVIDIA Container Runtime, stable pinned
  Python environments, and GPU-oriented inference engines such as TensorRT, CUDA-enabled PyTorch,
  CUDA-enabled TensorFlow, and JAX/XLA on NVIDIA GPUs.
- Apple Silicon should prefer native macOS workers, Homebrew or system dependencies, Python virtual
  environments, and Apple-native acceleration layers such as Metal, Core ML, JAX Metal, and PyTorch
  MPS. Docker and VM-only support is not sufficient for the Apple path.

The planned default engine choices are:

| ANN-backed model/tool | Primary workflow role | Linux + CUDA stack | Apple Silicon + Metal stack | Planned default |
| --- | --- | --- | --- | --- |
| `Whisper` / `whisper.cpp` | speech transcription, subtitle generation, transcript indexing | `CTranslate2`-backed Whisper serving for batch/server throughput; keep `whisper.cpp` available as a compact CLI path | `whisper.cpp` with Metal, optionally enabling the Core ML encoder path on Apple Silicon | split by platform |
| `Demucs HTDemucs` | music source separation, podcast stem cleanup, karaoke preparation | native `PyTorch` on CUDA | native `PyTorch` on MPS | `PyTorch` on both stacks |
| `Basic Pitch` | baseline audio-to-MIDI transcription | native `TensorFlow` with CUDA | native `Core ML` runtime from the shipped Core ML serialization | split by platform |
| `MT3` | higher-accuracy multi-instrument transcription | native `JAX` / `XLA` on NVIDIA GPUs | native `JAX` with the Apple `jax-metal` plug-in | `JAX` on both stacks |
| `Omnizart` family | music, vocal, drum, chord, and beat transcription | native `TensorFlow` with CUDA | repo-owned exported `Core ML` models; upstream package compatibility is not enough for first-class Apple support | split by platform |
| `Open-Unmix` | alternate or research-oriented source separation | native `PyTorch` on CUDA | native `PyTorch` on MPS | `PyTorch` on both stacks |

Operational notes for these ANN-backed paths:

- `Whisper`: the Linux path should optimize for throughput and queueable server inference, while the
  Apple path should optimize for offline local execution and low-friction native installs.
- `Demucs` and `Open-Unmix`: keep them in isolated GPU worker classes because source separation has
  materially different memory and batching behavior from speech transcription.
- `Basic Pitch`: keep both TensorFlow and non-TensorFlow serializations available, but treat
  TensorFlow-on-CUDA and Core ML-on-Apple as the default production lanes.
- `MT3`: treat JAX as the canonical execution model and keep the Apple Metal path under active
  conformance testing because JAX Metal support is younger than CUDA.
- `Omnizart`: do not treat the current upstream ARM-macOS incompatibility as acceptable. First-class
  Apple support means we own the model export and execution path needed to run it natively.
- `Audiveris`: although Audiveris uses a neural network internally for some symbol classes, it
  should be treated as an integrated JVM OMR application rather than as a separately managed ANN
  model runtime.

The non-ANN tools in the future stack, such as `ffmpeg`, `sox`, `rubberband`, `fluidsynth`,
`music21`, `lilypond`, `OpenSheetMusicDisplay`, `MuseScore`, `Essentia`, and `Sonic Annotator`,
remain important, but they do not need the same inference-engine matrix.

## Future FOSS Tooling Targets
The future workflow expansion is expected to add or deepen integration with:

- [`whisper.cpp`](https://github.com/ggml-org/whisper.cpp) for native speech transcription
- [`faster-whisper`](https://github.com/SYSTRAN/faster-whisper) and [`CTranslate2`](https://opennmt.net/CTranslate2/) for high-throughput Whisper inference on NVIDIA GPUs
- [`Demucs`](https://github.com/facebookresearch/demucs) and [`Open-Unmix`](https://github.com/sigsep/open-unmix-pytorch) for source separation
- [`Basic Pitch`](https://github.com/spotify/basic-pitch), [`MT3`](https://github.com/magenta/mt3), and [`Omnizart`](https://github.com/Music-and-Culture-Technology-Lab/omnizart) for automatic music transcription
- [`music21`](https://github.com/cuthbertLab/music21) for symbolic transformation and arrangement
- [`LilyPond`](https://github.com/lilypond/lilypond), [`MuseScore`](https://github.com/musescore/MuseScore), and [`OpenSheetMusicDisplay`](https://github.com/opensheetmusicdisplay/opensheetmusicdisplay) for notation, conversion, rendering, and browser preview
- [`Audiveris`](https://github.com/Audiveris/audiveris) for optical music recognition
- [`Essentia`](https://essentia.upf.edu/) and [`Sonic Annotator`](https://github.com/sonic-visualiser/sonic-annotator) for MIR extraction and analysis

## Development Roadmap
The authoritative implementation plan lives in [DEVELOPMENT_PLAN/README.md](/Users/matthewnowak/studioMCP/DEVELOPMENT_PLAN/README.md). The roadmap is split into an overview, system-component inventory, per-phase documents, and a cleanup ledger. Phases 1-24 are now closed against the current repository scope, including the compose-only workflow, expanded boundary-tool inventory, the repaired outer-container Whisper runtime, model and fixture infrastructure, adapter validators, example DAG chains, synthetic chaos coverage, SES email surface, and governed tool documentation. Redirect-based OAuth/PKCE remains intentionally deferred.

## Status / Current Maturity
Current state:

- Repository policy and development plan are in place.
- The `documents/` suite now has an explicit standards SSoT and index.
- Kubernetes-forward repo scaffolding is in place: one Dockerfile, one Helm chart, Skaffold config, and kind config.
- The no-scripts policy, outer development-container model, and local storage doctrine are now documented and materially embodied in code.
- The current roadmap is materially implemented on the supported path: the runtime, auth, control-plane contract, browser session contract, cluster parity, realm bootstrap automation, registry image flow, CLI-managed secrets, build artifact isolation, and final regression gate are all closed.
- The `studiomcp` CLI now includes native `test`, `test unit`, `test integration`, `test seed-fixtures`, `test verify-fixtures`, `test chaos`, `models sync`, `models list`, `models verify`, `email send-test`, `validate all`, `dag validate ...`, `dag validate-fixtures`, `validate docs`, `validate cluster`, `validate pulsar`, `validate minio`, `validate boundary`, `validate ffmpeg-adapter`, `validate sox-adapter`, `validate demucs-adapter`, `validate whisper-adapter`, `validate basic-pitch-adapter`, `validate fluidsynth-adapter`, `validate rubberband-adapter`, `validate imagemagick-adapter`, `validate mediainfo-adapter`, `validate executor`, `validate e2e`, `validate worker`, `validate inference`, `validate mcp-stdio`, `validate mcp-http`, `validate mcp-conformance`, `validate keycloak`, `validate mcp-auth`, `validate session-store`, `validate horizontal-scale`, `validate web-bff`, and `cluster ...` commands, plus `studiomcp bff`. See [documents/reference/cli_reference.md](/Users/matthewnowak/studioMCP/documents/reference/cli_reference.md) for the complete CLI reference.
- `docker-compose.yaml` now launches ephemeral outer `studiomcp` development containers; all application services run in the kind cluster.
- A real Haskell MinIO adapter now round-trips memo objects, manifests, and summaries through the deployed MinIO sidecar and maps missing-object lookups to a stable storage failure contract.
- A real boundary runtime now executes deterministic helper processes with stdout/stderr capture, non-zero exit projection, and enforced timeout failure mapping, and `studiomcp validate boundary` exercises that contract.
- A real FFmpeg adapter now runs on top of the boundary runtime, seeds a deterministic WAV fixture under `examples/assets/audio/`, validates one successful transcode, and asserts structured failure output for a missing input.
- The server, inference, worker, and BFF entrypoints are all real runtimes with validation coverage, including the live Keycloak-backed auth, browser session, and nginx edge paths.
- Verified commands now include `docker compose run --rm studiomcp cabal --builddir=/opt/build/studiomcp build all`, `docker compose run --rm studiomcp studiomcp test`, `docker compose run --rm studiomcp studiomcp validate docs`, `docker compose config`, the cluster validation family, the MCP validation family (`validate mcp-stdio`, `validate mcp-http`, `validate mcp-conformance`), the auth/session validation family (`validate keycloak`, `validate mcp-auth`, `validate session-store`, `validate horizontal-scale`, `validate web-bff`), the new boundary-validator family (`validate sox-adapter`, `validate demucs-adapter`, `validate whisper-adapter`, `validate basic-pitch-adapter`, `validate fluidsynth-adapter`, `validate rubberband-adapter`, `validate imagemagick-adapter`, `validate mediainfo-adapter`), plus `helm lint`, `helm template`, `skaffold diagnose`, and `skaffold render`. The current suite counts and latest aggregate validation results are tracked in [DEVELOPMENT_PLAN/README.md](/Users/matthewnowak/studioMCP/DEVELOPMENT_PLAN/README.md).
- The basic outer-container cluster workflow is now verified on this machine. The shipped `values-kind.yaml` uses manual host-backed persistent volumes for stateful sidecars, and `cluster storage reconcile` applies those PVs before Helm deployment.

## Contribution Guidance
The repo treats documentation, architecture notes, and tests as first-class artifacts. Follow the suite index at [documents/README.md](/Users/matthewnowak/studioMCP/documents/README.md) and the documentation rules at [documents/documentation_standards.md](/Users/matthewnowak/studioMCP/documents/documentation_standards.md). LLM agents may edit files and run local validation, but commits and pushes are reserved for the human user. See [AGENTS.md](/Users/matthewnowak/studioMCP/AGENTS.md) and [CLAUDE.md](/Users/matthewnowak/studioMCP/CLAUDE.md).

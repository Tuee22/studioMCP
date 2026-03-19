# studioMCP

## Project Vision
`studioMCP` is a Haskell-first MCP server for pure DAG-based studio workflows. It is intended to orchestrate free/open-source audio, image, and video tooling behind a typed execution model that makes timeouts, failures, memoization, and summaries explicit.

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
- the MCP-facing control plane

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
app/        executable entrypoints
src/        Haskell library modules
test/       unit and integration tests
docker/     single Dockerfile and integration-harness assets
chart/      Helm deployment source of truth
kind/       local kind cluster configuration
skaffold.yaml  Kubernetes-native development loop config
documents/  governed architecture, development, domain, and tool docs
examples/   sample DAGs and fixtures
scripts/    local developer helpers
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
- `adr/`

## Server Mode
`server` mode owns DAG submission, validation, execution orchestration, run-state progression, and summary retrieval. This is the authoritative execution path.

## Inference Mode
`inference` mode is a local reference-LLM path for DAG drafting, repair suggestions, documentation Q&A, and operator assistance. It is advisory only. It must not bypass typed validation or mutate persisted results directly.

## Docker Strategy
The repo uses one Dockerfile at [docker/Dockerfile](/Users/matthewnowak/studioMCP/docker/Dockerfile). Docker is the image-build substrate, not the deployment topology source of truth. The `production` target is the canonical image target consumed by Helm and Skaffold.

## Kubernetes-Native Development
The repo is Kubernetes-forward. Helm under [chart/](/Users/matthewnowak/studioMCP/chart) defines service topology, [skaffold.yaml](/Users/matthewnowak/studioMCP/skaffold.yaml) drives the local dev loop, and [kind/kind_config.yaml](/Users/matthewnowak/studioMCP/kind/kind_config.yaml) defines the local cluster. Compose at [docker/docker-compose.yaml](/Users/matthewnowak/studioMCP/docker/docker-compose.yaml) is retained only for the stateful integration harness. The canonical engineering policy is [documents/engineering/k8s_native_dev_policy.md](/Users/matthewnowak/studioMCP/documents/engineering/k8s_native_dev_policy.md).

## FOOS Ecosystem Survey
The project leans on existing tools instead of rebuilding them:

- FFmpeg and SoX for audio/video transforms
- GStreamer for pipeline-oriented media handling
- ImageMagick and OpenCV for image processing
- Blender for rendering/compositing boundaries
- Pulsar for in-flight execution state
- MinIO for immutable object persistence
- a local LLM host such as Ollama or `llama.cpp` for inference mode

## Development Roadmap
The implementation plan lives in [STUDIOMCP_DEVELOPMENT_PLAN.md](/Users/matthewnowak/studioMCP/STUDIOMCP_DEVELOPMENT_PLAN.md). Foundation, Haskell scaffolding, core types, and YAML DAG parsing/validation are already in place. The next sequence is:

1. Pulsar integration
2. MinIO integration
3. Boundary execution
4. End-to-end DAG runs
5. MCP surface
6. Inference mode
7. expanded documentation and tool coverage

## Status / Current Maturity
Current state:

- Repository policy and development plan are in place.
- The `documents/` suite now has an explicit standards SSoT and index.
- Kubernetes-forward repo scaffolding is in place: one Dockerfile, one Helm chart, Skaffold config, and kind config.
- Helm and Skaffold validation paths now run successfully in this environment.
- Phases 0 through 3 are implemented at the scaffold level: foundation, Haskell project, core DAG types, YAML parsing, and validation.
- `cabal build all`, `cabal test unit-tests`, and harness-backed Pulsar/MinIO integration checks are passing.

## Contribution Guidance
The repo treats documentation, architecture notes, and tests as first-class artifacts. Follow the suite index at [documents/README.md](/Users/matthewnowak/studioMCP/documents/README.md) and the documentation rules at [documents/documentation_standards.md](/Users/matthewnowak/studioMCP/documents/documentation_standards.md). LLM agents may edit files and run local validation, but commits and pushes are reserved for the human user. See [AGENTS.md](/Users/matthewnowak/studioMCP/AGENTS.md) and [CLAUDE.md](/Users/matthewnowak/studioMCP/CLAUDE.md).

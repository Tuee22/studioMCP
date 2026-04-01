# studioMCP

## Project Vision
`studioMCP` is a Haskell-first MCP platform for DAG-based studio workflows. The repository already contains the typed execution foundations, but the current public server surface is still being migrated from a custom DAG HTTP API to a standards-compliant MCP server.

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
docker-compose.yaml  outer development-container launcher
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
Supported operational commands are expected to live in the Haskell `studiomcp` CLI, not in checked-in shell helpers. The intended control-plane workflow is `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp <subcommand...>`. See [documents/architecture/cli_architecture.md](/Users/matthewnowak/studioMCP/documents/architecture/cli_architecture.md), [documents/reference/cli_surface.md](/Users/matthewnowak/studioMCP/documents/reference/cli_surface.md), and [documents/engineering/docker_policy.md](/Users/matthewnowak/studioMCP/documents/engineering/docker_policy.md).

## Docker Strategy
The repo uses one multi-stage Dockerfile at [docker/Dockerfile](/Users/matthewnowak/studioMCP/docker/Dockerfile). One stage is the outer development container with the Haskell toolchain and cluster-management tools. Another stage builds the runtime image for the actual MCP server, which is intended to run only inside the kind cluster.

## Kubernetes-Native Development
The repo is Kubernetes-forward. Helm under [chart/](/Users/matthewnowak/studioMCP/chart) defines service topology, [skaffold.yaml](/Users/matthewnowak/studioMCP/skaffold.yaml) remains part of the image-build and deploy toolchain, and [kind/kind_config.yaml](/Users/matthewnowak/studioMCP/kind/kind_config.yaml) defines the local cluster target. Compose at [docker-compose.yaml](/Users/matthewnowak/studioMCP/docker-compose.yaml) is intended to launch the outer development container and bind host `./.data/` plus the active Docker context into it. The canonical policies are [documents/engineering/k8s_native_dev_policy.md](/Users/matthewnowak/studioMCP/documents/engineering/k8s_native_dev_policy.md), [documents/engineering/docker_policy.md](/Users/matthewnowak/studioMCP/documents/engineering/docker_policy.md), and [documents/engineering/k8s_storage.md](/Users/matthewnowak/studioMCP/documents/engineering/k8s_storage.md).

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
The implementation plan lives in [STUDIOMCP_DEVELOPMENT_PLAN.md](/Users/matthewnowak/studioMCP/STUDIOMCP_DEVELOPMENT_PLAN.md). The current phase plan is complete through Phase 17. Remaining work now belongs to the next planning pass rather than to unfinished work inside the current roadmap.

## Status / Current Maturity
Current state:

- Repository policy and development plan are in place.
- The `documents/` suite now has an explicit standards SSoT and index.
- Kubernetes-forward repo scaffolding is in place: one Dockerfile, one Helm chart, Skaffold config, and kind config.
- The no-scripts policy, outer development-container model, and local storage doctrine are now documented and materially embodied in code.
- All phases in the current development plan are complete through Phase 17.
- The `studiomcp` CLI now includes native `dag validate ...`, `dag validate-fixtures`, `validate docs`, `validate cluster`, `validate pulsar`, `validate minio`, `validate boundary`, `validate ffmpeg-adapter`, `validate executor`, `validate e2e`, `validate worker`, `validate mcp`, `validate inference`, `validate observability`, `cluster up`, `cluster down`, `cluster status`, `cluster deploy ...`, and `cluster storage reconcile` commands.
- `docker-compose.yaml` now launches `studiomcp-env` as the outer development container instead of a local sidecar topology.
- A real Haskell MinIO adapter now round-trips memo objects, manifests, and summaries through the deployed MinIO sidecar and maps missing-object lookups to a stable storage failure contract.
- A real boundary runtime now executes deterministic helper processes with stdout/stderr capture, non-zero exit projection, and enforced timeout failure mapping, and `studiomcp validate boundary` exercises that contract.
- A real FFmpeg adapter now runs on top of the boundary runtime, seeds a deterministic WAV fixture under `examples/assets/audio/`, validates one successful transcode, and asserts structured failure output for a missing input.
- The server, inference, and worker entrypoints are all real HTTP runtimes with live validation coverage. The current `server` runtime still exposes a legacy custom DAG HTTP surface and is planned to migrate to a proper MCP protocol surface under the revised development plan.
- Verified commands now include `cabal build all`, `cabal test unit-tests`, `cabal test integration-tests` (requires outer container and cluster), `cabal run studiomcp -- validate docs`, `docker compose -f docker-compose.yaml exec -T studiomcp-env studiomcp validate cluster`, `... validate pulsar`, `... validate minio`, `... validate boundary`, `... validate ffmpeg-adapter`, `... validate executor`, `... validate e2e`, `... validate worker`, `... validate mcp`, `... validate inference`, `... validate observability`, plus `helm lint`, `skaffold diagnose`, and `skaffold render`.
- The basic outer-container cluster workflow is now verified on this machine. Persistence-backed Helm releases remain a non-default local workflow, and the shipped `values-kind.yaml` keeps MinIO and Pulsar persistence disabled, so `cluster storage reconcile` is currently a no-op under the default local values.

## Contribution Guidance
The repo treats documentation, architecture notes, and tests as first-class artifacts. Follow the suite index at [documents/README.md](/Users/matthewnowak/studioMCP/documents/README.md) and the documentation rules at [documents/documentation_standards.md](/Users/matthewnowak/studioMCP/documents/documentation_standards.md). LLM agents may edit files and run local validation, but commits and pushes are reserved for the human user. See [AGENTS.md](/Users/matthewnowak/studioMCP/AGENTS.md) and [CLAUDE.md](/Users/matthewnowak/studioMCP/CLAUDE.md).

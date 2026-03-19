# studioMCP Development Plan

## Purpose
This document is the working implementation plan for `studioMCP`. It is written to be consumed by CLI-based coding agents and human contributors together.

The goal is to build a serious Haskell-first MCP server for pure DAG-based audio, image, and video workflows. The repository must grow in deliberate, testable phases. Each phase must leave the codebase in a state that builds, is documented coherently, and can be understood by a new contributor without oral context.

## Implementation Checklist

- [x] Phase 0 foundation files, Docker skeleton, governed `documents/` suite, and test harness scripts
- [x] Phase 1 Haskell scaffold with executable entrypoints and separated unit/integration suites
- [x] Phase 2 initial `Result`, `Failure`, `Summary`, DAG, timeout, and memoization types
- [x] Phase 3 YAML DAG parsing, validation, example DAGs, and canonical DAG format documentation
- [ ] Phase 4 real Pulsar publish and consume integration
- [ ] Phase 5 real MinIO object persistence and manifest integration
- [ ] Phase 6 boundary execution engine and timeout-enforced tool adapters
- [ ] Phase 7 first end-to-end DAG execution
- [ ] Phase 8 MCP server surface
- [ ] Phase 9 inference mode integration
- [ ] Phase 10 expanded FOOS documentation suite
- [ ] Phase 11 observability and metrics
- [ ] Phase 12 parallel scheduling and optimization design

## Current Validation State

- `cabal build all` passes.
- `cabal test unit-tests` passes.
- `cabal run studiomcp -- validate-dag examples/dags/transcode-basic.yaml` passes.
- `./scripts/integration-harness.sh reset` boots live Pulsar and MinIO sidecars successfully.
- `STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests` passes against the live sidecars.
- `./scripts/helm_template.sh kind` renders successfully.
- `helm lint chart -f chart/values.yaml -f chart/values-kind.yaml` passes.
- `skaffold diagnose --yaml-only --profile kind` passes.
- `skaffold render --offline --profile kind --digest-source=tag` passes.

## Core Product Intent
`studioMCP` is a single MCP server that accepts only pure DAG execution requests expressed in a railway-oriented style.

- Every pure effect node returns `Result T F`.
- On success, `T` is memoized.
- The interpreter assumes failure after a fixed timeout.
- Timeout returns a structured failure value, not an implicit crash.
- Failure paths are explicit and graceful.
- The server always returns a clean immutable `Summary` explaining what ran, what failed, what was memoized, and why the run reached its terminal state.

The system is meant to replace large parts of traditional DAW, NLE, image-editing, and transcoding workflows by orchestrating free/open-source tools locally behind a rigorous pure execution model.

There are two top-level operating modes:

1. `server`
   - Runs the MCP server and orchestration stack.
   - Accepts DAG requests.
   - Coordinates tool execution, memoization, state transitions, artifact persistence, and summaries.
2. `inference`
   - Runs a reference local LLM for planning, graph generation, graph repair suggestions, documentation indexing, tool-selection help, and operator UX.
   - Is supportive, not authoritative over purity rules.
   - Must not bypass the typed DAG contract.

## Non-Negotiable Architectural Constraints

### DAG Purity Contract
Every executable node in the DAG is one of:

- `PureNode`
  - Deterministic interface.
  - Returns `Result T F`.
  - Success payload `T` is memoizable.
  - Failure payload `F` is structured and user-presentable.
- `BoundaryNode`
  - Wraps impure tool invocation.
  - Presents a pure typed boundary to the graph interpreter.
  - Enforces timeout, input normalization, output capture, and failure projection into `F`.
- `SummaryNode`
  - Derives the final immutable `Summary`.
  - Contains execution lineage, cache hits, failure reasons, output references, and state transitions.

### Timeout Rule
Every node execution must be governed by a fixed timeout policy. If the tool does not complete in time:

- The interpreter treats that node as failed.
- It returns a structured failure result.
- Downstream graph handling continues according to explicit failure-aware DAG semantics.
- The final `Summary` distinguishes timeout from semantic tool failure.

### Storage Split
Be precise in docs and code:

- Pulsar is for DAG execution data in flight.
  - Queueing.
  - State transitions.
  - Event sourcing for execution progress.
  - Retry and replay coordination.
  - Single source of truth for in-flight execution state.
- MinIO is for persistent immutable key-value storage.
  - Memoized node outputs.
  - Immutable intermediate assets.
  - Durable studio works.
  - Final rendered artifacts.
  - Persistent summaries and manifests.

Do not blur these roles.

### One Dockerfile
The repository must use exactly one `Dockerfile`, under `docker/`, based on Ubuntu 24.04. It must be multi-stage and expose a `production` target consumed by Kubernetes tooling. It may include optional CUDA hooks or stages, but there must still be one Dockerfile artifact in the repo.

### Kubernetes Deployment Source of Truth
The repository is Kubernetes-forward.

- Helm under `chart/` is the source of truth for service topology and deployment semantics.
- Skaffold under `skaffold.yaml` is the local development orchestrator.
- kind under `kind/kind_config.yaml` is the default local cluster target.
- Docker Compose exists only for the sidecar-backed integration harness.
- Compose must not become the canonical expression of application deployment topology.

### Haskell-First Ownership
The orchestration core, DAG model, purity model, summary model, timeout model, and memoization semantics must be implemented in Haskell. Python and other ecosystems are allowed for tool adapters, wrappers, and model-serving boundaries, but Haskell owns:

- Graph model.
- Execution semantics.
- Error algebra.
- Summary algebra.
- Cache addressability contract.
- Storage service contract.
- MCP surface.

## Repository Operating Policy

### Human-Only Git Actions
LLMs working in this repository must not create git commits and must not push to remotes. Git commits and pushes are reserved for the human user only.

Allowed:

- Creating and editing files.
- Running local builds and tests.
- Initializing a local repository and wiring remotes when explicitly requested by the human user.

Not allowed:

- `git commit`
- `git merge`
- `git rebase`
- `git push`
- Any automated background push or sync

### Phase Build Gate
The implementation must proceed in order. Before moving from one phase to the next:

1. Update docs and configuration so they match the code.
2. Run `cabal build all`.
3. Run the relevant tests for that phase.
4. Stop and fix build or test failures before continuing.

Practical note: Phase 0 is allowed to finish without a Haskell build only until the Phase 1 scaffold exists. From Phase 1 onward, every phase gate requires a successful `cabal build all`.

## Testing Strategy

### Unit Tests
Unit tests must be pure Haskell tests. They must mock or substitute all side effects.

- No live Pulsar access.
- No live MinIO access.
- No external process execution.
- No network dependency.
- Use pure test doubles, in-memory interpreters, and deterministic fixtures.

The unit suite is the place to validate:

- Railway semantics.
- Timeout-to-failure projection.
- DAG validation.
- Summary construction.
- Memoization-key derivation.
- Failure propagation.

### Integration Tests
Integration tests must exercise real boundaries.

- They may call real sidecar services.
- They may call external adapters through the foreign boundary mechanism used by production code.
- They must verify Haskell code against real process, HTTP, and service behavior where relevant.

Integration tests are expected to cover at least:

- Pulsar connectivity and event flow.
- MinIO object creation and retrieval.
- Boundary execution against sidecar or tool processes.
- Full end-to-end DAG execution once later phases exist.

### Stateful Test Harness
Pulsar and MinIO are stateful. Integration tests therefore require a reproducible harness that may wipe or reseed state at any time.

The harness must:

- Start the required sidecars deterministically.
- Wait for service readiness explicitly.
- Recreate required buckets, topics, tenants, namespaces, or equivalent state.
- Seed example data when needed.
- Be allowed to wipe test data and volumes between runs.
- Be safe to run repeatedly in local development and CI.

The harness is not optional. It is part of the project.

## Documentation Governance

The repository uses `documents/`, not `docs/`, for the governed documentation suite.

Hard rules:

- `documents/documentation_standards.md` is the documentation SSoT.
- `documents/README.md` is the navigation index for the suite.
- Each concept has exactly one canonical document.
- Markdown files in `documents/` use snake_case filenames.
- Every document in `documents/` carries explicit metadata headers.
- Mermaid diagrams must follow the compatibility-safe subset defined in the documentation standards.
- `documents/engineering/` is the home for engineering standards, beginning with `k8s_native_dev_policy.md`.

## Repository Outcome Target
By the end of the planned phases, the repo should contain:

- A strong `README.md`.
- `STUDIOMCP_DEVELOPMENT_PLAN.md`.
- `.gitignore`.
- `.dockerignore`.
- `docker/` with the single Dockerfile and harness-only compose stack.
- `chart/` with the canonical Helm deployment model.
- `skaffold.yaml` for the local dev loop.
- `kind/` for the local cluster configuration.
- A Haskell source tree.
- Separate unit and integration test suites.
- A governed `documents/` suite with standards, index, architecture, development, domain, tools, engineering, operations, reference, and ADR categories.
- Example DAGs and reproducible fixtures.
- Local dev and test harness scripts.

## Proposed Repository Structure
The structure should grow toward this shape over time:

```text
studioMCP/
├── README.md
├── AGENTS.md
├── CLAUDE.md
├── LICENSE
├── .gitignore
├── .dockerignore
├── cabal.project
├── studioMCP.cabal
├── skaffold.yaml
├── Makefile
├── STUDIOMCP_DEVELOPMENT_PLAN.md
├── chart/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-kind.yaml
│   ├── values-prod.yaml
│   └── templates/
├── kind/
│   └── kind_config.yaml
├── docker/
│   ├── Dockerfile
│   ├── docker-compose.yaml
│   ├── entrypoints/
│   └── scripts/
├── app/
├── src/
├── test/
├── examples/
├── documents/
│   ├── README.md
│   ├── documentation_standards.md
│   ├── architecture/
│   ├── development/
│   ├── domain/
│   ├── engineering/
│   ├── operations/
│   ├── reference/
│   ├── tools/
│   └── adr/
└── scripts/
```

## Multi-Phase Development Plan
Each phase must end with code, docs, and configuration that actually match.

### Phase 0: Repository Foundation and Bootstrapping
Status: Completed

Objective: establish project identity, Kubernetes-forward repository structure, baseline docs, and the integration-harness direction.

Completed steps:

- Root repo policy files, README, ignore files, and plan exist.
- The single Dockerfile exists and now exposes a multi-stage `production` target.
- Helm chart, kind config, and Skaffold config exist as the Kubernetes-native repo foundation.
- Compose is present but explicitly scoped to the integration harness.
- The governed `documents/` suite exists with standards and index.

Outstanding steps:

- None for the Phase 0 gate.

Completion criteria:

- Root docs clearly explain server mode, inference mode, and the Kubernetes-forward repository stance.
- Helm is the deployment source of truth and Compose is documented as harness-only.
- The test harness approach is documented.
- The documentation suite follows `documents/` naming, SSoT rules, and metadata conventions.

### Phase 1: Haskell Project Scaffold and Compile-able Skeleton
Status: Completed

Objective: create a compile-able Haskell project with the intended namespace layout and separate unit/integration test suites.

Completed steps:

- Cabal project metadata exists.
- `app/`, `src/`, and `test/` trees exist.
- Placeholder modules compile.
- `Main.hs`, `ServerMain.hs`, `InferenceMain.hs`, and `WorkerMain.hs` exist.
- `unit-tests` and `integration-tests` suites exist.

Outstanding steps:

- None for the Phase 1 gate.

Completion criteria:

- `cabal build all` succeeds.
- `cabal test unit-tests` passes.
- Module layout matches repo docs.
- Entry points for server, inference, and worker exist.

### Phase 2: Formalize the Type System and Railway Semantics
Status: Completed

Objective: define the core domain model in Haskell.

Completed steps:

- `Result T F` is implemented.
- Failure and summary types are implemented.
- DAG, timeout, and memoization primitives are implemented.
- Unit tests cover railway semantics and timeout failure projection.

Outstanding steps:

- None for the Phase 2 gate.

Completion criteria:

- Types are documented in code and docs.
- Unit tests cover timeout and failure propagation basics.
- The DAG validator can reject malformed graphs.
- `Summary` can represent both successful and failed runs.
- `cabal build all` succeeds before Phase 3 begins.

### Phase 3: Validation, Parsing, and Example DAG Ingestion
Status: Completed

Objective: load, parse, validate, and summarize example DAG definitions.

Completed steps:

- YAML DAG parsing is implemented.
- DAG validation rules are implemented.
- Example DAGs exist under `examples/dags/`.
- `documents/domain/dag_specification.md` documents the current schema.
- The CLI validation path works for example DAGs.

Outstanding steps:

- None for the Phase 3 gate.

Completion criteria:

- Example DAGs parse successfully.
- Invalid graphs fail with useful messages.
- Docs explain the graph format.
- The unit suite covers success and failure examples.
- `cabal build all` succeeds before Phase 4 begins.

### Phase 4: Messaging and Execution State with Pulsar
Status: In progress

Objective: introduce in-flight execution state via Pulsar.

Completed steps:

- The integration harness boots a real Pulsar sidecar.
- Helm models a Pulsar deployment and service.
- Live integration health checks reach the Pulsar admin endpoint.

Outstanding steps:

- Implement the real Haskell Pulsar integration layer.
- Flesh out execution event types and topic naming.
- Connect execution-state transitions to real publish and consume behavior.
- Upgrade integration tests from reachability to lifecycle semantics.

Completion criteria:

- The local harness environment boots with Pulsar.
- Haskell code can publish and consume basic events.
- Integration tests cover a trivial run lifecycle against the real harness.
- Docs state clearly that Pulsar is not object storage.

### Phase 5: Persistent Immutable Memoization and Studio Storage with MinIO
Status: In progress

Objective: introduce content-addressed immutable storage for node results and durable studio assets.

Completed steps:

- The integration harness boots a real MinIO sidecar and seeds buckets.
- Helm models MinIO deployment, service, and bucket bootstrap job.
- Live integration health checks reach MinIO successfully.

Outstanding steps:

- Implement the real Haskell MinIO integration layer.
- Add content-addressed object naming and manifest persistence.
- Connect memoization writes and reads to Haskell execution paths.
- Upgrade integration tests from reachability to object round-trip assertions.

Completion criteria:

- Successful node outputs can be written and read by key.
- Memoization API is covered by pure unit tests.
- Integration tests validate real MinIO writes and reads.
- Docs clearly separate MinIO from Pulsar.

### Phase 6: Boundary Execution Engine and Timeout Enforcement
Status: Planned

Objective: run external tools through pure Haskell boundaries with timeout and structured failure capture.

Completed steps:

- None yet.

Outstanding steps:

- Implement the generic boundary execution layer.
- Add timeout enforcement and stdout/stderr capture.
- Add first real tool adapters such as FFmpeg, SoX, ImageMagick, or a Python boundary.
- Expand integration tests to cover real process boundaries.

Completion criteria:

- At least three tool adapters execute through the common boundary layer.
- Timeout failure paths are real and tested.
- Integration tests exercise real process boundaries.
- Successful node execution can emit Pulsar events and MinIO outputs.

### Phase 7: First End-to-End DAG Execution Path
Status: Planned

Objective: run one complete example DAG from submission through summary.

Completed steps:

- None yet.

Outstanding steps:

- Connect parser, validator, executor, Pulsar, MinIO, and tool adapters.
- Emit and persist final summaries.
- Add smoke coverage for success and failure DAGs.

Completion criteria:

- Parser, validator, executor, Pulsar, MinIO, and tool adapters are connected.
- A successful example DAG runs locally end to end.
- A failing DAG also yields a clean final summary.
- Smoke tests cover both outcomes.

### Phase 8: MCP Server Surface
Status: Planned

Objective: expose DAG submission and result retrieval through an MCP-facing Haskell server.

Completed steps:

- None yet.

Outstanding steps:

- Build the actual MCP-facing submission and retrieval surface.
- Add dependency-aware health endpoints.
- Keep the validator authoritative at the server boundary.

Completion criteria:

- Server mode starts successfully.
- A client can submit a DAG and fetch a summary.
- Invalid DAGs are rejected before execution.
- Health endpoints reflect dependency state.

### Phase 9: Inference Mode with a Reference LLM
Status: Planned

Objective: add an optional local reference-LLM path for planning and assistive workflows.

Completed steps:

- Skeleton inference entrypoints and placeholder modules exist.

Outstanding steps:

- Integrate a real local model host.
- Add prompts and guardrails.
- Wire inference workflows without weakening execution authority.

Completion criteria:

- The reference LLM can be started locally or via compose.
- Prompts and guardrails are documented.
- Inference suggestions are advisory.
- Typed DAG execution remains authoritative.

### Phase 10: FOOS Documentation Suite
Status: In progress

Objective: expand the governed FOOS documentation suite relevant to `studioMCP`.

Completed steps:

- Documentation standards and index exist.
- Architecture docs, local dev docs, testing strategy, DAG specification, and the Kubernetes-native development policy exist.
- Initial FFmpeg, MinIO, and Pulsar docs exist.

Outstanding steps:

- Expand tool coverage across audio, video, image, AI, and infrastructure tooling.
- Add ADRs and deeper domain-specific docs as implementation grows.
- Keep the suite aligned with new repo mechanics and Haskell execution semantics.

Completion criteria:

- `documents/tools/` is rich, structured, and useful.
- A contributor can distinguish core versus optional tools.
- Tool docs connect back to the DAG model.
- The README links clearly into the `documents/` suite.
- New docs follow the documentation SSoT, metadata rules, and Mermaid constraints.

### Phase 11: Observability, Metrics, and Operability
Status: Planned

Objective: make the system debuggable and production-minded.

Completed steps:

- None yet.

Outstanding steps:

- Add structured logging and metrics.
- Add correlation identifiers.
- Add operational docs and debugging workflows.

Completion criteria:

- Logs include stable run and node identifiers.
- Metrics are exposed.
- Operational docs explain how to debug tool failures, timeouts, memoization misses, Pulsar lag, and MinIO write failures.

### Phase 12: Parallel Execution, Optimization, and Zero-Copy Planning
Status: Planned

Objective: prepare for scale and performance improvements without breaking semantics.

Completed steps:

- None yet.

Outstanding steps:

- Design deterministic parallel scheduling.
- Document zero-copy and reduced-copy plans.
- Preserve purity and summary semantics while optimizing execution.

Completion criteria:

- Parallel scheduling strategy is documented.
- Zero-copy and reduced-copy design notes exist.
- No optimization shortcuts violate the purity contract.

## README Requirements
The README must include these top-level sections and keep them accurate over time:

1. Project vision
2. Why this could replace large parts of DAW, photo, and video toolchains
3. Why Haskell is a fit
4. Pure DAG execution model
5. Railway-oriented result handling
6. Timeout semantics
7. Memoization semantics
8. Pulsar vs MinIO
9. Repository architecture
10. Documentation suite
11. Server mode
12. Inference mode
13. Docker strategy
14. Kubernetes-native development
15. FOOS ecosystem survey
16. Development roadmap
17. Status / current maturity
18. Contribution guidance

## Kubernetes and Harness Requirements

Kubernetes-facing artifacts must include at least:

- `chart/`
- `skaffold.yaml`
- `kind/kind_config.yaml`

Rules:

- Helm is the deployment source of truth.
- Skaffold drives the local Kubernetes dev loop.
- kind is the default local cluster target.
- Docker Compose is retained only for the sidecar-backed integration harness.

`docker/docker-compose.yaml` must still define at least:

- `studiomcp`
- `pulsar`
- `minio`
- `minio-init`

Optional later services:

- `llm-reference`
- `pulsar-init`
- `prometheus`
- `grafana`

Service intent:

- `studiomcp`: main Haskell service image, consumable via Helm and Skaffold, able to run server or inference mode.
- `pulsar`: broker for DAG execution state in flight.
- `minio`: immutable object storage for memoization and studio assets.
- `minio-init`: bucket/bootstrap helper for MinIO.
- `llm-reference`: optional local model service for inference mode.

## Documentation Requirements
Treat `documents/` as first-class code.

Required categories:

- architecture
- development
- domain
- engineering
- operations
- reference
- tools
- ADRs

Required governance documents:

- `documents/README.md`
- `documents/documentation_standards.md`

Create these early:

- `documents/architecture/overview.md`
- `documents/architecture/pulsar_vs_minio.md`
- `documents/architecture/server_mode.md`
- `documents/architecture/inference_mode.md`
- `documents/development/local_dev.md`
- `documents/development/testing_strategy.md`
- `documents/domain/dag_specification.md`
- `documents/engineering/k8s_native_dev_policy.md`
- `documents/tools/ffmpeg.md`
- `documents/tools/minio.md`
- `documents/tools/pulsar.md`
- `documents/engineering/` as the home for engineering standards

## Coding Guidance

### General
- Prefer clarity over premature cleverness.
- Keep types explicit.
- Keep docs close to code.
- Avoid hidden global state.
- Do not introduce impure shortcuts around the DAG interpreter.
- Keep adapter boundaries thin and typed.
- Prefer immutable manifests and content-addressed references.

### Haskell
- Keep domain types in dedicated modules.
- Separate protocol from execution logic.
- Avoid monolith modules.
- Prefer small composable functions.
- Use explicit newtypes for ids and keys.

### Python and Other Adapters
- Python is an adapter ecosystem, not the source of truth.
- Adapters must produce normalized typed outputs.
- Error text must be captured and projected into Haskell failure types.
- Adapter version changes must influence memoization keys when behavior changes.

### Documentation
- Treat `documents/documentation_standards.md` as the SSoT for documentation rules.
- Keep `documents/` in snake_case, except for allowed `README.md`.
- Each topic gets one canonical document; other docs link to it.
- Keep `documents/engineering/k8s_native_dev_policy.md` authoritative for Kubernetes-forward repo mechanics.
- When adding a new tool adapter, add or update the corresponding tool doc.
- When changing architecture, create or update an ADR.
- Keep the README accurate, not aspirational fiction.

## Definition of Done
The repository is in a meaningful initial state when all of the following are true:

- Root docs are strong and coherent.
- Docker build setup is understandable and runnable.
- Helm, kind, and Skaffold artifacts express the repo's deployment model coherently.
- The Haskell project compiles.
- At least one example DAG runs end to end.
- Timeouts are enforced.
- Failures are summarized cleanly.
- Pulsar tracks in-flight execution.
- MinIO stores immutable memoized results.
- The README explains server mode and inference mode.
- The `documents/` suite explains relevant FOOS tools and follows its own governance rules.

## Final Instruction
Build this repo as a serious, ambitious, but disciplined system. Do not treat it as a toy MCP wrapper.

The heart of the project is:

- a typed Haskell execution core
- pure DAG semantics
- explicit failure handling
- timeout-first robustness
- immutable memoization
- clean summaries
- leveraging open-source media tools rather than reimplementing them

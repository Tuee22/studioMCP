# studioMCP Development Plan

## Purpose
This document is the working implementation plan for `studioMCP`. It is meant to be used by human contributors and CLI-based coding agents as a delivery contract, not just as a vision statement.

The goal is to build a serious Haskell-first MCP server for pure DAG-based audio, image, and video workflows. The repository must grow in deliberate, testable phases. Each phase must leave the repo in a state that builds, is documented coherently, and can be understood by a new contributor without oral context.

## How to Use This Plan

- This document is the live progress tracker for the repository. Update it as implementation progresses.
- Treat each phase as a sprint-sized deliverable. If a phase grows beyond what one contributor can plausibly finish in one sprint, split it before implementation starts.
- A phase is not complete because files exist. A phase is complete only when its required behavior exists, its tests exist, its docs are updated, and its exact exit commands pass.
- Scaffolds are allowed only in scaffold phases. A `skeleton`, `placeholder`, or `to be implemented later` file does not count as delivered behavior.
- Every phase must name:
  - what it delivers
  - what is explicitly out of scope
  - what tests are required
  - what commands must pass before the phase can be marked complete
- Subjective language such as `useful`, `clean`, or `rich` must be backed by specific artifacts or testable expectations.

### Progress Tracking Rules

- Update the phase status, implementation checklist, and current repo assessment whenever a phase meaningfully advances or is completed.
- Do not mark a phase complete until its required coverage exists and all exit commands pass.
- If a phase is only partially implemented, leave it `In progress` and record the missing work in the phase body or current repo assessment.
- When a new native CLI validation command becomes part of the required gate for a phase, add it to this document in the same change.
- Keep `Current Validation State` aligned with checks that are actually known to pass in the repo now, not checks that are merely intended to pass later.

## Current Repo Assessment Against This Plan

This section records the current repo state as measured against the stricter phase gates below.

- Phase 0 is complete.
- Phase 1 is complete.
- Phase 2 is complete.
- Phase 3 is complete.
- Phase 4 is complete. The multi-stage Dockerfile, `studiomcp-env` Compose service, and first native cluster-management CLI commands now exist, and the built outer container has been verified on this machine for `cluster up`, `cluster status`, `validate cluster`, and `validate docs`.
- Phase 5 is complete. Messaging event contracts, topic naming rules, JSON round-trip coverage, and pure execution-state transitions are implemented and covered by dedicated unit tests. A real Pulsar adapter remains deferred to Phase 6.
- Phase 6 is complete. The Haskell Pulsar wrapper now publishes and consumes real execution events through the deployed Pulsar sidecar, `studiomcp validate pulsar` exercises the live lifecycle plus an invalid-namespace failure path, and the integration suite drives that path through the outer-container CLI workflow.
- Phase 7 is complete. Deterministic content-address derivation, typed memo and summary refs, manifest JSON contracts, and dedicated storage unit tests now exist.
- Phase 8 is complete. The Haskell MinIO wrapper now round-trips memo objects, manifests, and summaries through the deployed MinIO sidecar, exposes `studiomcp validate minio`, and the integration suite drives that path through the outer-container CLI workflow.
- Phase 9 is complete. The boundary runtime now executes deterministic helper processes with stdout and stderr capture, non-zero exit projection, enforced timeout failure mapping, and `studiomcp validate boundary` exercises that contract through the outer-container CLI workflow.
- Phase 10 is complete. The first real FFmpeg adapter now runs on top of the boundary runtime, seeds a deterministic WAV fixture under `examples/assets/audio/`, validates one successful transcode, and asserts structured failure output for a missing input.
- Phase 11 is complete. The sequential executor now runs DAGs in topological order, projects upstream failures into explicit skipped-node failures, and assembles in-memory summaries with dedicated unit coverage plus a native executor validation command.
- Phase 12 is complete. The runtime now persists summaries and manifests to MinIO, publishes lifecycle events to Pulsar, and validates one successful DAG run plus one failing DAG run end to end through the native CLI and integration suite.
- Phase 13 is complete. The server now exposes the real HTTP control surface on port `3000`, validates DAG submissions, returns running run identifiers, retrieves persisted summaries, and is covered by protocol-level validation plus unit coverage for the MCP protocol contracts.
- Phase 14 is complete. Inference mode now exposes a real advisory HTTP surface with prompt rendering, guardrails, reference-model integration, unavailable-host failure behavior, and dedicated unit plus validation coverage.
- Phase 15 is complete. The running server now emits structured run and node correlation logs, exposes stable Prometheus metrics, degrades `/healthz` when dependencies fail, and is covered by dedicated unit tests plus the live observability validation command.
- Phase 16 is complete.
- Phase 17 is complete. The repo now includes an explicit parallel scheduling design note and ADR that record scheduling guarantees, failure semantics, optimization boundaries, and non-goals without overstating delivered parallel execution code.
- The standalone `worker` executable path is now real as well. It exposes a direct execution HTTP surface on port `3002`, validates DAGs before execution, returns persisted summary plus manifest references synchronously, and is covered by `studiomcp validate worker` through the outer-container workflow.

## Implementation Checklist

This checklist tracks completed phases only. Use the current repo assessment and per-phase `Status` lines to track partial progress.

- [x] Phase 0 repository foundation, policy files, Kubernetes-forward scaffolding, and documentation governance
- [x] Phase 1 buildable Haskell scaffold with executable entrypoints and separated test suites
- [x] Phase 2 core `Result`, failure, summary, timeout, memoization, and provenance model hardened with unit tests
- [x] Phase 3 DAG schema, parser, validator, and automated fixture coverage
- [x] Phase 4 containerized development environment, kind lifecycle, and deployment-validation baseline
- [x] Phase 5 messaging contracts and pure execution-state model
- [x] Phase 6 real Pulsar adapter and lifecycle integration tests
- [x] Phase 7 storage contracts, content addressing, and manifest model
- [x] Phase 8 real MinIO adapter and memoization integration tests
- [x] Phase 9 boundary runtime and timeout projection
- [x] Phase 10 first production tool adapter and deterministic media fixtures
- [x] Phase 11 sequential DAG executor and in-memory summary assembly
- [x] Phase 12 summary persistence and first end-to-end DAG success and failure runs
- [x] Phase 13 MCP server transport, handlers, and protocol-level tests
- [x] Phase 14 inference advisory mode with guardrails and local model host integration
- [x] Phase 15 observability, metrics, and operational debugging surface
- [x] Phase 16 complete governed documentation suite, runbooks, and ADRs
- [x] Phase 17 parallel scheduling and optimization design package

## Current Validation State

These checks currently pass in the repo and form the current validation contract:

- `cabal build all`
- `cabal test unit-tests`
- `rg -n 'Messaging\.(ExecutionStateSpec|EventsSpec|TopicsSpec)' studioMCP.cabal`
- `rg -n 'Messaging\.(ExecutionStateSpec|EventsSpec|TopicsSpec)\.spec' test/Spec.hs`
- `rg -n 'Storage\.(ContentAddressedSpec|ManifestsSpec|KeysSpec)' studioMCP.cabal`
- `rg -n 'Storage\.(ContentAddressedSpec|ManifestsSpec|KeysSpec)\.spec' test/Spec.hs`
- `rg -n 'Storage\.MinIOSpec' studioMCP.cabal`
- `rg -n 'Storage\.MinIOSpec\.spec' test/Spec.hs`
- `rg -n 'Tools\.BoundarySpec' studioMCP.cabal`
- `rg -n 'Tools\.BoundarySpec\.spec' test/Spec.hs`
- `rg -n 'DAG\.ExecutorSpec' studioMCP.cabal`
- `rg -n 'DAG\.ExecutorSpec\.spec' test/Spec.hs`
- `rg -n 'MCP\.ProtocolSpec' studioMCP.cabal`
- `rg -n 'MCP\.ProtocolSpec\.spec' test/Spec.hs`
- `rg -n 'Inference\.(GuardrailsSpec|PromptsSpec)' studioMCP.cabal`
- `rg -n 'Inference\.(GuardrailsSpec|PromptsSpec)\.spec' test/Spec.hs`
- `rg -n 'API\.(HealthSpec|MetricsSpec)' studioMCP.cabal`
- `rg -n 'API\.(HealthSpec|MetricsSpec)\.spec' test/Spec.hs`
- `rg -n 'Worker\.ProtocolSpec' studioMCP.cabal`
- `rg -n 'Worker\.ProtocolSpec\.spec' test/Spec.hs`
- `cabal run studiomcp -- validate-dag examples/dags/transcode-basic.yaml`
- `cabal run studiomcp -- dag validate-fixtures`
- `cabal run studiomcp -- validate docs`
- `cabal run studiomcp -- validate boundary`
- `docker compose -f docker/docker-compose.yaml config`
- `docker compose -f docker/docker-compose.yaml build studiomcp-env`
- `docker compose -f docker/docker-compose.yaml up -d studiomcp-env`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp cluster up`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp cluster status`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp cluster deploy sidecars`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp dag validate-fixtures`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate cluster`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate docs`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate pulsar`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate minio`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate boundary`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate ffmpeg-adapter`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate executor`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate e2e`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate worker`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate mcp`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate inference`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate observability`
- `STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests`
- `helm lint chart -f chart/values.yaml -f chart/values-kind.yaml`
- `skaffold diagnose --yaml-only --profile kind`
- `skaffold render --offline --profile kind --digest-source=tag`
- `rg -n '^## Scheduling Guarantees$' documents/architecture/parallel_scheduling.md`
- `rg -n '^## Failure Semantics$' documents/architecture/parallel_scheduling.md`
- `rg -n '^## Tradeoffs$' documents/adr/0002_parallel_scheduling.md`

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
   - runs the MCP server and orchestration stack
   - accepts DAG requests
   - coordinates tool execution, memoization, state transitions, artifact persistence, and summaries
2. `inference`
   - runs a reference local LLM for planning, graph generation, graph repair suggestions, documentation indexing, tool-selection help, and operator UX
   - is supportive, not authoritative over purity rules
   - must not bypass the typed DAG contract

## Non-Negotiable Architectural Constraints

### DAG Purity Contract
Every executable node in the DAG is one of:

- `PureNode`
  - deterministic interface
  - returns `Result T F`
  - success payload `T` is memoizable
  - failure payload `F` is structured and user-presentable
- `BoundaryNode`
  - wraps impure tool invocation
  - presents a pure typed boundary to the graph interpreter
  - enforces timeout, input normalization, output capture, and failure projection into `F`
- `SummaryNode`
  - derives the final immutable `Summary`
  - contains execution lineage, cache hits, failure reasons, output references, and state transitions

### Timeout Rule
Every node execution must be governed by a fixed timeout policy. If the tool does not complete in time:

- the interpreter treats that node as failed
- it returns a structured failure result
- downstream graph handling continues according to explicit failure-aware DAG semantics
- the final `Summary` distinguishes timeout from semantic tool failure

### Storage Split
Be precise in docs and code:

- Pulsar is for DAG execution data in flight
  - queueing
  - state transitions
  - event sourcing for execution progress
  - retry and replay coordination
  - single source of truth for in-flight execution state
- MinIO is for persistent immutable key-value storage
  - memoized node outputs
  - immutable intermediate assets
  - durable studio works
  - final rendered artifacts
  - persistent summaries and manifests

Do not blur these roles.

### Storage Deployment Policy
MinIO and Pulsar should be deployed using their official Helm charts in HA mode where possible. The canonical deployment policy including null storage class requirements, rehydratable PV lifecycle, and CLI-owned storage reconciliation is documented in [documents/engineering/k8s_storage.md](documents/engineering/k8s_storage.md).

### One Dockerfile
The repository must use exactly one `Dockerfile`, under `docker/`, based on Ubuntu 24.04. It must be multi-stage and expose a `production` target consumed by Kubernetes tooling.

### Kubernetes Deployment Source of Truth
The repository is Kubernetes-forward.

- Helm under `chart/` is the source of truth for service topology and deployment semantics.
- Skaffold under `skaffold.yaml` is the local development orchestrator.
- kind under `kind/kind_config.yaml` is the default local cluster target.
- Docker Compose exists to launch the outer development container against the active Docker context.
- Compose must not become the canonical expression of application deployment topology.
- Local cluster lifecycle actions must flow through the Haskell CLI, not checked-in shell helpers.

### Haskell-First Ownership
The orchestration core, DAG model, purity model, summary model, timeout model, and memoization semantics must be implemented in Haskell. Python and other ecosystems are allowed for tool adapters, wrappers, and model-serving boundaries, but Haskell owns:

- graph model
- execution semantics
- error algebra
- summary algebra
- cache addressability contract
- storage service contract
- MCP surface

### No Placeholder Completion Claims
Do not mark a phase complete if any changed behavior is still represented only by:

- `placeholder`
- `skeleton`
- `stub`
- `future work`
- `later`
- `TODO`
- `TBD`

The only exception is a scaffold phase whose stated objective is compilation structure rather than runtime behavior.

## Repository Operating Policy

### Human-Only Git Actions
LLMs working in this repository must not create git commits and must not push to remotes. Git commits and pushes are reserved for the human user only.

Allowed:

- creating and editing files
- running local builds and tests
- initializing a local repository and wiring remotes when explicitly requested by the human user

Not allowed:

- `git commit`
- `git merge`
- `git rebase`
- `git push`
- any automated background push or sync

### Delivery Sequencing Rule
The implementation must proceed in order. Before moving from one phase to the next:

1. Update docs and configuration so they match the code.
2. Run the exact exit commands for the current phase.
3. Stop and fix any failure before continuing.
4. Update this document so status and evidence match reality.

## Phase Build Gate

From Phase 1 onward, every phase requires a successful Haskell build:

```bash
cabal build all
```

In addition:

- every phase that changes pure logic must add or update unit tests
- every phase that changes service or process boundaries must add or update integration tests
- every phase that changes user-facing behavior must add at least one negative-path check
- every repeated multi-step validation path should be exposed through a native `studiomcp` CLI command
- exit gates must prove the relevant tests are wired into a Cabal test suite and exercised by that suite; spec-file existence alone does not count
- any native validation command that touches long-lived processes must own startup, readiness checks, assertions, and cleanup itself

Required native validation commands to add as the project matures:

- `studiomcp dag validate-fixtures`
- `studiomcp validate pulsar`
- `studiomcp validate minio`
- `studiomcp validate boundary`
- `studiomcp validate executor`
- `studiomcp validate e2e`
- `studiomcp validate worker`
- `studiomcp validate mcp`
- `studiomcp validate inference`
- `studiomcp validate observability`
- `studiomcp validate docs`

## Testing Strategy

### Unit Tests
Unit tests must be pure Haskell tests. They must mock or substitute all side effects.

- no live Pulsar access
- no live MinIO access
- no external process execution unless a phase explicitly defines a deterministic local helper process as a test fixture
- no network dependency
- use pure test doubles, in-memory interpreters, and deterministic fixtures

The unit suite is the place to validate:

- railway semantics
- timeout-to-failure projection
- DAG validation
- summary construction
- memoization-key derivation
- failure propagation
- execution-state transitions
- storage-key and manifest derivation

### Integration Tests
Integration tests must exercise real boundaries.

- they may call real sidecar services
- they may call external adapters through the foreign boundary mechanism used by production code
- they must verify Haskell code against real process, HTTP, and service behavior where relevant

Integration tests are expected to cover at least:

- Pulsar connectivity and event flow
- MinIO object creation and retrieval
- boundary execution against deterministic helper processes and later real tools
- full end-to-end DAG execution
- MCP protocol behavior once the server surface exists

### Stateful Cluster Environment
Pulsar, MinIO, and any persistent local workloads are stateful. Integration tests therefore require a reproducible native CLI workflow that may wipe or reseed cluster state when appropriate.

That workflow must:

- start the outer development container deterministically
- ensure kind is running against the selected Docker context
- recreate required buckets, topics, tenants, namespaces, or equivalent state
- seed example data when needed
- manage explicit PV lifecycle through the Haskell CLI when persistence is enabled
- be safe to run repeatedly in local development and CI

The workflow is not optional. It is part of the project.

## Documentation Governance

The repository uses `documents/`, not `docs/`, for the governed documentation suite.

This section is a delivery summary only. [documents/documentation_standards.md](/Users/matthewnowak/studioMCP/documents/documentation_standards.md) is the Single Source of Truth for actual documentation standards. If this plan and the standards document ever disagree on documentation rules, the standards document wins.

Plan-level expectations:

- `documents/documentation_standards.md` remains the documentation SSoT
- `documents/README.md` remains the navigation index for the suite
- the repo must continue using `documents/` for governed documentation
- the repo must keep runbooks under `documents/operations/`, API or schema reference under `documents/reference/`, and ADRs under `documents/adr/`

## Recommended MCP Transport Decision

To keep the plan concrete and Kubernetes-aligned, the default implementation target should be:

- primary MCP transport: streamable HTTP on port `3000`
- optional secondary transport: `stdio` for local tooling if it adds value later
- separate admin surface on the same process for `/healthz`, `/metrics`, and `/version`

If the project chooses a different primary transport in a future plan, record the decision in an ADR before that transport replaces the current HTTP baseline.

## Multi-Phase Development Plan
Each phase must end with code, docs, and configuration that actually match.

### Phase 0: Repository Foundation and Governance
Status: Complete

Objective: establish project identity, repository policy, deployment scaffolding, and documentation governance.

Must deliver:

- root policy files and top-level docs
- one Dockerfile under `docker/`
- Helm chart, Skaffold config, and kind config
- governed `documents/` suite with standards and index

Explicitly out of scope:

- runtime Haskell behavior
- real service integrations

Required coverage:

- artifact presence checks
- Helm and Skaffold render and lint checks

Exit commands:

```bash
test -f README.md
test -f STUDIOMCP_DEVELOPMENT_PLAN.md
test -f docker/Dockerfile
test -f skaffold.yaml
test -f kind/kind_config.yaml
test -f documents/README.md
test -f documents/documentation_standards.md
docker compose -f docker/docker-compose.yaml config >/dev/null
helm lint chart -f chart/values.yaml -f chart/values-kind.yaml
skaffold diagnose --yaml-only --profile kind >/dev/null
skaffold render --offline --profile kind --digest-source=tag >/dev/null
```

### Phase 1: Buildable Haskell Scaffold
Status: Complete

Objective: create a compile-able Haskell project with the intended namespace layout and separated unit and integration suites.

Must deliver:

- Cabal project metadata
- `app/`, `src/`, and `test/` trees
- library and executable targets
- separate `unit-tests` and `integration-tests` suites

Explicitly out of scope:

- claiming runtime behavior beyond compilation and executable wiring

Required coverage:

- at least one unit test module wired into `unit-tests`
- at least one integration test module wired into `integration-tests`

Exit commands:

```bash
cabal build all
cabal build exe:studiomcp exe:studiomcp-server exe:studiomcp-inference exe:studiomcp-worker
cabal test unit-tests
cabal build test:integration-tests
```

### Phase 2: Core Result, Failure, Summary, Timeout, Memoization, and Provenance Model
Status: Complete

Objective: define the core execution algebra in Haskell before service integration begins.

Must deliver:

- `Result` and conversion helpers
- structured failure types
- summary model with both success and failure representation
- timeout policy and timeout failure projection
- memoization policy and deterministic key derivation
- provenance model

Explicitly out of scope:

- YAML parsing
- real service clients
- real process execution

Required coverage:

- railway success and failure behavior
- timeout maps to structured timeout failure
- summary marks successful and failed runs correctly
- memoization policy parsing and key normalization
- failure context fields are asserted, not just constructor shape

Exit commands:

```bash
cabal build all
cabal test unit-tests
rg -n 'DAG\\.(RailwaySpec|TimeoutSpec|SummarySpec|MemoizationSpec)' studioMCP.cabal
rg -n 'DAG\\.(RailwaySpec|TimeoutSpec|SummarySpec|MemoizationSpec)\\.spec' test/Spec.hs
```

### Phase 3: DAG Schema, Parser, Validator, and Fixture Automation
Status: Complete

Objective: load, parse, validate, and automatically verify example DAG definitions.

Must deliver:

- YAML DAG parser
- DAG validation rules
- canonical DAG schema document
- valid fixtures under `examples/dags/`
- invalid fixtures under an explicit invalid-fixture directory
- a repeatable native CLI fixture-validation command

Explicitly out of scope:

- execution engine
- real sidecar I/O

Required coverage:

- valid YAML fixture parses successfully
- malformed YAML fails with a parse error
- structurally invalid DAG fails with validation errors
- every file in the valid fixture directory is automatically checked
- at least one invalid fixture is automatically checked

Exit commands:

```bash
cabal build all
cabal test unit-tests
docker compose -f docker/docker-compose.yaml up -d studiomcp-env
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp dag validate-fixtures
cabal run studiomcp -- validate-dag examples/dags/transcode-basic.yaml
```

### Phase 4: Containerized Development Environment, kind Lifecycle, and Deployment Validation
Status: Complete

Objective: establish the outer development container, active-Docker-context access, and a resettable kind-based validation baseline.

Must deliver:

- Compose service for the outer development container
- Docker-context pass-through into that container
- `kind`, `kubectl`, and `helm` available in the outer container
- explicit `.data/` policy for local persistence
- Helm, Skaffold, and kind baseline validation

Explicitly out of scope:

- real Haskell Pulsar publish and consume
- real Haskell MinIO read and write
- real sidecar lifecycle validation beyond the cluster baseline

Required coverage:

- outer development-container image builds successfully
- outer development container can reach the active Docker context
- kind lifecycle is managed through the native CLI
- Helm and Skaffold validation work against the local cluster baseline

Exit commands:

```bash
cabal build all
docker compose -f docker/docker-compose.yaml build studiomcp-env
docker compose -f docker/docker-compose.yaml up -d studiomcp-env
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp cluster up
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate docs
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate cluster >/dev/null
helm lint chart -f chart/values.yaml -f chart/values-kind.yaml
skaffold diagnose --yaml-only --profile kind >/dev/null
skaffold render --offline --profile kind --digest-source=tag >/dev/null
```

### Phase 5: Messaging Contracts and Pure Execution-State Model
Status: Complete

Objective: define execution events, topic naming, and run-state transitions before building a real Pulsar adapter.

Must deliver:

- execution event types
- topic naming rules
- pure run-state transition model
- JSON encoding and decoding for events if they will cross process boundaries

Explicitly out of scope:

- network I/O to Pulsar

Required coverage:

- allowed and forbidden state transitions
- topic naming invariants
- event payload round-trip tests
- terminal-state behavior tests

Exit commands:

```bash
cabal build all
cabal test unit-tests
rg -n 'Messaging\.(ExecutionStateSpec|EventsSpec|TopicsSpec)' studioMCP.cabal
rg -n 'Messaging\.(ExecutionStateSpec|EventsSpec|TopicsSpec)\.spec' test/Spec.hs
```

### Phase 6: Real Pulsar Adapter and Lifecycle Integration
Status: Complete

Objective: publish and consume a minimal execution lifecycle against a real Pulsar sidecar.

Must deliver:

- Haskell Pulsar client wrapper
- publish API for execution events
- consume API for execution events
- failure mapping from client errors into structured failure types

Explicitly out of scope:

- full DAG execution

Required coverage:

- publish and consume a trivial lifecycle using a unique run id
- assert event ordering for at least one happy-path flow
- assert failure behavior for an unavailable topic, namespace, or broker path

Exit commands:

```bash
cabal build all
docker compose -f docker/docker-compose.yaml up -d studiomcp-env
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp cluster up
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp cluster deploy sidecars
STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate pulsar
```

### Phase 7: Storage Contracts, Content Addressing, and Manifest Model
Status: Complete

Objective: define deterministic storage semantics before wiring them to MinIO.

Must deliver:

- bucket naming rules
- content-address type and derivation rules
- manifest schema
- summary storage contract
- memoization read and write contract at the type level

Explicitly out of scope:

- real MinIO API calls

Required coverage:

- same semantic input gives same content address
- changed semantic input gives a different content address
- manifest encode and decode tests
- bucket and key selection tests

Exit commands:

```bash
cabal build all
cabal test unit-tests
rg -n 'Storage\.(ContentAddressedSpec|ManifestsSpec|KeysSpec)' studioMCP.cabal
rg -n 'Storage\.(ContentAddressedSpec|ManifestsSpec|KeysSpec)\.spec' test/Spec.hs
```

### Phase 8: Real MinIO Adapter and Memoization Integration
Status: Complete

Objective: persist and retrieve immutable objects, manifests, and summaries through a real MinIO sidecar.

Must deliver:

- Haskell MinIO client wrapper
- memoized object write and read path
- manifest write and read path
- summary write and read path

Explicitly out of scope:

- end-to-end DAG execution

Required coverage:

- byte round-trip for memo object
- manifest round-trip
- summary persistence round-trip
- failure-path assertion for missing object lookup

Exit commands:

```bash
cabal build all
docker compose -f docker/docker-compose.yaml up -d studiomcp-env
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp cluster up
STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate minio
```

### Phase 9: Boundary Runtime and Timeout Projection
Status: Complete

Objective: implement the common boundary layer for external tools with enforced timeout and structured failure capture.

Must deliver:

- process invocation abstraction
- stdout and stderr capture
- exit-code capture
- timeout enforcement
- structured failure projection for timeout and process failure

Explicitly out of scope:

- large tool catalog

Required coverage:

- deterministic success helper process
- deterministic failure helper process
- deterministic timeout helper process
- explicit assertions over captured stdout and stderr

Exit commands:

```bash
cabal build all
cabal test unit-tests
docker compose -f docker/docker-compose.yaml up -d studiomcp-env
STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate boundary
```

### Phase 10: First Production Tool Adapter and Deterministic Media Fixtures
Status: Complete

Objective: ship one real tool adapter end to end with safe deterministic fixtures.

Must deliver:

- one real FFmpeg adapter
- small deterministic binary fixtures under `examples/assets/`
- fixture seeding path for integration runs

Explicitly out of scope:

- multiple production-grade adapters in the same phase

Required coverage:

- at least one successful FFmpeg operation against a deterministic fixture
- at least one failing invocation with asserted structured failure output
- fixture reseeding is repeatable

Exit commands:

```bash
cabal build all
docker compose -f docker/docker-compose.yaml up -d studiomcp-env
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp cluster up
STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate ffmpeg-adapter
```

### Phase 11: Sequential DAG Executor and In-Memory Summary Assembly
Status: Complete

Objective: connect parser, validator, scheduler, and boundary runner in sequential topological order and produce a final summary in memory before broad end-to-end persistence work.

Must deliver:

- topological sequential executor
- failure-aware execution flow
- in-memory summary assembly from node outcomes
- explicit integration points for messaging and storage adapters already defined by earlier phases

Explicitly out of scope:

- parallel scheduling
- persisted summary verification against real storage
- broad end-to-end smoke coverage across multiple deployed boundaries

Required coverage:

- ordered execution for a simple DAG
- downstream stop or skip semantics on failure
- in-memory summary reflects successful and failed node outcomes
- adapter-facing calls are observable through deterministic test doubles or fixtures

Exit commands:

```bash
cabal build all
cabal test unit-tests
docker compose -f docker/docker-compose.yaml up -d studiomcp-env
STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate executor
```

### Phase 12: Summary Persistence and First End-to-End DAG Success and Failure Runs
Status: Complete

Objective: add persisted summary verification and run one real successful DAG and one real failing DAG from submission to persisted summary.

Must deliver:

- summary persistence path
- executable run path for a success fixture
- executable run path for a failure fixture
- native CLI end-to-end validation command for success and failure flows

Explicitly out of scope:

- broad adapter catalog
- parallel execution

Required coverage:

- success DAG produces outputs, events, and persisted summary
- failure DAG produces structured failure and persisted summary
- timeout or tool failure is distinguished in the summary
- persisted summary reference is stable and retrievable after the run completes

Exit commands:

```bash
cabal build all
docker compose -f docker/docker-compose.yaml up -d studiomcp-env
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp cluster up
STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate e2e
```

### Phase 13: MCP Server Transport, Handlers, and Protocol-Level Tests
Status: Complete

Objective: expose DAG submission and summary retrieval through the real MCP surface.

Must deliver:

- chosen and documented MCP transport
- real server startup path
- DAG submission handler
- summary retrieval handler
- validator enforcement at the server boundary
- basic admin surface for `/healthz` and `/version`
- route contract for `/metrics` on the same process, with the full observability semantics hardened by Phase 15

Explicitly out of scope:

- inference authority over execution
- dependency-aware health degradation and production-grade metrics semantics

Required coverage:

- protocol-level integration test using a repo-owned MCP client fixture or equivalent HTTP client assertions
- invalid DAG rejected through the MCP surface
- successful submission returns a run identifier
- summary retrieval returns stable structured output
- `/healthz` returns a basic success response
- `/version` returns version metadata

Validation command contract:

- `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate mcp` must start the target server process, wait for readiness, perform the protocol assertions for this phase, verify `/healthz` and `/version`, and clean up the process before exiting

Exit commands:

```bash
cabal build all
docker compose -f docker/docker-compose.yaml up -d studiomcp-env
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate mcp
```

### Phase 14: Inference Advisory Mode with Guardrails
Status: Complete

Objective: add an optional local reference-model path that remains advisory and never bypasses typed execution.

Must deliver:

- local model host integration
- prompts
- guardrails
- explicit separation between advisory output and authoritative execution

Explicitly out of scope:

- allowing inference output to mutate persisted execution state directly

Required coverage:

- guardrail tests
- prompt selection or rendering tests
- failure behavior when the local model host is unavailable
- integration smoke test for a simple advisory request

Exit commands:

```bash
cabal build all
cabal test unit-tests
docker compose -f docker/docker-compose.yaml up -d studiomcp-env
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate inference
```

### Phase 15: Observability, Metrics, and Operational Debugging Surface
Status: Complete

Objective: make the running system debuggable and production-minded before broadening feature scope.

Must deliver:

- structured logs
- stable run and node correlation identifiers
- meaningful `/metrics` endpoint with stable metric names
- dependency-aware `/healthz` behavior
- documented operational debugging workflow

Explicitly out of scope:

- performance optimization work

Required coverage:

- log output includes run id and node id where applicable
- metrics endpoint emits expected counters or gauges
- health surface reflects dependency failures

Validation command contract:

- `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate observability` must start the target server process, wait for readiness, induce or simulate at least one dependency-health condition, assert `/healthz` and `/metrics`, inspect representative log output, and clean up the process before exiting

Exit commands:

```bash
cabal build all
docker compose -f docker/docker-compose.yaml up -d studiomcp-env
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate observability
```

### Phase 16: Complete Governed Documentation Suite, Runbooks, and ADRs
Status: Complete

Objective: finish the documentation system so the repo is navigable and supportable without tribal knowledge.

Must deliver:

- accurate README
- governed docs under `documents/`
- runbooks under `documents/operations/`
- reference material under `documents/reference/`
- ADRs under `documents/adr/`
- tool docs aligned with the actual adapter set

Explicitly out of scope:

- aspirational docs for features that do not exist

Required coverage:

- documentation structure checks
- required-file existence checks
- link or reference validation where practical
- README and plan alignment review

Exit commands:

```bash
cabal build all
docker compose -f docker/docker-compose.yaml up -d studiomcp-env
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate docs
test -f documents/operations/runbook_local_debugging.md
test -f documents/reference/mcp_surface.md
test -f documents/adr/0001_mcp_transport.md
```

### Phase 17: Parallel Scheduling and Optimization Design Package
Status: Complete

Objective: define how the system will scale without weakening semantics.

Must deliver:

- deterministic parallel scheduling design
- optimization notes for zero-copy or reduced-copy execution where feasible
- ADR or architecture note covering the design tradeoffs

Explicitly out of scope:

- landing production parallel execution code in the same phase unless split into a new implementation phase

Required coverage:

- design documents are present and cross-linked
- architecture note includes explicit scheduling guarantees, failure semantics, and invariants
- ADR records explicit tradeoffs and non-goals
- no optimization claim contradicts the purity or summary contract

Exit commands:

```bash
cabal build all
docker compose -f docker/docker-compose.yaml up -d studiomcp-env
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate docs
rg -n '^## Scheduling Guarantees$' documents/architecture/parallel_scheduling.md
rg -n '^## Failure Semantics$' documents/architecture/parallel_scheduling.md
rg -n '^## Tradeoffs$' documents/adr/0002_parallel_scheduling.md
test -f documents/architecture/parallel_scheduling.md
test -f documents/adr/0002_parallel_scheduling.md
```

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
15. Development roadmap
16. Status / current maturity
17. Contribution guidance

## Repository Outcome Target
By the end of the planned phases, the repo should contain:

- a strong `README.md`
- `STUDIOMCP_DEVELOPMENT_PLAN.md`
- `.gitignore`
- `.dockerignore`
- `docker/` with the single Dockerfile and outer-development-container compose stack
- `chart/` with the canonical Helm deployment model
- `skaffold.yaml` for the local dev loop
- `kind/` for the local cluster configuration
- a Haskell source tree
- separate unit and integration test suites
- a governed `documents/` suite with standards, index, architecture, development, domain, engineering, operations, reference, tools, and ADR categories
- example DAGs and reproducible fixtures
- local native CLI commands for development, validation, and cluster lifecycle
- at least one real end-to-end DAG path
- real Pulsar event flow for in-flight execution
- real MinIO persistence for immutable outputs and summaries
- a real MCP surface

## Definition of Done
The repository is in a meaningful initial state when all of the following are true:

- root docs are strong and coherent
- Docker build setup is understandable and runnable
- Helm, kind, and Skaffold artifacts express the repo's deployment model coherently
- the Haskell project compiles
- pure core semantics are covered by unit tests
- stateful boundaries are covered by integration tests
- at least one example DAG runs end to end
- timeouts are enforced
- failures are summarized cleanly
- Pulsar tracks in-flight execution
- MinIO stores immutable memoized results and summaries
- the MCP surface is usable by a real client fixture
- inference mode is advisory only and tested as such
- the `documents/` suite explains relevant tools and operations and follows its own governance rules

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

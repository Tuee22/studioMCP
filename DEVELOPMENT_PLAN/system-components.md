# File: DEVELOPMENT_PLAN/system-components.md
# studioMCP System Components

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [development_plan_standards.md](development_plan_standards.md)

> **Purpose**: Record the authoritative component inventory for edge services, runtime binaries,
> trust boundaries, and durable state locations in `studioMCP`.

## Edge and Infrastructure Components

| Component | Technology | Deployment | Purpose | Durable State |
|-----------|------------|------------|---------|---------------|
| Outer dev container | Docker Compose | ephemeral via `run --rm`; one command per container | Build/test shell and cluster control entrypoint with `studiomcp` on `PATH`, no persistent daemon workflow, native boundary tools, a `whisper.cpp`-built `whisper` binary with its repository-owned shared libraries installed under `/usr/local/lib` and registered through `ldconfig`, and deterministic compatibility shims for `demucs` and `basic-pitch` | bind-mounted repo plus `./.data/` |
| Local cluster | Kind | Docker-backed Kubernetes | Hosts the application and supporting services | host-backed volumes under `./.data/` |
| Container registry | Harbor | In-cluster Helm deployment | Stores application images; all Helm workloads pull from Harbor, the local kind overlay uses persistent filesystem-backed registry storage with relative upload URLs on the manual-PV path, and the CLI compares local and remote digests, waits for PostgreSQL and Redis plus Harbor health and registry readiness before publication, and uses extended managed-registry retry/backoff with remote-digest confirmation before declaring publication failed | cluster storage |
| Edge router | ingress-nginx | Helm release | Unified entrypoint for web services: `/mcp`, `/api`, `/kc`, `/minio`; routes traffic only after published service endpoints and backend application readiness have both closed | none |
| Identity provider | Keycloak | Helm release | Login/password auth and token issuance | Keycloak PostgreSQL |
| Keycloak database | PostgreSQL | Helm release | Durable auth data | cluster storage |
| Session store | Redis | Helm release | Shared MCP and browser-adjacent session coordination | in-cluster runtime state |
| Local storage policy | `studiomcp-manual` StorageClass plus CLI-managed PVs | Kind cluster plus `studiomcp cluster storage reconcile` | Enforces explicit persistence for local stateful workloads | host-backed volumes under `./.data/` |
| Object storage | MinIO | Helm release | Immutable artifact and memo storage | cluster storage |
| Event transport | Pulsar | Helm release | Runtime eventing and validation lifecycle transport | cluster storage |
| Metrics collection | MCP `/metrics` endpoint and optional Prometheus-compatible tooling | Runtime service or cluster add-on | Time-series metrics for cluster and application | cluster storage when enabled |
| Metrics dashboards | Optional Grafana-compatible tooling | Cluster add-on | Visualization of Prometheus metrics | cluster storage when enabled |
| Application database | PostgreSQL where applicable | repo/runtime services | Durable application state for implemented flows | repo-specific runtime storage |

## Runtime and Application Components

| Component | Entry point | Purpose |
|-----------|-------------|---------|
| DAG parser and validator | `src/StudioMCP/DAG/*.hs` | Parse, validate, and summarize DAG execution graphs |
| Sequential and parallel execution runtime | `src/StudioMCP/DAG/Executor.hs`, `Scheduler.hs` | Execute DAGs with timeout and memoization support |
| Boundary runtime | `src/StudioMCP/Tools/Boundary.hs` | Execute deterministic helper processes with structured failure handling |
| FFmpeg adapter | `src/StudioMCP/Tools/FFmpeg.hs` | Media transformation boundary on top of the runtime |
| MCP core | `src/StudioMCP/MCP/*.hs` | JSON-RPC, catalogs, and MCP transport surfaces |
| MCP listener/server | `src/StudioMCP/MCP/Server.hs` | Expose MCP over supported transports |
| Artifact governance | `src/StudioMCP/Storage/Governance.hs` | Quotas, audit, and tenant storage contract |
| BFF | `src/StudioMCP/Web/BFF.hs`, `Handlers.hs` | Browser-facing auth and session surface |
| Auth middleware | `src/StudioMCP/Auth/*.hs` | JWT validation, claims extraction, scope enforcement, and Keycloak integration |
| Worker runtime | `src/StudioMCP/Worker/Server.hs` | Runtime worker validation and execution entrypoint |
| Inference runtime | `src/StudioMCP/Inference/*.hs` | Advisory inference service and related validation path |
| Cluster CLI | `src/StudioMCP/CLI/Cluster.hs` | Cluster ensure/deploy/bootstrap operations plus rollout, service-endpoint, shared application-readiness gates, and like-for-like local/remote image digest comparison with dependency-aware Harbor publication gates, PostgreSQL/Redis-backed Harbor dependency waits, extended managed-registry retry/backoff, and remote-digest confirmation before managed-registry pushes fail |
| Docs validator | `src/StudioMCP/CLI/Docs.hs` | Documentation validation entrypoint |
| Test CLI | `src/StudioMCP/CLI/Test.hs` | Test command handlers that build suites under `/opt/build/`, resolve test binaries, and execute them without repopulating the workspace build tree |
| Models CLI surface | `src/StudioMCP/CLI/Models.hs` | MinIO-backed model sync, list, and verify commands |
| Email CLI surface | `src/StudioMCP/CLI/Email.hs` | SES-backed test-email dispatch entrypoint |
| SoX adapter | `src/StudioMCP/Tools/SoX.hs` | Audio effects boundary |
| Demucs adapter | `src/StudioMCP/Tools/Demucs.hs` | Stem separation boundary with MinIO model loading |
| Whisper adapter | `src/StudioMCP/Tools/Whisper.hs` | Transcription boundary with MinIO model loading and a repaired outer-container runtime path for the installed `whisper` executable |
| BasicPitch adapter | `src/StudioMCP/Tools/BasicPitch.hs` | Audio-to-MIDI boundary |
| FluidSynth adapter | `src/StudioMCP/Tools/FluidSynth.hs` | MIDI synthesis boundary with MinIO SoundFont loading |
| Rubberband adapter | `src/StudioMCP/Tools/Rubberband.hs` | Time/pitch manipulation boundary |
| ImageMagick adapter | `src/StudioMCP/Tools/ImageMagick.hs` | Image processing boundary |
| MediaInfo adapter | `src/StudioMCP/Tools/MediaInfo.hs` | Media inspection boundary |
| Model registry | `src/StudioMCP/Models/Registry.hs` | Model metadata and source URLs |
| Model sync | `src/StudioMCP/Models/Sync.hs` | Idempotent sync from public repos to MinIO |
| Model loader | `src/StudioMCP/Models/Loader.hs` | Fetch models from MinIO for runtime use |
| Workflow tool registry | `src/StudioMCP/Tools/Registry.hs` | Resolve DAG `tool:` names to boundary executables; distinct from tenant-facing MCP `tools/list` entries |
| Fixture seeding | `src/StudioMCP/Test/Fixtures.hs` | Deterministic fixture generation plus MinIO seed/verify support |
| Chaos test utilities | `src/StudioMCP/Test/Chaos.hs` | Synthetic recovery-budget helpers used by the integration suite |
| SES email | `src/StudioMCP/Email/SES.hs` | AWS SES client for verification and password reset |
| Email templates | `src/StudioMCP/Email/Templates.hs` | Template rendering for email flows |

## Readiness and Startup Contract

- Kubernetes rollout, readiness probes, and `EndpointSlice` publication remain necessary routing
  gates on the cluster path.
- `src/StudioMCP/API/Readiness.hs` defines the shared readiness payload and blocking-reason model
  used by the MCP server, BFF, worker, inference surface, and cluster CLI.
- `src/StudioMCP/CLI/Cluster.hs` waits for shared-service readiness during `cluster ensure` and
  for ingress-routable application readiness during `cluster deploy server`.
- `src/StudioMCP/MCP/Server.hs`, `src/StudioMCP/Web/Handlers.hs`,
  `src/StudioMCP/Worker/Server.hs`, and `src/StudioMCP/Inference/Host.hs` now expose
  dependency-aware readiness handlers tied to real downstream requirements.

## External and Browser-Facing Boundaries

| Boundary | Direction | Format / Credential | Owner | Notes |
|----------|-----------|---------------------|-------|-------|
| Browser <-> BFF | External | HTTPS JSON plus HTTP-only session cookie | BFF | Cookie auth wins over bearer auth for browser flows |
| External client <-> MCP | External | stdio or HTTP JSON-RPC | MCP server | Standards-compliant MCP surface |
| BFF <-> Keycloak | Internal service-to-service | OIDC / token exchange | BFF and auth modules | Password grant and refresh-token flows remain active |
| MCP listener <-> Redis | Internal | Redis-backed session state | MCP session layer | Shared state for resumable sessions and scale-out |
| Runtime <-> Pulsar | Internal | message bus payloads | runtime adapters | Validation and lifecycle eventing |
| Runtime <-> MinIO | Internal | object storage API | storage adapters | Immutable object and artifact storage |
| DAG workflow nodes <-> tool registry | Internal | DAG `tool:` names | runtime adapters | Registry-backed boundary-tool lookup; not exposed as direct tenant-facing MCP tools |
| Runtime <-> local filesystem | Local | files under `./.data/` | config/runtime adapters | Durable local state must stay under the repo data root |

## State and Artifact Locations

| State Class | Authority | Durable Home | Notes |
|-------------|-----------|--------------|-------|
| Build artifacts | explicit `cabal --builddir=/opt/build/studiomcp` flags in the Dockerfile and CLI | `/opt/build/studiomcp` | Canonical repo build and test output; integration tests that already run inside the outer container reuse the installed `studiomcp` on `PATH`; Cabal bootstrap uses the baked-in package index or refreshes outside `/workspace`; nothing may land in the repo tree |
| Repo-local runtime state | local development environment | `./.data/` | Only supported repo-root durable path; also backs CLI-reconciled local PVs |
| Keycloak realm and auth data | Keycloak | PostgreSQL | Backing store for auth contracts |
| Shared resumable session state | MCP session layer | Redis | Required for horizontal scale validation |
| Immutable artifacts and memo objects | storage adapters | MinIO | Bulk bytes stay on the data plane |
| Cluster deployment config | Helm values and chart templates | `chart/` | Defines the canonical route split, registry image flow, and `studiomcp-manual` storage settings |
| Outer container workflow | Compose and Dockerfile | `docker-compose.yaml`, `docker/` | Ephemeral one-command containers via `docker compose run --rm`; the repository Dockerfile is single-stage, uses `tini`, and has no `CMD`; compose has no `command`; Kubernetes workloads declare explicit startup commands |
| Image registry | Harbor | cluster deployment and Harbor registry storage | Application images; the CLI populates Harbor with required images before Helm chart deployment |
| Validation assets | repo fixtures | `examples/`, `test/` | Deterministic inputs for runtime validation |
| ML models | Model sync | MinIO `studiomcp-models/` | HuggingFace, GGUF, SoundFonts - NOT in containers |
| Local model cache | model loader | `./.data/studiomcp/model-cache/` by default | Override with `STUDIOMCP_MODEL_CACHE_DIR` when needed |
| Test fixtures | Fixture seeding | MinIO `studiomcp-test-fixtures/` | Deterministic media for tool tests |

## Cross-References

- [00-overview.md](00-overview.md)
- [phase-1-repository-dag-runtime-foundations.md](phase-1-repository-dag-runtime-foundations.md)
- [phase-2-mcp-surface-catalog-artifact-governance.md](phase-2-mcp-surface-catalog-artifact-governance.md)
- [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md)
- [phase-4-control-plane-data-plane-contract.md](phase-4-control-plane-data-plane-contract.md)
- [phase-6-cluster-control-plane-parity.md](phase-6-cluster-control-plane-parity.md)
- [phase-9-cli-test-validate-consolidation.md](phase-9-cli-test-validate-consolidation.md)
- [phase-10-build-artifact-isolation.md](phase-10-build-artifact-isolation.md)
- [phase-11-runtime-readiness-and-condition-driven-startup.md](phase-11-runtime-readiness-and-condition-driven-startup.md)
- [phase-12-aggregate-test-artifact-isolation-and-warning-closure.md](phase-12-aggregate-test-artifact-isolation-and-warning-closure.md)
- [phase-13-harbor-push-reliability-and-mcp-http-closure.md](phase-13-harbor-push-reliability-and-mcp-http-closure.md)
- [phase-14-makefile-removal.md](phase-14-makefile-removal.md)
- [phase-15-monocontainer-tool-expansion.md](phase-15-monocontainer-tool-expansion.md)
- [phase-16-minio-model-storage.md](phase-16-minio-model-storage.md)
- [phase-17-haskell-tool-adapters.md](phase-17-haskell-tool-adapters.md)
- [phase-21-chaos-engineering.md](phase-21-chaos-engineering.md)
- [phase-22-ses-email-integration.md](phase-22-ses-email-integration.md)
- [phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md)

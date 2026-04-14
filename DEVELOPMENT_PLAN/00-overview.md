# File: DEVELOPMENT_PLAN/00-overview.md
# studioMCP Development Plan - Overview

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [system-components.md](system-components.md)

> **Purpose**: Capture the architecture baseline, current plan state, control-plane topology, and
> closure rules that every phase in `studioMCP` depends on.

## Target Outcome

`studioMCP` is a Kubernetes-forward Haskell application that:

- builds and validates DAG-based execution runtimes
- exposes MCP over stdio and HTTP with governed catalogs
- uses Keycloak for identity and Redis for shared MCP session state
- serves browser users through a BFF with cookie-first session handling
- routes `/mcp`, `/api`, and `/kc` through ingress-nginx
- treats readiness as a first-class runtime contract with explicit application conditions,
  watch-driven waiting, and structured blocking reasons
- keeps large artifact bytes on the data plane via presigned object-storage URLs
- stores all local durable repo state under `./.data/`

## Current Repo Assessment Against This Plan

| Phase | Status | Notes |
|-------|--------|-------|
| 1 | Done | Repository, DAG execution, tool boundaries, worker runtime, and inference entrypoints are implemented and validated |
| 2 | Done | MCP protocol surface, artifact governance, and observability are implemented and validated |
| 3 | Done | Keycloak-backed auth and shared Redis session behavior are implemented, validated, and documented against the stable Phase 2 MCP catalog |
| 4 | Done | Control-plane route split and object-storage public endpoint contract are explicit and validated |
| 5 | Done | Browser login, session, refresh, and logout behavior are cookie-first, validated, and aligned across the BFF and web-surface docs |
| 6 | Done | The cluster plan uses an in-cluster Harbor deployment as the registry source for all Helm workloads, with the CLI responsible for Harbor population and event-driven service endpoint publication before live edge validation |
| 7 | Done | Keycloak realm bootstrap is automated and idempotent on the default cluster path, and the runbook now documents the CLI-driven path without retired compose-era guidance |
| 8 | Done | The canonical regression gate remains `docker compose run --rm studiomcp studiomcp validate all`, and the final closure work now includes aligned suite indexes, one canonical doc per governed concept, and refreshed top-level status summaries |
| 9 | Done | CLI test and validate commands consolidated with unified interface and documentation |
| 10 | Done | Build artifact isolation baseline and the one-command container contract are implemented: single-stage Dockerfile, `tini`, no Dockerfile `CMD`, no compose `command`, and Kubernetes-owned runtime startup |
| 11 | Done | Dependency-aware readiness is implemented across workloads, CLI waits, validators, and governed docs, with the post-cleanup full-suite verification closed |
| 12 | Done | Aggregate test artifact isolation and repo-owned warning closure are complete: canonical build and test paths stay under `/opt/build/`, repo-owned compiler warnings are closed, and the workspace remains free of `dist-newstyle/` even when aggregate validation fails elsewhere |
| 13 | Done | Harbor-backed MCP HTTP validation and aggregate-suite reliability are now closed: the source tree uses persistent filesystem-backed local Harbor storage with relative upload URLs, reconciles Harbor registry storage through the manual-PV path, waits for PostgreSQL/Redis plus Harbor health before managed-registry publication, retries managed publication with extended backoff and remote-digest confirmation, and the April 14, 2026 clean post-prune rerun closed the April 13, 2026 `validate mcp-http` failure |

## Public Topology Baseline

The supported local and cluster topology is:

- browser and external clients reach the control plane through ingress-nginx
- `/mcp` routes to the MCP listener surface
- `/api` routes to the BFF and browser session endpoints
- `/kc` routes to Keycloak
- bulk upload and download bytes use presigned URLs rooted at the configured object-storage public endpoint
- Keycloak uses its own PostgreSQL store
- MCP listener nodes externalize resumable session state to Redis
- runtime services use Pulsar and MinIO for eventing and immutable artifact storage
- Harbor runs on the cluster and serves as the image source for Helm-managed workloads
- the CLI populates Harbor with required application images before Helm chart deployment begins
- server deploy now waits for Kubernetes service endpoint publication and dependency-aware
  application readiness before live ingress validation begins
- local cluster persistence uses CLI-reconciled PVs backed by `./.data/` through the `studiomcp-manual` StorageClass
- all durable local filesystem state lives under `./.data/`

## Design Decisions

- Browser auth is intentionally simplified to login/password over TLS to the BFF plus an HTTP-only
  session cookie. Redirect-based OAuth/PKCE is deferred.
- Keycloak remains the identity backend and JWT issuer.
- `docker-compose.yaml` is a one-command launcher only: every supported CLI action uses
  `docker compose run --rm studiomcp studiomcp <subcommand>`.
  `docker compose up` and `docker compose exec` are not supported workflow examples.
- The supported repository container contract uses a single-stage Dockerfile with `tini` as init,
  no Dockerfile `CMD`, and no compose `command`.
  Kubernetes manifests own explicit runtime startup for the in-cluster path rather than the
  development container.
- Environment variables (`LANG`, `LC_ALL`) are set only in the Dockerfile; compose inherits from image.
- Compose mounts are minimal: workspace, `.data`, and docker socket only.
- Web portals route through the ingress control-plane port: `/mcp`, `/api`, `/kc`, and `/minio`.
- Harbor is an in-cluster deployment, not a sidecar or other registry container
  running outside the cluster.
- All Helm deploys pull application containers from Harbor.
- The CLI is responsible for populating Harbor with the required application images before Helm
  chart deployment.
- The CLI treats workload rollout, Kubernetes service endpoint publication, and application
  readiness as separate gates for live `/mcp` and `/api` validation.
- Cluster secrets are managed by the CLI on deploy; no env files.
- Stateful Helm workloads bind only to the CLI-reconciled `studiomcp-manual` StorageClass; no
  default dynamic storage class remains on the supported local path.
- The control-plane route split is fixed: `/mcp` for MCP, `/api` for the BFF, `/kc` for Keycloak.
- Bulk artifact bytes stay off the control plane. The BFF authorizes access and returns presigned
  object-storage URLs.
- Durable repo-local state must live under `./.data/`; `.studiomcp-data/` is a removed legacy path.
- Build artifacts are isolated to `/opt/build/studiomcp` via explicit `--builddir` flags on
  repo-owned cabal invocations. The repo does not rely on `CABAL_BUILDDIR` or a `cabal.project`
  `builddir` directive because nix-style builds ignore them. Integration tests that already run
  inside the outer container reuse the installed `studiomcp` on `PATH` instead of self-bootstrapping
  a second CLI binary, and any fallback Cabal index refresh runs outside `/workspace` so the repo
  tree stays free of compiled output and `dist-newstyle/` metadata.

## Completion Rules

- A phase is complete only when the target behavior exists and the listed validation gates pass.
- Harness-based validation only counts for the exact behavior it exercises.
- Deployment rollout and `EndpointSlice` publication alone do not close runtime readiness; the
  supported path must also make dependency-aware application readiness explicit where traffic would
  otherwise race startup.
- When architecture changes, update [README.md](README.md), [system-components.md](system-components.md),
  and the affected phase file together.
- Public contract items are not complete until the contract and the environment-specific validation
  path are both explicit.

## Explicitly Deferred Scope

- Browser redirect OAuth/PKCE
- External PKCE client flow
- Routing bulk artifacts through the BFF instead of using presigned URLs

## Cross-References

- [README.md](README.md)
- [system-components.md](system-components.md)
- [phase-4-control-plane-data-plane-contract.md](phase-4-control-plane-data-plane-contract.md)
- [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md)
- [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md)
- [phase-9-cli-test-validate-consolidation.md](phase-9-cli-test-validate-consolidation.md)
- [phase-10-build-artifact-isolation.md](phase-10-build-artifact-isolation.md)
- [phase-11-runtime-readiness-and-condition-driven-startup.md](phase-11-runtime-readiness-and-condition-driven-startup.md)
- [phase-12-aggregate-test-artifact-isolation-and-warning-closure.md](phase-12-aggregate-test-artifact-isolation-and-warning-closure.md)
- [phase-13-harbor-push-reliability-and-mcp-http-closure.md](phase-13-harbor-push-reliability-and-mcp-http-closure.md)

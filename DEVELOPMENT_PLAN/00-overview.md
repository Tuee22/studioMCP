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
- keeps large artifact bytes on the data plane via presigned object-storage URLs
- stores all local durable repo state under `./.data/`

## Current Repo Assessment Against This Plan

| Phase | Status | Notes |
|-------|--------|-------|
| 1 | Done | Repository, DAG execution, tool boundaries, worker runtime, and inference entrypoints are implemented and validated |
| 2 | Done | MCP protocol surface, artifact governance, and observability are implemented and validated |
| 3 | Done | Keycloak-backed auth and shared Redis session behavior are implemented and validated |
| 4 | Done | Control-plane route split and object-storage public endpoint contract are explicit and validated |
| 5 | Done | Browser login, session, refresh, and logout behavior are cookie-first and validated |
| 6 | Done | Kind and Helm expose the canonical control-plane contract through unified ingress, registry-backed image pulls, CLI-managed secrets, and CLI-owned storage reconciliation |
| 7 | Done | Keycloak realm bootstrap is automated and idempotent on the default cluster path |
| 8 | Done | The full regression gate now passes on the supported outer-container and Kind-based workflow |
| 9 | Done | CLI test and validate commands consolidated with unified interface and documentation |
| 10 | Done | Build artifact isolation, ephemeral container operation, and minimal compose mounts are implemented |

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
- local cluster persistence uses CLI-reconciled PVs backed by `./.data/` through the `studiomcp-manual` StorageClass
- all durable local filesystem state lives under `./.data/`

## Design Decisions

- Browser auth is intentionally simplified to login/password over TLS to the BFF plus an HTTP-only
  session cookie. Redirect-based OAuth/PKCE is deferred.
- Keycloak remains the identity backend and JWT issuer.
- `docker-compose.yaml` runs ephemeral containers via `docker compose run --rm -it studiomcp <cmd>`.
  No persistent daemon; the `env` image has no CMD and compose has no command.
- Environment variables (`LANG`, `LC_ALL`) are set only in the Dockerfile; compose inherits from image.
- Compose mounts are minimal: workspace, `.data`, and docker socket only.
- Web portals route through the ingress control-plane port: `/mcp`, `/api`, `/kc`, and `/minio`.
- Helm deploys pull application containers from the configured Harbor-compatible registry; the CLI
  idempotently pushes images on change when the registry exposes a comparable manifest digest.
- Cluster secrets are managed by the CLI on deploy; no env files.
- Stateful Helm workloads bind only to the CLI-reconciled `studiomcp-manual` StorageClass; no
  default dynamic storage class remains on the supported local path.
- The control-plane route split is fixed: `/mcp` for MCP, `/api` for the BFF, `/kc` for Keycloak.
- Bulk artifact bytes stay off the control plane. The BFF authorizes access and returns presigned
  object-storage URLs.
- Durable repo-local state must live under `./.data/`; `.studiomcp-data/` is a removed legacy path.
- Build artifacts are isolated to `/opt/build/studiomcp` via explicit `--builddir` flags on all
  cabal invocations. The repo does not rely on `CABAL_BUILDDIR` or a `cabal.project` `builddir`
  directive because nix-style builds ignore them. The repo tree must remain free of compiled
  output.

## Completion Rules

- A phase is complete only when the target behavior exists and the listed validation gates pass.
- Harness-based validation only counts for the exact behavior it exercises.
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

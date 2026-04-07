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
| Outer dev container | Docker Compose | `studiomcp-env` | Build/test shell and cluster control entrypoint with `studiomcp` on `PATH` | bind-mounted repo plus `./.data/` |
| Local cluster | Kind | Docker-backed Kubernetes | Hosts the application and supporting services | host-backed volumes under `./.data/` |
| Edge router | ingress-nginx | Helm release | Public entrypoint for `/mcp`, `/api`, and `/kc` | none |
| Identity provider | Keycloak | Helm release | Login/password auth and token issuance | Keycloak PostgreSQL |
| Keycloak database | PostgreSQL | Helm release | Durable auth data | cluster storage |
| Session store | Redis | Helm release | Shared MCP and browser-adjacent session coordination | in-cluster runtime state |
| Object storage | MinIO | Helm release | Immutable artifact and memo storage | cluster storage |
| Event transport | Pulsar | Helm release | Runtime eventing and validation lifecycle transport | cluster storage |
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
| Cluster CLI | `src/StudioMCP/CLI/Cluster.hs` | Cluster ensure/deploy/bootstrap operations |
| Docs validator | `src/StudioMCP/CLI/Docs.hs` | Documentation validation entrypoint |

## External and Browser-Facing Boundaries

| Boundary | Direction | Format / Credential | Owner | Notes |
|----------|-----------|---------------------|-------|-------|
| Browser <-> BFF | External | HTTPS JSON plus HTTP-only session cookie | BFF | Cookie auth wins over bearer auth for browser flows |
| External client <-> MCP | External | stdio or HTTP JSON-RPC | MCP server | Standards-compliant MCP surface |
| BFF <-> Keycloak | Internal service-to-service | OIDC / token exchange | BFF and auth modules | Password grant and refresh-token flows remain active |
| MCP listener <-> Redis | Internal | Redis-backed session state | MCP session layer | Shared state for resumable sessions and scale-out |
| Runtime <-> Pulsar | Internal | message bus payloads | runtime adapters | Validation and lifecycle eventing |
| Runtime <-> MinIO | Internal | object storage API | storage adapters | Immutable object and artifact storage |
| Runtime <-> local filesystem | Local | files under `./.data/` | config/runtime adapters | Durable local state must stay under the repo data root |

## State and Artifact Locations

| State Class | Authority | Durable Home | Notes |
|-------------|-----------|--------------|-------|
| Repo-local runtime state | local development environment | `./.data/` | Only supported repo-root durable path |
| Keycloak realm and auth data | Keycloak | PostgreSQL | Backing store for auth contracts |
| Shared resumable session state | MCP session layer | Redis | Required for horizontal scale validation |
| Immutable artifacts and memo objects | storage adapters | MinIO | Bulk bytes stay on the data plane |
| Cluster deployment config | Helm values and chart templates | `chart/` | Defines the canonical route split and service topology |
| Outer container workflow | Compose and Dockerfile | `docker-compose.yaml`, `docker/` | Compose starts only the outer container, and the `env` image installs `studiomcp` to `/usr/local/bin` |
| Validation assets | repo fixtures | `examples/`, `test/` | Deterministic inputs for runtime validation |

## Cross-References

- [00-overview.md](00-overview.md)
- [phase-1-repository-dag-runtime-foundations.md](phase-1-repository-dag-runtime-foundations.md)
- [phase-2-mcp-surface-catalog-artifact-governance.md](phase-2-mcp-surface-catalog-artifact-governance.md)
- [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md)
- [phase-4-control-plane-data-plane-contract.md](phase-4-control-plane-data-plane-contract.md)

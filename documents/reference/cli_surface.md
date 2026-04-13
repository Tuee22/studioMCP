# File: documents/reference/cli_surface.md
# CLI Surface Reference

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite), [../development/local_dev.md](../development/local_dev.md#cross-references), [../operations/runbook_local_debugging.md](../operations/runbook_local_debugging.md#cross-references), [../architecture/cli_architecture.md](../architecture/cli_architecture.md#cross-references), [../engineering/k8s_storage.md](../engineering/k8s_storage.md#cross-references), [../../DEVELOPMENT_PLAN.md](../../DEVELOPMENT_PLAN.md#current-validation-state)

> **Purpose**: Detailed command surface reference. See [cli_reference.md](cli_reference.md) for a concise multi-tiered reference.

## Current Implemented Commands

The codebase currently implements this subset:

- `studiomcp help`
- `studiomcp --help`
- `studiomcp -h`
- `studiomcp server`
- `studiomcp stdio`
- `studiomcp bff`
- `studiomcp inference`
- `studiomcp worker`
- `studiomcp test`
- `studiomcp test all`
- `studiomcp test unit`
- `studiomcp test integration`
- `studiomcp validate all`
- `studiomcp validate-dag <path>`
- `studiomcp dag validate <path>`
- `studiomcp dag validate-fixtures`
- `studiomcp validate docs`
- `studiomcp validate cluster`
- `studiomcp validate e2e`
- `studiomcp validate worker`
- `studiomcp validate pulsar`
- `studiomcp validate minio`
- `studiomcp validate boundary`
- `studiomcp validate ffmpeg-adapter`
- `studiomcp validate executor`
- `studiomcp validate mcp-stdio`
- `studiomcp validate mcp-http`
- `studiomcp validate keycloak`
- `studiomcp validate mcp-auth`
- `studiomcp validate session-store`
- `studiomcp validate mcp-session-store`
- `studiomcp validate horizontal-scale`
- `studiomcp validate mcp-horizontal-scale`
- `studiomcp validate web-bff`
- `studiomcp validate artifact-storage`
- `studiomcp validate artifact-governance`
- `studiomcp validate mcp-tools`
- `studiomcp validate mcp-resources`
- `studiomcp validate mcp-prompts`
- `studiomcp validate inference`
- `studiomcp validate observability`
- `studiomcp validate audit`
- `studiomcp validate quotas`
- `studiomcp validate rate-limit`
- `studiomcp validate mcp-conformance`
- `studiomcp validate storage-policy`
- `studiomcp cluster up`
- `studiomcp cluster down`
- `studiomcp cluster reset`
- `studiomcp cluster status`
- `studiomcp cluster ensure`
- `studiomcp cluster push-images`
- `studiomcp cluster ensure-secrets`
- `studiomcp cluster deploy sidecars`
- `studiomcp cluster deploy server`
- `studiomcp cluster storage reconcile`
- `studiomcp cluster storage delete <name>`

Current note:

- The retired `studiomcp validate mcp` alias has been removed. Use `validate mcp-stdio`, `validate mcp-http`, or `validate mcp-conformance`.
- `studiomcp bff` is implemented in the main CLI, and `studiomcp-bff` remains available as a dedicated executable.

## Required Target Surface

The supported command surface must converge on one Haskell CLI with at least these families:

### Usage Commands

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp help` | Print usage text | ✅ Implemented |
| `studiomcp --help` | Print usage text | ✅ Implemented |
| `studiomcp -h` | Print usage text | ✅ Implemented |

### Server Modes

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp server` | Start MCP server (HTTP + operational endpoints) | ✅ Implemented |
| `studiomcp stdio` | Start MCP server in stdio transport mode | ✅ Implemented |
| `studiomcp inference` | Start inference mode server | ✅ Implemented |
| `studiomcp worker` | Start worker mode server | ✅ Implemented |
| `studiomcp bff` | Start BFF server | ✅ Implemented |

### Test Commands

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp test` | Run all tests (unit + integration) | ✅ Implemented |
| `studiomcp test all` | Run all tests (unit + integration) | ✅ Implemented |
| `studiomcp test unit` | Run unit tests only | ✅ Implemented |
| `studiomcp test integration` | Run integration tests only | ✅ Implemented |

### Aggregate Validation

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp validate all` | Run all validators with aggregate reporting | ✅ Implemented |

### DAG Commands

| Command | Description |
|---------|-------------|
| `studiomcp dag validate <path>` | Validate a DAG specification file |
| `studiomcp dag validate-fixtures` | Validate all fixture DAGs |
| `studiomcp validate-dag <path>` | Alias for dag validate |

### Cluster Commands

| Command | Description |
|---------|-------------|
| `studiomcp cluster up` | Start local Kubernetes cluster |
| `studiomcp cluster down` | Stop local Kubernetes cluster |
| `studiomcp cluster reset` | Reset the kind cluster to a clean Kubernetes state while preserving host-backed volumes |
| `studiomcp cluster status` | Show cluster status |
| `studiomcp cluster ensure` | Idempotent setup: up + Helm dependency reconcile + ingress edge + sidecars + Keycloak realm bootstrap + shared-service readiness waits (recommended for automation) |
| `studiomcp cluster push-images` | Build and push application images to the configured registry |
| `studiomcp cluster ensure-secrets` | Create/update CLI-managed Kubernetes secrets |
| `studiomcp cluster storage reconcile` | Reconcile storage resources |
| `studiomcp cluster storage delete <name>` | Delete a storage resource |
| `studiomcp cluster deploy sidecars` | Reconcile Helm dependencies and deploy sidecar services |
| `studiomcp cluster deploy server` | Reconcile Helm dependencies, deploy MCP/BFF/worker workloads, and wait for routing plus application readiness |

### Idempotency Guarantees

All cluster management commands are idempotent and safe to run repeatedly:

| Command | Behavior |
|---------|----------|
| `cluster up` | Creates cluster only if it doesn't exist; ensures network connectivity |
| `cluster down` | Deletes cluster only if it exists |
| `cluster reset` | Uninstalls the Helm release when present, recreates the kind cluster, and preserves host-backed volume contents |
| `cluster push-images` | Builds the application image from the repository Dockerfile, tags it for the configured registry, and pushes when the remote digest differs or is absent |
| `cluster ensure-secrets` | Applies the required Kubernetes secrets with fixed names and stable keys |
| `cluster deploy sidecars` | Ensures Helm dependencies are reconciled, ensures registry image availability, applies CLI-managed secrets, uses `helm upgrade --install`, ensures ingress-nginx, and bootstraps the checked-in Keycloak realm |
| `cluster deploy server` | Ensures Helm dependencies are reconciled, ensures registry image availability, applies CLI-managed secrets, uses `helm upgrade --install`, bootstraps the checked-in Keycloak realm, rolls server/BFF/worker/reference-model workloads, waits for rollout and `EndpointSlice` publication, and then waits for `/mcp`, `/api`, worker, and reference-model readiness |
| `cluster storage reconcile` | Uses `kubectl apply` (idempotent) |
| `cluster storage delete <name>` | Deletes the named PV if it exists |
| `cluster ensure` | Single idempotent command: brings up the kind cluster, reconciles Helm dependencies, applies ingress-nginx, deploys sidecars, imports the checked-in Keycloak realm if missing, and waits for Redis, PostgreSQL, MinIO, Pulsar, and Keycloak, including shared-service application readiness. Recommended for automation and tests. |

Running any of these commands multiple times produces the same result as running once. This design supports:
- **Developer workflow**: Run `cluster ensure` at any point to guarantee a working environment
- **CI/CD**: Integration tests use `cluster ensure` for reliable setup
- **Recovery**: After failures or interruptions, simply re-run the command

The default validated kind edge is:

- control plane: `http://localhost:8081`
- object storage: `http://localhost:9000`

### Readiness And Wait Semantics

The implemented cluster surface distinguishes three gates:

- workload rollout
- routing readiness through published Kubernetes service endpoints
- application readiness through runtime `/health/ready` handlers and reference-model health checks

Live validators rely on the CLI to close those gates before test traffic starts. Structured
blocking reasons come from the readiness payloads, and the integration harness now preserves
validator stdout and stderr when a readiness timeout fails.

### Validation Commands - Phase 1 Foundations

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp validate docs` | Validate documentation suite | ✅ Implemented |
| `studiomcp validate cluster` | Validate cluster readiness | ✅ Implemented |
| `studiomcp validate pulsar` | Validate Pulsar connectivity | ✅ Implemented |
| `studiomcp validate minio` | Validate MinIO connectivity | ✅ Implemented |
| `studiomcp validate boundary` | Validate boundary runtime | ✅ Implemented |
| `studiomcp validate ffmpeg-adapter` | Validate FFmpeg adapter | ✅ Implemented |
| `studiomcp validate executor` | Validate DAG executor | ✅ Implemented |
| `studiomcp validate e2e` | End-to-end validation | ✅ Implemented |
| `studiomcp validate worker` | Validate worker mode | ✅ Implemented |
| `studiomcp validate inference` | Validate inference mode | ✅ Implemented |

### Validation Commands - Phase 2 MCP Surface

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp validate mcp-stdio` | Validate MCP over stdio transport | ✅ Implemented |
| `studiomcp validate mcp-http` | Validate MCP over Streamable HTTP transport | ✅ Implemented |

**`validate mcp-stdio`** tests:
- Server starts in stdio mode
- Initialize handshake completes
- Capability negotiation succeeds
- tools/list returns expected tools
- Tool invocation works end-to-end
- Graceful shutdown

**`validate mcp-http`** tests:
- Server starts in HTTP mode
- Initialize handshake via POST /mcp
- Session ID returned and accepted
- Capability negotiation succeeds
- tools/list returns expected tools
- Tool invocation works end-to-end

### Validation Commands - Phase 3 Auth Foundations

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp validate keycloak` | Validate Keycloak connectivity and realm | ✅ Implemented |
| `studiomcp validate mcp-auth` | Validate MCP authentication flow | ✅ Implemented |

**`validate keycloak`** tests:
- Live JWKS endpoint is accessible when live auth env is configured
- Password login succeeds against the configured Keycloak realm
- JWT validation succeeds against the live realm, including subject recovery through `userinfo` when needed
- When `STUDIOMCP_VALIDATE_KIND_EDGE=true`, `cluster ensure` provisions the kind edge and bootstrapped realm before live validation runs
- Fake Keycloak-compatible JWKS coverage remains available as the fallback path when live auth env is absent

**`validate mcp-auth`** tests:
- Live `/mcp` rejects unauthenticated requests when live auth env is configured
- Live Keycloak-issued bearer token validates locally against the configured JWKS
- Authenticated initialize completes through the nginx edge
- Authenticated tool discovery works through the edge proxy
- Authenticated `GET /mcp` SSE bootstrap works through the edge proxy
- When `STUDIOMCP_VALIDATE_KIND_EDGE=true`, the live path targets the kind ingress edge at `http://localhost:8081`
- Synthetic token validation coverage remains available as the fallback path when live auth env is absent

### Validation Commands - Phase 3 Session Foundations

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp validate session-store` | Validate session externalization | ✅ Implemented |
| `studiomcp validate mcp-session-store` | Validate session externalization (alias) | ✅ Implemented |
| `studiomcp validate horizontal-scale` | Validate multi-replica operation | ✅ Implemented |
| `studiomcp validate mcp-horizontal-scale` | Validate multi-replica operation (alias) | ✅ Implemented |

**`validate mcp-session-store`** tests:
- Redis connectivity
- Session create/read/update/delete
- Session TTL expiration
- Session data serialization

**`validate mcp-horizontal-scale`** tests:
- Live MCP requests preserve session continuity across multiple nginx-routed server backends when live auth env is configured
- Session updates, subscriptions, and locks remain visible across Redis-backed store instances
- Lock contention and lock handoff behave correctly
- Shared-store-only coverage remains available as the fallback path when live auth env is absent

### Validation Commands - Phase 5 BFF Workflow Surface

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp validate web-bff` | Validate BFF integration | ✅ Implemented |

**`validate web-bff`** tests:
- Live login returns an HTTP-only browser session cookie when live auth env is configured
- Login and refresh JSON omit session identifiers and tokens
- `GET /api/v1/session/me` works from the login cookie
- Cookie auth wins over Bearer session compatibility credentials when both are present
- Live refresh, upload, confirm, download, chat, run submit, run status, and run-events SSE work through `/api`
- Upload and download presigned URLs are rooted at the configured public object-storage endpoint
- When `STUDIOMCP_VALIDATE_KIND_EDGE=true`, the live path targets the kind ingress edge at `http://localhost:8081`
- Live logout invalidates the session and post-logout refresh is rejected
- Runtime-backed BFF to MCP/service integration remains covered in both live and fallback modes

### Validation Commands - Phase 2 Artifact Governance

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp validate artifact-storage` | Validate tenant artifact storage | ✅ Implemented |
| `studiomcp validate artifact-governance` | Validate non-destructive artifact policy | ✅ Implemented |

**`validate artifact-storage`** tests:
- Tenant storage configuration loads
- Artifact creation succeeds
- Artifact versioning works
- Presigned URL generation works

**`validate artifact-governance`** tests:
- Artifact hide operation succeeds
- Artifact archive operation succeeds
- Artifact supersede operation succeeds
- Hard delete is rejected/not exposed
- Audit trail recorded

### Validation Commands - Phase 2 MCP Catalog

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp validate mcp-tools` | Validate MCP tool catalog | ✅ Implemented |
| `studiomcp validate mcp-resources` | Validate MCP resource catalog | ✅ Implemented |
| `studiomcp validate mcp-prompts` | Validate MCP prompt catalog | ✅ Implemented |

**`validate mcp-tools`** tests:
- tools/list returns all registered tools
- Each tool has valid inputSchema
- `workflow.submit`, `workflow.status`, `workflow.list`, and `workflow.cancel` persist run state
- `artifact.upload_url`, `artifact.get`, `artifact.download_url`, `artifact.hide`, and `artifact.archive` operate on tenant-scoped artifacts
- `tenant.info` reflects current artifact usage

**`validate mcp-resources`** tests:
- resources/list returns all registered resources
- Run summary resource readable
- Manifest resource readable
- Resource URIs follow convention

**`validate mcp-prompts`** tests:
- prompts/list returns all registered prompts
- Prompt templates render correctly
- Prompt arguments validated

### Validation Commands - Phase 2 Observability

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp validate observability` | Validate observability stack | ✅ Implemented |
| `studiomcp validate audit` | Validate audit logging | ✅ Implemented |
| `studiomcp validate quotas` | Validate quota enforcement | ✅ Implemented |
| `studiomcp validate rate-limit` | Validate rate limiting and redaction | ✅ Implemented |

**`validate audit`** tests:
- Correlation IDs present in logs
- Subject/tenant context logged
- Authorization decisions logged
- Token redaction working
- Structured log format correct

### Validation Commands - Phase 2 Conformance

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp validate mcp-conformance` | Full MCP protocol conformance validation | ✅ Implemented |

**`validate mcp-conformance`** tests:
- Full protocol lifecycle
- All registered capabilities
- Error code compliance
- Session behavior compliance
- Transport compliance (both stdio and HTTP)

## Validation Coverage By Plan Phase

| Phase | Commands Introduced |
|-------|---------------------|
| 1 | `validate docs`, `validate cluster`, `validate pulsar`, `validate minio`, `validate boundary`, `validate ffmpeg-adapter`, `validate executor`, `validate e2e`, `validate worker`, `validate inference` |
| 2 | `validate mcp-stdio`, `validate mcp-http`, `validate artifact-storage`, `validate artifact-governance`, `validate mcp-tools`, `validate mcp-resources`, `validate mcp-prompts`, `validate observability`, `validate audit`, `validate quotas`, `validate rate-limit`, `validate mcp-conformance` |
| 3 | `validate keycloak`, `validate mcp-auth`, `validate session-store`, `validate mcp-session-store`, `validate horizontal-scale`, `validate mcp-horizontal-scale` |
| 4 | Validation uses `cluster ensure` and kind-edge curl checks |
| 5 | `validate web-bff` |
| 6 | No dedicated deployment-alignment command yet; the development plan currently uses Helm, ingress, and runbook validation |
| 9 | `test`, `test all`, `test unit`, `test integration`, `validate all` |

## Legacy Alias Retirement

The historical `studiomcp validate mcp` alias has been removed.

Use:

- `studiomcp validate mcp-stdio` for the stdio transport
- `studiomcp validate mcp-http` for the HTTP transport
- `studiomcp validate mcp-conformance` for the broader end-to-end MCP validation story

The exact final taxonomy may evolve, but the repository must not reintroduce shell wrappers for these responsibilities.

## Usage Context

For local development and LLM-driven operations, the CLI runs inside one-off outer development containers:

```bash
# Bootstrap (run on host)
docker compose build

# Invoke CLI commands (run inside container)
docker compose run --rm studiomcp studiomcp <subcommand...>
```

Each command gets its own container. `docker compose up` and `docker compose exec` are not part
of the supported outer-container workflow.

Kind-edge validation uses the same outer-container entrypoint. Set `STUDIOMCP_VALIDATE_KIND_EDGE=true` to make `validate keycloak`, `validate mcp-auth`, `validate mcp-http`, and `validate web-bff` target the kind ingress edge after cluster provisioning.

## Current Repo Note

This reference now matches the implemented command surface. The Haskell CLI covers cluster lifecycle, registry image population, CLI-managed secrets, ingress-backed kind deployment, Keycloak realm bootstrap, storage reconciliation and deletion, DAG validation, documentation validation, executor and end-to-end validation, worker-runtime validation, Pulsar, MinIO, boundary, FFmpeg-adapter, MCP transport validation, auth validation, session scaling validation, BFF validation, artifact validation, MCP catalog validation, inference, observability, quotas, rate limiting, MCP conformance validation, and consolidated test/validate-all entrypoints.

## Cross-References

- [CLI Reference](cli_reference.md#studiomcp-cli-reference) - Concise multi-tiered command reference
- [CLI Architecture](../architecture/cli_architecture.md#cli-architecture)
- [Docker Policy](../engineering/docker_policy.md#docker-policy)
- [Kubernetes Storage Policy](../engineering/k8s_storage.md#kubernetes-storage-policy)
- [Local Development](../development/local_dev.md#local-development)
- [Phase 9: CLI Test and Validate Consolidation](../../DEVELOPMENT_PLAN/phase-9-cli-test-validate-consolidation.md#phase-9-cli-test-and-validate-consolidation)

# File: documents/reference/cli_surface.md
# CLI Surface Reference

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite), [../development/local_dev.md](../development/local_dev.md#cross-references), [../operations/runbook_local_debugging.md](../operations/runbook_local_debugging.md#cross-references), [../architecture/cli_architecture.md](../architecture/cli_architecture.md#cross-references), [../engineering/k8s_storage.md](../engineering/k8s_storage.md#cross-references), [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#current-validation-state)

> **Purpose**: Canonical reference for the supported current and future `studiomcp` CLI surface.

## Current Implemented Commands

The codebase currently implements this subset:

- `studiomcp server`
- `studiomcp inference`
- `studiomcp worker`
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
- `studiomcp validate mcp`
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
- `studiomcp cluster up`
- `studiomcp cluster down`
- `studiomcp cluster status`
- `studiomcp cluster deploy sidecars`
- `studiomcp cluster deploy server`
- `studiomcp cluster storage reconcile`

Current note:

- `studiomcp validate mcp` currently validates the legacy custom DAG HTTP server surface, not a standards-compliant MCP surface.
- `studiomcp-bff` exists as a dedicated executable today; wiring `studiomcp bff` into the main CLI remains future ergonomic work.

## Required Target Surface

The supported command surface must converge on one Haskell CLI with at least these families:

### Server Modes

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp server` | Start MCP server (HTTP + legacy routes) | ✅ Implemented |
| `studiomcp stdio` | Start MCP server in stdio transport mode | 📋 Planned (Phase 13) |
| `studiomcp inference` | Start inference mode server | ✅ Implemented |
| `studiomcp worker` | Start worker mode server | ✅ Implemented |
| `studiomcp bff` | Start BFF server | 📋 Planned (Phase 16) |

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
| `studiomcp cluster reset` | Reset cluster to clean state |
| `studiomcp cluster status` | Show cluster status |
| `studiomcp cluster storage reconcile` | Reconcile storage resources |
| `studiomcp cluster storage delete <name>` | Delete a storage resource |
| `studiomcp cluster deploy sidecars` | Deploy sidecar services |
| `studiomcp cluster deploy server` | Deploy MCP server |

### Validation Commands - Current (Phases 0-12)

| Command | Description | Phase |
|---------|-------------|-------|
| `studiomcp validate docs` | Validate documentation suite | 0 |
| `studiomcp validate cluster` | Validate cluster readiness | 4 |
| `studiomcp validate pulsar` | Validate Pulsar connectivity | 6 |
| `studiomcp validate minio` | Validate MinIO connectivity | 8 |
| `studiomcp validate boundary` | Validate boundary runtime | 9 |
| `studiomcp validate ffmpeg-adapter` | Validate FFmpeg adapter | 10 |
| `studiomcp validate executor` | Validate DAG executor | 11 |
| `studiomcp validate e2e` | End-to-end validation | 12 |
| `studiomcp validate worker` | Validate worker mode | 12 |
| `studiomcp validate mcp` | Validate legacy /runs surface (DEPRECATED in Phase 18) | 12 |
| `studiomcp validate inference` | Validate inference mode | 12 |
| `studiomcp validate observability` | Validate observability stack | 12 |

### Validation Commands - MCP Protocol (Phase 13) - ✅ IMPLEMENTED

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

### Validation Commands - Auth (Phase 14) - ✅ IMPLEMENTED

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp validate keycloak` | Validate Keycloak connectivity and realm | ✅ Implemented |
| `studiomcp validate mcp-auth` | Validate MCP authentication flow | ✅ Implemented |

**`validate keycloak`** tests:
- Keycloak reachable
- Realm exists
- JWKS endpoint accessible
- Test client credentials valid

**`validate mcp-auth`** tests:
- Valid token accepted
- Invalid token rejected (401)
- Expired token rejected
- Wrong audience rejected
- Insufficient scope rejected (403)
- Tenant context resolved correctly

### Validation Commands - Session Scaling (Phase 15) - ✅ IMPLEMENTED (local contract validation)

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
- Multiple MCP listener replicas running
- Session resume across different pods
- No sticky session requirement
- Load balancer behavior correct

### Validation Commands - Web/BFF (Phase 16) - ✅ IMPLEMENTED

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp validate web-bff` | Validate BFF integration | ✅ Implemented |

**`validate web-bff`** tests:
- BFF server starts
- User authentication flow
- MCP client integration
- Upload presigned URL generation
- Download presigned URL generation

### Validation Commands - Artifacts (Phase 17) - ✅ IMPLEMENTED

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

### Validation Commands - MCP Catalog (Phase 18) - ✅ IMPLEMENTED

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

### Validation Commands - Observability (Phase 19) - ✅ IMPLEMENTED (local services)

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp validate audit` | Validate audit logging | ✅ Implemented |
| `studiomcp validate quotas` | Validate quota enforcement | ✅ Implemented |
| `studiomcp validate rate-limit` | Validate rate limiting and redaction | ✅ Implemented |

**`validate audit`** tests:
- Correlation IDs present in logs
- Subject/tenant context logged
- Authorization decisions logged
- Token redaction working
- Structured log format correct

### Validation Commands - Conformance (Phase 21) - ✅ IMPLEMENTED (local conformance suite)

| Command | Description | Status |
|---------|-------------|--------|
| `studiomcp validate mcp-conformance` | Full MCP protocol conformance validation | ✅ Implemented |

**`validate mcp-conformance`** tests:
- Full protocol lifecycle
- All registered capabilities
- Error code compliance
- Session behavior compliance
- Transport compliance (both stdio and HTTP)

## Validation Command Evolution

| Phase | Commands Introduced |
|-------|---------------------|
| 13 | `validate mcp-stdio`, `validate mcp-http` |
| 14 | `validate keycloak`, `validate mcp-auth` |
| 15 | `validate session-store`, `validate mcp-session-store`, `validate horizontal-scale`, `validate mcp-horizontal-scale` |
| 16 | `validate web-bff` |
| 17 | `validate artifact-storage`, `validate artifact-governance` |
| 18 | `validate mcp-tools`, `validate mcp-resources`, `validate mcp-prompts` |
| 19 | `validate audit`, `validate quotas`, `validate rate-limit` |
| 21 | `validate mcp-conformance` |

## Deprecation Notice

Starting Phase 18, `studiomcp validate mcp` will emit a deprecation warning:

```
WARNING: 'validate mcp' validates the legacy /runs surface.
This surface is deprecated. Use 'validate mcp-http' or 'validate mcp-stdio'.
```

In Phase 21, the legacy `validate mcp` command will be removed or aliased to `validate mcp-http`.

The exact final taxonomy may evolve, but the repository must not reintroduce shell wrappers for these responsibilities.

## Usage Context

For local development and LLM-driven operations, the CLI is expected to run inside the outer development container:

```bash
docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp <subcommand...>
```

## Current Repo Note

This reference intentionally describes both the implemented surface and the remaining target state. The current command surface now covers cluster lifecycle, DAG validation, documentation validation, executor and end-to-end validation, worker-runtime validation, Pulsar, MinIO, boundary, FFmpeg-adapter, legacy MCP validation, MCP transport validation, auth validation, session scaling validation, BFF validation, artifact validation, MCP catalog validation, inference, observability, quotas, rate limiting, and local MCP conformance validation. The remaining target surface includes future ergonomics such as `cluster reset`, a first-class `studiomcp bff` subcommand, and deeper production-integration checks against live Keycloak and Redis infrastructure.

## Cross-References

- [CLI Architecture](../architecture/cli_architecture.md#cli-architecture)
- [Docker Policy](../engineering/docker_policy.md#docker-policy)
- [Kubernetes Storage Policy](../engineering/k8s_storage.md#kubernetes-storage-policy)
- [Local Development](../development/local_dev.md#local-development)

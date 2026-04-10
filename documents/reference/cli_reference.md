# File: documents/reference/cli_reference.md
# StudioMCP CLI Reference

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite), [../../DEVELOPMENT_PLAN/phase-9-cli-test-validate-consolidation.md](../../DEVELOPMENT_PLAN/phase-9-cli-test-validate-consolidation.md#deliverables), [../../DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md#cli-first-testing-policy)

> **Purpose**: Canonical reference for the `studiomcp` CLI, including all test, validate, cluster, and server commands.

The `studiomcp` CLI is the canonical interface for all development, validation, and testing operations.

## Execution Context

All CLI commands run inside the outer `studiomcp-env` container. Bootstrap and invoke as follows:

```bash
# Bootstrap (run on host)
docker compose up -d

# Invoke CLI commands (run inside container)
docker compose exec studiomcp-env studiomcp <command>
```

See [DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md#l-container-execution-context) for the complete container workflow.

## Command Categories

### Root Commands

Runtime modes for the StudioMCP server.

| Command | Description |
|---------|-------------|
| `studiomcp server` | Run MCP server over HTTP |
| `studiomcp stdio` | Run MCP server over stdio transport |
| `studiomcp bff` | Run Backend-for-Frontend mode |
| `studiomcp inference` | Run inference mode |
| `studiomcp worker` | Run worker mode |

### Test Commands

All test entrypoints route through the CLI.

| Command | Description |
|---------|-------------|
| `studiomcp test` | Run all tests (unit + integration) |
| `studiomcp test all` | Run all tests (unit + integration) |
| `studiomcp test unit` | Run unit tests only |
| `studiomcp test integration` | Run integration tests only |

### Validate Commands

Validators for individual subsystems and aggregate validation.

| Command | Description |
|---------|-------------|
| `studiomcp validate all` | Run all validators |
| `studiomcp validate docs` | Validate documentation structure |
| `studiomcp validate cluster` | Validate cluster connectivity |
| `studiomcp validate e2e` | End-to-end DAG execution |
| `studiomcp validate worker` | Worker runtime validation |
| `studiomcp validate pulsar` | Pulsar messaging validation |
| `studiomcp validate minio` | MinIO storage validation |
| `studiomcp validate boundary` | Boundary service validation |
| `studiomcp validate ffmpeg-adapter` | FFmpeg adapter validation |
| `studiomcp validate executor` | Sequential executor validation |
| `studiomcp validate mcp-stdio` | MCP over stdio transport |
| `studiomcp validate mcp-http` | MCP over HTTP transport |
| `studiomcp validate keycloak` | Keycloak connectivity |
| `studiomcp validate mcp-auth` | MCP authentication validation |
| `studiomcp validate session-store` | Session store validation |
| `studiomcp validate mcp-session-store` | Session store validation (alias) |
| `studiomcp validate horizontal-scale` | Horizontal scaling validation |
| `studiomcp validate mcp-horizontal-scale` | Horizontal scaling validation (alias) |
| `studiomcp validate web-bff` | Web BFF validation |
| `studiomcp validate artifact-storage` | Artifact storage validation |
| `studiomcp validate artifact-governance` | Artifact governance validation |
| `studiomcp validate mcp-tools` | MCP tools catalog validation |
| `studiomcp validate mcp-resources` | MCP resources catalog validation |
| `studiomcp validate mcp-prompts` | MCP prompts catalog validation |
| `studiomcp validate inference` | Inference mode validation |
| `studiomcp validate observability` | Observability surface validation |
| `studiomcp validate audit` | Audit trail validation |
| `studiomcp validate quotas` | Quota enforcement validation |
| `studiomcp validate rate-limit` | Rate limiting validation |
| `studiomcp validate mcp-conformance` | MCP protocol conformance |
| `studiomcp validate storage-policy` | Storage policy enforcement |

### DAG Commands

DAG file validation and fixture management.

| Command | Description |
|---------|-------------|
| `studiomcp validate-dag <path>` | Validate a single DAG file |
| `studiomcp dag validate <path>` | Validate a single DAG file (alternative syntax) |
| `studiomcp dag validate-fixtures` | Validate all DAG fixtures |

### Cluster Commands

Kubernetes cluster lifecycle management.

| Command | Description |
|---------|-------------|
| `studiomcp cluster up` | Create and start the Kind cluster |
| `studiomcp cluster down` | Stop and delete the Kind cluster |
| `studiomcp cluster reset` | Reset the cluster to clean state |
| `studiomcp cluster status` | Show cluster status |
| `studiomcp cluster ensure` | Idempotent: up + sidecars + wait for all services |
| `studiomcp cluster deploy sidecars` | Deploy sidecar services (Redis, MinIO, Pulsar, etc.) |
| `studiomcp cluster deploy server` | Deploy the MCP server |
| `studiomcp cluster storage reconcile` | Reconcile storage resources |
| `studiomcp cluster storage delete <name>` | Delete a named storage resource |

## Usage Examples

All examples assume `docker compose up -d` has been run on the host first.

### Running Tests

```bash
# Run all tests
docker compose exec studiomcp-env studiomcp test

# Run only unit tests
docker compose exec studiomcp-env studiomcp test unit

# Run only integration tests (requires cluster)
docker compose exec studiomcp-env studiomcp test integration
```

### Validation Workflow

```bash
# Ensure cluster is ready
docker compose exec studiomcp-env studiomcp cluster ensure

# Run all validators
docker compose exec studiomcp-env studiomcp validate all

# Or run specific validators
docker compose exec studiomcp-env studiomcp validate docs
docker compose exec studiomcp-env studiomcp validate mcp-http
```

### Development Workflow

```bash
# Start the cluster
docker compose exec studiomcp-env studiomcp cluster up

# Deploy sidecars
docker compose exec studiomcp-env studiomcp cluster deploy sidecars

# Deploy server
docker compose exec studiomcp-env studiomcp cluster deploy server

# Run tests
docker compose exec studiomcp-env studiomcp test all

# Validate everything
docker compose exec studiomcp-env studiomcp validate all
```

## Cross-References

- [DEVELOPMENT_PLAN/development_plan_standards.md](../../DEVELOPMENT_PLAN/development_plan_standards.md#cli-first-testing-policy)
- [DEVELOPMENT_PLAN/phase-9-cli-test-validate-consolidation.md](../../DEVELOPMENT_PLAN/phase-9-cli-test-validate-consolidation.md#phase-9-cli-test-and-validate-consolidation)
- [MCP Surface](mcp_surface.md#mcp-surface-reference)

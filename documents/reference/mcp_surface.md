# File: documents/reference/mcp_surface.md
# MCP Surface Reference

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite), [../operations/runbook_local_debugging.md](../operations/runbook_local_debugging.md#cross-references), [../reference/cli_surface.md](../reference/cli_surface.md#cross-references), [../adr/0001_mcp_transport.md](../adr/0001_mcp_transport.md#cross-references), [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#phase-13-mcp-server-transport-handlers-and-protocol-level-tests)

> **Purpose**: Canonical reference for the current public `studioMCP` control surface, including the implemented HTTP server, advisory inference surface, and the remaining runtime limitations.

## Current Public Surface

The repo currently exposes these user-invokable entrypoints:

- `studiomcp server`
- `studiomcp inference`
- `studiomcp worker`
- `studiomcp validate worker`
- `studiomcp validate mcp`
- `studiomcp validate inference`
- `studiomcp validate observability`
- `studiomcp-server`
- `studiomcp-inference`
- `studiomcp-worker`

## Current Behavior

### Implemented Today

- `studiomcp server` starts the implemented HTTP control surface on port `3000`
- that server exposes `POST /runs`, `GET /runs/:id/summary`, `GET /healthz`, `GET /version`, and `GET /metrics`
- valid DAG submission returns a run identifier in `RunRunning` state and summary retrieval resolves once the persisted summary exists
- `studiomcp validate mcp` deploys the server into kind, verifies invalid and valid submissions, verifies summary retrieval, and asserts `/healthz`, `/version`, and `/metrics`
- `studiomcp worker` starts a direct execution HTTP service with `POST /execute`, `GET /healthz`, and `GET /version`
- `studiomcp validate worker` verifies invalid and valid DAG execution against the real worker runtime and asserts the health and version surface
- `studiomcp inference` starts an advisory HTTP service with `POST /advice`, `GET /healthz`, and `GET /version`
- `studiomcp validate inference` verifies a successful advisory request against a fake model host and verifies typed failure behavior when the model host is unavailable
- `studiomcp validate observability` verifies metrics growth, correlated log output, and degraded `/healthz` behavior when a dependency is made unavailable

### Current Limitations

- the current server surface is HTTP-based only; an additional `stdio` transport remains optional future work
- protocol validation currently uses repo-owned HTTP client assertions rather than a third-party MCP client library

## CLI Reference

### `studiomcp server`

- starts the real HTTP server on port `3000`
- exposes the current control and admin routes used by the live validation commands

### `studiomcp inference`

- starts the advisory HTTP inference service
- calls the configured reference model host and applies prompt plus guardrail handling

### `studiomcp worker`

- starts the real direct execution worker service on port `3002`
- validates DAGs, executes them synchronously against the configured adapters and sidecars, and returns the persisted summary and manifest references

## Transport Decision

The current target and implementation are:

- primary transport: HTTP on port `3000`
- optional secondary transport: `stdio` later if it proves useful
- same process admin surface for `/healthz`, `/metrics`, and `/version`

That decision is recorded in [../adr/0001_mcp_transport.md](../adr/0001_mcp_transport.md#adr-0001-mcp-transport).

Implementation note:

- the transport and observability phases are complete in the current plan
- the native `studiomcp validate mcp` and `studiomcp validate observability` commands own deployment, readiness checks, assertions, and cleanup for their target surfaces

## Cross-References

- [ADR 0001: MCP Transport](../adr/0001_mcp_transport.md#adr-0001-mcp-transport)
- [CLI Surface Reference](../reference/cli_surface.md#cli-surface-reference)
- [Server Mode](../architecture/server_mode.md#server-mode)
- [Inference Mode](../architecture/inference_mode.md#inference-mode)
- [Local Debugging Runbook](../operations/runbook_local_debugging.md#local-debugging-runbook)

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
- `studiomcp validate inference`
- `studiomcp validate observability`
- `studiomcp cluster up`
- `studiomcp cluster down`
- `studiomcp cluster status`
- `studiomcp cluster deploy sidecars`
- `studiomcp cluster deploy server`
- `studiomcp cluster storage reconcile`

Current note:

- `studiomcp validate mcp` currently validates the legacy custom DAG HTTP server surface, not a standards-compliant MCP surface.

## Required Target Surface

The supported command surface must converge on one Haskell CLI with at least these families:

- `studiomcp dag validate <path>`
- `studiomcp dag validate-fixtures`
- `studiomcp cluster up`
- `studiomcp cluster down`
- `studiomcp cluster reset`
- `studiomcp cluster status`
- `studiomcp cluster storage reconcile`
- `studiomcp cluster storage delete <name>`
- `studiomcp cluster deploy sidecars`
- `studiomcp cluster deploy server`
- `studiomcp validate docs`
- `studiomcp validate cluster`
- `studiomcp validate executor`
- `studiomcp validate e2e`
- `studiomcp validate worker`
- `studiomcp validate pulsar`
- `studiomcp validate minio`
- `studiomcp validate boundary`
- `studiomcp validate ffmpeg-adapter`
- `studiomcp validate inference`
- `studiomcp validate integration`
- `studiomcp validate mcp`
- `studiomcp validate mcp-stdio`
- `studiomcp validate mcp-http`
- `studiomcp validate mcp-auth`
- `studiomcp validate observability`

The exact final taxonomy may evolve, but the repository must not reintroduce shell wrappers for these responsibilities.

## Usage Context

For local development and LLM-driven operations, the CLI is expected to run inside the outer development container:

```bash
docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp <subcommand...>
```

## Current Repo Note

This reference intentionally describes both the implemented surface and the remaining target state. The current command surface covers cluster lifecycle, DAG validation, documentation validation, executor and end-to-end validation, worker-runtime validation, Pulsar, MinIO, boundary, FFmpeg-adapter, legacy MCP-surface validation, inference, and observability validation. The remaining target surface includes real MCP transport and auth validation commands in addition to future ergonomics such as `cluster reset` and controlled storage deletion workflows.

## Cross-References

- [CLI Architecture](../architecture/cli_architecture.md#cli-architecture)
- [Docker Policy](../engineering/docker_policy.md#docker-policy)
- [Kubernetes Storage Policy](../engineering/k8s_storage.md#kubernetes-storage-policy)
- [Local Development](../development/local_dev.md#local-development)

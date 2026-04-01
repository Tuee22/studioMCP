# File: documents/architecture/cli_architecture.md
# CLI Architecture

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [overview.md](overview.md#canonical-follow-on-documents), [../development/local_dev.md](../development/local_dev.md#cross-references), [../engineering/docker_policy.md](../engineering/docker_policy.md#cross-references), [../engineering/k8s_storage.md](../engineering/k8s_storage.md#cross-references), [../reference/cli_surface.md](../reference/cli_surface.md#cross-references), [../../README.md](../../README.md#repository-architecture)

> **Purpose**: Canonical architecture for the single Haskell CLI that owns supported repository commands and local cluster lifecycle management.

## Summary

`studioMCP` has one supported CLI: `studiomcp`.

That binary is responsible for:

- DAG-oriented developer commands
- cluster lifecycle management for the local kind cluster
- explicit PV management for local Kubernetes storage
- deploying Helm charts for the MCP server and required sidecars
- validation workflows that would otherwise become repo helper scripts

## Architectural Role

The CLI is not a side utility. It is the supported control plane for local development and operations.

It must live in the same Haskell codebase as the rest of the system so that:

- command semantics stay typed and testable
- deployment assumptions stay versioned with the server
- LLM and human workflows converge on one command surface

## Execution Model

The CLI is expected to run inside the outer development container, not directly on the host as the primary workflow.

Canonical invocation shape:

```bash
docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp <subcommand...>
```

The CLI may internally call external tools such as `kind`, `kubectl`, and `helm`, but those calls must be orchestrated from Haskell rather than delegated to checked-in shell scripts.

## Command Families

The CLI command surface should be organized into clear families:

- `server`
- `inference`
- `worker`
- `dag ...`
- `cluster ...`
- `validate ...`

The exact spellings live in the CLI reference document, but the architectural split matters:

- `cluster` owns kind lifecycle, Helm-backed deployment, and kubeconfig-oriented flows
- `cluster storage ...` owns manual PV reconciliation and `.data/`-backed storage setup
- `validate` owns repo and runtime verification paths

## Responsibilities

- manage the local kind cluster lifecycle
- configure the cluster to host the MCP server image
- create and reconcile manual PVs for local Helm releases that request persistence
- deploy or reconcile sidecars through Helm
- expose native validation commands instead of repository shell wrappers
- preserve the existing `server`, `inference`, and `worker` runtime roles

## Non-Responsibilities

- becoming a second MCP protocol surface
- replacing Helm as the chart source of truth
- replacing Kubernetes as the runtime topology
- embedding Docker-in-Docker as the default strategy

## Current Repo Note

The implemented CLI surface already covers DAG validation, cluster lifecycle, sidecar deployment, server deployment, storage reconciliation, executor and end-to-end validation, MCP transport validation, auth validation, session scaling validation, inference validation, observability validation, and conformance validation. The remaining CLI gaps are ergonomic rather than architectural.

## Cross-References

- [Architecture Overview](overview.md#architecture-overview)
- [Docker Policy](../engineering/docker_policy.md#docker-policy)
- [Kubernetes Storage Policy](../engineering/k8s_storage.md#kubernetes-storage-policy)
- [CLI Surface Reference](../reference/cli_surface.md#cli-surface-reference)

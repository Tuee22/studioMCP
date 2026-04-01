# File: documents/engineering/local_dev.md
# Local Development

**Status**: Authoritative source
**Supersedes**: legacy local development doc
**Referenced by**: [../README.md](../README.md#documentation-suite), [testing.md](testing.md#cross-references), [k8s_native_dev_policy.md](k8s_native_dev_policy.md#cross-references), [../operations/runbook_local_debugging.md](../operations/runbook_local_debugging.md#cross-references), [../reference/cli_surface.md](../reference/cli_surface.md#cross-references)

> **Purpose**: Canonical local setup and workflow guide for contributors working on `studioMCP`.

## Tooling Baseline

- GHC 9.12.2
- cabal-install 3.16.0.0
- Docker for image builds and the host engine used by kind
- Docker Compose for launching the outer development container
- Helm for deployment rendering
- kind for the local cluster
- Skaffold for Kubernetes-oriented image and deploy workflows
- host `./.data/` for explicit local PV backing paths

## Common Commands

- `cabal build all`
- `cabal test unit-tests`
- `cabal test integration-tests` (requires outer container and cluster)
- `cabal run studiomcp -- validate-dag examples/dags/transcode-basic.yaml`
- `cabal run studiomcp -- dag validate-fixtures`
- `cabal run studiomcp -- validate docs`
- `docker compose -f docker-compose.yaml config`
- `helm lint chart -f chart/values.yaml -f chart/values-kind.yaml`
- `skaffold diagnose --yaml-only --profile kind`
- `skaffold render --offline --profile kind --digest-source=tag`

## Current Outer-Container Workflow

The repo now includes the outer development-container service and the first native cluster commands. The intended invocation shape is:

- `docker compose -f docker-compose.yaml up -d studiomcp-env`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp dag validate-fixtures`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp cluster up`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp cluster status`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp cluster storage reconcile`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp cluster deploy sidecars`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp cluster deploy server`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp validate cluster`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp validate executor`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp validate e2e`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp validate worker`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp validate pulsar`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp validate minio`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp validate boundary`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp validate ffmpeg-adapter`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp validate mcp-http`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp validate mcp-conformance`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp validate inference`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp validate observability`
- `docker compose -f docker-compose.yaml exec studiomcp-env studiomcp validate docs`

The outer container talks to the same engine through `/var/run/docker.sock`.
By default the CLI derives the host-visible `./.data/` path for kind from the outer container's `/.data/` bind mount. Set `STUDIOMCP_KIND_HOST_DATA_PATH` only as an override for non-standard Docker contexts.

## Container Management

All studioMCP containers use fixed names for idempotent management. This means:

- Re-running commands automatically cleans up stale containers
- No orphaned containers accumulate from interrupted tests
- Container state is always predictable

### Fixed Container Names

| Container | Purpose | Created By |
|-----------|---------|------------|
| `studiomcp` | Kind cluster | `studiomcp cluster up` |
| `studiomcp-test-redis` | Validation Redis | `validate mcp-session-store`, `validate mcp-horizontal-scale`, etc. |

### Manual Cleanup

If containers become orphaned (rare), clean them up with:

```bash
# View all studioMCP containers
docker ps -a --filter "name=studiomcp"

# Remove all studioMCP containers
docker rm -f $(docker ps -aq --filter "name=studiomcp")

# Or prune specific containers
docker rm -f studiomcp-test-redis
```

The kind cluster container can be removed with:

```bash
kind delete cluster --name studiomcp
```

## Working Rule

From Phase 1 onward, do not proceed to the next implementation phase until the Haskell build succeeds and the phase-relevant native CLI validations pass.

Target rule: for cluster and deployment work, enter the outer development container and run `studiomcp` there.
Do not add new repository helper scripts for developer workflows.
Do not rely on dynamic storage classes for local development; use the explicit `.data/` plus manual-PV flow defined in [k8s_storage.md](k8s_storage.md#kubernetes-storage-policy).
Current repo note: the outer-container workflow is now verified on this machine for `cluster up`, `cluster status`, `cluster deploy sidecars`, `validate cluster`, `validate executor`, `validate e2e`, `validate worker`, `validate pulsar`, `validate minio`, `validate boundary`, `validate ffmpeg-adapter`, `validate mcp-http`, `validate mcp-conformance`, `validate inference`, `validate observability`, and `validate docs`. Persistence-backed Helm releases for MinIO and Pulsar remain disabled by default in the shipped local values, so `cluster storage reconcile` is currently a no-op unless persistence is explicitly enabled.
Use [../documentation_standards.md](../documentation_standards.md#studiomcp-documentation-standards) as the SSoT for documentation rules.

## Cross-References

- [Testing Doctrine](testing.md#testing-doctrine)
- [Kubernetes-Native Development Policy](k8s_native_dev_policy.md#kubernetes-native-development-policy)
- [Kubernetes Storage Policy](k8s_storage.md#kubernetes-storage-policy)
- [CLI Surface Reference](../reference/cli_surface.md#cli-surface-reference)
- [Documentation Standards](../documentation_standards.md#studiomcp-documentation-standards)

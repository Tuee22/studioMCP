# File: documents/development/local_dev.md
# Local Development

**Status**: Authoritative source
**Supersedes**: legacy `documents/development/local-dev.md`
**Referenced by**: [../README.md](../README.md#documentation-suite), [testing_strategy.md](testing_strategy.md#cross-references), [../engineering/k8s_native_dev_policy.md](../engineering/k8s_native_dev_policy.md#cross-references), [../operations/runbook_local_debugging.md](../operations/runbook_local_debugging.md#cross-references), [../reference/cli_surface.md](../reference/cli_surface.md#cross-references)

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

- `docker compose -f docker-compose.yaml build studiomcp`
- `docker compose -f docker-compose.yaml run --rm studiomcp cabal --builddir=/opt/build/studiomcp build all`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp test unit`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp test integration` (requires cluster)
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate-dag examples/dags/transcode-basic.yaml`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp dag validate-fixtures`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate docs`
- `docker compose -f docker-compose.yaml config`
- `docker compose -f docker-compose.yaml run --rm studiomcp helm lint chart -f chart/values.yaml -f chart/values-kind.yaml`
- `docker compose -f docker-compose.yaml run --rm studiomcp skaffold diagnose --yaml-only --profile kind`
- `docker compose -f docker-compose.yaml run --rm studiomcp skaffold render --offline --profile kind --digest-source=tag`

## Current Outer-Container Workflow

The repo now includes the outer development-container service and the first native cluster commands. The intended invocation shape is:

- `docker compose -f docker-compose.yaml build studiomcp`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp dag validate-fixtures`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp cluster up`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp cluster status`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp cluster storage reconcile`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp cluster deploy sidecars`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp cluster deploy server`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate cluster`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate executor`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate e2e`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate worker`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate pulsar`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate minio`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate boundary`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate ffmpeg-adapter`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate mcp-http`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate mcp-conformance`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate inference`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate observability`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate docs`

The outer container talks to the same engine through `/var/run/docker.sock`.
By default the CLI derives the host-visible `./.data/` path for kind from the outer container's `/.data/` bind mount. Set `STUDIOMCP_KIND_HOST_DATA_PATH` only as an override for non-standard Docker contexts.

## Working Rule

From Phase 1 onward, do not proceed to the next implementation phase until the Haskell build succeeds and the phase-relevant native CLI validations pass.

Target rule: for cluster and deployment work, enter the outer development container and run `studiomcp` there.
Do not add new repository helper scripts for developer workflows.
Do not rely on dynamic storage classes for local development; use the explicit `.data/` plus manual-PV flow defined in [../engineering/k8s_storage.md](../engineering/k8s_storage.md#kubernetes-storage-policy).
Current repo note: the outer-container workflow is now verified on this machine for `cluster up`, `cluster status`, `cluster deploy sidecars`, `validate cluster`, `validate executor`, `validate e2e`, `validate worker`, `validate pulsar`, `validate minio`, `validate boundary`, `validate ffmpeg-adapter`, `validate mcp-http`, `validate mcp-conformance`, `validate inference`, `validate observability`, and `validate docs`. The shipped kind values use manual host-backed PVs for stateful sidecars, and `cluster storage reconcile` applies those PVs before Helm deployment.
Use [../documentation_standards.md](../documentation_standards.md#studiomcp-documentation-standards) as the SSoT for documentation rules.

## Cross-References

- [Testing Strategy](testing_strategy.md#testing-strategy)
- [Kubernetes-Native Development Policy](../engineering/k8s_native_dev_policy.md#kubernetes-native-development-policy)
- [Kubernetes Storage Policy](../engineering/k8s_storage.md#kubernetes-storage-policy)
- [CLI Surface Reference](../reference/cli_surface.md#cli-surface-reference)
- [Documentation Standards](../documentation_standards.md#studiomcp-documentation-standards)

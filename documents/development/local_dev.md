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
- Docker Compose for launching one-off outer development containers
- Helm for deployment rendering
- kind for the local cluster
- Skaffold for Kubernetes-oriented image and deploy workflows
- host `./.data/` for explicit local PV backing paths

## Canonical Supported Commands

- `docker compose build`
- `docker compose run --rm studiomcp studiomcp dag validate-fixtures`
- `docker compose run --rm studiomcp studiomcp cluster ensure`
- `docker compose run --rm studiomcp studiomcp cluster deploy server`
- `docker compose run --rm studiomcp studiomcp test unit`
- `docker compose run --rm studiomcp studiomcp test integration` (requires cluster)
- `docker compose run --rm studiomcp studiomcp validate docs`
- `docker compose run --rm studiomcp studiomcp validate all`

Repo-owned workflows are supported through `studiomcp` subcommands in one-off outer containers.

## Focused Diagnostics

The outer container still carries lower-level tools for focused debugging and renderer inspection.
Use them as diagnostics when needed, not as the canonical repository command surface:

- `docker compose run --rm studiomcp cabal --builddir=/opt/build/studiomcp build all`
- `docker compose config`
- `docker compose run --rm studiomcp helm lint chart -f chart/values.yaml -f chart/values-kind.yaml`
- `docker compose run --rm studiomcp skaffold diagnose --yaml-only --profile kind`
- `docker compose run --rm studiomcp skaffold render --offline --profile kind --digest-source=tag`

## Current Outer-Container Workflow

The recommended local workflow follows the plan-owned readiness gates:

- `docker compose build`
- `docker compose run --rm studiomcp studiomcp dag validate-fixtures`
- `docker compose run --rm studiomcp studiomcp cluster ensure`
- `docker compose run --rm studiomcp studiomcp cluster deploy server`
- `docker compose run --rm studiomcp studiomcp test unit`
- `docker compose run --rm studiomcp studiomcp test integration`
- `docker compose run --rm studiomcp studiomcp validate cluster`
- `docker compose run --rm studiomcp studiomcp validate executor`
- `docker compose run --rm studiomcp studiomcp validate e2e`
- `docker compose run --rm studiomcp studiomcp validate worker`
- `docker compose run --rm studiomcp studiomcp validate pulsar`
- `docker compose run --rm studiomcp studiomcp validate minio`
- `docker compose run --rm studiomcp studiomcp validate boundary`
- `docker compose run --rm studiomcp studiomcp validate ffmpeg-adapter`
- `docker compose run --rm studiomcp studiomcp validate mcp-http`
- `docker compose run --rm studiomcp studiomcp validate mcp-conformance`
- `docker compose run --rm studiomcp studiomcp validate inference`
- `docker compose run --rm studiomcp studiomcp validate observability`
- `docker compose run --rm studiomcp studiomcp validate docs`

Each supported command creates its own outer container and removes it on exit.
Do not use `docker compose up` or `docker compose exec` as the development workflow.
The outer container talks to the same engine through `/var/run/docker.sock`.
By default the CLI derives the host-visible `./.data/` path for kind from the outer container's `/.data/` bind mount. Set `STUDIOMCP_KIND_HOST_DATA_PATH` only as an override for non-standard Docker contexts.

`cluster up`, `cluster status`, `cluster storage reconcile`, and `cluster deploy sidecars` remain
available as lower-level commands, but `cluster ensure` is the canonical shared-service gate and
`cluster deploy server` is the canonical application gate before live validators.

## Container Management

All repo-managed validation containers use fixed names for idempotent cleanup and repeatable
debugging.

### Fixed Container Names

| Container | Purpose | Created By |
|-----------|---------|------------|
| `studiomcp` | Kind cluster | `studiomcp cluster up` |
| `studiomcp-test-redis` | Validation Redis | session-store and horizontal-scale validators |

### Manual Cleanup

If local test infrastructure is interrupted, use predictable names for cleanup:

```bash
docker ps -a --filter "name=studiomcp"
docker rm -f studiomcp-test-redis
kind delete cluster --name studiomcp
```

## Working Rule

From Phase 1 onward, do not proceed to the next implementation phase until the Haskell build succeeds and the phase-relevant native CLI validations pass.

Target rule: repo-owned build, test, validate, and deploy workflows should prefer `studiomcp`
through one-off `docker compose run --rm` containers. Lower-level `cabal`, `helm`, and `skaffold`
invocations are for focused diagnostics when the CLI does not own that surface.
Do not add new repository helper scripts for developer workflows.
Do not rely on dynamic storage classes for local development; use the explicit `.data/` plus manual-PV flow defined in [../engineering/k8s_storage.md](../engineering/k8s_storage.md#kubernetes-storage-policy).
Current repo note: the outer-container workflow is now verified on this machine for `cluster ensure`, `cluster deploy server`, `validate cluster`, `validate executor`, `validate e2e`, `validate worker`, `validate pulsar`, `validate minio`, `validate boundary`, `validate ffmpeg-adapter`, `validate mcp-http`, `validate mcp-conformance`, `validate inference`, `validate observability`, and `validate docs`. The shipped kind values use manual host-backed PVs for stateful sidecars, and `cluster storage reconcile` applies those PVs before Helm deployment.
Use [../documentation_standards.md](../documentation_standards.md#studiomcp-documentation-standards) as the SSoT for documentation rules.

## Cross-References

- [Testing Strategy](testing_strategy.md#testing-strategy)
- [Kubernetes-Native Development Policy](../engineering/k8s_native_dev_policy.md#kubernetes-native-development-policy)
- [Kubernetes Storage Policy](../engineering/k8s_storage.md#kubernetes-storage-policy)
- [CLI Surface Reference](../reference/cli_surface.md#cli-surface-reference)
- [Documentation Standards](../documentation_standards.md#studiomcp-documentation-standards)

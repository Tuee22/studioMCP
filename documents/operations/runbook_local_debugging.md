# File: documents/operations/runbook_local_debugging.md
# Local Debugging Runbook

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite), [../tools/minio.md](../tools/minio.md#cross-references), [../tools/pulsar.md](../tools/pulsar.md#cross-references), [../reference/cli_surface.md](../reference/cli_surface.md#cross-references), [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#documentation-governance)

> **Purpose**: Canonical runbook for debugging the local `studioMCP` repository state through the containerized native CLI workflow.

## Scope

This runbook covers the repo as it exists today:

- Haskell build and test validation
- DAG validation
- Docker and kind access validation
- live MCP-surface, inference, and observability validation
- Helm and Skaffold render validation
- documentation validation

It assumes that cluster-management actions flow through the outer development container and the `studiomcp` CLI.

## Primary Checks

Run these in roughly this order when debugging repo state:

1. `cabal build all`
2. `cabal test unit-tests`
3. `cabal run studiomcp -- validate-dag examples/dags/transcode-basic.yaml`
4. `cabal run studiomcp -- validate docs`
5. `docker compose -f docker/docker-compose.yaml config`
6. `docker compose -f docker/docker-compose.yaml up -d studiomcp-env`
7. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate cluster`
8. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate worker`
9. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate mcp-http`
10. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate mcp-conformance`
11. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate inference`
12. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate observability`
13. `helm lint chart -f chart/values.yaml -f chart/values-kind.yaml`
14. `skaffold diagnose --yaml-only --profile kind`
15. `skaffold render --offline --profile kind --digest-source=tag`

## Current Outer-Container Workflow

The repo now includes the intended outer-container entrypoint and the validated native cluster, server, and observability commands:

1. `docker compose -f docker/docker-compose.yaml up -d studiomcp-env`
2. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp cluster up`
3. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp cluster status`
4. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate cluster`
5. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate executor`
6. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate e2e`
7. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate worker`
8. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate boundary`
9. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate pulsar`
10. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate minio`
11. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate ffmpeg-adapter`
12. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate mcp-http`
13. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate mcp-conformance`
14. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate inference`
15. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate observability`
16. `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp validate docs`

The outer container should talk to the mounted daemon socket at `/var/run/docker.sock`.
The CLI derives the host-visible `./.data/` path for kind from the outer container bind mount by default. Set `STUDIOMCP_KIND_HOST_DATA_PATH` only to override that discovery for a non-standard Docker context.

## Common Failure Modes

### Haskell Build or Unit Test Failure

- rerun `cabal build all`
- rerun `cabal test unit-tests`
- inspect the touched Haskell modules and matching test modules together
- do not advance the implementation phase until the build and phase-relevant tests pass

### DAG Validation Failure

- rerun `cabal run studiomcp -- validate-dag <path>`
- compare the fixture with [../domain/dag_specification.md](../domain/dag_specification.md#dag-specification)
- inspect the validator rules in the Haskell source before editing the fixture docs

### Docker, kind, or Sidecar Failure

- if you are testing the target containerized workflow, confirm the outer development container can see the selected Docker context
- confirm `/var/run/docker.sock` is mounted into the outer container and that the `/.data/` bind mount is present
- rerun the failing Helm or Skaffold command directly
- current repo note: the native `studiomcp` cluster-management, worker, server, inference, and observability workflows are verified from inside the built outer container on this machine; remaining issues are more likely to be host-context-specific or tied to persistence-enabled local releases

### Documentation Validation Failure

- inspect the changed docs together with [../documentation_standards.md](../documentation_standards.md#studiomcp-documentation-standards)
- fix metadata headers, broken links, and stale anchors before changing prose depth
- when documentation rules are unclear, use [../documentation_standards.md](../documentation_standards.md#studiomcp-documentation-standards) as the SSoT

### Helm or Skaffold Validation Failure

- rerun `helm lint chart -f chart/values.yaml -f chart/values-kind.yaml`
- rerun `skaffold diagnose --yaml-only --profile kind`
- rerun `skaffold render --offline --profile kind --digest-source=tag`

## Cleanup

Use these commands to leave the repo in a clean local validation state:

- stop any ad hoc local processes you started for debugging
- `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp cluster down` if you want to remove the kind cluster
- `docker compose -f docker/docker-compose.yaml down` if you want to stop the outer development container

## Cross-References

- [Local Development](../development/local_dev.md#local-development)
- [Testing Strategy](../development/testing_strategy.md#testing-strategy)
- [Kubernetes-Native Development Policy](../engineering/k8s_native_dev_policy.md#kubernetes-native-development-policy)
- [CLI Surface Reference](../reference/cli_surface.md#cli-surface-reference)
- [MCP Surface Reference](../reference/mcp_surface.md#mcp-surface-reference)

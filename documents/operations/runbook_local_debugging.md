# File: documents/operations/runbook_local_debugging.md
# Local Debugging Runbook

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite), [../tools/minio.md](../tools/minio.md#cross-references), [../tools/pulsar.md](../tools/pulsar.md#cross-references), [../reference/cli_surface.md](../reference/cli_surface.md#cross-references), [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md#standards)

> **Purpose**: Canonical runbook for debugging the local `studioMCP` repository state through the containerized native CLI workflow.

## Scope

This runbook covers the repo as it exists today:

- Haskell build and test validation
- DAG validation
- Docker and kind access validation
- live MCP-surface, inference, and observability validation
- Helm and Skaffold render validation
- documentation validation

It assumes that cluster-management actions flow through one-off outer development containers and the `studiomcp` CLI.

## Primary Checks

Run these in roughly this order when debugging repo state:

1. `docker compose build`
2. `docker compose run --rm studiomcp studiomcp test unit`
3. `docker compose run --rm studiomcp studiomcp validate-dag examples/dags/transcode-basic.yaml`
4. `docker compose run --rm studiomcp studiomcp cluster ensure`
5. `docker compose run --rm studiomcp studiomcp cluster deploy server`
6. `docker compose run --rm studiomcp studiomcp validate cluster`
7. `docker compose run --rm studiomcp studiomcp validate worker`
8. `docker compose run --rm studiomcp studiomcp validate mcp-http`
9. `docker compose run --rm studiomcp studiomcp validate mcp-conformance`
10. `docker compose run --rm studiomcp studiomcp validate inference`
11. `docker compose run --rm studiomcp studiomcp validate observability`
12. `docker compose run --rm studiomcp studiomcp validate docs`

## Current Outer-Container Workflow

The recommended outer-container workflow follows the plan-owned readiness gates:

1. `docker compose build`
2. `docker compose run --rm studiomcp studiomcp cluster ensure`
3. `docker compose run --rm studiomcp studiomcp cluster deploy server`
4. `docker compose run --rm studiomcp studiomcp validate cluster`
5. `docker compose run --rm studiomcp studiomcp validate executor`
6. `docker compose run --rm studiomcp studiomcp validate e2e`
7. `docker compose run --rm studiomcp studiomcp validate worker`
8. `docker compose run --rm studiomcp studiomcp validate boundary`
9. `docker compose run --rm studiomcp studiomcp validate pulsar`
10. `docker compose run --rm studiomcp studiomcp validate minio`
11. `docker compose run --rm studiomcp studiomcp validate ffmpeg-adapter`
12. `docker compose run --rm studiomcp studiomcp validate mcp-http`
13. `docker compose run --rm studiomcp studiomcp validate mcp-conformance`
14. `docker compose run --rm studiomcp studiomcp validate inference`
15. `docker compose run --rm studiomcp studiomcp validate observability`
16. `docker compose run --rm studiomcp studiomcp validate docs`

Each supported command creates its own outer container and removes it on exit.
Do not use `docker compose up` or `docker compose exec` as the debugging workflow.
The outer container should talk to the mounted daemon socket at `/var/run/docker.sock`.
The CLI derives the host-visible `./.data/` path for kind from the outer container bind mount by default. Set `STUDIOMCP_KIND_HOST_DATA_PATH` only to override that discovery for a non-standard Docker context.

`cluster up`, `cluster status`, and `cluster deploy sidecars` remain available as lower-level
commands, but `cluster ensure` is the canonical shared-service gate and `cluster deploy server` is
the canonical application gate before live validators.

## Lower-Level Diagnostics

For focused debugging, the outer container also exposes lower-level tools that are useful for
build, renderer, and manifest inspection. They remain diagnostics rather than the canonical
repository command surface:

- `docker compose run --rm studiomcp cabal --builddir=/opt/build/studiomcp build all`
- `docker compose config`
- `docker compose run --rm studiomcp helm lint chart -f chart/values.yaml -f chart/values-kind.yaml`
- `docker compose run --rm studiomcp skaffold diagnose --yaml-only --profile kind`
- `docker compose run --rm studiomcp skaffold render --offline --profile kind --digest-source=tag`

## Common Failure Modes

### Haskell Build or Unit Test Failure

- rerun `docker compose run --rm studiomcp studiomcp test unit`
- if you need a compiler-only diagnostic, rerun `docker compose run --rm studiomcp cabal --builddir=/opt/build/studiomcp build all`
- inspect the touched Haskell modules and matching test modules together
- do not advance the implementation phase until the build and phase-relevant tests pass

### DAG Validation Failure

- rerun `docker compose run --rm studiomcp studiomcp validate-dag <path>`
- compare the fixture with [../domain/dag_specification.md](../domain/dag_specification.md#dag-specification)
- inspect the validator rules in the Haskell source before editing the fixture docs

### Docker, kind, or Sidecar Failure

- if you are testing the target containerized workflow, confirm the outer development container can see the selected Docker context
- confirm `/var/run/docker.sock` is mounted into the outer container and that the `/.data/` bind mount is present
- rerun the failing Helm or Skaffold command directly
- current repo note: the native `studiomcp` cluster-management, worker, server, inference, and observability workflows are verified from inside the built outer container on this machine; remaining issues are more likely to be host-context-specific or tied to persistence-enabled local releases

### Readiness Timeout Or Blocked Startup

- rerun `docker compose run --rm studiomcp studiomcp cluster deploy server`
- inspect the structured readiness payloads instead of guessing from rollout alone:
  `curl -fsS http://localhost:8081/mcp/health/ready`
  `curl -fsS http://localhost:8081/api/health/ready`
- if the edge routes are not available yet, port-forward the backing services and inspect:
  `kubectl port-forward service/studiomcp-worker 39032:3002`
  `curl -fsS http://127.0.0.1:39032/health/ready`
- use the returned blocking reasons to distinguish auth JWKS, Redis/session-store, Pulsar,
  MinIO, workflow-runtime, or reference-model failures
- when integration tests fail during startup, inspect the preserved validator stdout and stderr in
  the harness output before rerunning blindly

### Documentation Validation Failure

- inspect the changed docs together with [../documentation_standards.md](../documentation_standards.md#studiomcp-documentation-standards)
- fix metadata headers, broken links, and stale anchors before changing prose depth
- when documentation rules are unclear, use [../documentation_standards.md](../documentation_standards.md#studiomcp-documentation-standards) as the SSoT

### Helm or Skaffold Validation Failure

- rerun `docker compose run --rm studiomcp helm lint chart -f chart/values.yaml -f chart/values-kind.yaml`
- rerun `docker compose run --rm studiomcp skaffold diagnose --yaml-only --profile kind`
- rerun `docker compose run --rm studiomcp skaffold render --offline --profile kind --digest-source=tag`

## Cleanup

Use these commands to leave the repo in a clean local validation state:

- stop any ad hoc local processes you started for debugging
- `docker compose run --rm studiomcp studiomcp cluster down` if you want to remove the kind cluster
- there is no long-running outer development container to stop; one-off `docker compose run --rm` containers exit automatically

## Cross-References

- [Local Development](../development/local_dev.md#local-development)
- [Testing Strategy](../development/testing_strategy.md#testing-strategy)
- [Kubernetes-Native Development Policy](../engineering/k8s_native_dev_policy.md#kubernetes-native-development-policy)
- [CLI Surface Reference](../reference/cli_surface.md#cli-surface-reference)
- [MCP Surface Reference](../reference/mcp_surface.md#mcp-surface-reference)

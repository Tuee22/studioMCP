# File: DEVELOPMENT_PLAN/phase-10-build-artifact-isolation.md
# Phase 10: Build Artifact Isolation and Container Configuration

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [00-overview.md](00-overview.md)

> **Purpose**: Ensure all cabal build artifacts remain in `/opt/build/` inside the container and
> close the one-command outer-container contract: single-stage Dockerfile, `tini`, no Dockerfile
> `CMD`, no compose `command`, and no persistent-container workflow guidance.

## Phase Summary

**Status**: Done
**Implementation**: `docker/Dockerfile`, `docker-compose.yaml`, `chart/templates/studiomcp_deployment.yaml`, `chart/templates/worker.yaml`, `chart/templates/bff.yaml`, `src/StudioMCP/CLI/Test.hs`, `src/StudioMCP/CLI/Cluster.hs`, `test/Session/RedisStoreSpec.hs`
**Docs to update**: `README.md`, `documents/engineering/docker_policy.md`, `documents/engineering/k8s_native_dev_policy.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/development/local_dev.md`, `documents/operations/runbook_local_debugging.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Goal

Keep all cabal build artifacts out of the workspace bind mount and finish the supported outer
development container contract: one command per container, single-stage Dockerfile, `tini` as
init, and no Dockerfile `CMD` or compose `command`.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Explicit `--builddir=/opt/build/studiomcp` in Dockerfile build and install steps | `docker/Dockerfile` | Done |
| Explicit `--builddir=/opt/build/studiomcp` baseline in CLI test entrypoints | `src/StudioMCP/CLI/Test.hs` | Done |
| One-command outer-container contract documented consistently (`docker compose run --rm`; no supported `docker compose up` or `docker compose exec` workflow) | `DEVELOPMENT_PLAN/`, governed docs, compatibility instructions | Done |
| Single-stage Dockerfile for the supported repository workflow | `docker/Dockerfile` | Done |
| `tini` installed and used as the supported init / entrypoint | `docker/Dockerfile` | Done |
| No Dockerfile `CMD` and no compose service `command` on the supported path | `docker/Dockerfile`, `docker-compose.yaml` | Done |
| Minimal compose mount policy (`/workspace`, `/.data`, Docker socket only) | `docker-compose.yaml` | Done |
| Dockerfile-owned locale and PATH environment | `docker/Dockerfile`, `docker-compose.yaml` | Done |
| Outer-container Redis test harness compatibility | `test/Session/RedisStoreSpec.hs` | Done |
| Kubernetes-owned runtime startup for server, worker, and BFF workloads | `chart/templates/studiomcp_deployment.yaml`, `chart/templates/worker.yaml`, `chart/templates/bff.yaml` | Done |
| Registry-backed local deploy path forces fresh image pulls on rollout | `src/StudioMCP/CLI/Cluster.hs` | Done |

## Build Artifact Authority

- The supported workflow relies on explicit `cabal --builddir=/opt/build/...` flags in the
  Dockerfile and repo-owned automation.
- The repo does not carry `CABAL_BUILDDIR` or a `cabal.project` `builddir` compatibility hint
  because nix-style builds ignore them.
- Build output, test logs, and compiled artifacts must stay under `/opt/build/` and never land in
  the repo tree.
- Phase 10 established the explicit-builddir baseline. Follow-on regression closure for aggregate
  `studiomcp test all` execution and inner-container harness bootstrap is closed in
  [phase-12-aggregate-test-artifact-isolation-and-warning-closure.md](phase-12-aggregate-test-artifact-isolation-and-warning-closure.md).

## Outer-Container Contract

- Every supported operation creates a fresh container with `docker compose run --rm studiomcp ...`.
  The outer container exists to run an individual command and then exit.
- `docker compose up` and `docker compose exec` are not part of the supported outer-container
  workflow.
- The supported repository Dockerfile is single-stage, installs `tini`, and defines no `CMD`.
- `docker-compose.yaml` defines no long-running service `command`.
- Compose mounts only the workspace, `./.data/`, and the Docker socket.
- Locale configuration is defined in Dockerfile `ENV`; compose inherits it and does not add an
  `environment` block or `env_file`.
- Kubernetes manifests, not the development Dockerfile or compose file, own long-lived runtime
  startup behavior for the in-cluster path.

### Validation

#### Validation Prerequisites

All validation commands use the one-command outer-container pattern:

```bash
docker compose build
```

#### Validation Gates

| Check | Evidence | Expected |
|-------|----------|----------|
| Container build | `docker compose build` | Repository container image builds with artifacts isolated under `/opt/build/` |
| Container contract probe | `docker compose run --rm studiomcp sh -lc 'command -v tini && command -v studiomcp && command -v mc && test ! -d /workspace/dist-newstyle'` | `tini`, `studiomcp`, and `mc` resolve on `PATH`; no workspace artifact leak |
| Cluster ensure | `docker compose run --rm studiomcp studiomcp cluster ensure` | Supported kind sidecar path converges |
| Cluster deploy server | `docker compose run --rm studiomcp studiomcp cluster deploy server` | Supported local deploy path converges with registry-backed image pulls |
| One-off CLI invocation | `docker compose run --rm studiomcp studiomcp test` | Supported per-command path runs both unit and integration suites without a persistent outer container |
| Docs validation | `docker compose run --rm studiomcp studiomcp validate docs` | PASS after plan and governed docs remove stale persistent-container guidance |
| Dockerfile and compose contract | `docker/Dockerfile`, `docker-compose.yaml` | Single-stage Dockerfile, no Dockerfile `CMD`, and no compose `command` |
| Registry-backed rollout freshness | `src/StudioMCP/CLI/Cluster.hs`, Helm deployments | Local cluster deploy path forces fresh pulls for the pushed registry image |

### Current Validation State

- `docker compose build` passes for the single-stage outer-container image.
- `docker compose run --rm studiomcp sh -lc 'command -v tini && command -v studiomcp && command -v mc && test ! -d /workspace/dist-newstyle'` passes.
- `docker compose run --rm studiomcp studiomcp cluster ensure` passes on the supported Kind path.
- `docker compose run --rm studiomcp studiomcp validate docs` passed for the original Phase 10 documentation closure.
- The single-stage Dockerfile, `tini` entrypoint, no-`CMD` / no-`command` contract, minimal mount policy, and registry-backed rollout freshness remain implemented on the supported path.
- Aggregate CLI test execution and the inner-container integration-harness bootstrap later reopened the workspace-leak concern, and that follow-on regression is now closed through
  [phase-12-aggregate-test-artifact-isolation-and-warning-closure.md](phase-12-aggregate-test-artifact-isolation-and-warning-closure.md).
- The local cluster deploy path now forces fresh pulls of the pushed registry image, so updated `latest` tags are not masked by kind node caches.

### Test Mapping

| Test | File |
|------|------|
| Redis-backed outer-container unit path | `test/Session/RedisStoreSpec.hs` |
| CLI test entrypoint explicit-builddir baseline | `src/StudioMCP/CLI/Test.hs` with aggregate leak closure carried forward in [phase-12-aggregate-test-artifact-isolation-and-warning-closure.md](phase-12-aggregate-test-artifact-isolation-and-warning-closure.md) |
| Container contract closure surfaces | `docker/Dockerfile`, `docker-compose.yaml`, governed docs listed below |

### Remaining Work

None. This phase is complete on the current supported path.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/docker_policy.md` - one-command container workflow, single-stage Dockerfile, `tini`, no-`CMD` contract, and mount policy
- `documents/engineering/k8s_native_dev_policy.md` - Kubernetes-owned runtime startup on the in-cluster path
- `documents/reference/cli_reference.md` - CLI examples remain aligned with `docker compose run --rm`
- `documents/reference/cli_surface.md` - command-surface and bootstrap guidance stay aligned with the one-command workflow
- `documents/development/local_dev.md` - local workflow examples remove persistent-container guidance
- `documents/operations/runbook_local_debugging.md` - debugging workflow matches the one-command container contract
- `DEVELOPMENT_PLAN/system-components.md` - authoritative container and build-artifact inventory entry
- `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` - pending and completed cleanup for stale container workflow guidance and Dockerfile defaults

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [README.md](README.md), [00-overview.md](00-overview.md), and [system-components.md](system-components.md) aligned if the outer-container contract changes.
- Keep [development_plan_standards.md](development_plan_standards.md#l-container-execution-context) aligned if command context rules change.
- Keep [phase-12-aggregate-test-artifact-isolation-and-warning-closure.md](phase-12-aggregate-test-artifact-isolation-and-warning-closure.md) aligned if repo-owned artifact-isolation mechanics change again.

## Cross-References

- [README.md](README.md#phase-overview)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md#l-container-execution-context)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [phase-12-aggregate-test-artifact-isolation-and-warning-closure.md](phase-12-aggregate-test-artifact-isolation-and-warning-closure.md)

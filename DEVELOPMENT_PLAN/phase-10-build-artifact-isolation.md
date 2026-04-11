# File: DEVELOPMENT_PLAN/phase-10-build-artifact-isolation.md
# Phase 10: Build Artifact Isolation and Container Configuration

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [00-overview.md](00-overview.md)

> **Purpose**: Ensure all cabal build artifacts remain in `/opt/build/` inside the container,
> enforce ephemeral container operation, minimal mount policy, and proper environment configuration.

## Phase Summary

**Status**: Done
**Implementation**: `docker/Dockerfile`, `docker-compose.yaml`, `src/StudioMCP/CLI/Test.hs`, `test/Session/RedisStoreSpec.hs`
**Docs to update**: `documents/engineering/docker_policy.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`

### Goal

Keep all cabal build artifacts out of the workspace bind mount and define the supported outer
development container as an ephemeral, minimal-mount environment.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Explicit `--builddir=/opt/build/studiomcp` in Dockerfile build and install steps | `docker/Dockerfile` | Done |
| Explicit `--builddir=/opt/build/studiomcp` in CLI test entrypoints | `src/StudioMCP/CLI/Test.hs` | Done |
| Ephemeral outer-container contract (`env` target has no `CMD`; compose service has no `command`) | `docker/Dockerfile`, `docker-compose.yaml` | Done |
| Minimal compose mount policy (`/workspace`, `/.data`, Docker socket only) | `docker-compose.yaml` | Done |
| Dockerfile-owned locale and PATH environment | `docker/Dockerfile`, `docker-compose.yaml` | Done |
| Outer-container Redis test harness compatibility | `test/Session/RedisStoreSpec.hs` | Done |

## Build Artifact Authority

- The supported workflow relies on explicit `cabal --builddir=/opt/build/studiomcp` flags in the
  Dockerfile and CLI.
- The repo does not carry `CABAL_BUILDDIR` or a `cabal.project` `builddir` compatibility hint
  because nix-style builds ignore them.
- Build output, test logs, and compiled artifacts must stay under `/opt/build/studiomcp` and never
  land in the repo tree.

## Outer-Container Contract

- The `env` image target has no `CMD`, and `docker-compose.yaml` defines no long-running service
  `command`.
- The outer development path uses `docker compose run --rm studiomcp ...` for each operation.
- Compose mounts only the workspace, `./.data/`, and the Docker socket.
- Locale configuration is defined in Dockerfile `ENV`; compose inherits it and does not add an
  `environment` block or `env_file`.
- The production image remains separate from this rule and keeps its runtime `ENTRYPOINT`/`CMD`
  because it runs in-cluster, not as the outer development container.

### Validation

#### Validation Prerequisites

All validation commands use the ephemeral outer-container pattern:

```bash
docker compose build
```

#### Validation Gates

| Check | Command | Expected |
|-------|---------|----------|
| Container build | `docker compose build` | `env` image builds and installs `studiomcp` |
| Unit tests | `docker compose run --rm studiomcp studiomcp test unit` | 867 examples, 0 failures on the current worktree |
| Docs validation | `docker compose run --rm studiomcp studiomcp validate docs` | PASS |
| CLI availability | `docker compose run --rm studiomcp sh -lc 'command -v studiomcp'` | `/usr/local/bin/studiomcp` |
| Artifact leak check | `docker compose run --rm studiomcp sh -lc 'test ! -d /workspace/dist-newstyle'` | Success |

### Current Validation State

- `docker compose run --rm studiomcp studiomcp test unit` passes with 867 examples and 0 failures on the current worktree.
- Build and test output lands under `/opt/build/studiomcp/...`, not under `dist-newstyle/` in the workspace bind mount.
- The outer `studiomcp` container resolves `studiomcp` on `PATH` at `/usr/local/bin/studiomcp`.
- `test/Session/RedisStoreSpec.hs` uses container-aware Docker host resolution so the Redis-backed unit path works from the outer container.

### Test Mapping

| Test | File |
|------|------|
| Redis-backed outer-container unit path | `test/Session/RedisStoreSpec.hs` |
| CLI test entrypoint with explicit builddir | `src/StudioMCP/CLI/Test.hs` exercised by `docker compose run --rm studiomcp studiomcp test unit` |

### Remaining Work

None. This phase is complete on the current supported path.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/docker_policy.md` - outer-container workflow, builddir isolation, and mount policy
- `DEVELOPMENT_PLAN/system-components.md` - authoritative build-artifact inventory entry
- `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` - completed cleanup for stale builddir compatibility settings

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [README.md](README.md) and [00-overview.md](00-overview.md) aligned if the outer-container contract changes.
- Keep [development_plan_standards.md](development_plan_standards.md#l-container-execution-context) aligned if command context rules change.

## Cross-References

- [README.md](README.md#phase-overview)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md#l-container-execution-context)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

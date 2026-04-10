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
**Docs to update**: `documents/engineering/docker_policy.md`

### Goal

Enforce build artifact isolation and establish the canonical container configuration doctrine:
- Build artifacts isolated to `/opt/build/studiomcp`
- Ephemeral container model (no persistent daemon)
- Minimal mount policy (workspace, .data, docker socket only)
- Environment variables set in Dockerfile only

### Deliverables

| Item | Status |
|------|--------|
| Explicit --builddir flag in CLI | Done |
| Dockerfile build commands use --builddir | Done |
| Ephemeral outer-container model (`env` target has no `CMD`; compose service has no `command`) | Done |
| Minimal mount policy | Done |
| Environment in Dockerfile only | Done |

## Build Artifact Isolation

### Explicit --builddir Flag in CLI

- The `studiomcp` CLI passes `--builddir=/opt/build/studiomcp` to all cabal invocations
- This is the canonical enforcement mechanism for nix-style builds

### Dockerfile Build Commands

- Dockerfile build commands use `--builddir=/opt/build/studiomcp` explicitly
- The `CABAL_BUILDDIR` environment variable is also set (for documentation/legacy v1 commands)

### Important Note on CABAL_BUILDDIR

Cabal's nix-style builds (v2-commands, which are the default in modern cabal) **do not respect**
the `CABAL_BUILDDIR` environment variable or `builddir` settings in `cabal.project`.

The only reliable enforcement is the explicit `--builddir` command-line flag passed to each
cabal invocation.

## Ephemeral Container Model

The outer development container operates in ephemeral mode:

- Dockerfile `env` target has no `CMD`
- docker-compose.yaml service has no `command`
- All operations use `docker compose run --rm -it studiomcp <cmd>`
- No long-running container; container removed after each command
- Interactive sessions: `docker compose run --rm -it studiomcp sh`

The production image is separate from this rule. It retains its runtime `ENTRYPOINT`/`CMD`
because it runs inside the cluster as the application image, not as the outer development
container.

This model ensures:
- Clean state for each command
- No stale processes or state accumulation
- Consistent behavior across invocations

## Minimal Mount Policy

docker-compose.yaml volumes are limited to:

| Mount | Purpose |
|-------|---------|
| `.:/workspace` | Source code access |
| `./.data:/.data` | Persistent state |
| `/var/run/docker.sock:/var/run/docker.sock` | Docker operations |

Removed:
- `${HOME}/.docker:/root/.docker:ro` - not needed

## Environment Configuration

- `LANG` and `LC_ALL` set only in Dockerfile `ENV`
- docker-compose.yaml has no `environment` block (inherits from image)
- No `env_file` references

### Validation

All validation commands use the ephemeral container pattern:

```bash
# Build container
docker compose build

# Run unit tests
docker compose run --rm studiomcp studiomcp test unit

# Run doc validators
docker compose run --rm studiomcp studiomcp validate docs

# Verify no dist-newstyle on host (run on host, not in container)
ls -la dist-newstyle 2>/dev/null && echo "FAIL: dist-newstyle exists" || echo "PASS: no dist-newstyle"

# Interactive session
docker compose run --rm -it studiomcp sh
```

### Redis Test Infrastructure Fix

The unit tests previously failed with "Timed out waiting for temporary Redis container to
become ready" because the test infrastructure did not correctly resolve Docker host networking
when running inside the outer container.

**Fix applied to `test/Session/RedisStoreSpec.hs`:**
- Added `resolveDockerHost` to detect container environment and use appropriate host address
- Uses `host.docker.internal` for Docker Desktop or default gateway for Linux Docker
- Uses `/.dockerenv` detection for container context
- Fixed container naming with `testRedisContainerName` for idempotent cleanup

### Verified Working

- Build artifacts correctly go to `/opt/build/studiomcp/` (confirmed in test output paths)
- No `dist-newstyle` directory leaks to the workspace bind mount
- `docker compose run --rm studiomcp studiomcp validate docs` passes
- `docker compose run --rm studiomcp studiomcp test unit` passes (846 examples, 0 failures)
- The CLI correctly passes `--builddir=/opt/build/studiomcp` to all cabal invocations

### Integration Tests

Integration tests require a full Kind cluster setup (`docker compose run --rm studiomcp studiomcp cluster ensure`) and are
validated separately through the cluster infrastructure path.

### Remaining Work

None. This phase is complete on the current supported path.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/docker_policy.md` - Document build artifact isolation, ephemeral model, minimal mounts

**Product docs to create/update:**
- None.

**Cross-references to add:**
- `DEVELOPMENT_PLAN/README.md` - Phase 10 already in phase overview table
- `DEVELOPMENT_PLAN/development_plan_standards.md` - Update container execution context

## Implementation Details

### docker-compose.yaml Target State

```yaml
services:
  studiomcp:
    build:
      context: .
      dockerfile: docker/Dockerfile
      target: env
    init: true
    stdin_open: true
    tty: true
    working_dir: /workspace
    volumes:
      - .:/workspace
      - ./.data:/.data
      - /var/run/docker.sock:/var/run/docker.sock
```

Note: No `command`, no `environment` block (inherits from Dockerfile).

### Dockerfile Target State (env target)

```dockerfile
ENV LANG="C.UTF-8" \
    LC_ALL="C.UTF-8" \
    CABAL_BUILDDIR="/opt/build/studiomcp" \
    PATH="/root/.ghcup/bin:/root/.cabal/bin:/usr/local/bin:${PATH}"

# No CMD - ephemeral outer-container model
```

### Why --builddir Flag is Required

- `CABAL_BUILDDIR` environment variable does **not** affect nix-style builds (v2-build, build, etc.)
- The `builddir` setting in `cabal.project` is ignored for nix-style builds with a warning
- Only the explicit `--builddir=<path>` command-line flag reliably redirects build artifacts
- The Dockerfile already used `--builddir` in its build commands; this phase ensures the CLI does too

## Cross-References

- [README.md](README.md#phase-overview)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md#container-execution-context)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [Cabal builddir issue #2484](https://github.com/haskell/cabal/issues/2484)
- [Cabal builddir not honoured #6849](https://github.com/haskell/cabal/issues/6849)

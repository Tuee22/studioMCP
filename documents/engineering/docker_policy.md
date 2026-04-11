# File: documents/engineering/docker_policy.md
# Docker Policy

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [k8s_native_dev_policy.md](k8s_native_dev_policy.md#cross-references), [k8s_storage.md](k8s_storage.md#cross-references), [../development/local_dev.md](../development/local_dev.md#cross-references), [../architecture/cli_architecture.md](../architecture/cli_architecture.md#cross-references), [../../README.md](../../README.md#docker-strategy), [../../DEVELOPMENT_PLAN.md](../../DEVELOPMENT_PLAN.md#documentation-governance)

> **Purpose**: Canonical policy for the repository's Docker usage, including the no-scripts rule, the outer development container, and the runtime image boundary.

## Summary

`studioMCP` uses Docker for two different purposes:

- an outer development container that owns local build and cluster-management workflows
- a runtime image for the MCP server that is built locally but runs only inside the kind cluster

These are different concerns and must stay separate in both code and documentation.

## No Scripts Rule

The repository must not use checked-in shell helper scripts as the supported command surface.

- do not add new files under a top-level `scripts/` directory
- do not make shell wrappers the authoritative way to build, validate, deploy, or manage the cluster
- every supported operational command must exist as a Haskell CLI subcommand in `studiomcp`

Allowed:

- Dockerfile instructions
- incidental shell usage inside third-party images when the repo does not own that command surface

Not allowed:

- repository-owned shell helpers for cluster lifecycle
- repository-owned shell helpers for docs validation
- repository-owned shell helpers for Helm, kind, or integration orchestration

## Two-Image Strategy

The single Dockerfile under `docker/Dockerfile` must remain multi-stage.

### Outer Development Container

The outer development container exists to run the Haskell toolchain and the `studiomcp` CLI in a reproducible environment.

It must include:

- GHC and cabal-install
- Docker CLI tooling
- `kind`
- `kubectl`
- `helm`
- the `studiomcp` CLI binary or build path

This is the container that local humans and LLMs interact with.

### Runtime Image

The runtime image exists to run the actual MCP server in Kubernetes.

- it is built by the multi-stage Dockerfile
- it is not the primary local interactive development environment
- it should be scheduled only inside the kind cluster during local development

## Docker Context Handling

The outer development container must talk to the same Docker context the host user has selected.

Best-practice requirements:

- launch the outer container through the active host Docker context
- inside the outer container, Docker CLI calls use the mounted daemon socket at `/var/run/docker.sock`
- do not mount host-side client proxy sockets such as per-user Colima socket paths directly into the container
- derive the host-visible `./.data/` source for kind extra mounts from the outer container's bind mount by default, and use `STUDIOMCP_KIND_HOST_DATA_PATH` only as an override when discovery is not sufficient
- provide private registry credentials to the CLI when needed through `STUDIOMCP_HARBOR_USERNAME`
  and `STUDIOMCP_HARBOR_PASSWORD`, not by mounting host Docker config

Current implementation detail:

- the Compose file mounts `/var/run/docker.sock` into the outer container
- the Compose file binds host `./.data/` into `/.data/`, and the CLI derives the host-visible source path for kind from that bind mount via `docker inspect`

The goal is not Docker-in-Docker. The goal is idiomatic `kind` behavior inside the outer container against the selected host Docker engine.

## Build Artifact Isolation

All cabal build artifacts must remain inside the container and never leak to the host filesystem through bind mounts.

### Enforcement Mechanism

Cabal's nix-style builds (v2-commands) do not respect the `CABAL_BUILDDIR` environment variable or `builddir` settings in `cabal.project`. The only reliable enforcement is the explicit `--builddir` command-line flag, so the repository does not rely on either compatibility hint.

Build artifact isolation is enforced through:

1. **Dockerfile build commands**: Use `--builddir=/opt/build/studiomcp` explicitly
2. **CLI test commands**: The `studiomcp` CLI passes `--builddir=/opt/build/studiomcp` to all cabal invocations

This ensures:

- all `cabal build`, `cabal test`, and `cabal install` invocations write to `/opt/build/studiomcp` inside the container
- no `dist-newstyle` directory appears in the workspace bind mount
- no build artifacts leak to the host filesystem

### Important Note

The repository intentionally does not set `CABAL_BUILDDIR` or a `cabal.project` `builddir` value because they do not affect nix-style builds. The primary and only supported enforcement is the explicit `--builddir` flag.

Forbidden:

- running `cabal` commands outside the outer container that write to the workspace
- running `cabal` commands inside the container without `--builddir=/opt/build/studiomcp`
- manually specifying `--builddir` to a workspace-relative path

## Minimal Mount Policy

docker-compose.yaml volumes are limited to:

| Mount | Purpose |
|-------|---------|
| `.:/workspace` | Source code access |
| `./.data:/.data` | Persistent state |
| `/var/run/docker.sock:/var/run/docker.sock` | Docker operations |

Removed/forbidden mounts:
- `${HOME}/.docker:/root/.docker:ro` - not needed

Rules:
- The `./.data/` data path is not disposable container scratch space
- It must survive container removal
- It is the only supported source path for local persistent volumes managed by the CLI
- The CLI is responsible for ensuring the second bind into kind node containers is present before Helm workloads that need storage are deployed

## Environment Variable Policy

Environment variables (`LANG`, `LC_ALL`, `PATH`) are set only in the Dockerfile `ENV` block.

Rules:
- docker-compose.yaml has no `environment` block (inherits from image)
- No `env_file` references
- Cluster secrets are managed by the CLI on deploy, not via environment variables

## Compose Role

`docker-compose.yaml` exists to run ephemeral development containers via `docker compose run --rm`.

The ephemeral container model means:
- Dockerfile `env` target has no `CMD`
- docker-compose.yaml service has no `command`
- All operations use `docker compose run --rm -it studiomcp <cmd>`
- No long-running container; container removed after each command
- Interactive sessions: `docker compose run --rm -it studiomcp sh`

Compose must not become:

- the canonical runtime topology for the MCP server
- the place where the full application stack lives long term
- a substitute for the Haskell CLI
- a persistent daemon via `docker compose up -d`

## LLM Operating Rule

When an LLM needs to manage the local Kubernetes lifecycle, it should do so using ephemeral containers and invoking the Haskell CLI.

The canonical shape is:

```bash
docker compose run --rm studiomcp studiomcp <subcommand...>
```

Examples of intended usage:

- `docker compose run --rm studiomcp studiomcp cluster ensure`
- `docker compose run --rm studiomcp studiomcp cluster deploy sidecars`
- `docker compose run --rm studiomcp studiomcp cluster deploy server`
- `docker compose run --rm studiomcp studiomcp test unit`
- `docker compose run --rm -it studiomcp sh` (interactive session)

## Container Naming Policy

All containers created by the `studioMCP` CLI and validation tools must use fixed, predictable names.

Required naming convention:

| Purpose | Container Name | Notes |
|---------|---------------|-------|
| Kind cluster | `studiomcp` | Via `STUDIOMCP_KIND_CLUSTER` env var |
| Local image registry | `studiomcp-harbor-registry` | Used when `STUDIOMCP_HARBOR_REGISTRY` is not set |
| Validation Redis | `studiomcp-test-redis` | Used by `withTemporaryRedisConfig` |
| Future test containers | `studiomcp-test-{service}` | Follow this pattern for new services |

Rationale:

- Idempotent operations: Re-running a command automatically cleans up any stale container with the same name
- No orphaned containers: Fixed names prevent accumulation of randomly-named containers from interrupted tests
- Predictable state: `docker ps -a --filter "name=studiomcp"` shows all project containers

Implementation pattern for temporary containers:

```haskell
-- Cleanup-before-start ensures idempotent behavior
_ <- readProcessWithExitCode "docker" ["rm", "-f", containerName] ""
_ <- readProcessWithExitCode "docker" ["run", "-d", "--name", containerName, ...] ""
```

Forbidden:

- `docker run -d` without `--name` for project containers
- Random or timestamp-based container names for validation infrastructure

## Harbor-Compatible Registry Policy

All Helm deploys to the cluster pull application containers from the configured registry:

- CLI is responsible to idempotently push images before deploy
- Push only when image digest differs from the registry manifest when that digest is available
- Helm charts reference the configured registry repository, never local-only image loading
- No direct `kind load docker-image` usage; application images flow through the configured registry
- `STUDIOMCP_HARBOR_REGISTRY` can point at a real Harbor registry; local kind defaults to a
  CLI-managed `localhost:5001` registry container

The CLI commands for registry integration:

```bash
# Push images to the configured registry
docker compose run --rm studiomcp studiomcp cluster push-images

# Full deploy (includes image push if needed)
docker compose run --rm studiomcp studiomcp cluster deploy server
```

## Current Repo Note

This policy is materially embodied. The legacy top-level `scripts/` directory and Docker shell assets are gone, the multi-stage Dockerfile defines both `env` and `production` targets, the outer-container workflow is ephemeral, build artifacts stay under `/opt/build/studiomcp`, and cluster deploys use registry-backed image pulls with CLI-managed secrets.

## Cross-References

- [Kubernetes-Native Development Policy](k8s_native_dev_policy.md#kubernetes-native-development-policy)
- [Kubernetes Storage Policy](k8s_storage.md#kubernetes-storage-policy)
- [CLI Architecture](../architecture/cli_architecture.md#cli-architecture)
- [CLI Surface Reference](../reference/cli_surface.md#cli-surface-reference)

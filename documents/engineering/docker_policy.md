# File: documents/engineering/docker_policy.md
# Docker Policy

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [k8s_native_dev_policy.md](k8s_native_dev_policy.md#cross-references), [k8s_storage.md](k8s_storage.md#cross-references), [../development/local_dev.md](../development/local_dev.md#cross-references), [../architecture/cli_architecture.md](../architecture/cli_architecture.md#cross-references), [../../README.md](../../README.md#docker-strategy), [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md#standards)

> **Purpose**: Canonical policy for the repository's Docker usage, including the no-scripts rule, the outer development container, and the runtime image boundary.

## Summary

`studioMCP` uses one repository container image in two execution contexts:

- one-off outer development containers that own local build and cluster-management workflows
- in-cluster application containers scheduled by Helm inside kind or other Kubernetes environments

These contexts share a Dockerfile but not startup semantics. Compose is only a one-command
launcher. Kubernetes manifests own long-lived runtime startup.

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

## Single-Image Strategy

The single Dockerfile under `docker/Dockerfile` must remain single-stage.

### One-Off Outer Development Container

The outer development container exists to run the Haskell toolchain and the `studiomcp` CLI in a reproducible environment.

It must include:

- GHC and cabal-install
- Docker CLI tooling
- `kind`
- `kubectl`
- `helm`
- `tini`
- the `studiomcp` CLI binary or build path

This is the image that local humans and LLMs invoke through `docker compose run --rm`.

### In-Cluster Runtime Use

The same image is also pushed to the registry and run in Kubernetes.

- Helm manifests choose the runtime startup command explicitly at the workload layer
- the supported local kind deploy path forces fresh pulls of the pushed registry image
- the Dockerfile carries no default `CMD`
- Compose is not the runtime topology
- the image should be scheduled only inside the kind cluster during local development

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

1. **Dockerfile and repo-owned cabal commands**: Use explicit `--builddir=/opt/build/studiomcp`
   paths
2. **CLI test execution**: The `studiomcp` CLI builds `test:<suite>`, resolves the produced
   binary with `cabal list-bin`, and executes that binary instead of relying on `cabal test`
3. **Integration tests inside the outer container**: Reuse the installed `studiomcp` on `PATH`
   instead of self-bootstrapping a second CLI executable through repo-owned cabal commands

This ensures:

- canonical repo build and test output stays under `/opt/build/studiomcp` inside the container
- no `dist-newstyle` directory appears in the workspace bind mount
- no build artifacts leak to the host filesystem
- Cabal bootstrap either uses the image-baked package index or refreshes from outside `/workspace`,
  so CLI startup cannot recreate workspace-local `dist-newstyle` metadata

### Important Note

The repository intentionally does not set `CABAL_BUILDDIR` or a `cabal.project` `builddir` value because they do not affect nix-style builds. The primary and only supported enforcement is the explicit `--builddir` flag.

For the supported local cluster path, the CLI also compares local and remote image config digests
before publishing to Harbor and waits for managed-registry upload readiness before the first
`skopeo copy`, so a clean post-prune deploy does not republish unchanged images or race the first
large push.

Forbidden:

- running `cabal` commands outside the outer container that write to the workspace
- running repo-owned `cabal` commands inside the container without an explicit `--builddir` under `/opt/build/`
- relying on repo-owned `cabal test` or `cabal install` automation paths that recreate workspace `dist-newstyle`
- self-bootstrapping a second `studiomcp` executable inside the outer container through repo-owned cabal commands
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

`docker-compose.yaml` exists to launch one-off development containers via `docker compose run --rm`.

The one-command container model means:
- The Dockerfile uses `ENTRYPOINT ["tini", "--"]`
- The Dockerfile has no `CMD`
- `docker-compose.yaml` has no service `command`
- All operations use `docker compose run --rm studiomcp <cmd>`
- No long-running container; each command gets its own container
- Interactive sessions use `docker compose run --rm -it studiomcp sh`
- `docker compose up` and `docker compose exec` are not supported outer-container workflows

Compose must not become:

- the canonical runtime topology for the MCP server
- the place where the full application stack lives long term
- a substitute for the Haskell CLI
- a persistent daemon or `exec`-driven shell loop

## LLM Operating Rule

When an LLM needs to manage the local Kubernetes lifecycle, it should do so using one-off
containers and invoking the Haskell CLI.

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
| Validation Redis | `studiomcp-test-redis` | Used by `withTemporaryRedisConfig` |
| Future test containers | `studiomcp-test-{service}` | Follow this pattern for new services |

The in-cluster Harbor deployment is Helm-managed Kubernetes state, not a Docker container naming
requirement for the outer-container workflow.

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
- `STUDIOMCP_HARBOR_REGISTRY` can point at another Harbor-compatible registry host when an override
  is required
- The default local Kind path uses the in-cluster Harbor deployment exposed at
  `host.docker.internal:32443` for pushes from the outer development container and
  `localhost:32443` for pulls from Kind nodes

The CLI commands for registry integration:

```bash
# Push images to the configured registry
docker compose run --rm studiomcp studiomcp cluster push-images

# Full deploy (includes image push if needed)
docker compose run --rm studiomcp studiomcp cluster deploy server
```

## Current Repo Note

This policy is materially embodied. The legacy top-level `scripts/` directory and Docker shell
assets are gone, the Dockerfile is single-stage, the image entrypoint is `tini`, the Dockerfile
has no `CMD`, the outer-container workflow is one command per `docker compose run --rm`, build
artifacts stay under `/opt/build/`, and cluster deploys use registry-backed image pulls
with Kubernetes-owned runtime startup and fresh local repulls of the pushed registry image.

## Cross-References

- [Kubernetes-Native Development Policy](k8s_native_dev_policy.md#kubernetes-native-development-policy)
- [Kubernetes Storage Policy](k8s_storage.md#kubernetes-storage-policy)
- [CLI Architecture](../architecture/cli_architecture.md#cli-architecture)
- [CLI Surface Reference](../reference/cli_surface.md#cli-surface-reference)

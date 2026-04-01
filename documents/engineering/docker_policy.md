# File: documents/engineering/docker_policy.md
# Docker Policy

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [k8s_native_dev_policy.md](k8s_native_dev_policy.md#cross-references), [k8s_storage.md](k8s_storage.md#cross-references), [../development/local_dev.md](../development/local_dev.md#cross-references), [../architecture/cli_architecture.md](../architecture/cli_architecture.md#cross-references), [../../README.md](../../README.md#docker-strategy), [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#documentation-governance)

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

- mount the host Docker config directory so the container sees the same registry auth material and client metadata it needs
- launch the outer container through the active host Docker context
- inside the outer container, point Docker CLI calls at the mounted daemon socket at `/var/run/docker.sock`
- do not mount host-side client proxy sockets such as per-user Colima socket paths directly into the container
- derive the host-visible `./.data/` source for kind extra mounts from the outer container's bind mount by default, and use `STUDIOMCP_KIND_HOST_DATA_PATH` only as an override when discovery is not sufficient

Current implementation detail:

- the Compose file mounts `/var/run/docker.sock` into the outer container and sets `DOCKER_HOST=unix:///var/run/docker.sock`
- the Compose file binds host `./.data/` into `/.data/`, and the CLI derives the host-visible source path for kind from that bind mount via `docker inspect`

The goal is not Docker-in-Docker. The goal is idiomatic `kind` behavior inside the outer container against the selected host Docker engine.

## Data Mount Rule

The outer development container must bind host `./.data/` into container `/.data/`.

- this data path is not disposable container scratch space
- it must survive `docker compose down`
- it is the only supported source path for local persistent volumes managed by the CLI
- the CLI is responsible for ensuring the second bind into kind node containers is present before Helm workloads that need storage are deployed

## Compose Role

`docker/docker-compose.yaml` exists to start the outer development container and attach it to the active Docker context.

Compose must not become:

- the canonical runtime topology for the MCP server
- the place where the full application stack lives long term
- a substitute for the Haskell CLI

## LLM Operating Rule

When an LLM needs to manage the local Kubernetes lifecycle, it should do so by entering the outer development container and invoking the Haskell CLI.

The canonical shape is:

```bash
docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp <subcommand...>
```

Examples of intended usage:

- `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp cluster up`
- `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp cluster deploy sidecars`
- `docker compose -f docker/docker-compose.yaml exec studiomcp-env studiomcp cluster deploy server`

## Container Naming Policy

All containers created by the `studioMCP` CLI and validation tools must use fixed, predictable names.

Required naming convention:

| Purpose | Container Name | Notes |
|---------|---------------|-------|
| Kind cluster | `studiomcp` | Via `STUDIOMCP_KIND_CLUSTER` env var |
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

## Current Repo Note

This policy is now materially embodied. The legacy top-level `scripts/` directory and Docker shell assets are gone, the multi-stage Dockerfile now defines both `env` and `production` targets, and the outer-container workflow has been verified on this machine against a running kind cluster, deployed sidecars, and the deployed server. Remaining work is now incremental: storage-backed Helm releases under non-default values, broader host-context coverage, and any additional CLI ergonomics the next plan chooses to add.

## Cross-References

- [Kubernetes-Native Development Policy](k8s_native_dev_policy.md#kubernetes-native-development-policy)
- [Kubernetes Storage Policy](k8s_storage.md#kubernetes-storage-policy)
- [CLI Architecture](../architecture/cli_architecture.md#cli-architecture)
- [CLI Surface Reference](../reference/cli_surface.md#cli-surface-reference)

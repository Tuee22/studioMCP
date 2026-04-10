# File: DEVELOPMENT_PLAN/phase-6-cluster-control-plane-parity.md
# Phase 6: Cluster Control-Plane Parity

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the supported Kind and Helm deployment path that exposes the canonical
> control-plane contract in local cluster development, with unified ingress routing for web
> services, Harbor-compatible registry integration, and CLI-owned storage reconciliation.

## Phase Summary

**Status**: Done
**Implementation**: `chart/Chart.yaml`, `chart/templates/ingress.yaml`, `chart/values.yaml`, `chart/values-kind.yaml`, `kind/kind_config.yaml`, `src/StudioMCP/CLI/Cluster.hs`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/k8s_storage.md`, `documents/operations/runbook_local_debugging.md`

### Goal

Ensure the Kind and Helm workflow exposes the canonical control-plane contract with:
- Unified ingress routing for all web services on a single port
- Harbor-compatible registry integration for application images
- CLI-owned storage reconciliation and explicit `studiomcp-manual` persistence policy
- CLI-managed secrets (no env files)

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Helm chart dependencies | `chart/Chart.yaml` | Done |
| Ingress templates | `chart/templates/ingress.yaml` | Done |
| Kind config | `kind/kind_config.yaml` | Done |
| Cluster CLI | `src/StudioMCP/CLI/Cluster.hs` | Done |
| Unified ingress for web services | `chart/templates/ingress.yaml`, `chart/values-kind.yaml` | Done |
| Harbor-compatible registry integration | `src/StudioMCP/CLI/Cluster.hs`, `kind/kind_config.yaml` | Done |
| CLI-owned storage reconciliation | `src/StudioMCP/CLI/Cluster.hs`, `chart/values.yaml`, `chart/values-kind.yaml` | Done |
| CLI-managed secrets | `src/StudioMCP/CLI/Cluster.hs`, `chart/values.yaml` | Done |

## Unified Ingress Routing

All web services route through a single reverse proxy on the local ingress port. The Kind cluster
also exposes the object-storage data-plane port for presigned S3 URLs, as required by the Phase 4
control-plane/data-plane split.

| Path | Service | Port | Notes |
|------|---------|------|-------|
| `/mcp` | MCP listener | 3000 | MCP protocol surface |
| `/api` | BFF | 3002 | Browser session endpoints |
| `/kc` | Keycloak | 80 | Identity provider |
| `/minio` | MinIO Console | 9001 | Object storage admin |

### Ingress Configuration

A single ingress resource handles the web path routing. Prefixes are preserved at the edge; MCP,
BFF, and Keycloak all accept their canonical public prefixes directly.

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/upstream-hash-by: "$http_mcp_session_id"
  hosts:
    - host: ""
      paths:
        - path: /mcp
          pathType: Prefix
          service: studiomcp
          port: 3000
        - path: /api
          pathType: Prefix
          service: bff
          port: 3002
        - path: /kc
          pathType: Prefix
          service: keycloak
          port: 80
        - path: /minio
          pathType: Prefix
          service: minio-console
          port: 9001
```

## Harbor-Compatible Registry Integration

All Helm deploys to the cluster pull application containers from the configured registry:

- CLI is responsible to idempotently push images before deploy
- Push only when image digest differs from the registry manifest when that digest is available
- Helm charts reference the registry image repository instead of relying on `kind load docker-image`
- `STUDIOMCP_HARBOR_REGISTRY` can point at a real Harbor registry; local kind defaults to
  `localhost:5001` backed by a CLI-managed local registry container

### CLI Registry Commands

```bash
# Push images to the configured registry (idempotent, only on change when digest is available)
docker compose run --rm studiomcp studiomcp cluster push-images

# Deploy with registry pull
docker compose run --rm studiomcp studiomcp cluster deploy server
```

### Image Push Logic

The CLI compares local image digests with the registry manifest:
1. Build image locally if needed
2. Query the registry for existing image digest
3. Push only if digest differs or image not present
4. Helm values reference the registry repository and tag

## CLI-Owned Storage Reconciliation

The supported Kind path now includes explicit storage reconciliation before Helm deployment.

- the supported cluster deploy-sidecars, deploy-server, and ensure flows all call
  `clusterStorageReconcile`
- reconciliation deletes the default `standard` StorageClass when present and creates
  `studiomcp-manual`
- the CLI pre-creates the PV set that the Helm subcharts expect and backs those volumes from
  `./.data/`
- the storage contract is validated through the storage-policy validator

### Storage Commands

```bash
# Reconcile the local StorageClass and persistent volumes
docker compose run --rm studiomcp studiomcp cluster storage reconcile

# Delete one reconciled persistent volume by name
docker compose run --rm studiomcp studiomcp cluster storage delete <name>
```

## Secrets Management

- No environment files in compose or Helm
- Cluster passwords and secrets are populated by the CLI tool on deploy
- CLI creates Kubernetes secrets idempotently before Helm install
- Helm subcharts consume existing Kubernetes secrets by name

### CLI Secrets Commands

```bash
# Create/update secrets before deploy
docker compose run --rm studiomcp studiomcp cluster ensure-secrets

# Full deploy (includes secrets)
docker compose run --rm studiomcp studiomcp cluster deploy server
```

### Secrets Created by CLI

| Secret | Namespace | Contents |
|--------|-----------|----------|
| `studiomcp-postgres-credentials` | `default` | PostgreSQL user, postgres, repmgr, and pgpool passwords |
| `studiomcp-redis-credentials` | `default` | Redis password |
| `studiomcp-minio-credentials` | `default` | MinIO root credentials |
| `studiomcp-keycloak-admin` | `default` | Keycloak admin password and external database connection fields |

### Validation

#### Validation Prerequisites

All validation commands use the ephemeral container pattern:

```bash
docker compose build
```

#### Validation Gates

| Check | Command | Expected |
|-------|---------|----------|
| Helm lint | `docker compose run --rm studiomcp helm lint chart -f chart/values.yaml -f chart/values-kind.yaml` | Success |
| Helm template | `docker compose run --rm studiomcp helm template studiomcp chart -f chart/values.yaml -f chart/values-kind.yaml` | Renders unified ingress |
| Storage reconcile | `docker compose run --rm studiomcp studiomcp cluster storage reconcile` | `studiomcp-manual` and required PVs applied idempotently |
| Cluster ensure | `docker compose run --rm studiomcp studiomcp cluster ensure` | All services ready |
| Cluster deploy server | `docker compose run --rm studiomcp studiomcp cluster deploy server` | Server pods running |
| Integration tests | `docker compose run --rm studiomcp studiomcp test integration` | Pass on the supported parity path |
| Storage policy | `docker compose run --rm studiomcp studiomcp validate storage-policy` | PASS |
| Edge reachability | All web paths reachable | HTTP 200 on /kc, /mcp, /api, /minio |
| Control-plane port | Kind exposes one control-plane ingress port | `/mcp`, `/api`, `/kc`, `/minio` use ingress at 8081 |
| Data-plane port | Kind exposes object-storage data-plane port | Presigned URLs remain rooted at `http://localhost:9000` |
| Registry pull | Pods pull from configured registry | Image pull policy and registry URL correct |
| CLI secrets | `docker compose run --rm studiomcp studiomcp cluster ensure-secrets` | Required secrets applied idempotently |

### Remaining Work

None. This phase is complete on the current supported path.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/k8s_native_dev_policy.md` - Kind-native setup, unified ingress, registry integration
- `documents/engineering/k8s_storage.md` - manual StorageClass and CLI-owned PV lifecycle
- `documents/operations/runbook_local_debugging.md` - cluster debugging and readiness workflow

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [phase-4-control-plane-data-plane-contract.md](phase-4-control-plane-data-plane-contract.md) aligned when ingress behavior changes.
- Keep [system-components.md](system-components.md) aligned when deployment topology changes.

## Cross-References

- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-4-control-plane-data-plane-contract.md](phase-4-control-plane-data-plane-contract.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../documents/engineering/k8s_native_dev_policy.md](../documents/engineering/k8s_native_dev_policy.md)
- [../documents/engineering/k8s_storage.md](../documents/engineering/k8s_storage.md)

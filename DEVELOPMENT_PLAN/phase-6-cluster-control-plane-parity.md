# File: DEVELOPMENT_PLAN/phase-6-cluster-control-plane-parity.md
# Phase 6: Cluster Control-Plane Parity

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the supported Kind and Helm deployment path that exposes the canonical
> control-plane contract in local cluster development.

## Phase Summary

**Status**: Done
**Implementation**: `chart/Chart.yaml`, `chart/templates/ingress.yaml`, `kind/kind_config.yaml`, `src/StudioMCP/CLI/Cluster.hs`
**Docs to update**: `documents/engineering/k8s_native_dev_policy.md`, `documents/operations/runbook_local_debugging.md`

### Goal

Ensure the Kind and Helm workflow exposes the same canonical `/mcp`, `/api`, and `/kc` contract
described by the plan and the governed docs.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Helm chart dependencies | `chart/Chart.yaml` | Done |
| Ingress templates | `chart/templates/ingress.yaml` | Done |
| Kind config | `kind/kind_config.yaml` | Done |
| Cluster CLI | `src/StudioMCP/CLI/Cluster.hs` | Done |

### Validation

#### Validation Prerequisites

All validation commands run inside the outer container after bootstrap:

```bash
docker compose up -d
```

#### Validation Gates

| Check | Command | Expected |
|-------|---------|----------|
| Helm lint | `docker compose exec studiomcp-env helm lint chart -f chart/values.yaml -f chart/values-kind.yaml` | Success |
| Helm template | `docker compose exec studiomcp-env helm template studiomcp chart -f chart/values.yaml -f chart/values-kind.yaml` | Renders ingress |
| Cluster ensure | `docker compose exec studiomcp-env studiomcp cluster ensure` | All services ready |
| Cluster deploy server | `docker compose exec studiomcp-env studiomcp cluster deploy server` | Server pods running |
| Integration tests | `docker compose exec studiomcp-env cabal test integration-tests` | Pass on the supported parity path |
| Edge reachability | `/kc`, `/mcp`, `/api` reachable | HTTP 200 |

### Remaining Work

None. This phase is complete on the current supported path.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/k8s_native_dev_policy.md` - Kind-native setup and supported path
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
- [../documents/engineering/k8s_native_dev_policy.md](../documents/engineering/k8s_native_dev_policy.md)

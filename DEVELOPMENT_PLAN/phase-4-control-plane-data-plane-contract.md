# File: DEVELOPMENT_PLAN/phase-4-control-plane-data-plane-contract.md
# Phase 4: Control-Plane and Data-Plane Contract Closure

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the canonical route split, object-storage public endpoint contract, and
> durable local state policy for the deployed control plane.

## Phase Summary

**Status**: Done
**Implementation**: `chart/templates/studiomcp_deployment.yaml`, `chart/templates/bff.yaml`, `chart/templates/ingress.yaml`, `chart/templates/_helpers.tpl`, `chart/values.yaml`, `chart/values-kind.yaml`, `src/StudioMCP/MCP/Handlers.hs`
**Docs to update**: `documents/architecture/overview.md`, `documents/reference/web_portal_surface.md`

### Goal

Make the control-plane (`/mcp`, `/api`, `/kc`) and data-plane (presigned object-storage URLs)
contracts explicit in configuration, routing, and validation.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Helm chart services | `chart/templates/studiomcp_deployment.yaml`, `chart/templates/bff.yaml` | Done |
| Ingress configuration | `chart/templates/ingress.yaml` | Done |
| Values for Kind | `chart/values-kind.yaml` | Done |
| Public endpoint config | `chart/values.yaml` (`global.publicBaseUrl`) | Done |
| Object-storage endpoint | `chart/values.yaml` (`global.objectStorage.publicEndpoint`) | Done |
| Repo-local persistence root | `src/StudioMCP/MCP/Handlers.hs` (`resolvePersistenceRoot`) | Done |

### Validation

#### Validation Prerequisites

All validation commands run inside the outer container after bootstrap:

```bash
docker compose build
docker compose run --rm studiomcp studiomcp cluster ensure
docker compose run --rm studiomcp studiomcp cluster deploy server
```

#### Validation Gates

| Check | Command | Expected |
|-------|---------|----------|
| Helm lint | `docker compose run --rm studiomcp helm lint chart -f chart/values.yaml -f chart/values-kind.yaml` | Success |
| Helm template | `docker compose run --rm studiomcp helm template studiomcp chart -f chart/values.yaml -f chart/values-kind.yaml` | Renders |
| Cluster ensure | `docker compose run --rm studiomcp studiomcp cluster ensure` | Shared services, ingress, realm bootstrap, and data-plane prerequisites converge |
| Cluster deploy server | `docker compose run --rm studiomcp studiomcp cluster deploy server` | MCP and BFF workloads are rolled onto the supported ingress edge |
| Keycloak OIDC | `docker compose run --rm studiomcp curl localhost:8081/kc/realms/studiomcp/.well-known/openid-configuration` | HTTP 200 |
| MCP ingress route | `docker compose run --rm studiomcp studiomcp validate mcp-http` | PASS |
| BFF ingress route and public object-storage root | `docker compose run --rm studiomcp studiomcp validate web-bff` | PASS |
| Persistence root | `docker compose run --rm studiomcp studiomcp test unit` | `test/MCP/HandlersSpec.hs` keeps `.data/studiomcp` as the default |

### Remaining Work

None within the original route and public-endpoint closure scope. [Phase 25](phase-25-auth-storage-and-runtime-contract-realignment.md)
records the later MinIO-only tenant storage ownership realignment behind this control-plane and
data-plane split.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/overview.md` - control-plane and data-plane split

**Product docs to create/update:**
- `documents/reference/web_portal_surface.md` - endpoint contracts and object-storage URL behavior

**Cross-references to add:**
- Keep [00-overview.md](00-overview.md) aligned when route ownership changes.
- Keep [system-components.md](system-components.md) aligned when durable state locations change.

## Cross-References

- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md)
- [phase-25-auth-storage-and-runtime-contract-realignment.md](phase-25-auth-storage-and-runtime-contract-realignment.md)
- [../documents/architecture/overview.md](../documents/architecture/overview.md)

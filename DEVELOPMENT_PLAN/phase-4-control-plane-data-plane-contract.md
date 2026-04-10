# File: DEVELOPMENT_PLAN/phase-4-control-plane-data-plane-contract.md
# Phase 4: Control-Plane and Data-Plane Contract Closure

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the canonical route split, object-storage public endpoint contract, and
> durable local state policy for the deployed control plane.

## Phase Summary

**Status**: Done
**Implementation**: `chart/templates/studiomcp_deployment.yaml`, `chart/templates/bff.yaml`, `chart/templates/ingress.yaml`, `chart/values.yaml`, `chart/values-kind.yaml`, `src/StudioMCP/Config/Load.hs`
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
| Runtime persistence root | `src/StudioMCP/Config/Load.hs` (`./.data/`) | Done |

### Validation

#### Validation Prerequisites

All validation commands run inside the outer container after bootstrap:

```bash
docker compose build
docker compose run --rm studiomcp studiomcp cluster ensure
```

#### Validation Gates

| Check | Command | Expected |
|-------|---------|----------|
| Helm lint | `docker compose run --rm studiomcp helm lint chart -f chart/values.yaml -f chart/values-kind.yaml` | Success |
| Helm template | `docker compose run --rm studiomcp helm template studiomcp chart ...` | Renders |
| Cluster ensure | `docker compose run --rm studiomcp studiomcp cluster ensure` | Success |
| Keycloak OIDC | `docker compose run --rm studiomcp curl localhost:8081/kc/realms/studiomcp/.well-known/openid-configuration` | HTTP 200 |
| MCP endpoint | `docker compose run --rm studiomcp curl localhost:8081/mcp` | Responds |
| BFF endpoint | `docker compose run --rm studiomcp curl localhost:8081/api/health` | HTTP 200 |
| Upload presigned URL | `POST /api/v1/upload/request` returns `localhost:9000` rooted URL | Correct root |
| Persistence root | unit test for `./.data/studiomcp` default | Pass |

### Remaining Work

None. This phase is complete on the current supported path.

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
- [../documents/architecture/overview.md](../documents/architecture/overview.md)

# File: DEVELOPMENT_PLAN/phase-3-keycloak-auth-shared-sessions.md
# Phase 3: Keycloak Auth and Shared Session Foundations

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [system-components.md](system-components.md)

> **Purpose**: Define the Keycloak-backed auth stack, JWT validation rules, and Redis-backed shared
> session behavior that support browser and MCP access paths.

## Phase Summary

**Status**: Done
**Implementation**: `src/StudioMCP/Auth/Middleware.hs`, `src/StudioMCP/Auth/Jwks.hs`, `src/StudioMCP/Auth/PassthroughGuard.hs`, `src/StudioMCP/MCP/Session/RedisStore.hs`
**Docs to update**: `documents/architecture/multi_tenant_saas_mcp_auth_architecture.md`, `documents/engineering/security_model.md`, `documents/engineering/session_scaling.md`

### Goal

Implement JWT validation, Keycloak integration, and Redis-backed session sharing for horizontal
scale and browser/MCP auth flows. Redis session storage is ephemeral; no PVCs or PVs are deployed
for Redis because session state is regenerable runtime data, not durable business data.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Auth types | `src/StudioMCP/Auth/Types.hs` | Done |
| Claims extraction | `src/StudioMCP/Auth/Claims.hs` | Done |
| JWT validation | `src/StudioMCP/Auth/Middleware.hs` | Done |
| JWKS fetch | `src/StudioMCP/Auth/Jwks.hs` | Done |
| Token passthrough guard utilities | `src/StudioMCP/Auth/PassthroughGuard.hs` | Done |
| Scope enforcement | `src/StudioMCP/Auth/Scopes.hs` | Done |
| Auth config | `src/StudioMCP/Auth/Config.hs` | Done |
| Password and refresh-token helpers | `src/StudioMCP/Auth/PKCE.hs` | Done |
| Redis session store | `src/StudioMCP/MCP/Session/RedisStore.hs` | Done |
| Session types | `src/StudioMCP/MCP/Session/Types.hs` | Done |

### Validation

#### Validation Prerequisites

All validation commands run inside the outer container after bootstrap:

```bash
docker compose build
docker compose run --rm studiomcp studiomcp cluster ensure  # For cluster-based validators
```

#### Validation Gates

| Check | Command | Expected |
|-------|---------|----------|
| MCP auth | `docker compose run --rm studiomcp studiomcp validate mcp-auth` | PASS |
| Session store | `docker compose run --rm studiomcp studiomcp validate session-store` | PASS |
| Horizontal scale | `docker compose run --rm studiomcp studiomcp validate horizontal-scale` | PASS |
| Keycloak | `docker compose run --rm studiomcp studiomcp validate keycloak` | PASS |

### Test Mapping

| Test | File |
|------|------|
| Auth types | `test/Auth/TypesSpec.hs` |
| Claims | `test/Auth/ClaimsSpec.hs` |
| Middleware | `test/Auth/MiddlewareSpec.hs` |
| JWKS | `test/Auth/JwksSpec.hs` |
| Passthrough guard | `test/Auth/PassthroughGuardSpec.hs` |
| Scopes | `test/Auth/ScopesSpec.hs` |
| Config | `test/Auth/ConfigSpec.hs` |
| Redis store | `test/Session/RedisStoreSpec.hs` |
| Integration: Keycloak | `test/Integration/HarnessSpec.hs` |
| Integration: MCP auth | `test/Integration/HarnessSpec.hs` |

### Remaining Work

None within the original auth-and-session foundation scope. [Phase 25](phase-25-auth-storage-and-runtime-contract-realignment.md)
records the later BFF-default, bootstrap-helper, and dev or synthetic auth contract realignment.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/multi_tenant_saas_mcp_auth_architecture.md` - auth design, issuer rules,
  and per-tool scope tables aligned with the stable Phase 2 MCP catalog
- `documents/engineering/security_model.md` - enforcement rules and trust boundaries
- `documents/engineering/session_scaling.md` - shared-session and scale-out behavior

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [phase-2-mcp-surface-catalog-artifact-governance.md](phase-2-mcp-surface-catalog-artifact-governance.md) and [../documents/reference/mcp_tool_catalog.md](../documents/reference/mcp_tool_catalog.md) aligned when auth docs name MCP tools.
- Keep [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md) aligned when browser session rules change.
- Keep [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) aligned when auth compatibility surfaces change.

## Cross-References

- [README.md](README.md)
- [system-components.md](system-components.md)
- [phase-2-mcp-surface-catalog-artifact-governance.md](phase-2-mcp-surface-catalog-artifact-governance.md)
- [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md)
- [phase-25-auth-storage-and-runtime-contract-realignment.md](phase-25-auth-storage-and-runtime-contract-realignment.md)
- [../documents/engineering/security_model.md](../documents/engineering/security_model.md)

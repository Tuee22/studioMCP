# File: DEVELOPMENT_PLAN/phase-3-keycloak-auth-shared-sessions.md
# Phase 3: Keycloak Auth and Shared Session Foundations

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [system-components.md](system-components.md)

> **Purpose**: Define the Keycloak-backed auth stack, JWT validation rules, and Redis-backed shared
> session behavior that support browser and MCP access paths.

## Phase Summary

**Status**: Done
**Implementation**: `src/StudioMCP/Auth/Middleware.hs`, `src/StudioMCP/Auth/Jwks.hs`, `src/StudioMCP/MCP/Session/RedisStore.hs`
**Docs to update**: `documents/architecture/multi_tenant_saas_mcp_auth_architecture.md`, `documents/engineering/security_model.md`, `documents/engineering/session_scaling.md`

### Goal

Implement JWT validation, Keycloak integration, and Redis-backed session sharing for horizontal
scale and browser/MCP auth flows.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Auth types | `src/StudioMCP/Auth/Types.hs` | Done |
| Claims extraction | `src/StudioMCP/Auth/Claims.hs` | Done |
| JWT validation | `src/StudioMCP/Auth/Middleware.hs` | Done |
| JWKS fetch | `src/StudioMCP/Auth/Jwks.hs` | Done |
| Scope enforcement | `src/StudioMCP/Auth/Scopes.hs` | Done |
| Auth config | `src/StudioMCP/Auth/Config.hs` | Done |
| Password grant | `src/StudioMCP/Auth/PKCE.hs` | Done |
| Redis session store | `src/StudioMCP/MCP/Session/RedisStore.hs` | Done |
| Session types | `src/StudioMCP/MCP/Session/Types.hs` | Done |

### Validation

| Check | Command | Expected |
|-------|---------|----------|
| MCP auth | `studiomcp validate mcp-auth` | PASS |
| Session store | `studiomcp validate session-store` | PASS |
| Horizontal scale | `studiomcp validate horizontal-scale` | PASS |
| Keycloak | `studiomcp validate keycloak` | PASS |

### Test Mapping

| Test | File |
|------|------|
| Auth types | `test/Auth/TypesSpec.hs` |
| Claims | `test/Auth/ClaimsSpec.hs` |
| Middleware | `test/Auth/MiddlewareSpec.hs` |
| JWKS | `test/Auth/JwksSpec.hs` |
| Scopes | `test/Auth/ScopesSpec.hs` |
| Config | `test/Auth/ConfigSpec.hs` |
| Redis store | `test/Session/RedisStoreSpec.hs` |
| Integration: Keycloak | `test/Integration/HarnessSpec.hs` |
| Integration: MCP auth | `test/Integration/HarnessSpec.hs` |

### Remaining Work

None. This phase is complete on the current supported path.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/multi_tenant_saas_mcp_auth_architecture.md` - auth design and issuer rules
- `documents/engineering/security_model.md` - enforcement rules and trust boundaries
- `documents/engineering/session_scaling.md` - shared-session and scale-out behavior

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md) aligned when browser session rules change.
- Keep [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) aligned when auth compatibility surfaces change.

## Cross-References

- [README.md](README.md)
- [system-components.md](system-components.md)
- [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md)
- [../documents/engineering/security_model.md](../documents/engineering/security_model.md)

# File: DEVELOPMENT_PLAN/phase-5-browser-session-contract.md
# Phase 5: Browser Session Contract Hardening

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Define the browser-facing BFF contract, cookie-first session handling, and the
> intentional omission of token/session details from browser JSON responses.

## Phase Summary

**Status**: Done
**Implementation**: `src/StudioMCP/Web/Handlers.hs`, `src/StudioMCP/Web/BFF.hs`, `src/StudioMCP/Web/Types.hs`
**Docs to update**: `documents/reference/web_portal_surface.md`

### Goal

Harden the browser auth contract so the browser uses a BFF-managed HTTP-only session cookie rather
than receiving raw token details in the primary JSON surface.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| BFF handlers | `src/StudioMCP/Web/Handlers.hs` | Done |
| BFF service | `src/StudioMCP/Web/BFF.hs` | Done |
| Web types | `src/StudioMCP/Web/Types.hs` | Done |
| Login endpoint | `POST /api/v1/session/login` | Done |
| Session me endpoint | `GET /api/v1/session/me` | Done |
| Logout endpoint | `POST /api/v1/session/logout` | Done |
| Refresh endpoint | `POST /api/v1/session/refresh` | Done |
| Cookie-wins logic | cookie auth beats bearer auth when both are present | Done |

### Validation

#### Validation Prerequisites

All validation commands run inside the outer container after bootstrap:

```bash
docker compose up -d
docker compose exec studiomcp-env studiomcp cluster ensure
```

#### Validation Gates

| Check | Command | Expected |
|-------|---------|----------|
| Web BFF | `docker compose exec studiomcp-env studiomcp validate web-bff` | PASS |
| Unit: BFF | `docker compose exec studiomcp-env cabal test unit-tests --match "Web/"` | Pass |
| Login returns cookie | live login test | Sets `studiomcp_session` |
| Login omits tokens | response JSON | No `sessionId`; no tokens |
| `/session/me` works | live test with cookie | Returns session info |

### Test Mapping

| Test | File |
|------|------|
| BFF | `test/Web/BFFSpec.hs` |
| Handlers | `test/Web/HandlersSpec.hs` |
| Types | `test/Web/TypesSpec.hs` |
| Integration: web-bff | `test/Integration/HarnessSpec.hs` |

### Remaining Work

None. This phase is complete on the current supported path.

## Documentation Requirements

**Engineering docs to create/update:**
- None.

**Product docs to create/update:**
- `documents/reference/web_portal_surface.md` - browser auth and session behavior

**Cross-references to add:**
- Keep [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md) aligned when browser auth transport changes.
- Keep [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) aligned when deferred OAuth/PKCE surfaces change status.

## Cross-References

- [00-overview.md](00-overview.md)
- [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../documents/reference/web_portal_surface.md](../documents/reference/web_portal_surface.md)

# File: DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md
# studioMCP Legacy Tracking For Deletion

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md), [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md), [phase-7-keycloak-realm-bootstrap.md](phase-7-keycloak-realm-bootstrap.md), [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md)

> **Purpose**: Provide the explicit ledger of deprecated compatibility surfaces, stale configuration
> retained only for future work, and completed cleanup/removal work in `studioMCP`.

## Pending Removal

| Item | Location | Why it remains | Owning phase |
|------|----------|----------------|--------------|
| BFF redirect URIs | `docker/keycloak/realm/studiomcp-realm.json` | Kept only for the deferred browser redirect OAuth path | Phase 8 |
| `standardFlowEnabled` on the BFF client | `docker/keycloak/realm/studiomcp-realm.json` | Kept only for the deferred redirect-based auth path | Phase 8 |
| `studiomcp-cli` Keycloak client | `docker/keycloak/realm/studiomcp-realm.json` | Deferred external CLI auth surface; not part of the current supported path | Phase 8 |

## Completed

| Item | Former location | Verification |
|------|-----------------|--------------|
| `PKCEChallenge` type | `src/StudioMCP/Auth/PKCE.hs` | Removed |
| `generatePKCEChallenge` | `src/StudioMCP/Auth/PKCE.hs` | Removed |
| `AuthorizationParams` type | `src/StudioMCP/Auth/PKCE.hs` | Removed |
| `buildAuthorizationUrl` | `src/StudioMCP/Auth/PKCE.hs` | Removed |
| `TokenExchangeParams` type | `src/StudioMCP/Auth/PKCE.hs` | Removed |
| `exchangeCodeForTokens` | `src/StudioMCP/Auth/PKCE.hs` | Removed |
| Legacy durable-state root | `.studiomcp-data/` | Replaced by `./.data/` |
| Kebab-case governed docs | `documents/*.md` legacy naming | Replaced by snake_case naming |

## Intentionally Retained Active Surfaces

These items are not pending removal because the current implementation still depends on them.

| Export or surface | Used by | Reason it stays |
|-------------------|---------|-----------------|
| `TokenResponse` | BFF login and refresh flows | Still part of the supported password-grant path |
| `PasswordGrantParams` | BFF login flow | Required by the current browser auth contract |
| `exchangePasswordForTokens` | BFF login flow | Required by the current browser auth contract |
| `RefreshParams` | BFF refresh flow | Required by the current browser auth contract |
| `refreshAccessToken` | BFF refresh flow | Required by the current browser auth contract |
| `PKCEError` and `pkceErrorToText` | auth error handling | Shared error surface for the active auth path |

## Cross-References

- [README.md](README.md)
- [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md)
- [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md)
- [phase-7-keycloak-realm-bootstrap.md](phase-7-keycloak-realm-bootstrap.md)
- [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md)

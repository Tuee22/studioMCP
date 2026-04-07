# File: DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md
# studioMCP Legacy Tracking For Deletion

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md), [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md), [phase-7-keycloak-realm-bootstrap.md](phase-7-keycloak-realm-bootstrap.md), [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md)

> **Purpose**: Provide the explicit ledger of deprecated compatibility surfaces, stale configuration
> retained only for future work, and completed cleanup/removal work in `studioMCP`.

## Pending Removal

None.

## Completed

| Item | Former location | Verification |
|------|-----------------|--------------|
| BFF redirect URIs | `docker/keycloak/realm/studiomcp-realm.json` | Removed from the imported realm definition |
| `studiomcp-cli` Keycloak client | `docker/keycloak/realm/studiomcp-realm.json` | Removed from the imported realm definition |
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

| Export or surface | Location | Used by | Reason it stays | Owning phase |
|-------------------|----------|---------|-----------------|--------------|
| `TokenResponse` | `src/StudioMCP/Auth/PKCE.hs` | BFF login and refresh flows | Still part of the supported password-grant path | Phase 5 |
| `PasswordGrantParams` | `src/StudioMCP/Auth/PKCE.hs` | BFF login flow | Required by the current browser auth contract | Phase 5 |
| `exchangePasswordForTokens` | `src/StudioMCP/Auth/PKCE.hs` | BFF login flow | Required by the current browser auth contract | Phase 5 |
| `RefreshParams` | `src/StudioMCP/Auth/PKCE.hs` | BFF refresh flow | Required by the current browser auth contract | Phase 5 |
| `refreshAccessToken` | `src/StudioMCP/Auth/PKCE.hs` | BFF refresh flow | Required by the current browser auth contract | Phase 5 |
| `PKCEError` and `pkceErrorToText` | `src/StudioMCP/Auth/PKCE.hs` | auth error handling | Shared error surface for the active auth path | Phase 3 |
| `standardFlowEnabled: false` on `studiomcp-bff` | `docker/keycloak/realm/studiomcp-realm.json` | Keycloak realm bootstrap | Explicitly keeps redirect-based browser auth disabled on the supported path | Phase 7 |

## Cross-References

- [README.md](README.md)
- [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md)
- [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md)
- [phase-7-keycloak-realm-bootstrap.md](phase-7-keycloak-realm-bootstrap.md)
- [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md)

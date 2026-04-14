# File: DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md
# studioMCP Legacy Tracking For Deletion

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md), [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md), [phase-7-keycloak-realm-bootstrap.md](phase-7-keycloak-realm-bootstrap.md), [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md), [phase-14-makefile-removal.md](phase-14-makefile-removal.md)

> **Purpose**: Provide the explicit ledger of deprecated compatibility surfaces, stale configuration
> retained only for future work, and completed cleanup/removal work in `studioMCP`.

## Pending Removal

None. The current supported repository path does not retain any repo-local compatibility surfaces
that are still waiting on a future cleanup phase.

## Completed

| Item | Former location | Verification |
|------|-----------------|--------------|
| `builddir: /opt/build/studiomcp` compatibility hint | `cabal.project` | Removed; explicit `--builddir` flags in the Dockerfile and CLI remain authoritative |
| `CABAL_BUILDDIR=/opt/build/studiomcp` compatibility hint | `docker/Dockerfile` | Removed; nix-style builds rely only on explicit `--builddir` flags |
| Makefile workflow wrapper | `/Makefile` | Removed; the supported repo entrypoint is `docker compose run --rm studiomcp studiomcp ...` |
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
| Persistent outer container command | `docker-compose.yaml` | Removed for the ephemeral `docker compose run --rm` model |
| Persistent env-stage Dockerfile command | `docker/Dockerfile` | Removed for the ephemeral `docker compose run --rm` model |
| Compose-level locale environment | `docker-compose.yaml` | Removed; locale is inherited from Dockerfile `ENV` |
| Host Docker config bind mount | `docker-compose.yaml` | Removed; registry auth is supplied through CLI-managed login inputs when needed |
| `docker compose up` and `docker compose exec` plan examples | `DEVELOPMENT_PLAN/*.md` | Replaced with `docker compose run --rm studiomcp ...` examples |
| `docker compose up` and `docker compose exec` workflow examples outside the authoritative plan | `CLAUDE.md` and compatibility guidance | Replaced with the one-command `docker compose run --rm studiomcp ...` model |
| Multi-stage repository Dockerfile layout | `docker/Dockerfile` | Replaced by the single-stage repository Dockerfile |
| Default container startup in Dockerfile (`ENTRYPOINT ["studiomcp"]`, `CMD ["server"]`) | `docker/Dockerfile` | Replaced by `ENTRYPOINT ["tini", "--"]`; Kubernetes workloads now own explicit runtime startup and the Dockerfile has no `CMD` |
| Separate Keycloak ingress | `chart/templates/ingress.yaml` | Consolidated into the unified ingress |
| MinIO console NodePort | `chart/values-kind.yaml` | Replaced by the `/minio` ingress path; the MinIO S3 data-plane NodePort remains intentionally retained for presigned URLs |
| Local image loading to Kind | `src/StudioMCP/CLI/Cluster.hs` | Replaced by registry push and Helm registry image references |
| Host-level Harbor registry fallback | `src/StudioMCP/CLI/Cluster.hs`, `kind/kind_config.yaml`, `documents/engineering/docker_policy.md` | Removed; the supported local path now pushes through `host.docker.internal:32443` and pulls through the Kind mirror at `localhost:32443`, both backed by the in-cluster Harbor deployment |
| Obsolete manual Keycloak bootstrap appendix | `documents/operations/keycloak_realm_bootstrap_runbook.md` | Removed; the runbook now documents the CLI-driven bootstrap path only |
| Duplicate authoritative local-development doc | `documents/engineering/local_dev.md` | Resolved; the document is now a reference-only companion and `documents/development/local_dev.md` remains canonical |
| Duplicate authoritative testing-policy doc | `documents/engineering/testing.md` | Resolved; the document is now a reference-only companion and `documents/development/testing_strategy.md` remains canonical |

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
- [phase-14-makefile-removal.md](phase-14-makefile-removal.md)

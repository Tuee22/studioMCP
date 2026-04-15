# Phase 25: Auth, Storage, and Runtime Contract Realignment

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

> **Purpose**: Reconcile the implementation with the corrected governed contract for Keycloak
> bootstrap and browser auth, MinIO-only artifact storage, and model-backed FluidSynth runtime
> behavior.

## Phase Summary

**Status**: Done
**Implementation**: `docker/keycloak/realm/studiomcp-realm.json`, `src/StudioMCP/Auth/Admin.hs`, `src/StudioMCP/Auth/Config.hs`, `src/StudioMCP/Web/BFF.hs`, `src/StudioMCP/Auth/Middleware.hs`, `src/StudioMCP/CLI/Cluster.hs`, `src/StudioMCP/Storage/TenantStorage.hs`, `src/StudioMCP/MCP/Resources.hs`, `src/StudioMCP/Tools/FluidSynth.hs`
**Docs to update**: `documents/architecture/multi_tenant_saas_mcp_auth_architecture.md`, `documents/operations/keycloak_realm_bootstrap_runbook.md`, `documents/architecture/artifact_storage_architecture.md`, `documents/reference/web_portal_surface.md`, `documents/architecture/bff_architecture.md`, `documents/reference/mcp_tool_catalog.md`, `documents/tools/fluidsynth.md`, `documents/tools/keycloak.md`

### Goal

Close the post-documentation-review implementation drift without fragmenting the plan narrative:

- make the checked-in Keycloak realm export, bootstrap helper, and direct-process BFF defaults use
  the same `studiomcp-bff` / `studiomcp-mcp` / `studiomcp-service` client contract
- make synthetic validator tokens and dev-bypass auth contexts exercise the current scope surface,
  including `resource:read` and `tenant:read`
- remove tenant-owned S3 compatibility from the runtime storage contract so the supported repo path
  is MinIO-backed only
- remove the image-level FluidSynth SoundFont fallback so SoundFonts come from model storage or the
  explicit environment override

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Keycloak realm export updated for the current client/scope contract | `docker/keycloak/realm/studiomcp-realm.json` | Done |
| Keycloak admin bootstrap helper matches the imported realm contract | `src/StudioMCP/Auth/Admin.hs` | Done |
| Direct-process BFF auth defaults use the BFF client contract | `src/StudioMCP/Auth/Config.hs`, `src/StudioMCP/Web/BFF.hs`, `app/BFFMode.hs` | Done |
| Dev-bypass and synthetic validator scopes match the documented auth surface | `src/StudioMCP/Auth/Middleware.hs`, `src/StudioMCP/CLI/Cluster.hs`, related tests | Done |
| Tenant storage runtime exposes only the MinIO-backed supported contract | `src/StudioMCP/Storage/TenantStorage.hs`, `src/StudioMCP/MCP/Resources.hs`, related tests | Done |
| FluidSynth runtime depends on model storage or explicit override, not container-baked SoundFonts | `src/StudioMCP/Tools/FluidSynth.hs`, related tests | Done |

### Validation

| Check | Command | Expected |
|-------|---------|----------|
| Auth unit and scope coverage | `docker compose run --rm studiomcp studiomcp test unit` | PASS |
| Keycloak contract | `docker compose run --rm studiomcp studiomcp validate keycloak` | PASS |
| MCP auth | `docker compose run --rm studiomcp studiomcp validate mcp-auth` | PASS |
| Browser auth contract | `docker compose run --rm studiomcp studiomcp validate web-bff` | PASS |
| MCP tool and resource catalog | `docker compose run --rm studiomcp studiomcp validate mcp-tools` | PASS |
| MCP resources and tenant metadata surface | `docker compose run --rm studiomcp studiomcp validate mcp-resources` | PASS |
| FluidSynth adapter contract | `docker compose run --rm studiomcp studiomcp validate fluidsynth-adapter` | PASS |
| Aggregate regression gate | `docker compose run --rm studiomcp studiomcp test` | PASS |
| Docs validation | `docker compose run --rm studiomcp studiomcp validate docs` | PASS |

### Current Validation State

- The requested cold-state rerun on April 15, 2026 deleted the `studiomcp` kind cluster, pruned
  Docker images, caches, networks, and volumes, removed `./.data/`, and rebuilt the outer image
  with `docker compose build`.
- The requested cold-state `docker compose run --rm studiomcp studiomcp test` rerun on
  April 15, 2026 completed with `904 examples, 0 failures` for the unit suite,
  `26 examples, 0 failures` for the integration suite, and the CLI summary
  `Unit tests: PASSED`, `Integration tests: PASSED`, `All tests passed.`
- `docker compose run --rm studiomcp studiomcp validate docs` passes on April 15, 2026 after
  these plan updates landed.
- The cold-state Phase 25 validator reruns on April 14, 2026 passed:
  `validate keycloak`, `validate mcp-auth`, `validate web-bff`, `validate mcp-tools`,
  `validate mcp-resources`, and `validate fluidsynth-adapter`
  with `STUDIOMCP_FLUIDSYNTH_SOUNDFONT=/usr/share/sounds/sf2/TimGM6mb.sf2`.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/multi_tenant_saas_mcp_auth_architecture.md` - keep the client, issuer,
  and scope contract aligned with bootstrap and runtime behavior
- `documents/operations/keycloak_realm_bootstrap_runbook.md` - keep the checked-in realm export and
  helper behavior aligned
- `documents/architecture/artifact_storage_architecture.md` - keep the MinIO-only storage contract
  aligned with the runtime implementation
- `documents/tools/fluidsynth.md` and `documents/tools/keycloak.md` - keep adapter/bootstrap
  operator notes aligned with the corrected supported path

**Product docs to create/update:**
- `documents/reference/web_portal_surface.md` - keep browser login/session and run-submit behavior
  aligned with the BFF contract
- `documents/reference/mcp_tool_catalog.md` - keep tenant-facing tool/scope notes aligned with the
  corrected auth surface

**Cross-references to add:**
- Keep [phase-2-mcp-surface-catalog-artifact-governance.md](phase-2-mcp-surface-catalog-artifact-governance.md),
  [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md),
  [phase-4-control-plane-data-plane-contract.md](phase-4-control-plane-data-plane-contract.md),
  [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md),
  [phase-7-keycloak-realm-bootstrap.md](phase-7-keycloak-realm-bootstrap.md),
  [phase-15-monocontainer-tool-expansion.md](phase-15-monocontainer-tool-expansion.md), and
  [phase-16-minio-model-storage.md](phase-16-minio-model-storage.md) aligned as this follow-on
  closed.
- Move compatibility remnants out of [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
  as each removal lands.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-2-mcp-surface-catalog-artifact-governance.md](phase-2-mcp-surface-catalog-artifact-governance.md)
- [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md)
- [phase-4-control-plane-data-plane-contract.md](phase-4-control-plane-data-plane-contract.md)
- [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md)
- [phase-7-keycloak-realm-bootstrap.md](phase-7-keycloak-realm-bootstrap.md)
- [phase-15-monocontainer-tool-expansion.md](phase-15-monocontainer-tool-expansion.md)
- [phase-16-minio-model-storage.md](phase-16-minio-model-storage.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

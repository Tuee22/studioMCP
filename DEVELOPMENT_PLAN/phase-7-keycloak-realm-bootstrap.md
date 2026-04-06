# File: DEVELOPMENT_PLAN/phase-7-keycloak-realm-bootstrap.md
# Phase 7: Keycloak Realm Bootstrap Automation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md)

> **Purpose**: Define the automated Keycloak realm bootstrap path so fresh clusters do not depend
> on manual realm seeding.

## Phase Summary

**Status**: Done
**Implementation**: `docker/keycloak/realm/studiomcp-realm.json`, `src/StudioMCP/CLI/Cluster.hs`
**Docs to update**: `documents/operations/keycloak_realm_bootstrap_runbook.md`

### Goal

Remove manual Keycloak realm bootstrapping from the default cluster path and make repeated `cluster
ensure` runs idempotent.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Realm JSON | `docker/keycloak/realm/studiomcp-realm.json` | Done |
| CLI bootstrap | `src/StudioMCP/CLI/Cluster.hs` | Done |
| Idempotent import | `studiomcp cluster ensure` waits and imports safely | Done |

### Validation

| Check | Command | Expected |
|-------|---------|----------|
| Fresh cluster bootstrap | `studiomcp cluster ensure` on a new cluster | Realm ready |
| Idempotent re-run | `studiomcp cluster ensure` twice | Still healthy |
| Keycloak validate | `studiomcp validate keycloak` | PASS on the live path |

### Remaining Work

None. This phase is complete on the current supported path.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/operations/keycloak_realm_bootstrap_runbook.md` - automated bootstrap and recovery path

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md) aligned when auth bootstrap assumptions change.
- Keep [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) aligned if realm-export compatibility surfaces are removed.

## Cross-References

- [README.md](README.md)
- [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../documents/operations/keycloak_realm_bootstrap_runbook.md](../documents/operations/keycloak_realm_bootstrap_runbook.md)

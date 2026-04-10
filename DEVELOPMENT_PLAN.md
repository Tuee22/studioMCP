# studioMCP Development Plan

The authoritative development plan now lives under [DEVELOPMENT_PLAN/README.md](DEVELOPMENT_PLAN/README.md).
This root file remains as a compatibility index for existing links, tooling, and cross-references.

## Current Repo Assessment Against This Plan

| Phase | Status | Authoritative document |
|-------|--------|------------------------|
| 1 | Done | [DEVELOPMENT_PLAN/phase-1-repository-dag-runtime-foundations.md](DEVELOPMENT_PLAN/phase-1-repository-dag-runtime-foundations.md) |
| 2 | Done | [DEVELOPMENT_PLAN/phase-2-mcp-surface-catalog-artifact-governance.md](DEVELOPMENT_PLAN/phase-2-mcp-surface-catalog-artifact-governance.md) |
| 3 | Done | [DEVELOPMENT_PLAN/phase-3-keycloak-auth-shared-sessions.md](DEVELOPMENT_PLAN/phase-3-keycloak-auth-shared-sessions.md) |
| 4 | Done | [DEVELOPMENT_PLAN/phase-4-control-plane-data-plane-contract.md](DEVELOPMENT_PLAN/phase-4-control-plane-data-plane-contract.md) |
| 5 | Done | [DEVELOPMENT_PLAN/phase-5-browser-session-contract.md](DEVELOPMENT_PLAN/phase-5-browser-session-contract.md) |
| 6 | Done | [DEVELOPMENT_PLAN/phase-6-cluster-control-plane-parity.md](DEVELOPMENT_PLAN/phase-6-cluster-control-plane-parity.md) |
| 7 | Done | [DEVELOPMENT_PLAN/phase-7-keycloak-realm-bootstrap.md](DEVELOPMENT_PLAN/phase-7-keycloak-realm-bootstrap.md) |
| 8 | Done | [DEVELOPMENT_PLAN/phase-8-final-closure-regression-gate.md](DEVELOPMENT_PLAN/phase-8-final-closure-regression-gate.md) |
| 9 | Done | [DEVELOPMENT_PLAN/phase-9-cli-test-validate-consolidation.md](DEVELOPMENT_PLAN/phase-9-cli-test-validate-consolidation.md) |
| 10 | Done | [DEVELOPMENT_PLAN/phase-10-build-artifact-isolation.md](DEVELOPMENT_PLAN/phase-10-build-artifact-isolation.md) |

## Current Validation State

All commands run inside an ephemeral outer container:

- `docker compose run --rm studiomcp cabal --builddir=/opt/build/studiomcp build all` passes.
- `docker compose run --rm studiomcp studiomcp test unit` passes with 846 unit tests.
- `docker compose run --rm studiomcp studiomcp test integration` passes with 16 integration tests.
- `docker compose run --rm studiomcp studiomcp validate all` passes with 28 of 28 validators.
- Build artifacts go to `/opt/build/studiomcp/` and never leak to the workspace bind mount.
- The outer `studiomcp` container resolves `studiomcp` on `PATH` at `/usr/local/bin/studiomcp`.

**Cluster-Dependent:**
- `docker compose run --rm studiomcp studiomcp test integration` requires Kind cluster via `studiomcp cluster ensure`.
- Integration tests validate cluster services (Keycloak, MinIO, Pulsar, etc.) through the outer-container CLI.

## Public Topology Baseline

- `/mcp` routes to the MCP listener surface.
- `/api` routes to the BFF and browser-session endpoints.
- `/kc` routes to Keycloak.
- Bulk artifact bytes use presigned URLs rooted at the configured object-storage public endpoint.
- Redis owns shared resumable session state.
- All durable repo-local state lives under `./.data/`.

See [DEVELOPMENT_PLAN/00-overview.md](DEVELOPMENT_PLAN/00-overview.md) and
[DEVELOPMENT_PLAN/system-components.md](DEVELOPMENT_PLAN/system-components.md) for the full
topology and component inventory.

## Implementation Checklist

- [Plan index and status model](DEVELOPMENT_PLAN/README.md)
- [Standards and maintenance rules](DEVELOPMENT_PLAN/development_plan_standards.md)
- [Overview and completion rules](DEVELOPMENT_PLAN/00-overview.md)
- [System component inventory](DEVELOPMENT_PLAN/system-components.md)
- [Phase 1 foundations](DEVELOPMENT_PLAN/phase-1-repository-dag-runtime-foundations.md)
- [Phase 2 MCP and governance](DEVELOPMENT_PLAN/phase-2-mcp-surface-catalog-artifact-governance.md)
- [Phase 3 auth and shared sessions](DEVELOPMENT_PLAN/phase-3-keycloak-auth-shared-sessions.md)
- [Phase 4 control-plane and data-plane contract](DEVELOPMENT_PLAN/phase-4-control-plane-data-plane-contract.md)
- [Phase 5 browser session contract](DEVELOPMENT_PLAN/phase-5-browser-session-contract.md)
- [Phase 6 cluster parity](DEVELOPMENT_PLAN/phase-6-cluster-control-plane-parity.md)
- [Phase 7 Keycloak bootstrap automation](DEVELOPMENT_PLAN/phase-7-keycloak-realm-bootstrap.md)
- [Phase 8 final closure and regression gate](DEVELOPMENT_PLAN/phase-8-final-closure-regression-gate.md)
- [Phase 9 CLI test and validate consolidation](DEVELOPMENT_PLAN/phase-9-cli-test-validate-consolidation.md)
- [Phase 10 build artifact isolation](DEVELOPMENT_PLAN/phase-10-build-artifact-isolation.md)
- [Legacy tracking for deletion](DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md)

## Documentation Governance

Use [DEVELOPMENT_PLAN/development_plan_standards.md](DEVELOPMENT_PLAN/development_plan_standards.md)
for plan-maintenance rules and
[documents/documentation_standards.md](documents/documentation_standards.md) for the governed
`documents/` suite rules.

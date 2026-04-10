# File: DEVELOPMENT_PLAN/README.md
# studioMCP Development Plan

**Status**: Authoritative source
**Supersedes**: [../DEVELOPMENT_PLAN.md](../DEVELOPMENT_PLAN.md) as the monolithic plan layout
**Referenced by**: [../README.md](../README.md#development-roadmap), [../documents/documentation_standards.md](../documents/documentation_standards.md#8-documentation-maintenance-checklist)

> **Purpose**: Provide the single execution-ordered development plan for `studioMCP`, including
> phase status, validation gates, documentation obligations, and cleanup ownership.

## Standards

See [development_plan_standards.md](development_plan_standards.md) for the maintenance rules that
govern this plan.

## Document Index

| Document | Purpose |
|----------|---------|
| [development_plan_standards.md](development_plan_standards.md) | Maintenance rules for the development plan |
| [00-overview.md](00-overview.md) | Architecture overview, current constraints, and topology baseline |
| [system-components.md](system-components.md) | Authoritative component inventory and boundary map |
| [phase-1-repository-dag-runtime-foundations.md](phase-1-repository-dag-runtime-foundations.md) | Repository, DAG, and runtime foundations |
| [phase-2-mcp-surface-catalog-artifact-governance.md](phase-2-mcp-surface-catalog-artifact-governance.md) | MCP surface, catalogs, artifact governance, and observability |
| [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md) | Keycloak auth and shared Redis-backed sessions |
| [phase-4-control-plane-data-plane-contract.md](phase-4-control-plane-data-plane-contract.md) | Control-plane and data-plane contract closure |
| [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md) | Browser session contract hardening |
| [phase-6-cluster-control-plane-parity.md](phase-6-cluster-control-plane-parity.md) | Kind and Helm control-plane parity |
| [phase-7-keycloak-realm-bootstrap.md](phase-7-keycloak-realm-bootstrap.md) | Keycloak realm bootstrap automation |
| [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md) | Final regression closure and clean validation gate |
| [phase-9-cli-test-validate-consolidation.md](phase-9-cli-test-validate-consolidation.md) | CLI test and validate command consolidation |
| [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) | Cleanup and compatibility removal ledger |

## Status Vocabulary

| Status | Meaning |
|--------|---------|
| `Done` | Implemented, validated, docs aligned, no remaining work |
| `Active` | Implemented in part or mostly closed, but remaining work is explicit |
| `Blocked` | Waiting on named prerequisites |
| `Planned` | Ready to start with dependencies already satisfied |

## Definition of Done

A phase can move to `Done` only when all of the following are true:

1. The deliverables exist in the repository worktree.
2. The listed validation gates pass on the supported path.
3. The governed docs listed in `Docs to update` are aligned with the implementation.
4. No `Remaining Work` section remains open.
5. `docker compose exec studiomcp-env studiomcp validate docs` passes after the documentation change.
6. Cleanup promised by the phase is reflected in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Phase Overview

| Phase | Name | Status | Document |
|-------|------|--------|----------|
| 1 | Repository, DAG, and Runtime Foundations | Done | [phase-1-repository-dag-runtime-foundations.md](phase-1-repository-dag-runtime-foundations.md) |
| 2 | MCP Surface, Catalog, Artifact Governance, and Observability | Done | [phase-2-mcp-surface-catalog-artifact-governance.md](phase-2-mcp-surface-catalog-artifact-governance.md) |
| 3 | Keycloak Auth and Shared Session Foundations | Done | [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md) |
| 4 | Control-Plane and Data-Plane Contract Closure | Done | [phase-4-control-plane-data-plane-contract.md](phase-4-control-plane-data-plane-contract.md) |
| 5 | Browser Session Contract Hardening | Done | [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md) |
| 6 | Cluster Control-Plane Parity | Done | [phase-6-cluster-control-plane-parity.md](phase-6-cluster-control-plane-parity.md) |
| 7 | Keycloak Realm Bootstrap Automation | Done | [phase-7-keycloak-realm-bootstrap.md](phase-7-keycloak-realm-bootstrap.md) |
| 8 | Final Closure and Regression Gate | Done | [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md) |
| 9 | CLI Test and Validate Consolidation | Done | [phase-9-cli-test-validate-consolidation.md](phase-9-cli-test-validate-consolidation.md) |

## Current Validation State

- `docker compose exec studiomcp-env cabal build all` passes.
- `docker compose exec studiomcp-env studiomcp test unit` passes with 844 unit tests.
- `docker compose exec studiomcp-env studiomcp test integration` passes with 16 integration tests.
- `docker compose exec studiomcp-env studiomcp test all` passes end to end on the supported outer-container path.
- `docker compose exec studiomcp-env studiomcp validate all` runs all validators with aggregate reporting.
- `docker compose exec studiomcp-env studiomcp validate docs` passes.
- The outer `studiomcp-env` container resolves `studiomcp` on `PATH` at `/usr/local/bin/studiomcp`.

## Phase Details

| Phase | Status | Remaining Work | Docs to update |
|-------|--------|----------------|----------------|
| 1 | Done | None | `documents/domain/dag_specification.md`, `documents/architecture/parallel_scheduling.md`, `documents/tools/ffmpeg.md` |
| 2 | Done | None | `documents/architecture/mcp_protocol_architecture.md`, `documents/reference/mcp_surface.md`, `documents/reference/mcp_tool_catalog.md`, `documents/architecture/artifact_storage_architecture.md` |
| 3 | Done | None | `documents/architecture/multi_tenant_saas_mcp_auth_architecture.md`, `documents/engineering/security_model.md`, `documents/engineering/session_scaling.md` |
| 4 | Done | None | `documents/architecture/overview.md`, `documents/reference/web_portal_surface.md` |
| 5 | Done | None | `documents/reference/web_portal_surface.md` |
| 6 | Done | None | `documents/engineering/k8s_native_dev_policy.md`, `documents/operations/runbook_local_debugging.md` |
| 7 | Done | None | `documents/operations/keycloak_realm_bootstrap_runbook.md` |
| 8 | Done | None | `README.md`, `documents/documentation_standards.md`, plan index files as needed |
| 9 | Done | None | `documents/reference/cli_reference.md`, `DEVELOPMENT_PLAN/development_plan_standards.md` |

## Compatibility Entry Point

The root [../DEVELOPMENT_PLAN.md](../DEVELOPMENT_PLAN.md) file remains available as a compatibility
index for existing links and tooling. It should summarize, not replace, the authoritative plan
documents in this directory.

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

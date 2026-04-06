# File: DEVELOPMENT_PLAN/phase-8-final-closure-regression-gate.md
# Phase 8: Final Closure and Regression Gate

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [00-overview.md](00-overview.md)

> **Purpose**: Track the final remaining regression gap, summarize the currently passing coverage,
> and define what must close before the plan can move from nearly complete to fully closed.

## Phase Summary

**Status**: Active
**Implementation**: `test/Integration/HarnessSpec.hs`, `src/StudioMCP/CLI/Cluster.hs`, `chart/templates/ingress.yaml`, `docker-compose.yaml`
**Docs to update**: `README.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `DEVELOPMENT_PLAN.md`, `documents/documentation_standards.md`

### Goal

Close the remaining MCP conformance regression and establish a clean final regression gate for the
supported outer-container and Kind-based workflow.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| All phase 4-7 items closed | various | Done except for the remaining MCP conformance gap |
| Plan and docs aligned | `DEVELOPMENT_PLAN/`, `DEVELOPMENT_PLAN.md`, `documents/` | In progress |
| Regression command set documented | `DEVELOPMENT_PLAN/README.md`, this file | Done |

### Validation

| Check | Command | Expected | Current state |
|-------|---------|----------|---------------|
| Build | `cabal build all` | Success | Pass |
| Unit tests | `cabal test unit-tests` | Success | 844 pass |
| Integration tests | `cabal test integration-tests` | 0 failures | 15 pass, 1 fail |
| Kind edge matrix | cluster validators through `/kc`, `/mcp`, `/api` | PASS | MCP conformance still failing |
| Docs validation | `studiomcp validate docs` | PASS | Expected after plan refactor cleanup |

### Current Validation State

- 844 unit tests pass.
- 15 of 16 integration tests pass.
- The only listed failing integration test is MCP conformance through the outer-container CLI.
- Passing integration coverage includes deterministic helper processes, FFmpeg adapter validation,
  sequential executor validation, worker runtime validation, cluster validation, Keycloak bootstrap
  and connectivity, DAG end-to-end validation, Pulsar lifecycle validation, MinIO round-trips, MCP
  HTTP transport, inference advisory mode, observability, horizontal scale, MCP auth, and the BFF
  browser surface.

### Resolved Regressions Already Folded Into The Active Branch

- Keycloak edge routing and path-rewrite issues were resolved.
- Token issuer validation now accepts the supported public and internal issuers, including the
  localhost-oriented validation path used by the outer-container workflow.
- Service-port, rollout-timeout, and Helm-locking issues that blocked cluster stability were fixed.
- ingress-nginx webhook and ConfigMap compatibility issues were worked around on the supported path.
- Redis health checks and image-build-skip handling were tightened for the local workflow.

### Remaining Work

- Close the MCP conformance failure on the supported outer-container path.
- Rerun `cabal test integration-tests --test-show-details=direct` until the suite reaches 16 of 16.
- Rerun the broader regression gate: `cabal build all`, `cabal test all --test-show-details=direct`,
  and `cabal run studiomcp -- validate docs`.
- Once the regression gate is clean, mark this phase `Done` and remove any no-longer-needed
  compatibility items from [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Documentation Requirements

**Engineering docs to create/update:**
- `README.md` - top-level roadmap entry point and current validation summary
- `documents/documentation_standards.md` - plan/governed-doc alignment references if the plan entrypoint changes

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [README.md](README.md) aligned with the phase-status table.
- Keep [../DEVELOPMENT_PLAN.md](../DEVELOPMENT_PLAN.md) aligned as the compatibility index.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../README.md](../README.md#development-roadmap)

# File: DEVELOPMENT_PLAN/phase-8-final-closure-regression-gate.md
# Phase 8: Final Closure and Regression Gate

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [00-overview.md](00-overview.md)

> **Purpose**: Summarize the final regression gate, the validated coverage, and the closure criteria
> for the supported outer-container and Kind-based workflow.

## Phase Summary

**Status**: Done
**Implementation**: `test/Integration/HarnessSpec.hs`, `src/StudioMCP/CLI/Cluster.hs`, `chart/templates/ingress.yaml`, `docker-compose.yaml`, `docker/Dockerfile`
**Docs to update**: `README.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `DEVELOPMENT_PLAN.md`, `documents/documentation_standards.md`

### Goal

Close the final live validation regressions and establish a clean regression gate for the supported
outer-container and Kind-based workflow.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Phase 4-7 closure criteria remain satisfied on the supported path | various | Done |
| MCP conformance and horizontal-scale validation pass on the supported live path | `src/StudioMCP/CLI/Cluster.hs`, `test/Integration/HarnessSpec.hs` | Done |
| The outer development container exposes the canonical `studiomcp` binary on `PATH` | `docker/Dockerfile`, `docker-compose.yaml` | Done |
| Plan and docs remain aligned | `DEVELOPMENT_PLAN/`, `DEVELOPMENT_PLAN.md`, `documents/` | Done |
| Regression command set is documented | `DEVELOPMENT_PLAN/README.md`, this file | Done |

### Validation

#### Validation Prerequisites

All validation commands run inside the outer container after bootstrap:

```bash
docker compose build
docker compose run --rm studiomcp studiomcp cluster ensure
```

#### Validation Gates

| Check | Command | Expected | Current state |
|-------|---------|----------|---------------|
| Build | `docker compose run --rm studiomcp cabal --builddir=/opt/build/studiomcp build all` | Success | Pass |
| Unit tests | `docker compose run --rm studiomcp studiomcp test unit` | Success | 867 pass |
| Integration tests | `docker compose run --rm studiomcp studiomcp test integration` | 0 failures | 16 pass, 0 fail |
| Full regression gate | `docker compose run --rm studiomcp studiomcp test all` | 0 failures | Pass |
| Outer container CLI availability | `docker compose run --rm studiomcp sh -lc 'command -v studiomcp'` | `/usr/local/bin/studiomcp` | Pass |
| Kind edge matrix | cluster validators through `/kc`, `/mcp`, `/api` | PASS | PASS |
| Docs validation | `docker compose run --rm studiomcp studiomcp validate docs` | PASS | Pass |
| Full validation | `docker compose run --rm studiomcp studiomcp validate all` | PASS | 28/28 pass |

### Current Validation State

- 867 unit tests pass.
- 16 of 16 integration tests pass.
- `docker compose run --rm studiomcp studiomcp test all` passes on the supported outer-container path.
- `docker compose run --rm studiomcp studiomcp validate all` passes with 28 of 28 validators.
- The outer `studiomcp` container resolves `studiomcp` on `PATH` at `/usr/local/bin/studiomcp`.
- Passing integration coverage includes deterministic helper processes, FFmpeg adapter validation,
  sequential executor validation, worker runtime validation, cluster validation, Keycloak bootstrap
  and connectivity, DAG end-to-end validation, Pulsar lifecycle validation, MinIO round-trips, MCP
  HTTP transport, inference advisory mode, observability, horizontal scale, MCP auth, MCP
  conformance, and the BFF browser surface.

### Supported Closure State

- Keycloak edge routing uses the prefix-preserving ingress contract for `/kc`.
- Token issuer validation accepts the supported public and internal issuers, including the
  localhost-oriented validation path used by the outer-container workflow.
- Cluster lifecycle handling tolerates the service-port, rollout-timeout, and Helm-lock conditions
  that arise on the supported local workflow.
- ingress-nginx compatibility handling keeps the supported path stable across the webhook and
  ConfigMap variants exercised in local development.
- Redis health checks and image-build-skip handling remain part of the supported local workflow.
- The outer development container installs `studiomcp` to `/usr/local/bin`, so the supported
  workflow invokes the CLI directly by name inside `studiomcp`.
- MCP session bootstrap retries the `notifications/initialized` step across transient rollout-time
  `401`, `502`, `503`, and `504` responses.
- The live horizontal-scale validator accepts both existing-session recovery and clean
  post-recovery MCP session re-establishment after a Redis outage.
- MinIO readiness checks wait for write quorum (`/minio/health/cluster`) before DAG execution
  begins, preventing transient failures during cluster rollouts where MinIO may be alive but
  not yet ready to accept writes.

### Remaining Work

None. This phase is complete on the current supported path.

## Documentation Requirements

**Engineering docs to create/update:**
- `README.md` - top-level roadmap entry point and current validation summary
- `DEVELOPMENT_PLAN/README.md` - authoritative plan index and validation summary
- `DEVELOPMENT_PLAN/00-overview.md` - phase-status snapshot and topology baseline
- `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` - cleanup ledger alignment for compatibility removals
- `DEVELOPMENT_PLAN.md` - compatibility index for existing links and tooling
- `documents/documentation_standards.md` - plan/governed-doc alignment references if the plan entrypoint changes

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [../README.md](../README.md#development-roadmap) aligned with the phase-status table.
- Keep [README.md](README.md) aligned with the validated command set.
- Keep [../DEVELOPMENT_PLAN.md](../DEVELOPMENT_PLAN.md) aligned as the compatibility index.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../README.md](../README.md#development-roadmap)

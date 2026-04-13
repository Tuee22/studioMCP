# File: DEVELOPMENT_PLAN/phase-8-final-closure-regression-gate.md
# Phase 8: Final Closure and Regression Gate

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [00-overview.md](00-overview.md)

> **Purpose**: Summarize the final regression gate, the validated coverage, and the closure criteria
> for the supported outer-container and Kind-based workflow.

## Phase Summary

**Status**: Done
**Implementation**: `test/Integration/HarnessSpec.hs`, `src/StudioMCP/CLI/Cluster.hs`, `chart/values-kind.yaml`, `docker-compose.yaml`, `docker/Dockerfile`, `DEVELOPMENT_PLAN/README.md`, `documents/README.md`
**Docs to update**: `README.md`, `documents/README.md`, `documents/documentation_standards.md`, `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/development/local_dev.md`, `documents/engineering/local_dev.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md`, `DEVELOPMENT_PLAN.md`

### Goal

Close the final live validation regressions and establish a clean regression gate for the supported
outer-container and Kind-based workflow.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Phase 4-7 closure criteria remain satisfied on the supported path | various | Done |
| Aggregate validation reruns cleanly on the supported live path | `src/StudioMCP/CLI/Cluster.hs`, `test/Integration/HarnessSpec.hs` | Done |
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

| Check | Command | Expected | Review state |
|-------|---------|----------|--------------|
| Build | `docker compose run --rm studiomcp cabal --builddir=/opt/build/studiomcp build all` | Success | Container rebuild reran via `docker compose build` |
| Unit tests | `docker compose run --rm studiomcp studiomcp test unit` | Success | 867 pass, 0 failures |
| Integration tests | `docker compose run --rm studiomcp studiomcp test integration` | 0 failures | 16 pass, 0 failures |
| Full regression gate | `docker compose run --rm studiomcp studiomcp test` | 0 failures | Pass; aggregate CLI run completed on the supported path |
| Outer container CLI availability | `docker compose run --rm studiomcp sh -lc 'command -v studiomcp'` | `/usr/local/bin/studiomcp` | Pass |
| Kind edge matrix | cluster validators through `/kc`, `/mcp`, `/api` | PASS | Pass through the aggregate validator set on the supported cluster path |
| Docs validation | `docker compose run --rm studiomcp studiomcp validate docs` | PASS | Pass |
| Full validation | `docker compose run --rm studiomcp studiomcp validate all` | PASS | Pass; 28/28 validators |

### Current Validation State

- `docker compose build` passes for the current worktree.
- `docker compose run --rm studiomcp studiomcp cluster ensure` passes on the supported Kind path.
- `docker compose run --rm studiomcp studiomcp test unit` passes with 867 examples and 0 failures on the current worktree.
- `docker compose run --rm studiomcp studiomcp test integration` passes with 16 examples and 0 failures on the supported cluster path.
- `docker compose run --rm studiomcp studiomcp test` passes and runs both suites through the canonical aggregate CLI entrypoint.
- `docker compose run --rm studiomcp studiomcp validate docs` passes on the current worktree.
- `docker compose run --rm studiomcp studiomcp validate all` passes with 28/28 validators on the current worktree.
- The outer `studiomcp` container resolves `studiomcp` on `PATH` at `/usr/local/bin/studiomcp`.
- The supported integration coverage set includes deterministic helper processes, FFmpeg adapter
  validation, sequential executor validation, worker runtime validation, cluster validation,
  Keycloak bootstrap and connectivity, DAG end-to-end validation, Pulsar lifecycle validation,
  MinIO round-trips, MCP HTTP transport, inference advisory mode, observability, horizontal scale,
  MCP auth, MCP conformance, and the BFF browser surface.

### Supported Closure State

- Keycloak edge routing uses the prefix-preserving ingress contract for `/kc`.
- Token issuer validation accepts the supported public and internal issuers, including the
  localhost-oriented validation path used by the outer-container workflow.
- Cluster lifecycle handling tolerates the service-port, rollout-timeout, and Helm-lock conditions
  that arise on the supported local workflow.
- Cluster lifecycle handling now recovers stale pending Helm revisions via a repo-local Helm lock
  and stale revision cleanup before retrying the supported upgrade path.
- Kind-specific PostgreSQL HA pgpool settings are sized for the supported single-node cluster path,
  preventing startup OOMs during `cluster ensure` and aggregate validation reruns.
- ingress-nginx compatibility handling keeps the supported path stable across the webhook and
  ConfigMap variants exercised in local development.
- Redis health checks and image-build-skip handling remain part of the supported local workflow.
- The outer development container installs `studiomcp` to `/usr/local/bin`, so the supported
  workflow invokes the CLI directly by name inside `studiomcp`.
- Live server deploy now blocks on Kubernetes service endpoint publication for `studiomcp` and
  `studiomcp-bff` before `/mcp` or `/api` edge validation begins.
- MCP session bootstrap retry handling remains available for outage-recovery and scale-transition
  validations, but steady-state live edge readiness no longer depends on validator-local HTTP retries.
- The live horizontal-scale validator accepts both existing-session recovery and clean
  post-recovery MCP session re-establishment after a Redis outage.
- MinIO readiness checks wait for write quorum (`/minio/health/cluster`) before DAG execution
  begins, preventing transient failures during cluster rollouts where MinIO may be alive but
  not yet ready to accept writes.
- The governed documentation suite now has one canonical document per concept again, with
  `documents/development/local_dev.md` and `documents/development/testing_strategy.md` as the
  canonical development and testing documents and the engineering companions demoted to
  reference-only status.

### Remaining Work

None. This phase is complete on the current supported path.

## Documentation Requirements

**Engineering docs to create/update:**
- `README.md` - top-level roadmap entry point and current validation summary
- `documents/README.md` - authoritative suite index aligned with the actual canonical documents
- `DEVELOPMENT_PLAN/README.md` - authoritative plan index and validation summary
- `DEVELOPMENT_PLAN/00-overview.md` - phase-status snapshot and topology baseline
- `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` - cleanup ledger alignment for compatibility removals
- `DEVELOPMENT_PLAN.md` - compatibility index for existing links and tooling
- `documents/documentation_standards.md` - plan/governed-doc alignment references if canonical docs move or suite governance changes
- `documents/development/testing_strategy.md` and `documents/engineering/testing.md` - converge testing policy back to one canonical document
- `documents/development/local_dev.md` and `documents/engineering/local_dev.md` - converge outer-container local-development guidance back to one canonical document

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [../README.md](../README.md#development-roadmap) aligned with the phase-status table.
- Keep [../documents/README.md](../documents/README.md#studiomcp-documentation-index) aligned with the canonical suite after governance cleanup.
- Keep [README.md](README.md) aligned with the validated command set.
- Keep [../DEVELOPMENT_PLAN.md](../DEVELOPMENT_PLAN.md) aligned as the compatibility index.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
- [../README.md](../README.md#development-roadmap)

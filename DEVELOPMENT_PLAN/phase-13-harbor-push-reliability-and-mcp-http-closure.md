# Phase 13: Harbor Push Reliability and MCP HTTP Closure

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Close the remaining Harbor-backed MCP HTTP validation failure on the canonical
> aggregate test path without reopening build-artifact leaks or repo-owned compiler warnings.

## Phase Summary

**Status**: Done
**Implementation**: `src/StudioMCP/CLI/Cluster.hs`, `test/Integration/HarnessSpec.hs`
**Docs to update**: `documents/engineering/docker_policy.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/phase-12-aggregate-test-artifact-isolation-and-warning-closure.md`

### Goal

Make Harbor-backed image publication reliable enough that `studiomcp validate mcp-http` and the
canonical `studiomcp test` run pass end to end on the supported outer-container path.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Local kind Harbor publication uses persistent filesystem-backed registry storage with relative upload URLs, waits for Harbor backing services plus stable Harbor health, and still keeps extended managed-registry retry/backoff with remote-digest confirmation before giving up on publication | `chart/values-kind.yaml`, `src/StudioMCP/CLI/Cluster.hs` | Done |
| `validate mcp-http` passes through the integration harness without manual retries or warm-up runs | `src/StudioMCP/CLI/Cluster.hs`, `test/Integration/HarnessSpec.hs` | Done |
| The canonical `studiomcp test` run returns success after the Harbor-backed MCP HTTP validator closes | `src/StudioMCP/CLI/Test.hs`, `test/Integration/HarnessSpec.hs` | Done |

### Reopened Gap

- On April 13, 2026, the canonical `docker compose run --rm studiomcp studiomcp test all` run
  failed in `test/Integration/HarnessSpec.hs:155` while executing `studiomcp validate mcp-http`.
- The failing validator rebuilt `studiomcp:latest`, attempted to publish
  `host.docker.internal:32443/library/studiomcp:latest`, and then hit repeated Harbor upload
  failures:
  `blob upload invalid` followed by `500 Internal Server Error`.
- Artifact isolation and repo-owned warning closure stayed intact during that failing run:
  `/workspace/dist-newstyle` remained absent and the only warning lines in the canonical logs were
  from third-party packages.

### Validation

### Validation Prerequisites

All validation commands use the supported outer-container workflow:

```bash
docker compose build
```

### Validation Gates

| Check | Command | Expected |
|-------|---------|----------|
| Container build | `docker compose build` | Updated repository image contains the current `studiomcp` CLI |
| Direct MCP HTTP validator | `docker compose run --rm studiomcp studiomcp validate mcp-http` | Harbor-backed MCP HTTP validator passes without registry upload failures |
| Aggregate tests | `docker compose run --rm studiomcp studiomcp test` | Unit and integration suites both pass on the canonical CLI path |
| Docs validation | `docker compose run --rm studiomcp studiomcp validate docs` | PASS on the updated plan and registry-policy docs |

### Current Validation State

- On April 14, 2026, the supported clean-room workflow completed successfully:
  `docker compose down --remove-orphans`, `docker system prune -af --volumes`,
  `.data/` removal, `docker compose build`, and
  `docker compose run --rm studiomcp studiomcp test`.
- The clean April 14, 2026 aggregate run passed end to end, and the final aggregate summary
  reported `All tests passed.` The current suite counts are tracked in `DEVELOPMENT_PLAN/README.md`.
- `docker compose run --rm studiomcp studiomcp validate mcp-http` passed on April 14, 2026, on
  the repaired Harbor-backed cluster path without manual retries or warm-up runs.
- The host workspace still left `dist-newstyle/` absent after the clean-room aggregate run.
- A clean post-prune April 14, 2026 rerun showed the remaining Harbor failure was still a local
  registry-storage issue: Harbor returned `upload resumed at wrong offset: 724905406 !=
  745876926`, then `blob upload invalid`, while the kind overlay still configured the Harbor
  registry against the MinIO/S3 backend.
- The current source tree now makes local managed Harbor publication wait for PostgreSQL and Redis
  readiness, Harbor `/api/v2.0/health`, and registry `/v2/` readiness before `skopeo copy`
  begins.
- A clean April 14, 2026 rerun advanced past the original upload-offset failure but exposed a
  second local-registry durability gap: workloads pulled `localhost:32443/library/studiomcp:latest`
  after Helm restarted Harbor, and the pull failed with `not found` because the filesystem-backed
  registry data still lived on an `emptyDir`.
- The current source tree now configures Harbor's registry with `registry.relativeurls: true` and a
  persistent filesystem-backed `imageChartStorage` backend on the repo's manual-PV path, so a
  Helm-driven Harbor restart no longer discards the just-published image.
- The current source tree also captures managed-Harbor `skopeo` failures, reapplies a longer
  managed-registry retry/backoff schedule, and treats a matching remote image config digest as
  success even when the client reports a late failure.
- `docker compose run --rm studiomcp studiomcp test all` failed on April 13, 2026, with
  `16 examples, 1 failure` in the integration suite.
- The failing integration example was
  `integration harness exercises the MCP HTTP transport through the outer-container CLI` at
  `test/Integration/HarnessSpec.hs:155`.
- The failing `studiomcp validate mcp-http` run retried Harbor publication of
  `host.docker.internal:32443/library/studiomcp:latest`, then failed with repeated
  `blob upload invalid` responses and later `500 Internal Server Error` responses from Harbor
  during `skopeo copy`.
- The failing aggregate run still left `/workspace/dist-newstyle` absent, so Phase 12 closure
  remained intact while this follow-on regression was investigated and repaired.

### Remaining Work

None. This phase is complete on the supported post-prune path.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/docker_policy.md` - Harbor-compatible registry policy must match the repaired upload and retry contract
- `DEVELOPMENT_PLAN/README.md` - phase index and validation summary must reflect the closed Harbor follow-on phase
- `DEVELOPMENT_PLAN/00-overview.md` - current repo assessment must show the repaired Harbor-backed MCP HTTP path
- `DEVELOPMENT_PLAN/system-components.md` - registry inventory notes must stay aligned with the managed-registry push contract
- `DEVELOPMENT_PLAN/phase-12-aggregate-test-artifact-isolation-and-warning-closure.md` - completed artifact-isolation and warning-closure work must remain clearly separated from this now-closed follow-on phase

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [phase-12-aggregate-test-artifact-isolation-and-warning-closure.md](phase-12-aggregate-test-artifact-isolation-and-warning-closure.md) aligned so completed warning closure is not reopened silently.
- Keep [documents/engineering/docker_policy.md](../documents/engineering/docker_policy.md) aligned if Harbor upload readiness, retry/backoff, or publication-success criteria change.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-12-aggregate-test-artifact-isolation-and-warning-closure.md](phase-12-aggregate-test-artifact-isolation-and-warning-closure.md)
- [../documents/engineering/docker_policy.md](../documents/engineering/docker_policy.md)

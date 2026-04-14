# File: DEVELOPMENT_PLAN/phase-12-aggregate-test-artifact-isolation-and-warning-closure.md
# Phase 12: Aggregate Test Artifact Isolation and Warning Closure

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Close the reopened workspace build-artifact leak in aggregate test execution and
> integration-harness bootstrap, and remove repo-owned compiler warnings that were burying failure
> signal in the full `studiomcp test all` output.

## Phase Summary

**Status**: Done
**Implementation**: `src/StudioMCP/CLI/Test.hs`, `src/StudioMCP/Util/Cabal.hs`, `src/StudioMCP/MCP/Context.hs`, `src/StudioMCP/MCP/Core.hs`, `src/StudioMCP/MCP/Transport/Http.hs`, `src/StudioMCP/CLI/Cluster.hs`, `test/Integration/HarnessSpec.hs`, `test/Auth/ConfigSpec.hs`, `test/Auth/JwksSpec.hs`, `test/MCP/ConformanceSpec.hs`, `test/MCP/CoreSpec.hs`, `test/MCP/ToolsSpec.hs`, `test/Session/StoreSpec.hs`, `test/Storage/GovernanceSpec.hs`, `test/Storage/TenantStorageSpec.hs`, `test/Web/HandlersSpec.hs`
**Docs to update**: `documents/engineering/docker_policy.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/phase-10-build-artifact-isolation.md`

### Goal

Restore the build-artifact isolation doctrine for `studiomcp test unit`, `studiomcp test
integration`, and `studiomcp test all` by keeping repo-owned build output under `/opt/build/`
only, and trim repo-owned source and test warnings so aggregate test failures remain visible at the end of the
run.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| CLI test commands build suites and execute resolved test binaries instead of relying on `cabal test` | `src/StudioMCP/CLI/Test.hs` | Done |
| Inner-container integration-harness execution reuses the installed outer-container CLI instead of self-bootstrapping a second binary | `test/Integration/HarnessSpec.hs` | Done |
| Harness-side guardrails fail fast if repo-owned CLI/bootstrap commands recreate `/workspace/dist-newstyle` | `test/Integration/HarnessSpec.hs` | Done |
| Repo-owned source and test warnings are removed, and the weak route/storage tests exposed by those warnings are strengthened | `src/StudioMCP/Auth/Claims.hs`, `src/StudioMCP/Auth/Jwks.hs`, `src/StudioMCP/Auth/Middleware.hs`, `src/StudioMCP/Auth/Scopes.hs`, `src/StudioMCP/Auth/ServiceAccount.hs`, `src/StudioMCP/MCP/Context.hs`, `src/StudioMCP/MCP/Core.hs`, `src/StudioMCP/MCP/Prompts.hs`, `src/StudioMCP/MCP/Session/RedisStore.hs`, `src/StudioMCP/MCP/Tools.hs`, `src/StudioMCP/MCP/Transport/Http.hs`, `src/StudioMCP/MCP/Transport/Stdio.hs`, `src/StudioMCP/MCP/Transport/Types.hs`, `src/StudioMCP/Observability/McpMetrics.hs`, `src/StudioMCP/Observability/Quotas.hs`, `src/StudioMCP/Storage/AuditTrail.hs`, `src/StudioMCP/Storage/Governance.hs`, `src/StudioMCP/Storage/TenantStorage.hs`, `src/StudioMCP/Util/Startup.hs`, `test/Auth/ConfigSpec.hs`, `test/Auth/JwksSpec.hs`, `test/MCP/ConformanceSpec.hs`, `test/MCP/CoreSpec.hs`, `test/MCP/ToolsSpec.hs`, `test/Session/StoreSpec.hs`, `test/Storage/GovernanceSpec.hs`, `test/Storage/TenantStorageSpec.hs`, `test/Web/HandlersSpec.hs` | Done |
| Cabal bootstrap no longer recreates workspace-local `dist-newstyle` metadata when the outer-container CLI starts a test command | `src/StudioMCP/Util/Cabal.hs` | Done |

### Reopened Gap

- Explicit `--builddir` flags remained necessary but were not sufficient on their own: the
  repo-owned `cabal test`, `cabal install`, and helper-binary bootstrap paths were still capable of recreating
  `/workspace/dist-newstyle/cache/config` even when they targeted build roots under `/opt/build/`.
- `src/StudioMCP/CLI/Test.hs` routed `studiomcp test unit`, `studiomcp test integration`, and
  `studiomcp test all` through `cabal test`, so aggregate test runs could repopulate the workspace
  build tree.
- `test/Integration/HarnessSpec.hs` previously self-bootstrapped an inner-container CLI helper
  instead of reusing the installed outer-container `studiomcp`, which reopened the same leak
  during integration-harness setup.
- Repo-owned test warnings from stale imports and unused bindings inflated the full test log and
  made real failures harder to spot.

### Validation

### Validation Prerequisites

All validation commands use the supported outer-container workflow:

```bash
docker compose build
```

### Validation Gates

| Check | Command | Expected |
|-------|---------|----------|
| Container build | `docker compose build` | Updated repository image contains the repaired `studiomcp` CLI |
| Unit tests | `docker compose run --rm studiomcp studiomcp test unit` | Unit suite passes without repo-owned warnings and without recreating workspace build artifacts |
| Artifact-isolation probe | `docker compose run --rm studiomcp sh -lc 'rm -rf /workspace/dist-newstyle; studiomcp test unit >/tmp/studiomcp-unit.log 2>&1; test ! -d /workspace/dist-newstyle'` | Canonical CLI test execution does not recreate workspace-local build artifacts |
| Docs validation | `docker compose run --rm studiomcp studiomcp validate docs` | PASS on the updated plan and engineering policy docs |

### Current Validation State

- `docker compose build` passed on April 13, 2026, confirming that the repaired source tree still
  rebuilds from a cold Docker state without repo-owned compiler warnings on the `src/StudioMCP/...`
  path.
- `docker compose run --rm studiomcp studiomcp test unit` passed on April 13, 2026.
  The unit-suite compile path emitted only third-party package warnings; no repo-owned warning
  lines remained under `src/StudioMCP/...` or `test/...`.
- `docker compose run --rm studiomcp sh -lc 'rm -rf /workspace/dist-newstyle; cabal --builddir=/opt/build/studiomcp build test:integration-tests && test_bin=$(cabal --builddir=/opt/build/studiomcp list-bin test:integration-tests) && "$test_bin" --match "deterministic helper processes"'`
  passes without recreating `/workspace/dist-newstyle`, confirming that the repaired
  inner-container harness path no longer seeds workspace build artifacts.
- The April 13, 2026 canonical `docker compose run --rm studiomcp studiomcp test all` run still
  left `/workspace/dist-newstyle` absent even though a separate Harbor-backed MCP HTTP validator
  failure remained. That follow-on regression is now closed in
  [phase-13-harbor-push-reliability-and-mcp-http-closure.md](phase-13-harbor-push-reliability-and-mcp-http-closure.md),
  which passed clean-room `validate mcp-http` and `test all` on April 14, 2026.

### Remaining Work

None. This phase is complete on the supported post-prune path.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/engineering/docker_policy.md` - artifact-isolation policy must describe the build/list-bin execution pattern and the prohibition on repo-owned `cabal test` / `cabal install` leakage paths
- `DEVELOPMENT_PLAN/development_plan_standards.md` - canonical folder model and CLI-first testing policy must describe the repaired test execution path
- `DEVELOPMENT_PLAN/README.md` - phase index and phase overview must include the reopened follow-on phase
- `DEVELOPMENT_PLAN/00-overview.md` - current repo assessment and artifact-location doctrine must include the follow-on phase
- `DEVELOPMENT_PLAN/system-components.md` - build-artifact authority and test CLI inventory must reflect the repaired execution path
- `DEVELOPMENT_PLAN/phase-10-build-artifact-isolation.md` - earlier closure language must be narrowed so the reopened gap is tracked here instead of left as stale `Done` wording

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [phase-10-build-artifact-isolation.md](phase-10-build-artifact-isolation.md) aligned so Phase 10 stays the baseline container-contract closure and this phase owns the follow-on regression repair.
- Keep [development_plan_standards.md](development_plan_standards.md#cli-first-testing-policy) aligned if the CLI changes how it executes repo-owned tests again.
- Keep [phase-13-harbor-push-reliability-and-mcp-http-closure.md](phase-13-harbor-push-reliability-and-mcp-http-closure.md) aligned so Harbor-backed MCP HTTP stabilization is tracked separately from the completed artifact-isolation and warning-closure work.
- Keep [documents/engineering/docker_policy.md](../documents/engineering/docker_policy.md) aligned with the supported `/opt/build/` doctrine.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-10-build-artifact-isolation.md](phase-10-build-artifact-isolation.md)
- [phase-13-harbor-push-reliability-and-mcp-http-closure.md](phase-13-harbor-push-reliability-and-mcp-http-closure.md)
- [development_plan_standards.md](development_plan_standards.md#cli-first-testing-policy)
- [../documents/engineering/docker_policy.md](../documents/engineering/docker_policy.md)

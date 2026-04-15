# Phase 21: Chaos Engineering Test Suite

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md)

> **Purpose**: Add deterministic recovery-budget coverage for transient infrastructure-style
> failures without depending on destructive live-cluster fault injection during the repository test
> run.

## Phase Summary

**Status**: Done
**Implementation**: `src/StudioMCP/Test/Chaos.hs`, `test/Integration/ChaosSpec.hs`, `src/StudioMCP/CLI/Test.hs`
**Blocked by**: Phase 20 (Done)
**Docs to update**: `documents/development/chaos_testing.md`

### Goal

Close the repository-owned chaos layer with a synthetic recovery harness:

- shared `waitForRecoveryWithin` helper logic
- chaos-focused integration tests that exercise retry-until-recovery behavior
- CLI `test chaos` entrypoint

This phase validates the recovery-budget contract used by the repo test suite. It does **not**
claim live pod restarts, network partitions, or destructive cluster fault injection in the default
test path.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Recovery-budget helper utilities | `src/StudioMCP/Test/Chaos.hs` | Done |
| Chaos-focused integration spec | `test/Integration/ChaosSpec.hs` | Done |
| CLI `test chaos` command | `src/StudioMCP/CLI/Test.hs`, `src/StudioMCP/CLI/Command.hs` | Done |
| Governed chaos-testing doc | `documents/development/chaos_testing.md` | Done |

### Validation

| Check | Command | Expected |
|-------|---------|----------|
| Chaos subset | `docker compose run --rm studiomcp studiomcp test chaos` | PASS |
| Full integration suite | `docker compose run --rm studiomcp studiomcp test integration` | PASS |
| Docs validation | `docker compose run --rm studiomcp studiomcp validate docs` | PASS |

### Remaining Work

None. Synthetic recovery-budget coverage and the CLI entrypoint are now part of the supported
repository validation surface.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/development/chaos_testing.md`

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md)
  aligned when chaos coverage changes the supported aggregate test story.
- Keep [phase-9-cli-test-validate-consolidation.md](phase-9-cli-test-validate-consolidation.md)
  aligned when `test chaos` or related CLI test entrypoints change.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)

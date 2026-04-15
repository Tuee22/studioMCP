# Phase 24: Whisper Runtime Shared-Library Closure

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md), [system-components.md](system-components.md), [phase-15-monocontainer-tool-expansion.md](phase-15-monocontainer-tool-expansion.md), [phase-17-haskell-tool-adapters.md](phase-17-haskell-tool-adapters.md), [phase-19-individual-tool-tests.md](phase-19-individual-tool-tests.md), [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md)

> **Purpose**: Close the reopened outer-container Whisper runtime regression so the installed
> `whisper` executable resolves its required shared libraries, the Whisper adapter validation path
> runs again, and the aggregate `studiomcp test` gate returns to a clean state.

## Phase Summary

**Status**: Done
**Implementation**: `docker/Dockerfile`, `src/StudioMCP/Tools/Whisper.hs`, `test/Tools/AdaptersSpec.hs`, `src/StudioMCP/CLI/Test.hs`
**Docs to update**: `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/phase-8-final-closure-regression-gate.md`, `DEVELOPMENT_PLAN/phase-15-monocontainer-tool-expansion.md`, `DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md`, `DEVELOPMENT_PLAN/phase-19-individual-tool-tests.md`, `documents/engineering/docker_policy.md`, `documents/tools/whisper.md`

### Goal

Restore the supported outer-container Whisper runtime so:

- `docker compose run --rm studiomcp whisper --help` succeeds without manual environment fixes
- the Whisper adapter unit and validator paths execute successfully through the canonical CLI
- the aggregate `docker compose run --rm studiomcp studiomcp test` gate closes cleanly again
- the authoritative plan and related docs describe the repaired runtime and closed follow-on honestly

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Outer image exposes the shared-library path required by `/usr/local/bin/whisper` | `docker/Dockerfile` | Done |
| Whisper adapter validation runs cleanly through the installed runtime | `src/StudioMCP/Tools/Whisper.hs`, `test/Tools/AdaptersSpec.hs` | Done |
| Aggregate CLI test path returns to a clean pass state after the Whisper runtime fix | `src/StudioMCP/CLI/Test.hs`, `test/Tools/AdaptersSpec.hs` | Done |
| Plan and companion docs record the closed follow-on and repaired runtime behavior | `DEVELOPMENT_PLAN/*.md`, `documents/engineering/docker_policy.md`, `documents/tools/whisper.md` | Done |

### Validation

| Check | Command | Expected |
|-------|---------|----------|
| Container build | `docker compose build` | Updated repository image contains the Whisper runtime fix |
| Whisper surface available | `docker compose run --rm studiomcp whisper --help` | Help output without `libwhisper.so.1` loader errors |
| Whisper validator | `docker compose run --rm studiomcp studiomcp validate whisper-adapter` | PASS |
| Unit suite | `docker compose run --rm studiomcp studiomcp test unit` | PASS |
| Aggregate test gate | `docker compose run --rm studiomcp studiomcp test` | PASS |
| Docs validation | `docker compose run --rm studiomcp studiomcp validate docs` | PASS |
| Full validation | `docker compose run --rm studiomcp studiomcp validate all` | PASS |

### Current Validation State

- `docker compose run --rm studiomcp studiomcp --help` passes on April 15, 2026, and still
  exposes `validate whisper-adapter`, `test`, and the `test all` alias.
- `docker compose run --rm studiomcp whisper --help` passes on April 15, 2026 without
  shared-library loader errors.
- `docker compose run --rm studiomcp studiomcp validate whisper-adapter` passes on
  April 15, 2026.
- The requested cold-state rerun on April 15, 2026 deleted the `studiomcp` kind cluster, pruned
  Docker including volumes, removed `./.data/`, rebuilt the outer image with
  `docker compose build`, and completed `docker compose run --rm studiomcp studiomcp test` with
  `904 examples, 0 failures` for unit coverage, `26 examples, 0 failures` for integration
  coverage, and the CLI summary `Unit tests: PASSED`, `Integration tests: PASSED`,
  `All tests passed.`
- `docker compose run --rm studiomcp studiomcp validate docs` passes on April 15, 2026 after this
  plan review landed.
- The latest recorded `docker compose run --rm studiomcp studiomcp validate all` pass on April 14,
  2026 completed with `Passed: 36/36`.

### Remaining Work

None. This follow-on phase is complete on the supported path.

## Documentation Requirements

**Engineering docs to create/update:**
- `DEVELOPMENT_PLAN/README.md` - current validation state and phase tables must record the closed Whisper runtime follow-on
- `DEVELOPMENT_PLAN/00-overview.md` - phase status snapshot must reflect the closed Phase 24 follow-on
- `DEVELOPMENT_PLAN/system-components.md` - outer-container and Whisper adapter inventory notes must stay aligned with the current runtime state
- `DEVELOPMENT_PLAN/phase-8-final-closure-regression-gate.md` - aggregate test gate language must stay aligned with the closed follow-on
- `DEVELOPMENT_PLAN/phase-15-monocontainer-tool-expansion.md` - baseline image-inventory closure must stay aligned with the repaired Whisper runtime
- `DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md` - baseline adapter closure must stay aligned with the repaired Whisper runtime
- `DEVELOPMENT_PLAN/phase-19-individual-tool-tests.md` - baseline tool-test closure must stay aligned with the repaired Whisper runtime
- `documents/engineering/docker_policy.md` - container runtime guidance must match the eventual Whisper shared-library fix
- `documents/tools/whisper.md` - tool guidance must match the repaired outer-container runtime behavior

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [phase-15-monocontainer-tool-expansion.md](phase-15-monocontainer-tool-expansion.md), [phase-17-haskell-tool-adapters.md](phase-17-haskell-tool-adapters.md), and [phase-19-individual-tool-tests.md](phase-19-individual-tool-tests.md) aligned so the closed follow-on remains historical instead of leaving stale reopened-language in older `Done` phases.
- Keep [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md) aligned as the aggregate gate record now that `studiomcp test` and `validate all` both close again.
- Keep [documents/engineering/docker_policy.md](../documents/engineering/docker_policy.md) and [documents/tools/whisper.md](../documents/tools/whisper.md) aligned with the repaired runtime behavior.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md)
- [phase-15-monocontainer-tool-expansion.md](phase-15-monocontainer-tool-expansion.md)
- [phase-17-haskell-tool-adapters.md](phase-17-haskell-tool-adapters.md)
- [phase-19-individual-tool-tests.md](phase-19-individual-tool-tests.md)
- [../documents/engineering/docker_policy.md](../documents/engineering/docker_policy.md)
- [../documents/tools/whisper.md](../documents/tools/whisper.md)

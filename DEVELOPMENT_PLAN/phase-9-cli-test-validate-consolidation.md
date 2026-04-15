# File: DEVELOPMENT_PLAN/phase-9-cli-test-validate-consolidation.md
# Phase 9: CLI Test and Validate Consolidation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [00-overview.md](00-overview.md)

> **Purpose**: Consolidate test and validation entrypoints into the `studiomcp` CLI, providing a
> unified interface for running unit tests, integration tests, and validators.

## Phase Summary

**Status**: Done
**Implementation**: `app/Main.hs`, `src/StudioMCP/CLI/Command.hs`, `src/StudioMCP/CLI/Test.hs`, `src/StudioMCP/CLI/Cluster.hs`, `studioMCP.cabal`
**Docs to update**: `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`

### Goal

Expose one canonical CLI surface for test and validation execution so the supported workflow uses
`studiomcp`, not direct `cabal test` or scattered validator entrypoints.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Test command parsing and dispatch | `src/StudioMCP/CLI/Command.hs`, `app/Main.hs` | Done |
| CLI help and usage aliases | `src/StudioMCP/CLI/Command.hs`, `app/Main.hs` | Done |
| Unit, integration, and aggregate test handlers with explicit builddir isolation | `src/StudioMCP/CLI/Test.hs` | Done |
| Aggregate validator runner (`validate all`) | `src/StudioMCP/CLI/Cluster.hs` | Done |
| CLI module exposure and executable wiring | `studioMCP.cabal`, `app/Main.hs` | Done |
| CLI reference and detailed command-surface docs | `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md` | Done |
| CLI-first testing policy in the development-plan standard | `DEVELOPMENT_PLAN/development_plan_standards.md` | Done |

### Validation

#### Validation Prerequisites

All validation commands run inside the outer container after bootstrap:

```bash
docker compose build
docker compose run --rm studiomcp studiomcp cluster ensure  # Required for integration tests and validate all
```

#### Validation Gates

| Check | Command | Expected |
|-------|---------|----------|
| Default test command | `docker compose run --rm studiomcp studiomcp test` | Runs unit and integration suites through the CLI |
| Aggregate test command | `docker compose run --rm studiomcp studiomcp test all` | Runs unit and integration suites through the CLI |
| Unit tests | `docker compose run --rm studiomcp studiomcp test unit` | Pass on the current worktree; latest suite counts are tracked in `DEVELOPMENT_PLAN/README.md` |
| Integration tests | `docker compose run --rm studiomcp studiomcp test integration` | Pass on the supported path; latest suite counts are tracked in `DEVELOPMENT_PLAN/README.md` |
| Aggregate validation command | `docker compose run --rm studiomcp studiomcp validate all` | Runs the aggregate validator runner through the CLI and emits an aggregate summary |
| Docs validation | `docker compose run --rm studiomcp studiomcp validate docs` | PASS |
| CLI usage text | `docker compose run --rm studiomcp studiomcp --help` | Prints usage text containing `test` and `validate all` commands |

### Current Validation State

- `docker compose run --rm studiomcp studiomcp --help` exits successfully and prints the supported
  CLI surface, including `test`, the `test all` alias, `validate whisper-adapter`, `email`, and
  `models`, on April 15, 2026.
- The requested cold-state `docker compose run --rm studiomcp studiomcp test` rerun on
  April 15, 2026 completed through the CLI with `904 examples, 0 failures` for unit coverage,
  `26 examples, 0 failures` for integration coverage, and the summary
  `Unit tests: PASSED`, `Integration tests: PASSED`, `All tests passed.`
- The latest recorded `docker compose run --rm studiomcp studiomcp validate all` pass on April 14, 2026 completed with `Passed: 36/36`; the aggregate validator runner still invokes 36 validators sequentially and emits an aggregate summary.
- The canonical `studiomcp` binary exposes `test`, the `test all` alias, `test unit`,
  `test integration`, and `validate all` as first-class commands.
- [phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md) now records the closed
  Whisper runtime repair that returned the aggregate CLI test path to green.

### Test Mapping

| Test | File |
|------|------|
| CLI parser and command aliases | `test/CLI/CommandSpec.hs` |
| CLI docs structure | `test/CLI/DocsSpec.hs` |
| Unit-suite composition after CLI additions | `test/Spec.hs` |

### Remaining Work

None. This phase is complete on the current supported path.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/reference/cli_reference.md` - concise CLI reference organized by command category
- `documents/reference/cli_surface.md` - detailed command inventory and behavior notes
- `DEVELOPMENT_PLAN/development_plan_standards.md` - CLI-first testing policy and container command conventions

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [README.md](README.md) and [00-overview.md](00-overview.md) aligned when CLI validation entrypoints change.
- Keep [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) aligned if compatibility aliases are retired.
- Keep [phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md) aligned as the closed follow-on record for the Whisper runtime repair.

## Cross-References

- [README.md](README.md#phase-overview)
- [00-overview.md](00-overview.md)
- [phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md)
- [development_plan_standards.md](development_plan_standards.md#cli-first-testing-policy)
- [../documents/reference/cli_reference.md](../documents/reference/cli_reference.md#studiomcp-cli-reference)
- [../documents/reference/cli_surface.md](../documents/reference/cli_surface.md)

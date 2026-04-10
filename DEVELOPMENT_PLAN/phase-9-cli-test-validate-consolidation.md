# File: DEVELOPMENT_PLAN/phase-9-cli-test-validate-consolidation.md
# Phase 9: CLI Test and Validate Consolidation

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [00-overview.md](00-overview.md)

> **Purpose**: Consolidate test and validation entrypoints into the `studiomcp` CLI, providing a
> unified interface for running unit tests, integration tests, and validators.

## Phase Summary

**Status**: Done
**Implementation**: `src/StudioMCP/CLI/Test.hs`, `src/StudioMCP/CLI/Command.hs`, `src/StudioMCP/CLI/Cluster.hs`
**Docs to update**: `documents/reference/cli_reference.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`

### Goal

Consolidate all test and validation entrypoints into the `studiomcp` CLI, providing a unified
interface for running unit tests, integration tests, and all validators.

### Deliverables

1. **Test Commands**
   - `studiomcp test` - Run all tests (unit + integration)
   - `studiomcp test all` - Run all tests (unit + integration)
   - `studiomcp test unit` - Run unit tests only
   - `studiomcp test integration` - Run integration tests only

2. **Validate All Command**
   - `studiomcp validate all` - Run all 28 validators with aggregate reporting

3. **CLI Reference Documentation**
   - Multi-tiered, category-organized CLI reference at `documents/reference/cli_reference.md`

4. **CLI-First Testing Policy**
   - Policy documented in `development_plan_standards.md`

### Validation

#### Validation Prerequisites

All validation commands run inside the outer container after bootstrap:

```bash
docker compose up -d
```

#### Validation Gates

```bash
# Verify test commands
docker compose exec studiomcp-env studiomcp test unit
docker compose exec studiomcp-env studiomcp test integration
docker compose exec studiomcp-env studiomcp test all

# Verify validate all command
docker compose exec studiomcp-env studiomcp validate all

# Verify docs
docker compose exec studiomcp-env studiomcp validate docs
```

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/reference/cli_reference.md` - New CLI reference organized by command category

**Product docs to create/update:**
- None.

**Cross-references to add:**
- `DEVELOPMENT_PLAN/development_plan_standards.md` - CLI-First Testing Policy section

## Implementation Details

### New Files

| File | Description |
|------|-------------|
| `src/StudioMCP/CLI/Test.hs` | Test command handlers (`runTestUnit`, `runTestIntegration`, `runTestAll`) |
| `documents/reference/cli_reference.md` | Category-organized CLI reference |

### Modified Files

| File | Changes |
|------|---------|
| `src/StudioMCP/CLI/Command.hs` | Added `TestCommand` type, `ValidateAllCommand`, parser updates |
| `src/StudioMCP/CLI/Cluster.hs` | Added `validateAll` function |
| `app/Main.hs` | Wired up `TestCommand` dispatch |
| `studioMCP.cabal` | Added `StudioMCP.CLI.Test` to exposed-modules |
| `DEVELOPMENT_PLAN/development_plan_standards.md` | Added CLI-First Testing Policy |

### Command Implementation

The test commands invoke `cabal test` directly:

```haskell
runTestUnit :: IO ()
runTestUnit = do
  putStrLn "Running unit tests..."
  (exitCode, _, _) <- readProcessWithExitCode "cabal"
    ["test", "unit-tests", "--test-show-details=direct"]
    ""
  -- Handle exit code
```

The `validateAll` command runs all validators sequentially with error handling:

```haskell
validateAll :: IO ()
validateAll = do
  putStrLn "Running all validators..."
  let validators = [ ("docs", validateDocsCommand), ... ]
  results <- forM validators $ \(name, validator) -> do
    result <- try validator
    -- Report pass/fail
  -- Aggregate summary
```

## Test Mapping

| Command | Test Suite |
|---------|------------|
| `studiomcp test unit` | `unit-tests` (844 tests) |
| `studiomcp test integration` | `integration-tests` (16 tests) |
| `studiomcp test all` | Both suites |
| `studiomcp validate all` | All 28 validators |

## Cross-References

- [README.md](README.md#phase-overview)
- [00-overview.md](00-overview.md)
- [development_plan_standards.md](development_plan_standards.md#cli-first-testing-policy)
- [documents/reference/cli_reference.md](../documents/reference/cli_reference.md#studiomcp-cli-reference)

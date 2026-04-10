# File: DEVELOPMENT_PLAN/phase-1-repository-dag-runtime-foundations.md
# Phase 1: Repository, DAG, and Runtime Foundations

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [system-components.md](system-components.md)

> **Purpose**: Define the repository, DAG execution engine, tool boundaries, worker runtime, and
> foundational validation surface that the rest of the system builds on.

## Phase Summary

**Status**: Done
**Implementation**: `src/StudioMCP/DAG/Parser.hs`, `src/StudioMCP/DAG/Validator.hs`, `src/StudioMCP/DAG/Executor.hs`, `src/StudioMCP/DAG/Scheduler.hs`, `src/StudioMCP/DAG/Timeout.hs`, `src/StudioMCP/DAG/Memoization.hs`, `src/StudioMCP/Tools/Boundary.hs`, `src/StudioMCP/Tools/FFmpeg.hs`, `src/StudioMCP/Worker/Server.hs`, `src/StudioMCP/Inference/Host.hs`
**Docs to update**: `documents/domain/dag_specification.md`, `documents/architecture/parallel_scheduling.md`, `documents/tools/ffmpeg.md`

### Goal

Establish a buildable Haskell repository with DAG parsing and execution, tool boundaries, runtime
adapters, worker entrypoints, and foundational validation commands.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| DAG parser and validator | `src/StudioMCP/DAG/Parser.hs`, `src/StudioMCP/DAG/Validator.hs` | Done |
| Sequential executor | `src/StudioMCP/DAG/Executor.hs` | Done |
| Parallel scheduler | `src/StudioMCP/DAG/Scheduler.hs` | Done |
| Timeout and memoization | `src/StudioMCP/DAG/Timeout.hs`, `src/StudioMCP/DAG/Memoization.hs` | Done |
| Summary model | `src/StudioMCP/DAG/Summary.hs` | Done |
| Boundary runtime | `src/StudioMCP/Tools/Boundary.hs` | Done |
| FFmpeg adapter | `src/StudioMCP/Tools/FFmpeg.hs` | Done |
| Pulsar messaging | `src/StudioMCP/Messaging/Pulsar.hs` | Done |
| MinIO storage | `src/StudioMCP/Storage/MinIO.hs` | Done |
| Worker entrypoint | `src/StudioMCP/Worker/Server.hs` | Done |
| Inference entrypoint | `src/StudioMCP/Inference/Host.hs`, `src/StudioMCP/Inference/ReferenceModel.hs` | Done |
| Build artifact isolation | `cabal.project`, `Makefile` | Done |

### Validation

#### Validation Prerequisites

All validation commands run inside the outer container after bootstrap:

```bash
docker compose up -d
```

#### Validation Gates

| Check | Command | Expected |
|-------|---------|----------|
| Build | `docker compose exec studiomcp-env cabal build all` | Success (artifacts in /opt/build/studiomcp) |
| Unit tests | `docker compose exec studiomcp-env cabal test unit-tests` | Pass |
| DAG fixtures | `docker compose exec studiomcp-env studiomcp dag validate-fixtures` | PASS |
| Boundary | `docker compose exec studiomcp-env studiomcp validate boundary` | PASS |
| FFmpeg | `docker compose exec studiomcp-env studiomcp validate ffmpeg-adapter` | PASS |
| Executor | `docker compose exec studiomcp-env studiomcp validate executor` | PASS |
| Worker | `docker compose exec studiomcp-env studiomcp validate worker` | PASS |
| End to end DAG path | `docker compose exec studiomcp-env studiomcp validate e2e` | PASS |
| Inference advisory path | `docker compose exec studiomcp-env studiomcp validate inference` | PASS |

### Test Mapping

| Test | File |
|------|------|
| DAG parser | `test/DAG/ParserSpec.hs` |
| DAG validator | `test/DAG/ValidatorSpec.hs` |
| Executor | `test/DAG/ExecutorSpec.hs` |
| Scheduler | `test/DAG/SchedulerSpec.hs` |
| Boundary | `test/Tools/BoundarySpec.hs` |
| FFmpeg | `test/Tools/FFmpegSpec.hs` |
| Worker | `test/Worker/ServerSpec.hs` |
| Integration: boundary | `test/Integration/HarnessSpec.hs` |
| Integration: executor | `test/Integration/HarnessSpec.hs` |

### Remaining Work

None. This phase is complete on the current supported path.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/domain/dag_specification.md` - DAG schema and execution-domain rules
- `documents/architecture/parallel_scheduling.md` - scheduler and execution behavior
- `documents/tools/ffmpeg.md` - FFmpeg adapter contract and validation path

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [00-overview.md](00-overview.md) aligned if the execution-runtime foundation changes.
- Keep [system-components.md](system-components.md) aligned if runtime ownership changes.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [../documents/domain/dag_specification.md](../documents/domain/dag_specification.md)

# File: documents/architecture/parallel_scheduling.md
# Parallel Scheduling

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [overview.md](overview.md#canonical-follow-on-documents), [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#current-repo-assessment-against-this-plan)

> **Purpose**: Canonical current-state contract for the deterministic parallel scheduler implemented in `studioMCP`, including the semantics it must preserve as the runtime evolves.

## Summary

`studioMCP` now executes DAGs in deterministic topological batches. The runtime runs each runnable batch concurrently while preserving the same externally visible semantics that previously held under strictly sequential execution:

- DAG validity is still decided before execution starts
- every node still resolves to a typed success or structured failure
- timeout remains a first-class failure outcome
- the final summary remains the terminal immutable record of the run

This document defines the guarantees of the implemented scheduler and the constraints any future optimization must preserve.

## Execution Model

The implemented scheduler reduces wall-clock time for workflows with independent stages:

```
DAG: A -> [B, C] -> D

Sequential: A, B, C, D (4 time units)
Parallel:   A, (B || C), D (3 time units)
```

Independent nodes (B and C above) may execute concurrently while respecting dependency edges. The current runtime groups runnable nodes into deterministic batches using stable `NodeId` ordering and executes each batch concurrently before advancing to the next batch.

## Design Rationale

Parallel scheduling was chosen for the following reasons:

- **Performance**: Parallel execution reduces total workflow time for DAGs with independent branches
- **Type safety**: Typed boundaries prevent data races between parallel stages
- **Observability**: Deterministic scheduling enables reproducible debugging
- **Backward compatibility**: Sequential semantics preserved for linear DAGs

This design implies that worker pool sizing affects parallel throughput, Pulsar topic partitioning must support concurrent consumers, resource quotas must account for parallel resource consumption, and monitoring must track both per-stage and aggregate metrics.

## Correctness Baseline

- the sequential topological order remains the semantic baseline for validation, reporting order, and summary construction
- DAG validation remains the authority for dependency correctness before execution starts
- parallel scheduling may change throughput, but it may not redefine runtime semantics
- the standalone `worker` entrypoint may support direct execution, but the server remains the authoritative orchestration runtime

## Scheduling Guarantees

- Only nodes whose dependencies have already completed successfully may become runnable.
- The runnable set may execute concurrently, but summary lineage must still be emitted in a deterministic order.
- Deterministic order means: when multiple nodes become runnable at the same logical step, their recorded execution order must be derived from a stable tie-breaker such as normalized `NodeId`.
- A node that depends on any failed or timed-out upstream node must not execute. It must produce the same structured upstream-dependency failure projection used by the sequential executor.
- Summary nodes remain terminal aggregation nodes. They may not run until all declared inputs have completed or failed.

## Failure Semantics

- A node timeout remains a typed node outcome, not an infrastructure exception.
- A failed node must prevent downstream nodes from executing when their declared inputs require that node.
- Parallel work must not erase partial progress. Completed successful node outcomes still contribute to the final summary and manifest set.
- Messaging, metrics, and logs must remain correlation-safe under concurrency. `runId` and `nodeId` must continue to identify every meaningful lifecycle event.
- Parallel scheduling must not invent retry behavior. Any retry policy must be explicitly designed in a later planning pass.

## Optimization Notes

- Prefer bounded worker pools over unbounded fork-per-node behavior.
- Preserve content-addressed memoization boundaries. Parallel scheduling may reduce wall-clock time, but it must not weaken cache key determinism.
- Keep MinIO writes and Pulsar event publication behind the same typed adapter contracts that already exist for the sequential runtime.
- If zero-copy or reduced-copy media handling is introduced, it must remain an optimization beneath the same typed node contracts and summary model.

## Non-Goals

- This design does not authorize speculative execution of nodes whose dependencies are unresolved.
- This design does not authorize partial summary emission as a replacement for the final immutable summary.
- This design does not introduce distributed scheduling across multiple clusters or hosts.
- This design does not require the standalone `worker` runtime entrypoint to become authoritative.

## Cross-References

- [Architecture Overview](overview.md#architecture-overview)
- [Server Mode](server_mode.md#server-mode)
- [studioMCP Development Plan](../../STUDIOMCP_DEVELOPMENT_PLAN.md#studiomcp-development-plan)

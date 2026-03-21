# File: documents/architecture/parallel_scheduling.md
# Parallel Scheduling

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [overview.md](overview.md#canonical-follow-on-documents), [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#phase-17-parallel-scheduling-and-optimization-design-package), [../adr/0002_parallel_scheduling.md](../adr/0002_parallel_scheduling.md#cross-references)

> **Purpose**: Canonical design note for how `studioMCP` may add deterministic parallel scheduling without weakening the typed execution, timeout, and summary guarantees that already exist in the sequential runtime.

## Summary

`studioMCP` currently executes DAGs sequentially in topological order. Any future parallel executor must preserve the same externally visible semantics:

- DAG validity is still decided before execution starts
- every node still resolves to a typed success or structured failure
- timeout remains a first-class failure outcome
- the final summary remains the terminal immutable record of the run

This document records the required guarantees for a future parallel scheduler. It does not claim that production parallel execution code exists today.

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
- [ADR 0002: Parallel Scheduling](../adr/0002_parallel_scheduling.md#adr-0002-parallel-scheduling)
- [studioMCP Development Plan](../../STUDIOMCP_DEVELOPMENT_PLAN.md#phase-17-parallel-scheduling-and-optimization-design-package)

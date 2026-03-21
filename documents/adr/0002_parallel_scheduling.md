# File: documents/adr/0002_parallel_scheduling.md
# ADR 0002: Parallel Scheduling

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../architecture/parallel_scheduling.md](../architecture/parallel_scheduling.md#cross-references), [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#phase-17-parallel-scheduling-and-optimization-design-package)

> **Purpose**: Record the design decision to treat parallel scheduling as a future execution optimization that must preserve the current sequential runtime's typed failure, timeout, memoization, and summary guarantees.

## Context

- the current runtime executes DAGs sequentially in topological order
- the current plan already delivers typed failures, persisted summaries, Pulsar lifecycle events, MinIO persistence, MCP handlers, inference guardrails, and observability
- future performance work must not weaken the semantics that the current phases already validate

## Decision

`studioMCP` should treat parallel scheduling as a bounded, deterministic optimization layer rather than as a semantic rewrite of the execution model.

Required decision points:

- preserve the existing DAG validator as the authority for dependency correctness
- allow concurrency only among dependency-satisfied runnable nodes
- preserve deterministic summary ordering with a stable scheduler tie-breaker
- keep timeout projection, upstream-failure projection, and summary assembly semantically identical to the sequential executor

## Tradeoffs

Positive:

- allows wall-clock improvements for independent media-processing branches
- keeps the public execution contract stable while improving throughput
- reduces the chance that future optimization work quietly weakens failure reporting

Negative:

- requires extra care to keep logs, events, and summary ordering deterministic
- increases adapter and persistence coordination complexity
- makes debugging race-related defects harder than the current sequential runtime

## Consequences

- the sequential executor remains the correctness baseline
- any production parallel executor should land in a new implementation phase, not as an unbounded extension of the design phase
- the standalone `worker` entrypoint may support direct execution, but the server remains the authoritative orchestration runtime

## Cross-References

- [Parallel Scheduling](../architecture/parallel_scheduling.md#parallel-scheduling)
- [Server Mode](../architecture/server_mode.md#server-mode)
- [studioMCP Development Plan](../../STUDIOMCP_DEVELOPMENT_PLAN.md#phase-17-parallel-scheduling-and-optimization-design-package)

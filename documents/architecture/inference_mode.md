# File: documents/architecture/inference_mode.md
# Inference Mode

**Status**: Authoritative source
**Supersedes**: legacy `documents/architecture/inference-mode.md`
**Referenced by**: [overview.md](overview.md#canonical-follow-on-documents), [server_mode.md](server_mode.md#cross-references), [../README.md](../README.md#documentation-suite)

> **Purpose**: Canonical definition of the optional local assistive model path in `studioMCP`.

## Summary

Inference mode is an assistive layer for planning and operator support. It may help draft DAGs, suggest repairs, answer documentation questions, and explain summaries, but it does not own execution semantics.

Current repo note: the inference runtime is implemented. `studiomcp inference` and `studiomcp-inference` expose an advisory HTTP service with `POST /advice`, `GET /healthz`, and `GET /version`, apply prompt rendering plus guardrails, and surface unavailable model-host behavior as a typed HTTP failure. Delivery status lives in [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#phase-14-inference-advisory-mode-with-guardrails).

## Allowed Uses

- DAG drafting
- DAG repair suggestions
- tool selection hints
- documentation question answering
- summary explanation

## Forbidden Uses

- bypassing typed validation
- inventing execution success
- mutating persisted run state directly
- replacing the Haskell execution contract

## Cross-References

- [Architecture Overview](overview.md#architecture-overview)
- [Server Mode](server_mode.md#server-mode)
- [DAG Specification](../domain/dag_specification.md#dag-specification)

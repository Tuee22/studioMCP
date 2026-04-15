# File: documents/architecture/inference_mode.md
# Inference Mode

**Status**: Authoritative source
**Supersedes**: legacy `documents/architecture/inference-mode.md`
**Referenced by**: [overview.md](overview.md#canonical-follow-on-documents), [server_mode.md](server_mode.md#cross-references), [../README.md](../README.md#documentation-suite)

> **Purpose**: Canonical definition of the optional local assistive model path in `studioMCP`.

## Summary

Inference mode is an assistive layer for planning and operator support. It may help draft DAGs, suggest repairs, answer documentation questions, and explain summaries, but it does not own execution semantics.

Current repo note: the inference runtime is implemented. The supported outer-container entrypoint
is `docker compose run --rm studiomcp studiomcp inference`. The repo also ships the
`studiomcp-inference` executable for focused process debugging, but `studiomcp` remains the
canonical supported CLI surface. The service exposes `POST /advice`, `GET /healthz`,
`GET /health/live`, `GET /health/ready`, and `GET /version`, applies prompt rendering plus
guardrails, and reports dependency-aware readiness blocking reasons when the advisory
reference-model path is unavailable. Current implementation status lives in
[../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/00-overview.md#current-repo-assessment-against-this-plan).

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

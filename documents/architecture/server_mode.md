# File: documents/architecture/server_mode.md
# Server Mode

**Status**: Authoritative source
**Supersedes**: legacy `documents/architecture/server-mode.md`
**Referenced by**: [overview.md](overview.md#canonical-follow-on-documents), [../README.md](../README.md#documentation-suite)

> **Purpose**: Canonical definition of the authoritative execution runtime in `studioMCP`.

## Summary

Server mode is the authoritative execution path. It is responsible for validating DAGs, coordinating execution, publishing state, persisting immutable outputs, and deriving final summaries.

Current repo note: the server runtime is implemented. `studiomcp server` and `studiomcp-server` expose the HTTP control surface on port `3000`, including `POST /runs`, `GET /runs/:id/summary`, `GET /healthz`, `GET /version`, and `GET /metrics`. Delivery status lives in [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#phase-13-mcp-server-transport-handlers-and-protocol-level-tests).

Phase-boundary note: the transport and observability phases are both complete in the current plan. The server now exposes both the submission and summary handlers plus the admin and observability surface they depend on.

## Responsibilities

- accept DAG submissions
- validate DAG definitions before execution
- schedule node execution
- project tool behavior into typed success or failure values
- update Pulsar with in-flight state
- persist immutable artifacts and summaries in MinIO

## Non-Responsibilities

- inventing DAG validity
- allowing callers to bypass the Haskell validator
- letting inference output mutate persisted state directly

## Cross-References

- [Architecture Overview](overview.md#architecture-overview)
- [Inference Mode](inference_mode.md#inference-mode)
- [Pulsar vs MinIO](pulsar_vs_minio.md#pulsar-vs-minio)

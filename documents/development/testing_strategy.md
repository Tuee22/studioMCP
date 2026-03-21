# File: documents/development/testing_strategy.md
# Testing Strategy

**Status**: Authoritative source
**Supersedes**: legacy `documents/development/testing-strategy.md`
**Referenced by**: [../README.md](../README.md#documentation-suite), [../architecture/overview.md](../architecture/overview.md#canonical-follow-on-documents), [../architecture/pulsar_vs_minio.md](../architecture/pulsar_vs_minio.md#testing-implication), [../reference/cli_surface.md](../reference/cli_surface.md#cross-references)

> **Purpose**: Canonical testing policy for unit tests, integration tests, and native Haskell validation entrypoints in `studioMCP`.

## Unit Tests

Unit tests are pure Haskell tests.

- mock all side effects
- do not talk to live Pulsar
- do not talk to live MinIO
- do not require network access
- do not run external tools unless a phase gate explicitly allows a deterministic local helper-process fixture
- use pure test doubles, in-memory interpreters, and deterministic fixtures

Use unit tests for:

- DAG validation
- railway semantics
- timeout-to-failure projection
- summary construction
- memoization-key derivation
- failure propagation
- execution-state transitions
- storage-key and manifest derivation

## Integration Tests

Integration tests exercise real boundaries.

- use real Pulsar and MinIO sidecars
- use the same foreign or process boundary style as production code when adapters exist
- verify that Haskell contracts survive contact with real services and processes
- phase exit gates must prove the relevant tests are wired into a Cabal test suite and actually executed; spec-file existence alone is not enough

Expected integration coverage grows by phase and should include at least:

- Pulsar connectivity and event flow
- MinIO object creation and retrieval
- boundary execution against deterministic helper processes and later real tools
- full end-to-end DAG execution
- MCP protocol and observability behavior once the server surface exists
- advisory inference behavior and unavailable-model-host projection

Integration note: test orchestration must migrate into the Haskell CLI command surface rather than shell wrappers.

## Native Validation Rules

- do not add repository shell scripts as supported validation entrypoints
- repeated multi-step verification paths must be exposed as Haskell CLI commands
- when a validation command starts long-lived processes, the Haskell implementation must own startup, readiness checks, assertions, and cleanup
- do not treat a stray manually started process as phase verification

## Reproducible Environment

Stateful services still require a resettable environment.

That environment is expected to be managed through the containerized Haskell CLI workflow. It must be allowed to:

- stop and recreate sidecars
- wipe volumes
- recreate buckets and other required service state
- reseed deterministic fixtures
- wait for readiness before tests start

## Current Implemented Coverage

- unit coverage currently exists for DAG validation, parser-fixture automation, railway semantics, timeout mapping, memoization key normalization, success and failure summary construction plus JSON round-trip, messaging event/state/topic contracts, storage key and manifest derivation, MinIO failure mapping, and deterministic boundary success, failure, and timeout projection
- integration coverage currently includes the outer-container cluster workflow plus real Pulsar publish and consume validation, real MinIO memo, manifest, and summary round-trips against the deployed sidecars, native boundary validation through deterministic helper processes in the outer container, real FFmpeg adapter validation with deterministic fixture reseeding plus success and failure assertions, sequential executor validation, end-to-end DAG success and failure runs, live worker-runtime validation against the deployed sidecars, MCP submission and summary validation against the deployed server, advisory inference validation against a fake model host, and observability validation for metrics, health degradation, and correlation-bearing logs
- the remaining gaps are no longer foundational test categories; they are future coverage expansions tied to new tools or new cluster commands

## Cross-References

- [Local Development](local_dev.md#local-development)
- [Pulsar vs MinIO](../architecture/pulsar_vs_minio.md#pulsar-vs-minio)
- [Kubernetes-Native Development Policy](../engineering/k8s_native_dev_policy.md#kubernetes-native-development-policy)
- [CLI Surface Reference](../reference/cli_surface.md#cli-surface-reference)

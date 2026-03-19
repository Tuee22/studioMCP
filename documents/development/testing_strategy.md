# File: documents/development/testing_strategy.md
# Testing Strategy

**Status**: Authoritative source
**Supersedes**: legacy `documents/development/testing-strategy.md`
**Referenced by**: [../README.md](../README.md#documentation-suite), [../architecture/overview.md](../architecture/overview.md#canonical-follow-on-documents), [../architecture/pulsar_vs_minio.md](../architecture/pulsar_vs_minio.md#testing-implication)

> **Purpose**: Canonical testing policy for unit tests, integration tests, and the reproducible sidecar harness in `studioMCP`.

## Unit Tests

Unit tests are pure Haskell tests.

- mock all side effects
- do not talk to live Pulsar
- do not talk to live MinIO
- do not run external tools
- do not require network access

Use unit tests for:

- DAG validation
- railway semantics
- timeout mapping
- summary construction
- memoization rules
- failure propagation

## Integration Tests

Integration tests exercise real boundaries.

- use real Pulsar and MinIO sidecars
- use the same foreign or process boundary style as production code when adapters exist
- verify that Haskell contracts survive contact with real services and processes

Integration harness note: Compose is retained here as a narrow test fixture mechanism. It is not the deployment source of truth for the application runtime.

## Reproducible Harness

Stateful services require a resettable harness.

The canonical harness entrypoint is [../../scripts/integration-harness.sh](../../scripts/integration-harness.sh). It must be allowed to:

- stop and recreate sidecars
- wipe volumes
- recreate buckets and other required service state
- reseed deterministic fixtures
- wait for readiness before tests start

## Current Implemented Coverage

- pure unit suite for DAG and summary primitives
- live integration checks for Pulsar and MinIO reachability under the harness

## Cross-References

- [Local Development](local_dev.md#local-development)
- [Pulsar vs MinIO](../architecture/pulsar_vs_minio.md#pulsar-vs-minio)
- [Kubernetes-Native Development Policy](../engineering/k8s_native_dev_policy.md#kubernetes-native-development-policy)

# File: documents/tools/minio.md
# MinIO

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite)

> **Purpose**: Canonical integration note for MinIO as the immutable storage backend in `studioMCP`.

## Role

MinIO stores:

- memoized node outputs
- summaries
- manifests
- durable media artifacts

## Testing Rule

MinIO is stateful infrastructure. Integration tests must reset it through the harness when reproducibility matters.

## Cross-References

- [Pulsar vs MinIO](../architecture/pulsar_vs_minio.md#pulsar-vs-minio)
- [Testing Strategy](../development/testing_strategy.md#testing-strategy)

# File: documents/tools/pulsar.md
# Pulsar

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite)

> **Purpose**: Canonical integration note for Pulsar as the in-flight execution-state backend in `studioMCP`.

## Role

Pulsar carries:

- run submission events
- node lifecycle transitions
- summary emission notifications

## Testing Rule

Pulsar is stateful infrastructure. Integration tests should exercise it through the resettable harness rather than through ad hoc local state.

## Cross-References

- [Pulsar vs MinIO](../architecture/pulsar_vs_minio.md#pulsar-vs-minio)
- [Testing Strategy](../development/testing_strategy.md#testing-strategy)

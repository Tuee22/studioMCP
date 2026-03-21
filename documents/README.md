# File: documents/README.md
# studioMCP Documentation Index

**Status**: Reference only
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#contribution-guidance), [documentation_standards.md](documentation_standards.md#cross-references)

> **Purpose**: Entry point to the `documents/` suite and index of the current canonical documentation set.
> **📖 Authoritative Reference**: [Documentation Standards](documentation_standards.md#studiomcp-documentation-standards)

## Suite Structure

- `architecture/`: canonical system boundaries, storage split, and operating modes
- `development/`: contributor workflows, local setup, and testing policy
- `domain/`: DAG model and format specifications
- `engineering/`: engineering standards such as the Kubernetes-native development policy
- `operations/`: runbooks and operational debugging procedures
- `reference/`: public surface and schema-oriented reference material
- `tools/`: tool and sidecar integration notes
- `adr/`: architecture decision records

## Canonical Documents

- [Architecture Overview](architecture/overview.md#architecture-overview)
- [CLI Architecture](architecture/cli_architecture.md#cli-architecture)
- [Pulsar vs MinIO](architecture/pulsar_vs_minio.md#pulsar-vs-minio)
- [Server Mode](architecture/server_mode.md#server-mode)
- [Inference Mode](architecture/inference_mode.md#inference-mode)
- [Parallel Scheduling](architecture/parallel_scheduling.md#parallel-scheduling)
- [DAG Specification](domain/dag_specification.md#dag-specification)
- [Docker Policy](engineering/docker_policy.md#docker-policy)
- [Kubernetes Storage Policy](engineering/k8s_storage.md#kubernetes-storage-policy)
- [Kubernetes-Native Development Policy](engineering/k8s_native_dev_policy.md#kubernetes-native-development-policy)
- [Local Development](development/local_dev.md#local-development)
- [Testing Strategy](development/testing_strategy.md#testing-strategy)
- [Documentation Standards](documentation_standards.md#studiomcp-documentation-standards)
- [FFmpeg](tools/ffmpeg.md#ffmpeg)
- [MinIO](tools/minio.md#minio)
- [Pulsar](tools/pulsar.md#pulsar)
- [Local Debugging Runbook](operations/runbook_local_debugging.md#local-debugging-runbook)
- [CLI Surface Reference](reference/cli_surface.md#cli-surface-reference)
- [MCP Surface Reference](reference/mcp_surface.md#mcp-surface-reference)
- [ADR 0001: MCP Transport](adr/0001_mcp_transport.md#adr-0001-mcp-transport)
- [ADR 0002: Parallel Scheduling](adr/0002_parallel_scheduling.md#adr-0002-parallel-scheduling)

## Working Rules

- [Documentation Standards](documentation_standards.md#studiomcp-documentation-standards) is the SSoT for documentation rules.
- This index is the navigation layer for the suite and should be updated when new canonical docs are added.
- Each concept has one canonical document. Other docs link back to it.

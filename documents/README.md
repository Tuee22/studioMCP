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
- `operations/`: future runbooks and operational procedures
- `reference/`: future generated and API-oriented reference material
- `tools/`: tool and sidecar integration notes
- `adr/`: future architecture decision records

## Canonical Documents

- [Architecture Overview](architecture/overview.md#architecture-overview)
- [Pulsar vs MinIO](architecture/pulsar_vs_minio.md#pulsar-vs-minio)
- [Server Mode](architecture/server_mode.md#server-mode)
- [Inference Mode](architecture/inference_mode.md#inference-mode)
- [DAG Specification](domain/dag_specification.md#dag-specification)
- [Kubernetes-Native Development Policy](engineering/k8s_native_dev_policy.md#kubernetes-native-development-policy)
- [Local Development](development/local_dev.md#local-development)
- [Testing Strategy](development/testing_strategy.md#testing-strategy)
- [Documentation Standards](documentation_standards.md#studiomcp-documentation-standards)

## Working Rules

- Each concept has one canonical document. Other docs link back to it.
- Markdown files inside `documents/` use snake_case filenames.
- Mermaid diagrams must follow the compatibility-safe subset in [documentation_standards.md](documentation_standards.md#mermaid-rendering-rules).

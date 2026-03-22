# File: documents/README.md
# studioMCP Documentation Index

**Status**: Reference only
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#contribution-guidance), [documentation_standards.md](documentation_standards.md#cross-references)

> **Purpose**: Entry point to the `documents/` suite and index of the current canonical documentation set.
> **📖 Authoritative Reference**: [Documentation Standards](documentation_standards.md#studiomcp-documentation-standards)

## Suite Structure

- `architecture/`: canonical system, protocol, auth, and storage architecture
- `development/`: contributor workflows, local setup, and testing policy
- `domain/`: DAG model and format specifications
- `engineering/`: security, scaling, and deployment standards
- `operations/`: runbooks and operational procedures
- `reference/`: public surface, capability, and API-oriented reference material
- `tools/`: tool and sidecar integration notes

## Canonical Documents

- [Architecture Overview](architecture/overview.md#architecture-overview)
- [MCP Protocol Architecture](architecture/mcp_protocol_architecture.md#mcp-protocol-architecture)
- [Server Mode](architecture/server_mode.md#server-mode)
- [Multi-Tenant SaaS MCP Auth Architecture](architecture/multi_tenant_saas_mcp_auth_architecture.md#multi-tenant-saas-mcp-auth-architecture)
- [Artifact Storage Architecture](architecture/artifact_storage_architecture.md#artifact-storage-architecture)
- [CLI Architecture](architecture/cli_architecture.md#cli-architecture)
- [Pulsar vs MinIO](architecture/pulsar_vs_minio.md#pulsar-vs-minio)
- [Parallel Scheduling](architecture/parallel_scheduling.md#parallel-scheduling)
- [DAG Specification](domain/dag_specification.md#dag-specification)
- [Security Model](engineering/security_model.md#security-model)
- [Session Scaling](engineering/session_scaling.md#session-scaling)
- [Docker Policy](engineering/docker_policy.md#docker-policy)
- [Kubernetes Storage Policy](engineering/k8s_storage.md#kubernetes-storage-policy)
- [Kubernetes-Native Development Policy](engineering/k8s_native_dev_policy.md#kubernetes-native-development-policy)
- [Local Development](development/local_dev.md#local-development)
- [Testing Strategy](development/testing_strategy.md#testing-strategy)
- [Documentation Standards](documentation_standards.md#studiomcp-documentation-standards)
- [Local Debugging Runbook](operations/runbook_local_debugging.md#local-debugging-runbook)
- [Keycloak Realm Bootstrap Runbook](operations/keycloak_realm_bootstrap_runbook.md#keycloak-realm-bootstrap-runbook)
- [CLI Surface Reference](reference/cli_surface.md#cli-surface-reference)
- [MCP Surface Reference](reference/mcp_surface.md#mcp-surface-reference)
- [MCP Tool Catalog](reference/mcp_tool_catalog.md#mcp-tool-catalog)
- [Web Portal Surface](reference/web_portal_surface.md#web-portal-surface)
- [FFmpeg](tools/ffmpeg.md#ffmpeg)
- [MinIO](tools/minio.md#minio)
- [Pulsar](tools/pulsar.md#pulsar)

## Working Rules

- [Documentation Standards](documentation_standards.md#studiomcp-documentation-standards) is the SSoT for documentation rules.
- This index is the navigation layer for the suite and must be updated whenever new canonical docs are added.
- Each concept has one canonical document. Other docs link back to it.
- The governed suite contains current-state declarative documentation only. Historical decision records do not belong under `documents/`.

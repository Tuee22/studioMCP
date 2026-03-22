# File: documents/reference/mcp_tool_catalog.md
# MCP Tool Catalog

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [mcp_surface.md](mcp_surface.md#capability-scope), [../architecture/mcp_protocol_architecture.md](../architecture/mcp_protocol_architecture.md#cross-references), [../architecture/artifact_storage_architecture.md](../architecture/artifact_storage_architecture.md#cross-references), [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#documentation-governance)

> **Purpose**: Canonical reference for the target `studioMCP` tool, resource, and prompt catalog exposed through MCP.

## Summary

This document defines the target release-priority MCP capability catalog. It is intentionally explicit because the repository is implementing MCP in Haskell without an official Haskell SDK.

## Current Repo Note

The catalog below is a target-state reference. The current repository has not yet exposed these capabilities through a real MCP surface.

## Tools

| Name | Purpose | Auth Scope | Mutation Class |
| --- | --- | --- | --- |
| `workflow.submit_dag` | Submit a typed DAG workflow for execution. | tenant workflow submit | creates run records and artifacts |
| `workflow.list_runs` | List runs visible to the subject in a tenant. | tenant workflow read | read only |
| `workflow.get_run` | Fetch run status, summary, and manifest references. | tenant workflow read | read only |
| `workflow.cancel_run` | Request cancellation of a run where the runtime supports it. | tenant workflow cancel | mutates run control state |
| `artifact.prepare_upload` | Create a short-lived upload authorization for a tenant storage target. | tenant artifact write | creates upload intent only |
| `artifact.prepare_download` | Create a short-lived download authorization for an artifact version. | tenant artifact read | creates download intent only |
| `artifact.list_versions` | List versions of a logical artifact. | tenant artifact read | read only |
| `artifact.hide` | Mark an artifact hidden without hard deleting the backing media. | tenant artifact govern | metadata only |
| `artifact.archive` | Mark an artifact archived without hard deleting the backing media. | tenant artifact govern | metadata only |
| `tenant.get_profile` | Return tenant-facing configuration and storage targets visible to the caller. | tenant read | read only |

## Tool Rules

- tool names are stable once public
- tool inputs must validate before runtime dispatch
- tool outputs should provide structured content where possible
- no tool may permanently delete media artifacts
- artifact mutation tools are metadata-oriented unless they are explicitly creating new versions
- artifact governance tools may hide, archive, supersede, or revoke future access, but they may not hard delete backing media

## Resources

| URI Pattern | Meaning | Visibility |
| --- | --- | --- |
| `studiomcp://tenants/{tenantId}/runs/{runId}/summary` | run summary projection | tenant scoped |
| `studiomcp://tenants/{tenantId}/runs/{runId}/manifest` | run manifest projection | tenant scoped |
| `studiomcp://tenants/{tenantId}/runs/{runId}/events` | read-oriented execution event stream view | tenant scoped |
| `studiomcp://tenants/{tenantId}/artifacts/{artifactId}` | artifact metadata and version references | tenant scoped |
| `studiomcp://tenants/{tenantId}/docs/{name}` | selected tenant-safe documentation | tenant or platform scoped |

## Prompts

| Name | Purpose | Authority |
| --- | --- | --- |
| `workflow.plan_media_pipeline` | Draft a DAG-oriented media pipeline from user intent. | advisory only |
| `workflow.repair_dag` | Explain or repair a rejected DAG. | advisory only |
| `workflow.explain_failure` | Summarize run failure context for operators or chat UX. | advisory only |

## Deferred Catalog Items

Deferred until justified:

- arbitrary filesystem tools
- raw shell tools
- permanent delete tools
- tenant-crossing search capabilities

## Cross-References

- [MCP Surface Reference](mcp_surface.md#mcp-surface-reference)
- [MCP Protocol Architecture](../architecture/mcp_protocol_architecture.md#mcp-protocol-architecture)
- [Artifact Storage Architecture](../architecture/artifact_storage_architecture.md#artifact-storage-architecture)
- [Web Portal Surface](web_portal_surface.md#web-portal-surface)

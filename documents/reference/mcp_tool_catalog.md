# File: documents/reference/mcp_tool_catalog.md
# MCP Tool Catalog

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [mcp_surface.md](mcp_surface.md#capability-scope), [../architecture/mcp_protocol_architecture.md](../architecture/mcp_protocol_architecture.md#cross-references), [../architecture/artifact_storage_architecture.md](../architecture/artifact_storage_architecture.md#cross-references), [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#documentation-governance)

> **Purpose**: Canonical reference for the target `studioMCP` tool, resource, and prompt catalog exposed through MCP.

## Summary

This document defines the target release-priority MCP capability catalog. It is intentionally explicit because the repository is implementing MCP in Haskell without an official Haskell SDK.

## Current Repo Note

The repository now exposes this catalog through the MCP surface using the stable tool names below. The current implementation returns `CallToolResult` text content for tool responses, so the examples here describe the semantic payload rather than the exact wire wrapper.

## Tools

| Name | Purpose | Auth Scope | Mutation Class |
| --- | --- | --- | --- |
| `workflow.submit` | Submit a typed DAG workflow for execution. | tenant workflow submit | creates run records |
| `workflow.list` | List runs visible to the subject in a tenant. | tenant workflow read | read only |
| `workflow.status` | Fetch run status for a specific run. | tenant workflow read | read only |
| `workflow.cancel` | Request cancellation of a run where the runtime supports it. | tenant workflow cancel | mutates run control state |
| `artifact.upload_url` | Create a tenant-scoped upload artifact and return a short-lived upload authorization. | tenant artifact write | creates upload intent only |
| `artifact.download_url` | Create a short-lived download authorization for an artifact version. | tenant artifact read | read only |
| `artifact.get` | Return artifact metadata and current governance state. | tenant artifact read | read only |
| `artifact.hide` | Mark an artifact hidden without hard deleting the backing media. | tenant artifact govern | metadata only |
| `artifact.archive` | Mark an artifact archived without hard deleting the backing media. | tenant artifact govern | metadata only |
| `tenant.info` | Return tenant-facing metadata visible to the caller. | tenant read | read only |

## Tool Rules

- tool names are stable once public
- tool inputs must validate before runtime dispatch
- tool outputs should provide structured content where possible
- no tool may permanently delete media artifacts
- artifact mutation tools are metadata-oriented unless they are explicitly creating new versions
- artifact governance tools may hide, archive, supersede, or revoke future access, but they may not hard delete backing media

## Tool Schemas

### workflow.submit

Submit a typed DAG workflow for execution.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "dag_spec": {
      "type": "string",
      "description": "The YAML DAG specification"
    },
    "priority": {
      "type": "string",
      "enum": ["low", "normal", "high"],
      "default": "normal"
    },
    "labels": {
      "type": "object",
      "additionalProperties": { "type": "string" }
    }
  },
  "required": ["dag_spec"]
}
```

**Output:**

```json
{
  "runId": "run-abc123",
  "status": "accepted",
  "submittedAt": "2024-01-15T10:00:00Z",
  "message": "Workflow accepted for tenant tenant-acme"
}
```

**Required Scope:** `workflow:write`

### workflow.list

List runs visible to the authenticated user.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "status": {
      "type": "string",
      "enum": ["all", "running", "completed", "failed", "cancelled"]
    },
    "limit": {
      "type": "integer",
      "minimum": 1,
      "maximum": 100,
      "default": 20
    },
    "cursor": {
      "type": "string",
      "description": "Pagination cursor"
    }
  }
}
```

**Output:**

```json
{
  "runs": [
    {
      "runId": "run-abc123",
      "status": "accepted"
    }
  ]
}
```

**Required Scope:** `workflow:read`

### workflow.status

Get detailed status and summary for a specific run.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "run_id": {
      "type": "string",
      "description": "The run identifier"
    }
  },
  "required": ["run_id"]
}
```

**Output:**

```json
{
  "runId": "run-abc123",
  "status": "accepted"
}
```

**Required Scope:** `workflow:read`

### workflow.cancel

Request cancellation of a running workflow.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "run_id": {
      "type": "string"
    },
    "reason": {
      "type": "string",
      "description": "Optional cancellation reason"
    }
  },
  "required": ["run_id"]
}
```

**Output:**

```json
{
  "runId": "run-abc123",
  "status": "cancelled",
  "message": "Cancellation requested"
}
```

**Required Scope:** `workflow:write`

### artifact.upload_url

Generate a presigned URL for artifact upload.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "file_name": {
      "type": "string",
      "description": "Original filename"
    },
    "content_type": {
      "type": "string",
      "description": "MIME type"
    },
    "file_size": {
      "type": "integer",
      "description": "File size in bytes"
    }
  },
  "required": ["content_type"]
}
```

**Output:**

```json
{
  "artifactId": "artifact-xyz789",
  "presignedUrl": "http://localhost:9000/studiomcp-tenant-acme/artifact-xyz789?operation=upload&version=1&signature=abc123",
  "expiresAt": "2024-01-15T10:30:00Z",
  "headers": {
    "Content-Type": "video/mp4"
  }
}
```

**Required Scope:** `artifact:write`

### artifact.download_url

Generate a presigned URL for artifact download.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "artifact_id": {
      "type": "string"
    },
    "version": {
      "type": "integer",
      "description": "Version number, defaults to latest"
    }
  },
  "required": ["artifact_id"]
}
```

**Output:**

```json
{
  "artifactId": "artifact-xyz789",
  "version": 1,
  "presignedUrl": "http://localhost:9000/studiomcp-tenant-acme/artifact-xyz789?operation=download&version=1&signature=def456",
  "expiresAt": "2024-01-15T10:30:00Z",
  "filename": "output.mp4",
  "contentType": "video/mp4",
  "size": 1073741824
}
```

**Required Scope:** `artifact:read`

### artifact.get

Get metadata and current governance state for an artifact.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "artifact_id": {
      "type": "string"
    }
  },
  "required": ["artifact_id"]
}
```

**Output:**

```json
{
  "artifactId": "artifact-xyz789",
  "contentType": "video/mp4",
  "size": 1073741824,
  "version": 1,
  "state": "active"
}
```

**Required Scope:** `artifact:read`

### artifact.hide

Hide an artifact (metadata-only operation).

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "artifact_id": {
      "type": "string"
    },
    "reason": {
      "type": "string",
      "description": "Reason for hiding"
    }
  },
  "required": ["artifact_id"]
}
```

**Output:**

```json
{
  "artifactId": "artifact-xyz789",
  "state": "hidden"
}
```

**Required Scope:** `artifact:manage`

### artifact.archive

Archive an artifact (metadata-only operation).

**Input Schema:**

```json
{
  "type": "object",
  "properties": {
    "artifact_id": {
      "type": "string"
    },
    "reason": {
      "type": "string"
    }
  },
  "required": ["artifact_id"]
}
```

**Output:**

```json
{
  "artifactId": "artifact-xyz789",
  "state": "archived"
}
```

**Required Scope:** `artifact:manage`

### tenant.info

Get tenant profile and current storage usage.

**Input Schema:**

```json
{
  "type": "object",
  "properties": {}
}
```

**Output:**

```json
{
  "tenantId": "tenant-acme",
  "subjectId": "user-123",
  "storageBackend": "platform-minio",
  "quotas": {
    "storageQuotaBytes": 1099511627776
  },
  "artifactCount": 12,
  "usedBytes": 536870912
}
```

**Required Scope:** (authenticated user in tenant)

## Resources

| URI Pattern | Meaning | Visibility |
| --- | --- | --- |
| `studiomcp://summaries/{run_id}` | run summary projection | tenant scoped |
| `studiomcp://manifests/{run_id}` | run manifest projection | tenant scoped |
| `studiomcp://metadata/tenant/{tenant_id}` | tenant metadata | tenant scoped |
| `studiomcp://metadata/quotas` | quota information | tenant scoped |
| `studiomcp://artifacts/{artifact_id}` | artifact metadata and current state | tenant scoped |
| `studiomcp://history/runs` | run history projection | tenant scoped |

## Prompts

| Name | Purpose | Authority |
| --- | --- | --- |
| `dag-planning` | Draft a DAG-oriented media pipeline from user intent. | advisory only |
| `dag-repair` | Explain or repair a rejected DAG. | advisory only |
| `workflow-analysis` | Summarize workflow context and state. | advisory only |
| `artifact-naming` | Suggest artifact naming and metadata conventions. | advisory only |
| `error-diagnosis` | Summarize error context and likely fixes. | advisory only |

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

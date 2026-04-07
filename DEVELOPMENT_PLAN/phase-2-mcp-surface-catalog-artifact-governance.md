# File: DEVELOPMENT_PLAN/phase-2-mcp-surface-catalog-artifact-governance.md
# Phase 2: MCP Surface, Catalog, Artifact Governance, and Observability

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [system-components.md](system-components.md)

> **Purpose**: Define the MCP protocol surface, transport and catalog ownership, storage governance,
> and observability baseline for the repository.

## Phase Summary

**Status**: Done
**Implementation**: `src/StudioMCP/MCP/Core.hs`, `src/StudioMCP/MCP/Transport/Http.hs`, `src/StudioMCP/Storage/Governance.hs`, `src/StudioMCP/Observability/CorrelationId.hs`, `src/StudioMCP/Observability/McpMetrics.hs`, `src/StudioMCP/Observability/Quotas.hs`, `src/StudioMCP/Observability/RateLimiting.hs`, `src/StudioMCP/Observability/Redaction.hs`
**Docs to update**: `documents/architecture/mcp_protocol_architecture.md`, `documents/reference/mcp_surface.md`, `documents/reference/mcp_tool_catalog.md`, `documents/architecture/artifact_storage_architecture.md`

### Goal

Implement a standards-compliant MCP core with transports, catalogs, artifact governance, tenant
storage rules, and observability hooks.

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| MCP core | `src/StudioMCP/MCP/Core.hs` | Done |
| JSON-RPC lifecycle | `src/StudioMCP/MCP/JsonRpc.hs` | Done |
| Stdio transport | `src/StudioMCP/MCP/Transport/Stdio.hs` | Done |
| HTTP transport | `src/StudioMCP/MCP/Transport/Http.hs` | Done |
| Tool catalog | `src/StudioMCP/MCP/Tools.hs` | Done |
| Resource catalog | `src/StudioMCP/MCP/Resources.hs` | Done |
| Prompt catalog | `src/StudioMCP/MCP/Prompts.hs` | Done |
| Artifact governance | `src/StudioMCP/Storage/Governance.hs` | Done |
| Tenant storage | `src/StudioMCP/Storage/TenantStorage.hs` | Done |
| Observability | `src/StudioMCP/Observability/CorrelationId.hs`, `src/StudioMCP/Observability/McpMetrics.hs`, `src/StudioMCP/Observability/Quotas.hs`, `src/StudioMCP/Observability/RateLimiting.hs`, `src/StudioMCP/Observability/Redaction.hs` | Done |
| MCP server | `src/StudioMCP/MCP/Server.hs` | Done |

### Validation

| Check | Command | Expected |
|-------|---------|----------|
| MCP stdio | `studiomcp validate mcp-stdio` | PASS |
| MCP HTTP | `studiomcp validate mcp-http` | PASS |
| Artifact storage | `studiomcp validate artifact-storage` | PASS |
| Artifact governance | `studiomcp validate artifact-governance` | PASS |
| MCP tools | `studiomcp validate mcp-tools` | PASS |
| MCP resources | `studiomcp validate mcp-resources` | PASS |
| MCP prompts | `studiomcp validate mcp-prompts` | PASS |
| Observability | `studiomcp validate observability` | PASS |
| Audit | `studiomcp validate audit` | PASS |
| Quotas | `studiomcp validate quotas` | PASS |
| Rate limit | `studiomcp validate rate-limit` | PASS |
| MCP conformance | `studiomcp validate mcp-conformance` | PASS on the phase-close path |

### Test Mapping

| Test | File |
|------|------|
| MCP core | `test/MCP/CoreSpec.hs` |
| Protocol | `test/MCP/ProtocolSpec.hs` |
| Handlers | `test/MCP/HandlersSpec.hs` |
| Tools | `test/MCP/ToolsSpec.hs` |
| Resources | `test/MCP/ResourcesSpec.hs` |
| Conformance | `test/MCP/ConformanceSpec.hs` |
| Governance | `test/Storage/GovernanceSpec.hs` |
| Integration: MCP HTTP | `test/Integration/HarnessSpec.hs` |

### Remaining Work

None. This phase is complete on the current supported path.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/architecture/mcp_protocol_architecture.md` - protocol lifecycle and transport ownership
- `documents/architecture/artifact_storage_architecture.md` - artifact/data-plane architecture

**Product docs to create/update:**
- `documents/reference/mcp_surface.md` - supported MCP surface and validation path
- `documents/reference/mcp_tool_catalog.md` - tool catalog contract

**Cross-references to add:**
- Keep [system-components.md](system-components.md) aligned if transport or storage ownership changes.
- Keep [phase-4-control-plane-data-plane-contract.md](phase-4-control-plane-data-plane-contract.md) aligned if public endpoints move.

## Cross-References

- [README.md](README.md)
- [system-components.md](system-components.md)
- [phase-4-control-plane-data-plane-contract.md](phase-4-control-plane-data-plane-contract.md)
- [../documents/reference/mcp_surface.md](../documents/reference/mcp_surface.md)

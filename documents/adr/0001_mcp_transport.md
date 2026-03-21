# File: documents/adr/0001_mcp_transport.md
# ADR 0001: MCP Transport

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite), [../reference/mcp_surface.md](../reference/mcp_surface.md#cross-references), [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#recommended-mcp-transport-decision)

> **Purpose**: Record the architectural decision for the default MCP transport shape and the fact that the current server implementation follows it.

## Context

- the repo is Kubernetes-forward and centered on Helm, Skaffold, and kind
- the server now implements the chosen HTTP control surface on port `3000`
- the development plan still needs the decision recorded so later transport work stays anchored

## Decision

The default MCP transport target for `studioMCP` is:

- primary transport: streamable HTTP on port `3000`
- optional secondary transport: `stdio` only if later use cases justify it
- same process admin surface for `/healthz`, `/metrics`, and `/version`

Implementation split:

- the MCP transport phase landed the real transport plus `/healthz` and `/version`
- the observability phase hardened `/healthz` and made `/metrics` meaningful

## Consequences

Positive:

- aligns with the Kubernetes-forward deployment model
- fits straightforwardly with Helm services and Skaffold port-forwarding
- simplifies protocol-level integration testing
- works cleanly with self-contained native CLI validation commands that start and stop the server for protocol and admin-surface checks

Tradeoffs:

- requires explicit protocol and admin-surface design instead of relying on `stdio` alone
- still leaves open whether a future `stdio` mode is worth carrying

Current status:

- this decision is accepted and implemented in the running codebase
- future work may add `stdio`, but the HTTP transport is now the authoritative baseline

## Cross-References

- [MCP Surface Reference](../reference/mcp_surface.md#mcp-surface-reference)
- [Server Mode](../architecture/server_mode.md#server-mode)
- [studioMCP Development Plan](../../STUDIOMCP_DEVELOPMENT_PLAN.md#recommended-mcp-transport-decision)

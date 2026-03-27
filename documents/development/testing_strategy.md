# File: documents/development/testing_strategy.md
# Testing Strategy

**Status**: Authoritative source
**Supersedes**: legacy `documents/development/testing-strategy.md`
**Referenced by**: [../README.md](../README.md#documentation-suite), [../architecture/overview.md](../architecture/overview.md#cross-references), [../reference/cli_surface.md](../reference/cli_surface.md#cross-references), [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#documentation-governance)

> **Purpose**: Canonical testing policy for unit tests, integration tests, protocol validation, auth validation, and runtime verification in `studioMCP`.

## No Silent Failures Policy

Tests must never be silently skipped, suppressed, or gated behind environment variables.

Forbidden practices:

- environment variable gates that convert tests to "pending"
- catch-all exception handlers that swallow failures
- conditional test registration based on environment
- any mechanism that makes `0 failures` appear when tests haven't run

Acceptable practices:

- tests that fail with clear error messages when infrastructure is unavailable
- tests that fail with actionable remediation steps (e.g., "run `studiomcp cluster up` first")
- CI configurations that run different test suites in different jobs (with explicit job names)

Rationale: a test suite that reports "0 failures" must mean all tests actually executed and passed. Silent skips create false confidence and hide integration gaps.

## Testing Layers

`studioMCP` requires five test layers:

- unit tests
- component integration tests
- protocol validation tests
- cluster and operational validation tests
- product-surface end-to-end tests

## Unit Tests

Unit tests remain pure Haskell tests wherever possible.

Use unit tests for:

- DAG validation
- summary construction
- timeout projection
- memoization contracts
- protocol state machine behavior
- tool schema validation
- authz policy evaluation
- artifact governance rules

Unit tests must not depend on:

- live Keycloak
- live Redis
- live object storage
- live browsers

## Integration Tests

Integration tests exercise real boundaries and must grow beyond the current sidecar-focused runtime checks.

Required integration categories:

- storage and messaging boundaries
- Keycloak-backed auth
- session-store-backed reconnect behavior
- real MCP transport behavior over `stdio`
- real MCP transport behavior over Streamable HTTP
- browser and BFF flows through the live BFF-to-MCP path

## Protocol Validation

Protocol validation is a first-class category and must not be reduced to ad hoc REST assertions.

Required protocol validation includes:

- lifecycle negotiation
- tool and resource behavior
- prompt behavior where implemented
- wrong-order lifecycle rejection
- malformed protocol message rejection
- Inspector connectivity

## Multi-Node Validation

Because sticky sessions are forbidden, the test plan must include:

- reconnect to a different listener pod
- rolling deployment behavior
- remote session-store outage behavior
- resumption or deterministic reinitialization behavior

## Security Validation

Security validation must cover:

- wrong-issuer rejection
- wrong-audience rejection
- cross-tenant access denial
- service-account scope enforcement
- no token passthrough behavior
- forbidden permanent media deletion

## Browser And BFF Validation

The BFF and browser-facing validation surface must cover:

- login
- profile lookup
- upload
- run submission
- run listing and status observation
- run cancellation
- artifact governance actions
- progress observation
- artifact download
- chat-assisted workflow operations
- logout and session invalidation

## Current Repo Note

The current repo already has strong foundational unit and integration coverage for execution and sidecar behavior. Its MCP transport and conformance coverage now runs through `validate mcp-stdio`, `validate mcp-http`, and `validate mcp-conformance`, and the browser-facing BFF surface is exercised through `validate web-bff` plus the outer integration harness, including the served browser shell and the chat/run SSE routes.

## Cross-References

- [Architecture Overview](../architecture/overview.md#architecture-overview)
- [MCP Protocol Architecture](../architecture/mcp_protocol_architecture.md#mcp-protocol-architecture)
- [Session Scaling](../engineering/session_scaling.md#session-scaling)
- [Security Model](../engineering/security_model.md#security-model)
- [Web Portal Surface](../reference/web_portal_surface.md#web-portal-surface)

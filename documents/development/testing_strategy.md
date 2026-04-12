# File: documents/development/testing_strategy.md
# Testing Strategy

**Status**: Authoritative source
**Supersedes**: legacy `documents/development/testing-strategy.md`
**Referenced by**: [../README.md](../README.md#documentation-suite), [local_dev.md](local_dev.md#cross-references), [../architecture/overview.md](../architecture/overview.md#cross-references), [../reference/cli_surface.md](../reference/cli_surface.md#cross-references), [../../DEVELOPMENT_PLAN.md](../../DEVELOPMENT_PLAN.md#documentation-governance)

> **Purpose**: Canonical testing policy for unit tests, property tests, state-machine tests, integration tests, protocol validation, and browser-surface validation in `studioMCP`.

## No Silent Failures Policy

Tests must never be silently skipped, suppressed, or gated behind environment variables.

Forbidden practices:

- environment variable gates that convert tests to "pending"
- catch-all exception handlers that swallow failures
- conditional test registration based on environment
- any mechanism that makes `0 failures` appear when tests have not run

Acceptable practices:

- tests that fail with clear error messages when infrastructure is unavailable
- tests that fail with actionable remediation steps such as `run studiomcp cluster up first`
- CI configurations that run different suites in different jobs with explicit job names

Rationale: a test suite that reports `0 failures` must mean all registered tests actually executed and passed.

## Haskell-First Testing Rules

`studioMCP` treats tests as proof of invariants and contracts, not as a pursuit of line coverage.

- keep decision logic pure wherever possible
- write small example tests for concrete regressions and generated property tests for algebraic or normalization-heavy behavior
- prefer state-machine or model-based tests for lifecycle-sensitive code
- use explicit dependency passing rather than hidden globals
- keep effectful orchestration as a narrow shell around pure cores

Coverage is a guardrail, not the target. Phase exit criteria are invariants, laws, lifecycle guarantees, and real-boundary proofs.

## Effect Design Rules

Effectful code must be structured so the test boundary is obvious and narrow.

- do not write large monolithic `IO` functions that mix parsing, policy, orchestration, and external calls
- isolate external systems such as Redis, Keycloak, object storage, queues, browsers, and HTTP servers behind explicit records, small interfaces, or interpreters
- pass dependencies explicitly through function arguments, adapter records, or constrained interfaces
- make pure transformations testable without starting real infrastructure

Mocks are not the default tool. Use in-memory interpreters or explicit test doubles first. Interaction-verifying mocks are allowed only when the interaction itself is the observable contract.

## Testing Layers

`studioMCP` requires five test layers:

- unit and property tests
- interpreter-backed boundary tests
- integration tests against real services
- protocol validation tests
- browser-surface end-to-end validation

## Unit And Property Tests

Unit tests remain pure Haskell tests wherever possible.

Use unit and property tests for:

- DAG validation and scheduler determinism
- summary construction and failure projection
- timeout projection
- memoization contracts
- protocol state machine behavior
- tool schema validation
- authz policy evaluation
- artifact governance rules
- redaction and configuration normalization

Unit tests must not depend on:

- live Keycloak
- live Redis
- live object storage
- live browsers

Generated properties are the default expansion path for:

- parsers and decoders
- normalization and redaction
- ordering and scheduler guarantees
- serialization round-trips
- state-transition rules with finite models

## State-Machine And Model Tests

Lifecycle-sensitive code must be tested as ordered traces, not only as isolated examples.

Required model-oriented targets include:

- MCP protocol lifecycle handling
- session lifecycle and reconnect behavior
- deterministic parallel scheduling guarantees
- retry or shutdown logic whose correctness depends on event order

Hand-written examples remain useful for named regressions, but they do not replace generated trace coverage.

## Interpreter-Based Boundary Tests

When behavior crosses an effect boundary but does not require a live third-party service, prefer interpreter-backed tests.

- use explicit adapter records such as executor or boundary capability records
- use small interfaces such as `SessionStore` for reusable behavioral laws
- provide in-memory interpreters in tests for generic store or adapter rules
- keep these tests deterministic and side-effect owned by the test process

## Integration Tests

Integration tests exercise real boundaries and must use real services.

Required integration categories:

- storage and messaging boundaries
- Keycloak-backed auth
- session-store-backed reconnect behavior
- real MCP transport behavior over `stdio`
- real MCP transport behavior over Streamable HTTP
- browser and BFF flows through the live BFF-to-MCP path

Rules:

- no mocks for service integrations
- tests own their full data lifecycle, including unique ids and cleanup
- tests must be deterministic and parallel-safe
- tests fail loudly when required infrastructure is unavailable

## Reproducible Environment

The canonical validation entrypoints remain:

- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp test unit`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp test integration`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate docs`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate mcp-stdio`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate mcp-http`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate mcp-conformance`
- `docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate web-bff`

When a validator or integration suite provisions external state, it must do so with deterministic inputs, unique namespaces, and cleanup rules that do not depend on manual intervention.

## Protocol Validation

Protocol validation is a first-class category and must not regress into ad hoc REST assertions.

Required protocol validation includes:

- lifecycle negotiation
- tool and resource behavior
- prompt behavior where implemented
- wrong-order lifecycle rejection
- malformed protocol message rejection
- external-client or inspector connectivity proof

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

## Idempotent Test Infrastructure

Test infrastructure that creates external resources (containers, clusters, temporary files) must follow idempotent patterns:

Required behavior:

- Fixed, predictable names for all test containers (see [Docker Policy](../engineering/docker_policy.md#container-naming-policy))
- Cleanup-before-start: Remove any existing resource with the same name before creating
- Cleanup-on-exit: Bracket patterns that remove resources even on test failure

Implementation pattern:

```haskell
withTemporaryResource action =
  bracket
    (cleanupExisting >> createResource)  -- cleanup-before-start
    cleanupResource                       -- cleanup-on-exit
    action
```

Benefits:

- Re-running tests never fails due to leftover containers from previous runs
- Interrupted tests (Ctrl+C, crashes) don't leave orphaned resources
- CI runners don't accumulate stale test infrastructure
- `docker ps -a --filter "name=studiomcp"` shows predictable container state

Fixed names in use:

| Container | Purpose |
|-----------|---------|
| `studiomcp` | Kind cluster |
| `studiomcp-test-redis` | Validation Redis for session tests |

## Frontend Logic And FFI Boundaries

`studioMCP` currently validates browser behavior through the live BFF surface. If a PureScript client is introduced later:

- PureScript unit tests cover only pure logic
- browser behavior is validated through Playwright
- the FFI boundary stays thin and must not accumulate complex business logic in JavaScript

## Current Repo Note

The current repo already has strong example-based unit coverage and real-service integration coverage for execution and sidecar behavior. Its MCP transport and conformance coverage runs through `validate mcp-stdio`, `validate mcp-http`, and `validate mcp-conformance`, and the browser-facing BFF surface is exercised through `validate web-bff` plus the outer integration harness.

The current doctrine refactor adds property testing, generated lifecycle traces, and interpreter-backed store laws on top of that existing validation surface rather than replacing the real-service checks.

## Cross-References

- [Local Development](local_dev.md#local-development)
- [Architecture Overview](../architecture/overview.md#architecture-overview)
- [MCP Protocol Architecture](../architecture/mcp_protocol_architecture.md#mcp-protocol-architecture)
- [Session Scaling](../engineering/session_scaling.md#session-scaling)
- [Security Model](../engineering/security_model.md#security-model)
- [Web Portal Surface](../reference/web_portal_surface.md#web-portal-surface)

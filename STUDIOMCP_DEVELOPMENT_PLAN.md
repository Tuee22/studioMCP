# studioMCP Development Plan

## Purpose
This document is the working implementation plan for `studioMCP`. It is the delivery contract for the repository, not a marketing artifact.

The goal is to build a standards-compliant MCP server in Haskell for secure multi-tenant studio workflows. The repo already contains substantial execution, storage, and tooling foundations, but its current public server surface is still a custom DAG-oriented HTTP API rather than a real MCP server. This plan replaces that ambiguity with an explicit migration path.

## How to Use This Plan

- Treat each phase as a delivery contract with required behavior, tests, docs, and exact exit commands.
- Do not mark a phase complete because files exist. A phase is complete only when the behavior exists, validation exists, and the exit commands pass.
- Keep this plan aligned with the governed documentation suite under `documents/`.
- When the target architecture changes, update the authoritative docs first, then update this plan.
- When the implemented repo behavior differs from the target architecture, say so explicitly. Do not blur target state and current state.

### Progress Tracking Rules

- Update phase status and implementation checklist whenever a phase materially advances.
- Do not mark a phase complete while relying on placeholder routes, fake auth, sticky sessions, or undocumented operational assumptions.
- Each deliverable within a phase is marked `[x]` (complete) or `[ ]` (incomplete).

## Current Status

The repository has completed the core transition from a DAG-oriented HTTP control plane to an MCP-first architecture:

- `/mcp` is the live public automation surface with JSON-RPC lifecycle, tool/resource/prompt catalogs, and runtime-backed execution
- JWT validation infrastructure (parsing, JWKS, signature verification) is complete; production Keycloak flows are incomplete
- Session state is shared through Redis-backed store
- BFF, artifact storage, governance, and observability paths are wired to runtime-backed services
- Helm packages the full service topology with HA dependencies

**Phases 0-12**: Complete (DAG foundations)
**Phases 13, 17, 19, 20, 21**: Complete
**Phases 14, 15, 16, 18**: In Progress

Current session progress:
- Phase 14: PKCE, ServiceAccount, PassthroughGuard, Admin modules complete; BFF OAuth handlers complete
- Phase 16: OAuth types complete; Browser login flow (BFF + Handlers) complete
- Remaining: CLI keycloak bootstrap command, EventStream module, integration tests

## Implementation Checklist

- [x] Phase 0 repository foundation and documentation governance baseline
- [x] Phase 1 buildable Haskell scaffold with separated test suites
- [x] Phase 2 core result, failure, summary, timeout, memoization, and provenance model
- [x] Phase 3 DAG schema, parser, validator, and fixture coverage
- [x] Phase 4 containerized development environment and cluster lifecycle baseline
- [x] Phase 5 messaging contracts and pure execution-state model
- [x] Phase 6 real Pulsar adapter and lifecycle validation
- [x] Phase 7 storage contracts, content addressing, and manifest model
- [x] Phase 8 real MinIO adapter and memoization integration validation
- [x] Phase 9 boundary runtime and timeout projection
- [x] Phase 10 first production tool adapter and deterministic media fixtures
- [x] Phase 11 DAG executor and in-memory summary assembly
- [x] Phase 12 persisted summaries plus first end-to-end DAG success and failure runs
- [x] Phase 13 standards-compliant MCP protocol core and Haskell transport abstraction
- [ ] Phase 14 OAuth-protected multi-tenant auth and authorization (1 item incomplete: CLI command)
- [ ] Phase 15 non-sticky horizontal session architecture (2 items incomplete)
- [ ] Phase 16 web portal, BFF, and browser upload/download/chat surface (2 items incomplete)
- [x] Phase 17 tenant artifact storage model and non-destructive media governance
- [ ] Phase 18 MCP tool, resource, and prompt catalog on top of the execution runtime (1 item incomplete)
- [x] Phase 19 observability, audit, quotas, and abuse controls for SaaS operation
- [x] Phase 20 Helm-packaged public deployment topology including Keycloak, Postgres, and session store
- [x] Phase 21 protocol conformance, migration completion, and retirement of the legacy `/runs` surface

## Core Product Intent

`studioMCP` must become a real MCP system, not a misnamed REST service.

The target product has three externally visible faces:

1. A standards-compliant MCP server implemented in Haskell.
2. A browser-facing SaaS product with upload, download, render, and chat workflows.
3. A backend-for-frontend that interacts with the MCP server on behalf of authenticated users.

The MCP server is the typed execution and automation plane. The BFF and web portal are product surfaces layered on top of it, not replacements for it.

## Non-Negotiable Architectural Constraints

### Proper MCP, Not Ad Hoc REST

The authoritative public automation surface must be real MCP:

- JSON-RPC 2.0 message handling
- MCP lifecycle negotiation with `initialize`
- capability negotiation
- standard MCP transports
- tool, resource, and prompt semantics where supported
- protocol-level validation against real MCP clients and developer tools

Custom business routes such as `POST /runs` may exist temporarily for migration, but they are not the target public automation contract.

### Haskell-First Ownership

Haskell owns:

- the MCP protocol layer
- transport adapters
- authn/authz enforcement at the MCP boundary
- tool dispatch
- DAG execution semantics
- failure algebra
- summary construction
- memoization contracts
- artifact and manifest contracts

Other runtimes may exist for the web application, model-serving boundaries, or adapters, but the MCP server itself is Haskell-owned.

### Secure Multi-Tenancy

The SaaS surface must be tenant-aware from the start.

- every authenticated request resolves to a subject and tenant
- authorization is enforced server-side
- tenant boundaries apply to tools, resources, prompts, run metadata, and object storage access
- no token passthrough to downstream services
- the BFF acts on behalf of the user through explicit token or token-exchange rules

### Horizontally Scalable Listener Nodes

The number of MCP listener pods must be horizontally scalable without sticky sessions.

- remote MCP nodes must remain fungible behind a load balancer
- session state required for remote transport must live outside individual pods
- Redis or a functionally equivalent HA session store may be used for session data, resumability metadata, and subscription state
- durable run state and immutable artifacts must not depend on in-memory pod state

### Non-Destructive Artifact Rule

Hard rule:

- the MCP server does not have the ability to permanently delete user media artifacts

Allowed operations include:

- create new artifacts
- write new immutable versions
- create manifests and summaries
- mark artifacts hidden, superseded, archived, or logically removed at the metadata layer
- revoke future access by changing metadata or credentials

Forbidden operations include:

- hard deleting raw footage
- hard deleting rendered media
- permanently deleting tenant-owned media objects from S3 or MinIO

### Tenant-Controlled Durable Storage

Users and tenants may keep durable post-production artifacts in their own cloud object storage.

- local development may use MinIO
- shared platform-managed S3-compatible storage may exist for staging, metadata, or local deployments
- production tenants may point durable artifact storage at tenant-owned S3-compatible buckets or prefixes
- upload and download should prefer presigned flows rather than funneling large media through the MCP server

### Public Topology Baseline

The public service and network topology is based on `documents/architecture/multi_tenant_saas_mcp_auth_architecture.md`.

At minimum the topology must include:

- browser client
- BFF
- MCP listener deployment
- execution workers and tool boundaries
- Keycloak
- dedicated Postgres for Keycloak
- session store for non-sticky MCP nodes
- tenant object storage

### Documentation Is a Deliverable

Because Haskell does not yet have an official MCP SDK, the repository must document the intended MCP behavior explicitly.

That documentation must define:

- target transport behavior
- target method and capability surface
- target auth model
- target tenant model
- target artifact and storage behavior
- target session and scaling behavior
- target browser and BFF interaction model
- security and audit rules

### Third-Party Service Deployment Doctrine

All third-party stateful services must be deployed via high-availability Helm charts, not custom templates.

Required chart sources and HA configurations:

| Service    | Chart                      | HA Requirement        | Rationale                    |
|------------|----------------------------|-----------------------|------------------------------|
| MinIO      | minio/minio (official)     | 3+ replicas           | Native distributed mode      |
| Pulsar     | apache/pulsar (official)   | 3+ per component      | Native HA support            |
| PostgreSQL | bitnami/postgresql-ha      | 3 replicas            | Official chart lacks HA      |
| Redis      | bitnami/redis              | Sentinel mode         | Official chart lacks Sentinel|
| Keycloak   | bitnami/keycloak           | 2+ replicas           | Better HA than official      |

Chart selection priority:

1. Official chart with native HA support (minio/minio, apache/pulsar)
2. Bitnami HA chart when official lacks HA (postgresql-ha, redis, keycloak)
3. Never: custom templates for standard infrastructure

Helm charts own PVCs:

- Helm charts are the only thing creating PVCs for stateful services
- Use the null storage class pattern: `storageClassName: ""`
- CLI creates PVs that match expected PVC names from charts
- No custom PVC templates in our chart

Full HA in all environments:

- Local kind development uses the same HA replica counts as production
- No reduced replicas for resource constraints
- This ensures local development mirrors production deployment patterns

Custom templates are allowed only for:

- studioMCP-specific workloads (mcp-server, worker, bff)
- Application configuration and secrets
- Ingress rules specific to studioMCP routing

See `documents/engineering/k8s_storage.md` for the full storage policy including the null storage class rule and rehydratable PV system.

## Delivery Sequencing Rule

Implementation proceeds in order. Before advancing a phase:

1. Update the relevant authoritative docs.
2. Update the dependent docs and references.
3. Implement the behavior.
4. Add or update validation.
5. Run the phase exit commands.

## Revised Delivery Phases

### Phase 13: Standards-Compliant MCP Protocol Core
Status: **Complete**

**Deliverables:**
- [x] JSON-RPC 2.0 request, notification, and response handling
- [x] MCP lifecycle negotiation with `initialize`
- [x] Protocol state machine (Uninitialized → Initializing → Ready)
- [x] Server capability advertisement
- [x] Transport-agnostic Haskell protocol core
- [x] `stdio` transport for local development
- [x] HTTP transport with `/mcp` endpoint
- [x] SSE bootstrap for server-to-client streaming
- [x] `tools/list`, `resources/list`, `prompts/list` handlers
- [x] `tools/call` dispatch to catalog handlers
- [x] Admin endpoints (`/healthz`, `/version`, `/metrics`) separate from MCP

**Validation Criteria:**
- `cabal build all` completes
- `cabal test unit-tests` passes
- `studiomcp validate mcp-stdio` exercises stdio transport
- `studiomcp validate mcp-http` exercises HTTP transport

### Phase 14: OAuth-Protected Multi-Tenant Auth And Authorization
Status: **In Progress**

**Deliverables:**
- [x] Auth types (AuthContext, Subject, Tenant, Scopes, Roles)
- [x] Keycloak configuration types
- [x] JWT parsing and structure validation
- [x] Timing validation (exp, nbf)
- [x] Issuer and audience validation
- [x] JWKS cache and fetch
- [x] RSA/EC signature verification
- [x] Development bypass auth
- [x] Claims extraction and scope/role enforcement
- [x] PKCE module (`src/StudioMCP/Auth/PKCE.hs`) - challenge generation, authorization URL, token exchange
- [x] Service account module (`src/StudioMCP/Auth/ServiceAccount.hs`) - client_credentials grant with caching
- [x] Token passthrough guard (`src/StudioMCP/Auth/PassthroughGuard.hs`) - header sanitization, violation detection
- [x] Keycloak Admin API module (`src/StudioMCP/Auth/Admin.hs`) - realm, client, scope operations, bootstrap
- [x] BFF OAuth handlers (`src/StudioMCP/Web/BFF.hs`) - initiateLogin, handleOAuthCallback, handleLogout, handleTokenRefresh
- [x] BFF OAuth routes (`src/StudioMCP/Web/Handlers.hs`) - /auth/login, /auth/callback, /auth/logout, /auth/refresh
- [ ] CLI command for Keycloak bootstrap (`studiomcp keycloak bootstrap`)

**Validation Criteria:**
- `studiomcp validate keycloak` verifies realm, clients, scopes
- `studiomcp validate mcp-auth` verifies JWT validation

### Phase 15: Non-Sticky Horizontal Session Architecture
Status: **In Progress**

**Deliverables:**
- [x] Session types (SessionId, SessionState)
- [x] Session store interface (SessionStore typeclass)
- [x] Redis configuration types
- [x] RedisSessionStore implementation
- [x] Session CRUD operations (create, get, update, delete, touch)
- [x] Subscription tracking in Redis
- [x] Cursor position storage in Redis
- [x] Lock acquisition/release
- [x] TTL-based expiration
- [x] Listener failover behavior documentation
- [ ] Multi-replica failover integration test
- [ ] Load test proving multi-replica correctness

**Validation Criteria:**
- `studiomcp validate session-store` verifies Redis operations
- `studiomcp validate mcp-horizontal-scale` verifies cross-pod session visibility

### Phase 16: Web Portal, BFF, And Browser Media Workflows
Status: **In Progress**

**Deliverables:**
- [x] BFF types (WebSession, ChatMessage, UploadRequest)
- [x] BFF service with session management
- [x] Upload request flow with presigned URLs
- [x] Upload confirmation flow
- [x] Download request flow with presigned URLs
- [x] Chat message flow (runtime-backed)
- [x] Run submission
- [x] Run status retrieval
- [x] WAI handlers
- [x] MinIO/S3-style presigning
- [x] OAuth types in Web.Types (OAuthState, LoginInitiateResponse, OAuthCallbackRequest, LogoutResponse, TokenRefreshResponse)
- [x] Browser login flow (OAuth handlers in BFF.hs, routes in Handlers.hs)
- [ ] Progress streaming/subscription (EventStream module + SSE endpoint)
- [ ] BFF to MCP integration tests

**Validation Criteria:**
- `studiomcp validate web-bff` exercises upload/download/chat flows

### Phase 17: Tenant Artifact Storage And Non-Destructive Media Governance
Status: **Complete**

**Deliverables:**
- [x] Tenant-scoped object storage contract
- [x] Support for tenant-owned S3-compatible storage
- [x] Immutable artifact versioning rules
- [x] Manifest and summary links to durable artifacts
- [x] ArtifactState types (Active, Hidden, Archived, Superseded)
- [x] State transition functions (hide, archive, supersede, restore)
- [x] Hard delete denial (`denyHardDelete` always fails)
- [x] Audit trail for artifact mutations
- [x] Presigned URL generation

**Validation Criteria:**
- `studiomcp validate artifact-storage` verifies storage operations
- `studiomcp validate artifact-governance` verifies state transitions and hard delete denial

### Phase 18: MCP Tool, Resource, And Prompt Catalog
Status: **In Progress**

**Deliverables:**
- [x] Tool catalog (10 tools with handlers)
- [x] Tool definitions with JSON schemas
- [x] Tool authorization (scope checking)
- [x] workflow.* tools (submit, status, cancel, list)
- [x] artifact.* tools (get, download-url, upload-url, hide, archive)
- [x] tenant.info tool
- [x] Resource catalog with URI parsing
- [x] Prompt catalog (5 system prompts)
- [x] Resource URI conventions
- [ ] Inspector-based manual verification notes in docs

**Validation Criteria:**
- `studiomcp validate mcp-tools` verifies tool dispatch
- `studiomcp validate mcp-resources` verifies resource access
- `studiomcp validate mcp-prompts` verifies prompt retrieval

### Phase 19: Observability, Audit, Quotas, And Abuse Controls
Status: **Complete**

**Deliverables:**
- [x] Per-request correlation IDs
- [x] Correlation ID propagation through stack
- [x] Subject and tenant audit logging
- [x] MCP method and tool metrics
- [x] Per-tenant quota enforcement
- [x] Rate limiting and concurrency limits
- [x] Alertable health and saturation metrics
- [x] Prometheus metrics export via `/metrics`
- [x] Secret and token redaction rules

**Validation Criteria:**
- `studiomcp validate observability` verifies /metrics and /healthz
- `studiomcp validate audit` verifies audit trail
- `studiomcp validate quotas` verifies quota enforcement
- `studiomcp validate rate-limit` verifies rate limiting

### Phase 20: Public Deployment Topology And Helm Hardening
Status: **Complete**

**Deliverables:**
- [x] Chart.yaml with HA dependencies (MinIO, Pulsar, PostgreSQL-HA, Redis, Keycloak)
- [x] Third-party chart integration via Helm dependencies
- [x] studioMCP-specific templates (deployment, worker, BFF, ingress)
- [x] Storage class and PV management
- [x] HA replica counts in all values files
- [x] Null storage class enforcement across all subcharts
- [x] Ingress and TLS topology
- [x] Keycloak realm bootstrap runbook
- [x] values-kind.yaml with soft anti-affinity for single-node clusters

**Validation Criteria:**
- `helm lint chart -f chart/values.yaml -f chart/values-kind.yaml`
- `helm template studiomcp chart -f chart/values.yaml -f chart/values-kind.yaml`

### Phase 21: Conformance, Migration Completion, And Legacy Surface Retirement
Status: **Complete**

**Deliverables:**
- [x] MCP protocol conformance validation
- [x] Documented migration path from /runs clients
- [x] Deprecation plan for legacy HTTP routes
- [x] Legacy /runs surface retirement
- [x] Documentation suite aligned with architecture
- [x] Tool, resource, and prompt round-trip validation
- [x] Session-store migration validation

**Validation Criteria:**
- `studiomcp validate docs` verifies documentation coverage
- `studiomcp validate mcp-conformance` verifies protocol compliance

## Documentation Governance

The expanded documentation suite is now part of the implementation plan, not separate from it.

The canonical docs for this revised architecture include:

- `documents/architecture/overview.md`
- `documents/architecture/mcp_protocol_architecture.md`
- `documents/architecture/server_mode.md`
- `documents/architecture/multi_tenant_saas_mcp_auth_architecture.md`
- `documents/architecture/artifact_storage_architecture.md`
- `documents/reference/mcp_surface.md`
- `documents/reference/mcp_tool_catalog.md`
- `documents/reference/web_portal_surface.md`
- `documents/engineering/security_model.md`
- `documents/engineering/session_scaling.md`
- `documents/operations/keycloak_realm_bootstrap_runbook.md`

## Human-Only Git Actions

LLMs working in this repository must not create git commits or push to remotes. Git commits and pushes remain reserved for the human user only.

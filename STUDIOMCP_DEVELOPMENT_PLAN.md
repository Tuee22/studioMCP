# studioMCP Development Plan

## Purpose
This document is the working implementation plan for `studioMCP`. It is the delivery contract for the repository, not a marketing artifact.

The goal is to run a standards-compliant MCP server in Haskell for secure multi-tenant studio workflows and to keep the browser-facing product surface honest about what is implemented. The repo now has a real MCP server on `/mcp`, a browser-facing BFF that mediates workflow and governance operations through MCP, and the completed validation surface tracked below.

## How to Use This Plan

- Treat each phase as a delivery contract with required behavior, tests, docs, and exact exit commands.
- Do not mark a phase complete because files exist. A phase is complete only when the behavior exists, validation exists, and the exit commands pass.
- Keep this plan aligned with the governed documentation suite under `documents/`.
- When the target architecture changes, update the authoritative docs first, then update this plan.
- When the implemented repo behavior differs from the target architecture, say so explicitly. Do not blur target state and current state.

### Progress Tracking Rules

- Update phase status, implementation checklist, and current repo assessment whenever a phase materially advances.
- Do not mark a phase complete while relying on placeholder routes, fake auth, sticky sessions, or undocumented operational assumptions.
- Keep `Current Validation State` aligned with commands that are known to pass now.
- New validation commands belong in this plan in the same change that introduces them.

## Current Repo Assessment Against This Plan

This section records the current repo state against the revised MCP-first plan.

### Complete

- Phases 0 through 12 remain complete. The repo has the Haskell DAG model, validation, summary construction, timeout handling, boundary execution, Pulsar integration, MinIO integration, and end-to-end DAG execution foundations required by the original execution stack.
- Phases 13 through 21 are implemented at the feature-surface level. The default `/mcp` server is runtime-backed, JWT signature verification is active, Redis-backed shared MCP session state is live, artifact/governance services are wired to the runtime-backed system, MCP observability is enabled on the running server, the browser-facing BFF now mediates workflow and governance operations through the live MCP HTTP surface, the BFF now serves a built-in browser UI plus SSE chat and run-progress surfaces, deterministic parallel DAG execution is live, the CLI ergonomics tracked in this plan are implemented, and Helm packaging for the current topology exists in the repo.
- The legacy `validate mcp` alias has been removed and the main MCP server no longer relies on the retired `/runs` automation surface as its public automation contract.
- Unit tests pass.

### Summary

The repository has completed the server-side transition from the legacy DAG-oriented HTTP control plane to an MCP-first architecture:

1. `/mcp` is the live public automation surface, with JSON-RPC lifecycle, SSE bootstrap, tool/resource/prompt catalogs, and runtime-backed execution paths.
2. Signed JWT validation, scope enforcement, tenant resolution, and Keycloak/JWKS-backed verification are active.
3. MCP session state is shared through the Redis-backed store and validated across store instances plus alternating live listener nodes without sticky routing.
4. Artifact storage, governance, audit, and observability paths are wired into the runtime-backed system rather than local-only placeholders.
5. The BFF is a live MCP client for workflow and governance operations, supports browser login/logout/profile plus cookie-backed sessions, and now externalizes browser-session state, pending uploads, and cached MCP session ids through Redis for multi-instance deployment.
6. The execution runtime now schedules independent DAG branches in deterministic parallel batches, and the browser-facing product surface now includes a built-in browser UI plus SSE chat and run-progress surfaces.

## Open Runtime Wiring / Production-Hardening Inventory

No blocking repository-level runtime wiring gaps are currently open for phases 15, 16, 20, or the deterministic parallel scheduler. The remaining work to keep explicit is operational rather than missing repo-level feature work:

- Tenant artifact metadata, version history, and tenant backend overrides are now restart-durable under `STUDIOMCP_DATA_DIR`, and the running server can load tenant backend overrides from `STUDIO_MCP_TENANT_BACKENDS_FILE` or `STUDIOMCP_TENANT_BACKENDS_FILE`. The remaining work in this area is live-cluster rehearsal of tenant-owned storage credentials and buckets beyond the current validator surface.
- The remaining operational work for the already-wired phases is cluster rehearsal and scale testing beyond the local validator surface.

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
- [x] Phase 14 OAuth-protected multi-tenant auth and authorization
- [x] Phase 15 non-sticky horizontal session architecture
- [x] Phase 16 web portal, BFF, and browser upload/download/chat surface
- [x] Phase 17 tenant artifact storage model and non-destructive media governance
- [x] Phase 18 MCP tool, resource, and prompt catalog on top of the execution runtime
- [x] Phase 19 observability, audit, quotas, and abuse controls for SaaS operation
- [x] Phase 20 Helm-packaged public deployment topology including Keycloak, Postgres, and session store
- [x] Phase 21 protocol conformance, migration completion, and retirement of the legacy `/runs` surface

## Current Validation State

These commands were re-checked during the March 26, 2026 parallel-execution and BFF UI/SSE completion pass:

- `cabal build all`
- `cabal test unit-tests`
- `cabal run studiomcp -- validate docs`
- `cabal run studiomcp -- validate web-bff`
- `cabal run studiomcp -- validate mcp-conformance`

`validate web-bff` and the BFF portion of `validate mcp-conformance` now exercise the built-in browser shell, login, profile, upload confirmation, chat SSE, MCP-backed run operations, run SSE, artifact governance, and logout across two BFF instances that share Redis-backed browser state.

Unit coverage now additionally proves restart-durable tenant artifact metadata/version history plus tenant backend override reload behavior, deterministic parallel DAG execution, the served browser shell, and SSE route framing.

The retired `validate mcp` alias is intentionally not part of the current validation state.

## Core Product Intent

`studioMCP` must remain a real MCP system, not regress into a misnamed REST service.

The product has three externally visible faces:

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
Status: **Implemented**

Current state:
- JSON-RPC 2.0 parsing and response handling: **Complete**
- MCP lifecycle negotiation with `initialize`: **Complete**
- Protocol state machine (Uninitialized → Initializing → Ready): **Complete**
- Server capability advertisement: **Complete**
- `stdio` transport: **Complete**
- HTTP transport with `/mcp` endpoint: **Complete**
- SSE bootstrap for server-to-client: **Complete** (`GET /mcp` returns a ready event stream)
- `tools/list`, `resources/list`, `prompts/list`: **Return catalog entries**
- `tools/call`: **Dispatches catalog handlers**
- Live workflow execution flows through the runtime-backed `/mcp` surface: **Complete**
- Legacy `validate mcp` alias: **Removed**
- Conformance and external-client proof: **Covered by the live HTTP and conformance validators**
- Exit commands `validate mcp-stdio` and `validate mcp-http`: **Implemented**

Objective: replace the current custom DAG HTTP control surface with a real MCP protocol core implemented in Haskell.

Must deliver:

- JSON-RPC 2.0 request, notification, and response handling
- MCP lifecycle negotiation with `initialize`
- protocol version handling
- server capability advertisement
- a transport-agnostic Haskell protocol core
- `stdio` transport for local development and tooling
- Streamable HTTP transport for remote clients
- admin endpoints such as `/healthz`, `/version`, and `/metrics` kept separate from the MCP endpoint

Explicitly out of scope:

- browser BFF workflows
- production auth
- complete tool catalog
- artifact deletion governance

Required coverage:

- JSON round-trip and protocol state-machine unit coverage
- initialization success and rejection cases
- `stdio` integration validation
- Streamable HTTP integration validation
- MCP Inspector connectivity proof

Exit commands:

```bash
cabal build all
cabal test unit-tests
cabal run studiomcp -- validate mcp-stdio
cabal run studiomcp -- validate mcp-http
cabal test integration-tests
```

### Phase 14: OAuth-Protected Multi-Tenant Auth And Authorization
Status: **Implemented**

Current state:
- Auth types (AuthContext, Subject, Tenant, Scopes, Roles): **Complete**
- Keycloak configuration types: **Complete**
- JWT parsing and structure validation: **Complete**
- Timing validation (exp, nbf): **Complete**
- Issuer and audience validation: **Complete**
- JWKS cache and fetch: **Complete**
- RSA/EC signature verification: **Complete**
- Development bypass auth: **Complete**
- Claims extraction and scope/role enforcement: **Complete**
- Real signed-token validation coverage: **Complete**
- Exit commands `validate keycloak` and `validate mcp-auth`: **Implemented**

Objective: add a real multi-tenant auth boundary for remote MCP use.

Must deliver:

- Keycloak-backed OAuth and OIDC integration
- audience validation at the MCP boundary
- tenant resolution rules
- scope and role enforcement
- external MCP client flow with PKCE
- BFF flow for user-facing sessions
- service account flow for platform automation
- no token passthrough to downstream services

Explicitly out of scope:

- browser UX polish
- full billing model
- per-tenant rate limiting

Required coverage:

- valid token acceptance
- invalid issuer rejection
- wrong audience rejection
- cross-tenant access rejection
- service-account scope enforcement
- BFF on-behalf-of integration tests

Exit commands:

```bash
cabal build all
cabal test unit-tests
cabal run studiomcp -- validate keycloak
cabal run studiomcp -- validate mcp-auth
cabal test integration-tests
```

### Phase 15: Non-Sticky Horizontal Session Architecture
Status: **Implemented**

Current state:
- Session types (SessionId, SessionState): **Complete**
- Session store interface (SessionStore typeclass): **Complete**
- Redis configuration types: **Complete**
- RedisSessionStore implementation: **Complete** (Redis-backed shared store)
- Session operations (create, get, update, delete, touch): **Complete**
- Subscription tracking: **Complete**
- Cursor position storage: **Complete**
- Lock acquisition/release: **Complete**
- Real Redis client integration: **Complete**
- TTL-based expiration: **Complete**
- Multi-replica validation: **Complete** (shared Redis-store behavior plus alternating live listener validation)
- Listener-pod session invalidation across replicas: **Complete**
- No-sticky ingress and multi-listener request-burst validation: **Complete**
- Exit commands `validate mcp-session-store` and `validate mcp-horizontal-scale`: **Implemented**

Objective: make remote MCP listener nodes horizontally scalable without sticky load balancing.

Must deliver:

- externalized remote session store
- resumable session metadata
- subscription and stream cursor storage outside pod memory
- pod-agnostic request handling
- multi-replica HTTP listener deployment
- explicit Redis or equivalent HA session-store contract
- listener failover behavior documentation and tests

Explicitly out of scope:

- global multi-region replication
- cross-cloud active-active durability

Required coverage:

- session resume across pods
- subscription behavior after pod loss
- reconnect behavior under rolling deployment
- no-sticky ingress validation
- load test proving correctness under multiple MCP listener replicas

Exit commands:

```bash
cabal build all
cabal test unit-tests
cabal run studiomcp -- validate mcp-session-store
cabal run studiomcp -- validate mcp-horizontal-scale
cabal test integration-tests
```

### Phase 16: Web Portal, BFF, And Browser Media Workflows
Status: **Implemented**

Current state:
- BFF types (WebSession, ChatMessage, UploadRequest, etc.): **Complete**
- BFF service with session management: **Complete**
- Browser login, logout, and profile routes: **Complete**
- Upload request flow: **Complete** (returns tenant-scoped artifact-backed upload URLs)
- Upload confirmation flow: **Complete**
- Download request flow: **Complete** (returns tenant-scoped artifact-backed download URLs)
- Chat message flow: **Complete** (runtime-backed)
- Chat SSE stream: **Complete**
- Run submission, list, status, and cancel: **Complete**
- Run progress SSE event window: **Complete**
- Artifact-governance browser routes: **Complete**
- Cookie-backed browser session contract: **Complete**
- Browser-session externalization across BFF replicas: **Complete**
- WAI handlers: **Complete**
- Real MinIO/S3-style presigning: **Complete**
- Inference service integration: **Complete**
- Live BFF-to-MCP orchestration over the `/mcp` network surface: **Complete**
- Built-in browser UI route: **Complete**
- Expanded browser-facing route and SSE surface: **Complete**
- Exit command `validate web-bff`: **Implemented**

Objective: add the first real product-facing browser surface on top of the MCP system.

Must deliver:

- browser upload flow for raw footage
- browser download flow for artifacts
- browser chat interface
- BFF with authenticated user session management
- BFF to MCP interaction model
- presigned upload and download flow where appropriate
- run submission and progress display through the BFF

Explicitly out of scope:

- advanced editing UI
- native desktop application
- collaborative editing

Required coverage:

- upload authorization tests
- chat request auth and tenant-scoping tests
- BFF to MCP integration tests
- browser-facing end-to-end flow for submit, observe, and retrieve

Exit commands:

```bash
cabal build all
cabal test unit-tests
cabal run studiomcp -- validate web-bff
cabal test integration-tests
```

### Phase 17: Tenant Artifact Storage And Non-Destructive Media Governance
Status: **Implemented**

Current state:
- ArtifactState (Active, Hidden, Archived, Superseded): **Complete**
- GovernancePolicy with configurable rules: **Complete**
- State transition functions (hide, archive, supersede, restore): **Complete**
- Hard delete denial (`denyHardDelete` always fails): **Complete**
- State history tracking: **Complete**
- Audit trail service: **Complete**
- TenantStorage service: **Complete**
- VersioningService: **Complete** (validated as an in-process service)
- Presigned URL generation: **Complete**
- GovernanceService backend: **Complete**
- AuditTrailService backend: **Complete**
- Runtime boundary: tenant artifact metadata and version-chain state are persisted and reloaded through the tenant storage snapshot file: **Complete**
- Runtime boundary: tenant-specific backend provisioning is wired into the running server through persisted assignments and optional backend override config loading: **Complete**
- Exit commands `validate artifact-storage` and `validate artifact-governance`: **Implemented**

Objective: formalize durable artifact ownership and enforce the no-permanent-delete rule.

Must deliver:

- tenant-scoped object storage contract
- support for tenant-owned S3-compatible storage
- immutable artifact versioning rules
- manifest and summary links to durable artifacts
- metadata-level hide, archive, and supersede semantics
- explicit denial of permanent media deletion through MCP tools
- audit trail for artifact mutation requests

Explicitly out of scope:

- legal retention productization
- cross-tenant object replication

Required coverage:

- artifact creation and versioning tests
- presigned transfer validation
- forbidden hard-delete tests
- storage policy unit tests
- end-to-end render plus retrieval validation

Exit commands:

```bash
cabal build all
cabal test unit-tests
cabal run studiomcp -- validate artifact-storage
cabal run studiomcp -- validate artifact-governance
cabal test integration-tests
```

### Phase 18: MCP Tool, Resource, And Prompt Catalog
Status: **Implemented**

Current state:
- Tool catalog with 10 tools defined: **Complete**
- Tool definitions with JSON schemas: **Complete**
- Tool authorization (toolRequiredScopes): **Complete**
- `workflow.submit` execution: **Complete**
- `workflow.status` execution: **Complete**
- `workflow.cancel` execution: **Complete**
- `workflow.list` execution: **Complete**
- `artifact.*` execution: **Complete**
- `tenant.info` execution: **Complete**
- Resource catalog: **Complete**
- Prompt catalog: **Complete (types and structure)**
- Integration with MCP Core: **Complete**
- Exit commands `validate mcp-tools`, `validate mcp-resources`, `validate mcp-prompts`: **Implemented**

Objective: expose the execution system through an explicit documented MCP capability surface.

Must deliver:

- initial tool catalog for workflow submission, inspection, cancellation, artifact access mediation, and tenant metadata lookup
- read-only resources for summaries, manifests, and operational metadata
- prompt catalog for DAG planning and repair assistance where appropriate
- schema definitions for tool input and structured output
- capability-specific auth rules
- resource URI conventions

Explicitly out of scope:

- unconstrained arbitrary shell execution
- tools that bypass typed DAG execution

Required coverage:

- tool schema validation
- tool authz tests
- resource access tests
- prompt registration tests
- Inspector-based manual verification notes

Exit commands:

```bash
cabal build all
cabal test unit-tests
cabal run studiomcp -- validate mcp-tools
cabal run studiomcp -- validate mcp-resources
cabal run studiomcp -- validate mcp-prompts
```

### Phase 19: Observability, Audit, Quotas, And Abuse Controls
Status: **Implemented**

Current state:
- Correlation ID types: **Complete**
- Request context with correlation tracking: **Complete**
- McpMetricsService with method call recording: **Complete**
- RateLimiterService with per-tenant limiting: **Complete**
- Rate limit integration in MCP Core: **Complete**
- Quota enforcement: **Complete**
- Prometheus metrics export via `/metrics`: **Complete**
- Structured logging with correlation: **Complete**
- Audit logging service: **Complete**
- External observability export surface: **Complete for the in-scope MCP service metrics and audit paths**
- Exit commands `validate observability`, `validate audit`, `validate quotas`, and `validate rate-limit`: **Implemented**

Objective: make the service operable and safe as a public multi-tenant system.

Must deliver:

- per-request correlation ids
- subject and tenant audit logging
- MCP method and tool metrics
- per-tenant quota enforcement hooks
- rate limiting and concurrency limits
- alertable health and saturation metrics
- explicit secret and token redaction rules

Explicitly out of scope:

- full billing and invoicing
- SIEM integration beyond documented export points

Required coverage:

- structured log tests
- metric growth assertions
- rate-limit tests
- quota-enforcement tests
- token redaction tests

Exit commands:

```bash
cabal build all
cabal test unit-tests
cabal run studiomcp -- validate observability
cabal run studiomcp -- validate audit
cabal run studiomcp -- validate quotas
cabal run studiomcp -- validate rate-limit
cabal test integration-tests
```

### Phase 20: Public Deployment Topology And Helm Hardening
Status: **Implemented**

Current state:
- Chart.yaml with dependencies: **Complete**
- Chart.lock with resolved versions: **Complete**
- Third-party chart downloads in `chart/charts/`: **Complete**
- values.yaml, values-kind.yaml, values-prod.yaml, values-saas.yaml: **Complete**
- studioMCP-specific templates (deployment, ingress, secrets, worker): **Complete**
- Storage class and PV management: **Complete**
- HA replica counts in all values files: **Configured**
- Helm lint for kind and SaaS profiles: **Complete**
- Helm template rendering: **Complete**
- Skaffold diagnose and offline render: **Complete**
- Kind cluster validation and sidecar deployment: **Complete locally**
- Keycloak, Postgres, Redis, and BFF deployment wiring: **Present**
- BFF multi-replica safety: **Complete** (browser sessions are Redis-backed and the chart now exports the BFF-specific MCP endpoint)

Objective: package the public SaaS topology for Kubernetes with secure defaults, enforcing the Third-Party Service Deployment Doctrine.

Must deliver:

- replace custom templates with official/Bitnami Helm chart dependencies
- delete custom templates: minio.yaml, pulsar.yaml, postgres.yaml, redis.yaml, keycloak.yaml, pvc.yaml
- add Chart.yaml dependencies for minio/minio, apache/pulsar, bitnami/postgresql-ha, bitnami/redis, bitnami/keycloak
- configure HA replica counts in values files (3+ replicas for all stateful services)
- Helm values and templates for MCP listeners
- worker deployment topology
- BFF deployment as separate service
- ingress and TLS topology
- secrets and config management strategy
- dev, kind, and SaaS-oriented values files with full HA in all environments
- update k8s_storage.md to cover PostgreSQL, Redis, and Keycloak
- create tool docs: redis.md, postgres.md, keycloak.md

Explicitly out of scope:

- support for every cloud vendor
- hand-maintained shell deployment scripts
- reduced replica counts for local development

Required coverage:

- Helm lint for all supported profiles
- Helm dependency update and validation
- rendered manifest checks with correct subchart values
- multi-replica deployment validation
- Keycloak realm bootstrap runbook verification
- null storage class enforcement across all subcharts

Exit commands:

```bash
helm dependency update chart/
helm lint chart -f chart/values.yaml -f chart/values-kind.yaml
helm lint chart -f chart/values.yaml -f chart/values-saas.yaml
helm template studiomcp chart -f chart/values.yaml -f chart/values-kind.yaml
skaffold diagnose --yaml-only --profile kind
skaffold render --offline --profile kind --digest-source=tag
```

### Phase 21: Conformance, Migration Completion, And Legacy Surface Retirement
Status: **Implemented**

Current state:
- MCP protocol conformance-oriented local validation: **Complete**
- Tool, resource, and prompt round-trip coverage in validator: **Complete**
- Session-store migration and shared-backend checks in validator: **Complete**
- BFF validation exists for login, profile, upload, download, chat, run submit/list/status/cancel, artifact governance, and logout: **Complete**
- BFF-mediated use of the MCP network surface: **Complete**
- Documentation suite updates for MCP, BFF, and catalog surfaces: **Complete**
- Live `/mcp` end-to-end proof against executor-backed tools and storage-backed resources: **Complete**
- Documented migration path from `/runs` clients: **Complete**
- Deprecation plan for legacy custom HTTP routes: **Complete**
- Legacy `/runs` surface retirement: **Complete**
- Integration harness coverage for `validate web-bff`: **Complete**
- Exit commands `validate docs` and `validate mcp-conformance`: **Implemented**

Objective: preserve conformance and keep the MCP-first migration complete.

Must deliver:

- MCP protocol conformance validation story
- documented migration path from `/runs` clients to MCP clients or BFF-mediated access
- deprecation plan for legacy custom HTTP routes
- updated validation commands and runbooks
- completed governed documentation suite aligned with the implemented architecture

Explicitly out of scope:

- indefinite support for duplicate public automation surfaces

Required coverage:

- conformance-oriented protocol validation
- migration regression coverage
- docs validation covering the expanded suite
- end-to-end SaaS validation through BFF and remote MCP clients

Exit commands:

```bash
cabal build all
cabal test unit-tests
cabal run studiomcp -- validate docs
cabal run studiomcp -- validate mcp-conformance
cabal test integration-tests
```

## Documentation Governance

The expanded documentation suite is now part of the implementation plan, not separate from it.

The canonical docs for this revised architecture include:

- `documents/architecture/overview.md`
- `documents/architecture/bff_architecture.md`
- `documents/architecture/cli_architecture.md`
- `documents/architecture/inference_mode.md`
- `documents/architecture/mcp_protocol_architecture.md`
- `documents/architecture/server_mode.md`
- `documents/architecture/multi_tenant_saas_mcp_auth_architecture.md`
- `documents/architecture/artifact_storage_architecture.md`
- `documents/architecture/pulsar_vs_minio.md`
- `documents/architecture/parallel_scheduling.md`
- `documents/development/local_dev.md`
- `documents/development/testing_strategy.md`
- `documents/reference/mcp_surface.md`
- `documents/reference/cli_surface.md`
- `documents/reference/mcp_tool_catalog.md`
- `documents/reference/web_portal_surface.md`
- `documents/engineering/security_model.md`
- `documents/engineering/session_scaling.md`
- `documents/engineering/docker_policy.md`
- `documents/engineering/k8s_native_dev_policy.md`
- `documents/engineering/k8s_storage.md`
- `documents/engineering/timeout_policy.md`
- `documents/domain/dag_specification.md`
- `documents/operations/keycloak_realm_bootstrap_runbook.md`
- `documents/operations/runbook_local_debugging.md`

## Human-Only Git Actions

LLMs working in this repository must not create git commits or push to remotes. Git commits and pushes remain reserved for the human user only.

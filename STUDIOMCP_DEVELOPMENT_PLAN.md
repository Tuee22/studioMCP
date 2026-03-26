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

- Update phase status, implementation checklist, and current repo assessment whenever a phase materially advances.
- Do not mark a phase complete while relying on placeholder routes, fake auth, sticky sessions, or undocumented operational assumptions.
- Keep `Current Validation State` aligned with commands that are known to pass now.
- New validation commands belong in this plan in the same change that introduces them.

## Current Repo Assessment Against This Plan

This section records the current repo state against the revised MCP-first plan.

### Complete (Phases 0-12)

- Foundational phases 0 through 12 remain materially complete. The repo already has the Haskell DAG model, validation, summary construction, timeout handling, boundary execution, Pulsar integration, MinIO integration, and end-to-end DAG execution foundations needed for a serious MCP server.
- Unit tests pass: 819/819
- Integration tests require sidecars running (blocked by resource constraints in local development)

### Partially Implemented / Locally Validated (Phases 13-21)

The current repository is materially beyond the previous stub state. Local behavior and validation now exist across Phases 13-21, but the remaining gaps are not limited to production hardening. Several live runtime paths are still wired to local-only implementations:

**Phase 13 (MCP Protocol Core):**
- MCP JSON-RPC lifecycle, protocol state machine, `/mcp` endpoint, and SSE bootstrap: **Implemented locally**
- Validation commands `validate mcp-stdio` and `validate mcp-http`: **Implemented**
- Real workflow execution still remains split with the legacy `/runs` surface rather than flowing end-to-end through the live `/mcp` server path: **NOT COMPLETE**

**Phase 14 (Auth):**
- JWT parsing, timing, issuer, and audience validation: **Implemented**
- Scope and role enforcement scaffolding: **Implemented**
- Signature verification: **NOT IMPLEMENTED** (critical production security gap)
- `validate keycloak` and `validate mcp-auth`: **Implemented**, but they do not yet prove a live Keycloak-backed signed-token flow

**Phase 15 (Session Store):**
- Session lifecycle, cursors, subscriptions, locks, TTL cleanup: **Implemented**
- Cross-store visibility validation: **Implemented**
- Real Redis client integration: **NOT IMPLEMENTED** (current local implementation simulates an externalized backend)

**Phase 16 (Web/BFF):**
- Upload and download handlers: **Implemented locally**
- Upload confirmation, chat, and run submit/status handlers: **LOCAL-ONLY / PARTIAL**
- Tenant-scoped artifact-backed URLs: **Implemented locally**
- Browser-facing validation command `validate web-bff`: **Implemented** against local flows
- Live BFF-to-MCP orchestration and inference-backed chat: **NOT IMPLEMENTED**

**Phase 17 (Artifact Governance):**
- Artifact metadata, versioning, hide/archive/supersede/restore rules: **Implemented**
- Audit and governance validation commands: **Implemented**
- Governance/audit persistence backends: **IN-MEMORY ONLY**

**Phase 18 (Tool, Resource, Prompt Catalog):**
- Tool, resource, and prompt catalogs: **Implemented locally**
- MCP Core catalog dispatch wiring: **Implemented locally**
- Default running server wiring to executor-backed tools and storage-backed resources: **NOT IMPLEMENTED**
- Validation commands `validate mcp-tools`, `validate mcp-resources`, and `validate mcp-prompts`: **Implemented** against local catalogs

**Phase 19 (Observability):**
- MCP metrics, audit trail, quotas, rate limiting, and redaction modules: **Implemented locally**
- Default running server wiring for MCP metrics and rate limiting: **NOT IMPLEMENTED**
- `/metrics` endpoint: **PARTIAL** (currently exports legacy run counters on the running server)
- External observability backends and durable audit sink: **NOT IMPLEMENTED**

**Phase 20 (Helm):**
- Helm dependency graph, values files, templates, linting, template rendering, and Skaffold diagnose/render: **Implemented and passing locally**
- Full multi-service deployment proof remains environment-dependent

**Phase 21 (Conformance / Legacy Retirement):**
- Local MCP conformance validator: **Implemented**
- Validator coverage is still local-catalog/local-BFF oriented rather than proving live `/mcp` runtime integration: **PARTIAL**
- Legacy `/runs` surface still present and still carries real DAG execution: **NOT RETIRED**

### Summary

The repo has not yet fully transitioned from "custom DAG HTTP API" to a complete MCP-first system. It now contains a locally validated MCP protocol surface, local catalogs, and local BFF flows, but several material gaps remain in both runtime wiring and production hardening:

1. Cryptographic JWT signature verification and a live signed-token Keycloak flow
2. A real Redis-backed external session store instead of the local shared-backend simulation
3. Live BFF-to-MCP orchestration and inference-backed chat rather than deterministic/cache-backed local handlers
4. Default `/mcp` server wiring to executor-backed tools and storage-backed resources instead of local-only catalog variants
5. Durable governance and audit persistence backends plus real S3/MinIO presigning
6. Default server wiring for MCP metrics, rate limiting, and quotas rather than validator-only / alternate-constructor coverage
7. Retirement of the legacy `/runs` automation surface

## Open Runtime Wiring / Production-Hardening Inventory

These items remain open after the local implementation and validation work completed in this turn.

### Phase 14

| File | Issue |
|------|-------|
| `src/StudioMCP/Auth/Middleware.hs` | JWT signature verification is still skipped after JWKS retrieval |
| `src/StudioMCP/CLI/Cluster.hs` | `validate keycloak` and `validate mcp-auth` do not yet require a live signed-token round trip |

### Phase 15

| File | Issue |
|------|-------|
| `src/StudioMCP/MCP/Session/RedisStore.hs` | Session store contract is locally externalized but still not backed by a real Redis client |

### Phase 16 / 17

| File | Issue |
|------|-------|
| `src/StudioMCP/Web/BFF.hs` | Upload confirm, chat, and run submit/status remain local handlers; they do not notify or orchestrate the live MCP/runtime path |
| `src/StudioMCP/Storage/TenantStorage.hs` | Presigned URLs are deterministic local URLs rather than SDK-generated S3/MinIO signatures |
| `src/StudioMCP/Storage/Governance.hs` | Governance metadata is in-memory only |
| `src/StudioMCP/Storage/AuditTrail.hs` | Audit trail is in-memory only |

### Phase 18

| File | Issue |
|------|-------|
| `src/StudioMCP/MCP/Server.hs` / `src/StudioMCP/MCP/Core.hs` | Running server constructs the local `newToolCatalog` and `newResourceCatalog` variants instead of executor-backed / storage-backed catalogs |
| `src/StudioMCP/MCP/Tools.hs` | `workflow.submit` without executor adapters only records a local accepted run rather than executing a DAG |
| `src/StudioMCP/MCP/Resources.hs` | Several resources return static/mock JSON unless a storage-backed catalog variant is explicitly wired |

### Phase 19

| File | Issue |
|------|-------|
| `src/StudioMCP/MCP/Server.hs` | Default server path does not use `newMcpServerWithObservability`, so live MCP rate limiting and MCP metrics are inactive |
| `src/StudioMCP/API/Metrics.hs` | `/metrics` exports legacy run counters rather than the full MCP observability surface |
| `src/StudioMCP/Observability/` | Observability services are local/in-memory and do not yet ship data to external systems |

### Phase 21

| File | Issue |
|------|-------|
| `src/StudioMCP/CLI/Cluster.hs` / `src/StudioMCP/MCP/Server.hs` | Legacy `/runs` validation and server surface still coexist with MCP instead of being fully retired |

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
- [ ] Phase 14 OAuth-protected multi-tenant auth and authorization (**PARTIAL - SIGNATURE VERIFICATION STILL MISSING**)
- [ ] Phase 15 non-sticky horizontal session architecture (**PARTIAL - LOCAL SHARED BACKEND ONLY, NO REAL REDIS CLIENT**)
- [ ] Phase 16 web portal, BFF, and browser upload/download/chat surface (**PARTIAL - BFF FLOWS IMPLEMENTED, LIVE MCP/INFERENCE ORCHESTRATION STILL OPEN**)
- [ ] Phase 17 tenant artifact storage model and non-destructive media governance (**PARTIAL - LOCAL STORAGE/GOVERNANCE/AUDIT BACKENDS ONLY**)
- [ ] Phase 18 MCP tool, resource, and prompt catalog on top of the execution runtime (**PARTIAL - CATALOGS EXIST, BUT THE LIVE `/mcp` SERVER IS NOT WIRED TO EXECUTOR/STORAGE-BACKED RUNTIME PATHS**)
- [ ] Phase 19 observability, audit, quotas, and abuse controls for SaaS operation (**PARTIAL - LOCAL SERVICES ONLY, AND THE DEFAULT SERVER DOES NOT ENABLE THE FULL MCP OBSERVABILITY PATH**)
- [x] Phase 20 Helm-packaged public deployment topology including Keycloak, Postgres, and session store
- [ ] Phase 21 protocol conformance, migration completion, and retirement of the legacy `/runs` surface (**PARTIAL - CONFORMANCE VALIDATION EXISTS, LEGACY SURFACE STILL PRESENT**)

## Current Validation State

These checks are known current validations for the existing repository state:

- `cabal build all`
- `cabal test unit-tests`
- `cabal run studiomcp -- validate-dag examples/dags/transcode-basic.yaml`
- `cabal run studiomcp -- dag validate-fixtures`
- `cabal run studiomcp -- validate docs`
- `cabal run studiomcp -- validate boundary`
- `cabal run studiomcp -- validate mcp-stdio`
- `cabal run studiomcp -- validate keycloak`
- `cabal run studiomcp -- validate mcp-auth`
- `cabal run studiomcp -- validate session-store`
- `cabal run studiomcp -- validate mcp-session-store`
- `cabal run studiomcp -- validate horizontal-scale`
- `cabal run studiomcp -- validate mcp-horizontal-scale`
- `cabal run studiomcp -- validate web-bff`
- `cabal run studiomcp -- validate artifact-storage`
- `cabal run studiomcp -- validate artifact-governance`
- `cabal run studiomcp -- validate mcp-tools`
- `cabal run studiomcp -- validate mcp-resources`
- `cabal run studiomcp -- validate mcp-prompts`
- `cabal run studiomcp -- validate audit`
- `cabal run studiomcp -- validate quotas`
- `cabal run studiomcp -- validate rate-limit`
- `cabal run studiomcp -- validate mcp-conformance`
- `docker compose -f docker/docker-compose.yaml config`
- `docker compose -f docker/docker-compose.yaml build studiomcp-env`
- `docker compose -f docker/docker-compose.yaml up -d studiomcp-env`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp cluster up`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp cluster status`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp cluster deploy sidecars`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate cluster`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate pulsar`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate minio`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate boundary`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate ffmpeg-adapter`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate executor`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate e2e`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate worker`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate mcp`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate inference`
- `docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate observability`
- `cabal test integration-tests`
- `helm dependency update chart/`
- `helm lint chart -f chart/values.yaml -f chart/values-kind.yaml`
- `helm lint chart -f chart/values.yaml -f chart/values-saas.yaml`
- `helm template studiomcp chart -f chart/values.yaml -f chart/values-kind.yaml`
- `skaffold diagnose --yaml-only --profile kind`
- `skaffold render --offline --profile kind --digest-source=tag`

Current validation note:

- `validate mcp` currently validates the legacy custom DAG HTTP control surface, not true MCP conformance.
- `validate keycloak` currently passes in configuration-only mode when no live Keycloak JWKS endpoint is available.
- `validate mcp-auth` currently validates JWT parsing/issuer/audience/scope scaffolding, not cryptographic signature verification.
- `validate session-store` and `validate horizontal-scale` currently validate the local shared-backend session simulation, not a live Redis service.
- `validate web-bff` currently validates local BFF flows, not live MCP orchestration or inference-backed chat.
- `validate mcp-conformance` currently validates local catalog and BFF behavior, not end-to-end executor/storage integration through the running `/mcp` server.
- `/metrics` on the running server currently exposes legacy run counters rather than the full MCP metrics service.

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
Status: **Implemented Locally - MCP transports exist, but live execution/runtime wiring still remains split with legacy `/runs`**

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
- Live workflow execution is still primarily exposed through the legacy `/runs` surface: **Partial migration**
- Legacy `/runs` validation via `validate mcp`: **Still present** (validator now emits a deprecation warning)
- MCP Inspector/manual external-client proof: **Not automated in-repo**
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
Status: **In Progress - Types and validation exist, signature verification missing**

Current state:
- Auth types (AuthContext, Subject, Tenant, Scopes, Roles): **Complete**
- Keycloak configuration types: **Complete**
- JWT parsing and structure validation: **Complete**
- Timing validation (exp, nbf): **Complete**
- Issuer and audience validation: **Complete**
- JWKS cache and fetch: **Complete (configuration/scaffolding only)**
- RSA/EC signature verification: **NOT IMPLEMENTED** (requires jose or cryptonite library)
- Development bypass auth: **Complete**
- Claims extraction and scope/role enforcement: **Complete**
- Real Keycloak integration testing: **Partial** (configuration-mode validation exists; live signed-token proof still missing)
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
Status: **In Progress - Local shared-backend validation exists, real Redis integration missing**

Current state:
- Session types (SessionId, SessionState): **Complete**
- Session store interface (SessionStore typeclass): **Complete**
- Redis configuration types: **Complete**
- RedisSessionStore implementation: **LOCAL SHARED BACKEND SIMULATION** (uses STM-backed shared state, not hedis)
- Session operations (create, get, update, delete, touch): **Complete (in-memory)**
- Subscription tracking: **Complete (in-memory)**
- Cursor position storage: **Complete (in-memory)**
- Lock acquisition/release: **Complete (in-memory)**
- Real Redis client (hedis): **NOT INTEGRATED**
- TTL-based expiration: **Complete (local explicit cleanup path)**
- Multi-replica validation: **Complete locally**
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
Status: **In Progress - Browser-facing flows exist locally, but MCP/runtime/inference integrations remain open**

Current state:
- BFF types (WebSession, ChatMessage, UploadRequest, etc.): **Complete**
- BFF service with session management: **Complete (local/in-memory sessions)**
- Upload request flow: **Complete** (returns tenant-scoped artifact-backed upload URLs)
- Upload confirmation flow: **Partial** (local pending-upload cleanup only; does not notify MCP/runtime)
- Download request flow: **Complete** (returns tenant-scoped artifact-backed download URLs)
- Chat message flow: **Complete** (deterministic local response, not live inference)
- Run submission/status: **Partial** (local cache only; not forwarded to MCP/runtime)
- WAI handlers: **Complete (basic)**
- Real MinIO/S3 presigned URL generation: **NOT INTEGRATED** (requires amazonka-s3 or minio-hs)
- Live BFF-to-MCP orchestration and inference service integration: **NOT INTEGRATED**
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
Status: **In Progress - Governance flows work locally, durable storage backends remain open**

Current state:
- ArtifactState (Active, Hidden, Archived, Superseded): **Complete**
- GovernancePolicy with configurable rules: **Complete**
- State transition functions (hide, archive, supersede, restore): **Complete**
- Hard delete denial (`denyHardDelete` always fails): **Complete**
- State history tracking: **Complete (in-memory)**
- Audit trail service: **Complete (in-memory)**
- TenantStorage service: **Complete (local artifact-backed URLs)**
- Presigned URL generation: **LOCAL DETERMINISTIC URLS ONLY** (not SDK-signed S3/MinIO URLs)
- GovernanceService backend: **IN-MEMORY ONLY** (uses TVar, no database)
- AuditTrailService backend: **IN-MEMORY ONLY** (no durable storage)
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
Status: **In Progress - Catalogs exist, but live `/mcp` runtime wiring remains local-only**

Current state:
- Tool catalog with 10 tools defined: **Complete**
- Tool definitions with JSON schemas: **Complete**
- Tool authorization (toolRequiredScopes): **Complete**
- `workflow.submit` execution: **Partial** (real DAG execution only exists in the executor-backed variant; default server uses the local accepted-run path)
- `workflow.status` execution: **Partial** (local run records unless a storage-backed path is manually wired)
- `workflow.cancel` execution: **Partial** (local run records only)
- `workflow.list` execution: **Partial** (local run records only)
- `artifact.*` execution: **Partial** (local tenant storage/governance services only)
- `tenant.info` execution: **Partial** (reports local/static backend and quota information)
- Resource catalog: **Partial** (types exist; several resources return static/mock JSON unless the storage-backed variant is wired)
- Prompt catalog: **Complete (types and structure)**
- Integration with MCP Core: **Partial** (running server uses local-only catalog constructors)
- Exit commands `validate mcp-tools`, `validate mcp-resources`, `validate mcp-prompts`: **Implemented** against local catalogs

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
Status: **In Progress - Local modules exist, but the default running server does not expose the full MCP observability path**

Current state:
- Correlation ID types: **Complete**
- Request context with correlation tracking: **Complete**
- McpMetricsService with method call recording: **Complete (in-memory)**
- RateLimiterService with per-tenant limiting: **Complete (in-memory)**
- Rate limit integration in MCP Core: **Present in an alternate constructor, not enabled by the default running server**
- Quota enforcement: **Complete (local/in-memory)**
- Prometheus metrics export via `/metrics`: **Partial** (running server exports legacy run counters rather than MCP metrics)
- Structured logging with correlation: **Partial**
- Audit logging service: **IN-MEMORY ONLY**
- External observability sinks / durable audit storage: **NOT INTEGRATED**
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
Status: **Implemented Locally - Helm and Skaffold validation are passing**

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
- Keycloak realm bootstrap: **Documented, not exercised end-to-end by the validator suite**

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
Status: **Partial - Local conformance validation exists, but legacy `/runs` still carries real execution/runtime behavior**

Current state:
- MCP protocol conformance-oriented local validation: **Complete**
- Tool, resource, and prompt round-trip coverage in validator: **Complete**
- Session-store migration and shared-backend checks in validator: **Complete**
- BFF-mediated upload, download, and chat validation in validator: **Complete**
- Documentation suite updates for MCP, BFF, and catalog surfaces: **Complete**
- Live `/mcp` end-to-end proof against executor-backed tools and storage-backed resources: **NOT IMPLEMENTED**
- Documented migration path from `/runs` clients: **Partial**
- Deprecation plan for legacy custom HTTP routes: **Partial**
- Legacy `/runs` surface retirement: **NOT IMPLEMENTED**
- Exit commands `validate docs` and `validate mcp-conformance`: **Implemented**

Objective: finish the migration from the legacy custom DAG API to the real MCP system.

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

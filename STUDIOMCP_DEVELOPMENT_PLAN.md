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

- Foundational phases 0 through 12 remain materially complete. The repo already has the Haskell DAG model, validation, summary construction, timeout handling, boundary execution, Pulsar integration, MinIO integration, and end-to-end DAG execution foundations needed for a serious MCP server.
- The current public `server` surface is not yet a standards-compliant MCP surface. It is a custom DAG HTTP API centered on `POST /runs` and `GET /runs/:id/summary`.
- The current `validate mcp` command validates that legacy HTTP surface. It is not proof of MCP protocol conformance.
- The repo does not yet implement MCP lifecycle negotiation, JSON-RPC message handling, standard MCP tool/resource/prompt surfaces, or true MCP transport validation.
- The repo does not yet implement multi-tenant OAuth-protected remote MCP access, Keycloak-backed auth, a browser BFF, or a tenant-facing upload/download/chat product surface.
- The repo does not yet implement horizontally scalable non-sticky MCP listener nodes backed by an externalized session store.
- The repo does not yet implement the hard product rule that the MCP server may never permanently delete media artifacts on behalf of users.
- The governed documentation suite previously described the custom HTTP surface too loosely. This plan treats documentation expansion as a first-class implementation deliverable.

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
- [ ] Phase 13 standards-compliant MCP protocol core and Haskell transport abstraction
- [ ] Phase 14 OAuth-protected multi-tenant auth and authorization
- [ ] Phase 15 non-sticky horizontal session architecture
- [ ] Phase 16 web portal, BFF, and browser upload/download/chat surface
- [ ] Phase 17 tenant artifact storage model and non-destructive media governance
- [ ] Phase 18 MCP tool, resource, and prompt catalog on top of the execution runtime
- [ ] Phase 19 observability, audit, quotas, and abuse controls for SaaS operation
- [ ] Phase 20 Helm-packaged public deployment topology including Keycloak, Postgres, and session store
- [ ] Phase 21 protocol conformance, migration completion, and retirement of the legacy `/runs` surface

## Current Validation State

These checks are known current validations for the existing repository state:

- `cabal build all`
- `cabal test unit-tests`
- `cabal run studiomcp -- validate-dag examples/dags/transcode-basic.yaml`
- `cabal run studiomcp -- dag validate-fixtures`
- `cabal run studiomcp -- validate docs`
- `cabal run studiomcp -- validate boundary`
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
- `STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests`
- `helm lint chart -f chart/values.yaml -f chart/values-kind.yaml`
- `skaffold diagnose --yaml-only --profile kind`
- `skaffold render --offline --profile kind --digest-source=tag`

Current validation note:

- `validate mcp` currently validates the legacy custom DAG HTTP control surface, not true MCP conformance.

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

## Delivery Sequencing Rule

Implementation proceeds in order. Before advancing a phase:

1. Update the relevant authoritative docs.
2. Update the dependent docs and references.
3. Implement the behavior.
4. Add or update validation.
5. Run the phase exit commands.

## Revised Delivery Phases

### Phase 13: Standards-Compliant MCP Protocol Core
Status: Not started

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
STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests
```

### Phase 14: OAuth-Protected Multi-Tenant Auth And Authorization
Status: Not started

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
STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests
```

### Phase 15: Non-Sticky Horizontal Session Architecture
Status: Not started

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
STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests
```

### Phase 16: Web Portal, BFF, And Browser Media Workflows
Status: Not started

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
docker compose -f docker/docker-compose.yaml exec -T studiomcp-env studiomcp validate web-bff
STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests
```

### Phase 17: Tenant Artifact Storage And Non-Destructive Media Governance
Status: Not started

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
STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests
```

### Phase 18: MCP Tool, Resource, And Prompt Catalog
Status: Not started

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
Status: Not started

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
STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests
```

### Phase 20: Public Deployment Topology And Helm Hardening
Status: Not started

Objective: package the public SaaS topology for Kubernetes with secure defaults.

Must deliver:

- Helm values and templates for MCP listeners
- worker deployment topology
- Redis or equivalent session-store deployment profile
- Keycloak deployment profile
- dedicated Postgres deployment profile for Keycloak
- ingress and TLS topology
- secrets and config management strategy
- dev, kind, and SaaS-oriented values files

Explicitly out of scope:

- support for every cloud vendor
- hand-maintained shell deployment scripts

Required coverage:

- Helm lint for all supported profiles
- rendered manifest checks
- multi-replica deployment validation
- Keycloak realm bootstrap runbook verification

Exit commands:

```bash
helm lint chart -f chart/values.yaml -f chart/values-kind.yaml
helm lint chart -f chart/values.yaml -f chart/values-saas.yaml
skaffold diagnose --yaml-only --profile kind
skaffold render --offline --profile kind --digest-source=tag
```

### Phase 21: Conformance, Migration Completion, And Legacy Surface Retirement
Status: Not started

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
STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests
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

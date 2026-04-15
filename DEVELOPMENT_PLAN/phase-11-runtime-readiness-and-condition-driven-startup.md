# File: DEVELOPMENT_PLAN/phase-11-runtime-readiness-and-condition-driven-startup.md
# Phase 11: Runtime Readiness and Condition-Driven Startup

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#phase-overview), [00-overview.md](00-overview.md), [system-components.md](system-components.md)

> **Purpose**: Close the cross-cutting readiness gap across the `studioMCP` server, BFF, worker,
> inference, cluster CLI, validators, and integration harness so deploy-time and validation-time
> behavior depends on explicit application conditions rather than shallow probes, fixed sleeps, or
> ad hoc command-local retries.

## Phase Summary

**Status**: Done
**Implementation**: `src/StudioMCP/API/Readiness.hs`, `src/StudioMCP/API/Health.hs`, `src/StudioMCP/CLI/Cluster.hs`, `src/StudioMCP/MCP/Handlers.hs`, `src/StudioMCP/MCP/Server.hs`, `src/StudioMCP/Web/Handlers.hs`, `src/StudioMCP/Worker/Server.hs`, `src/StudioMCP/Inference/Host.hs`, `src/StudioMCP/Inference/ReferenceModel.hs`, `chart/templates/studiomcp_deployment.yaml`, `chart/templates/bff.yaml`, `chart/templates/worker.yaml`, `chart/templates/llm_reference.yaml`, `chart/values.yaml`, `test/API/ReadinessSpec.hs`, `test/Integration/HarnessSpec.hs`
**Docs to update**: `DEVELOPMENT_PLAN/system-components.md`, `documents/architecture/overview.md`, `documents/architecture/server_mode.md`, `documents/architecture/bff_architecture.md`, `documents/architecture/mcp_protocol_architecture.md`, `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/session_scaling.md`, `documents/development/testing_strategy.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/operations/runbook_local_debugging.md`

### Goal

Make readiness a first-class runtime contract throughout `studioMCP` by:

- expressing startup and dependency state as explicit conditions with reason codes
- aligning HTTP readiness endpoints and Kubernetes probes with real application capability
- waiting on condition closure through watch-driven cluster logic instead of sleeps
- reusing the same readiness contract across `cluster ensure`, `cluster deploy server`,
  validators, and integration tests
- keeping bounded final-request retries only as a last-mile transport hedge, not as the primary
  startup synchronization mechanism

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Shared readiness condition model and reason vocabulary | `src/StudioMCP/API/Readiness.hs`, `src/StudioMCP/API/Health.hs`, `src/StudioMCP/CLI/Cluster.hs` | Done |
| Dependency-aware MCP server readiness | `src/StudioMCP/MCP/Server.hs`, `src/StudioMCP/Auth/*.hs`, `src/StudioMCP/MCP/Session/*.hs` | Done |
| Dependency-aware BFF readiness | `src/StudioMCP/Web/Handlers.hs`, `src/StudioMCP/Web/BFF.hs` | Done |
| Worker, inference, and advisory reference-model startup/readiness contract | `src/StudioMCP/Worker/Server.hs`, `src/StudioMCP/Inference/*.hs`, `chart/templates/llm_reference.yaml` | Done |
| Kubernetes probes aligned to application conditions | `chart/templates/studiomcp_deployment.yaml`, `chart/templates/bff.yaml`, `chart/templates/worker.yaml`, `chart/values.yaml` | Done |
| Watch- and condition-driven cluster waiters across rollout, routing, and application readiness | `src/StudioMCP/CLI/Cluster.hs` | Done |
| Explicit bootstrap-complete gates for shared services and one-time setup | `src/StudioMCP/CLI/Cluster.hs` | Done |
| Shared readiness diagnostics reused by validators and the integration harness | `src/StudioMCP/CLI/Cluster.hs`, `test/Integration/HarnessSpec.hs` | Done |
| Readiness metrics and logs with blocking reasons | `src/StudioMCP/MCP/Server.hs`, `src/StudioMCP/Web/Handlers.hs`, `src/StudioMCP/Worker/Server.hs`, `src/StudioMCP/Inference/Host.hs` | Done |

### Implemented Closure

The supported path now closes the cross-cutting readiness gap in code:

- `src/StudioMCP/API/Readiness.hs` defines the shared readiness status, check, reason, and report
  model reused by runtimes and the cluster CLI
- the MCP server, BFF, worker, and inference surfaces now expose dependency-aware readiness
  payloads with structured blocking reasons instead of generic `ready` responses
- the Helm-managed advisory reference-model service publishes `/healthz`, and the cluster path now
  treats that internal service as a peer readiness gate for BFF and inference consumers
- `cluster deploy server` now waits for workload rollout, Kubernetes `EndpointSlice`
  publication, ingress-routable readiness for `/mcp` and `/api`, worker readiness, and
  reference-model health before live validators proceed
- shared-service startup in `cluster ensure` now blocks on MinIO, Pulsar, and Keycloak
  application availability instead of stopping at pod rollout alone
- the integration harness now preserves validator stdout and stderr when a live readiness gate
  fails so blocking reasons survive into test output
- the MCP `/metrics` surface now emits readiness gauges and blocking-check detail labels, while
  all runtime surfaces log readiness transitions with the active blocking summary

### Target Readiness Architecture

### 1. Readiness Model

`studioMCP` treats readiness as a pure state model driven by observed signals.

- input signals come from Kubernetes watches, HTTP health checks, dependency checks, and bootstrap
  completion notifications
- the reducer from `Signal -> Model -> Model` stays pure
- blocking behavior uses STM or equivalent wait primitives over the current model rather than
  fixed sleeps
- every blocking condition carries a machine-readable reason that can be logged, surfaced in
  health payloads, and emitted by the CLI on timeout

### 2. Kubernetes Contract

Kubernetes readiness reflects real application capability, not just process liveness.

- `readinessProbe` returns success only when the role-specific application conditions have closed
- one-time bootstrap work surfaces explicit completion conditions through Kubernetes `Job`
  completion or an equivalent explicit control-plane gate
- routing readiness and application readiness remain distinct:
  rollout plus `EndpointSlice` publication prove routability, while application conditions prove
  the backend can actually serve authenticated MCP, browser, worker, or inference traffic
- status conditions remain the supported extension point when external dependency closure must be
  reflected before traffic is safe

### 3. CLI Contract

The cluster CLI owns one shared readiness waiter.

- `cluster ensure` and `cluster deploy server` use `LIST + WATCH` semantics over the
  relevant Kubernetes resources instead of sleeping and retrying blind
- correctness comes from the reconciled current snapshot, not from trusting Kubernetes
  `Event` objects as the source of truth
- validators and integration tests call the same readiness helper instead of each command
  inventing its own startup logic
- timeout failures name the exact blocking condition, resource, and last observed reason

### 4. Runtime Contract

Each major runtime surface exposes the conditions it requires before it is safe to receive
traffic.

- MCP server: auth service initialized, JWKS issuer path usable, shared session store reachable,
  required runtime dependencies reachable for the exposed surface
- BFF: auth and session dependencies ready, cookie/session flows usable, downstream APIs reachable
- worker and inference surfaces: role-specific dependencies ready before the workload reports ready
- readiness payloads return structured JSON reasons rather than a single generic `ready`
  response

### 5. Validation Contract

Validation proves the shared readiness contract rather than mask it.

- `validate mcp-http`, `validate web-bff`, `validate mcp-auth`, `validate mcp-conformance`,
  integration tests, and the aggregate `test` and `validate all` flows depend on the same
  readiness gating primitive
- validator-local transport retries remain acceptable only as bounded final-request hedges after
  the shared readiness gate has already closed
- the integration harness surfaces validator stdout and stderr for readiness failures so the
  blocking reason survives into test output

### Validation

### Validation Prerequisites

All validation commands run inside the outer container after bootstrap:

```bash
docker compose build
docker compose run --rm studiomcp studiomcp cluster ensure
```

### Validation Gates

| Check | Command | Expected |
|-------|---------|----------|
| Unit tests | `docker compose run --rm studiomcp studiomcp test unit` | Readiness reducers, reason rendering, and health-handler unit tests pass |
| Cluster ensure | `docker compose run --rm studiomcp studiomcp cluster ensure` | Shared services, bootstrap jobs, and readiness conditions converge without fixed sleeps |
| Cluster deploy server | `docker compose run --rm studiomcp studiomcp cluster deploy server` | MCP and BFF workloads become routable and application-ready through shared condition gating |
| MCP HTTP validation | `docker compose run --rm studiomcp studiomcp validate mcp-http` | Passes through the shared readiness contract without depending on startup-race retries as the primary mechanism |
| BFF validation | `docker compose run --rm studiomcp studiomcp validate web-bff` | Passes through the shared readiness contract |
| Aggregate validation | `docker compose run --rm studiomcp studiomcp validate all` | Uses shared readiness gating across the live validator set |
| Integration tests | `docker compose run --rm studiomcp studiomcp test integration` | Harness reuses shared readiness gating and surfaces blocking reasons on failure |
| Docs validation | `docker compose run --rm studiomcp studiomcp validate docs` | PASS |

### Current Validation State

- `docker compose build` passes after the requested `kind` teardown and `docker system prune -af
  --volumes` sequence.
- `docker compose run --rm studiomcp studiomcp test` passes on the readiness-updated worktree
  after the requested teardown, prune, rebuild, and full-suite rerun.
- `docker compose run --rm studiomcp studiomcp validate docs` passes on the governed-doc updates
  for this phase.
- The governed docs listed for this phase are aligned with the implemented readiness contract in
  this change set.

### Remaining Work

None.

## Documentation Requirements

**Engineering docs to create/update:**
- `DEVELOPMENT_PLAN/system-components.md` - component inventory must name the internal reference-model service and boundary
- `documents/architecture/overview.md` - system-wide readiness ownership and route-level versus application-level readiness
- `documents/architecture/server_mode.md` - MCP server readiness conditions and startup contract
- `documents/architecture/bff_architecture.md` - BFF dependency-aware readiness and session bootstrap requirements
- `documents/architecture/mcp_protocol_architecture.md` - MCP HTTP startup and session bootstrap expectations
- `documents/engineering/k8s_native_dev_policy.md` - watch-driven waiters, probes, jobs, and supported deploy-time readiness semantics
- `documents/engineering/session_scaling.md` - session-store readiness and scale-out startup behavior
- `documents/development/testing_strategy.md` - readiness-aware integration and validator expectations
- `documents/reference/cli_reference.md` and `documents/reference/cli_surface.md` - any CLI readiness/waiting commands or changed deploy semantics
- `documents/operations/runbook_local_debugging.md` - diagnosing blocked readiness conditions and timeout output

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Keep [phase-6-cluster-control-plane-parity.md](phase-6-cluster-control-plane-parity.md) aligned with the narrower routing-level readiness scope.
- Keep [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md) aligned with the aggregate validation gate once shared readiness replaces command-local startup handling.
- Keep [README.md](README.md), [00-overview.md](00-overview.md), and [system-components.md](system-components.md) aligned as the phase advances.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-6-cluster-control-plane-parity.md](phase-6-cluster-control-plane-parity.md)
- [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md)

# File: DEVELOPMENT_PLAN/README.md
# studioMCP Development Plan

**Status**: Authoritative source
**Supersedes**: legacy monolithic development plan layout
**Referenced by**: [../README.md](../README.md#development-roadmap), [../documents/documentation_standards.md](../documents/documentation_standards.md#8-documentation-maintenance-checklist)

> **Purpose**: Provide the single execution-ordered development plan for `studioMCP`, including
> phase status, validation gates, documentation obligations, and cleanup ownership.

## Standards

See [development_plan_standards.md](development_plan_standards.md) for the maintenance rules that
govern this plan.

## Document Index

| Document | Purpose |
|----------|---------|
| [development_plan_standards.md](development_plan_standards.md) | Maintenance rules for the development plan |
| [00-overview.md](00-overview.md) | Architecture overview, current constraints, and topology baseline |
| [system-components.md](system-components.md) | Authoritative component inventory and boundary map |
| [phase-1-repository-dag-runtime-foundations.md](phase-1-repository-dag-runtime-foundations.md) | Repository, DAG, and runtime foundations |
| [phase-2-mcp-surface-catalog-artifact-governance.md](phase-2-mcp-surface-catalog-artifact-governance.md) | MCP surface, catalogs, artifact governance, and observability |
| [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md) | Keycloak auth and shared Redis-backed sessions |
| [phase-4-control-plane-data-plane-contract.md](phase-4-control-plane-data-plane-contract.md) | Control-plane and data-plane contract closure |
| [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md) | Browser session contract hardening |
| [phase-6-cluster-control-plane-parity.md](phase-6-cluster-control-plane-parity.md) | Kind and Helm control-plane parity |
| [phase-7-keycloak-realm-bootstrap.md](phase-7-keycloak-realm-bootstrap.md) | Keycloak realm bootstrap automation |
| [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md) | Final regression closure and clean validation gate |
| [phase-9-cli-test-validate-consolidation.md](phase-9-cli-test-validate-consolidation.md) | CLI test and validate command consolidation |
| [phase-10-build-artifact-isolation.md](phase-10-build-artifact-isolation.md) | Build artifact isolation and one-command container configuration closure |
| [phase-11-runtime-readiness-and-condition-driven-startup.md](phase-11-runtime-readiness-and-condition-driven-startup.md) | Runtime readiness, condition-driven startup, and shared wait-gate closure |
| [phase-12-aggregate-test-artifact-isolation-and-warning-closure.md](phase-12-aggregate-test-artifact-isolation-and-warning-closure.md) | Aggregate test artifact isolation and repo-owned warning closure |
| [phase-13-harbor-push-reliability-and-mcp-http-closure.md](phase-13-harbor-push-reliability-and-mcp-http-closure.md) | Harbor-backed MCP HTTP validation and aggregate-suite reliability closure |
| [phase-14-makefile-removal.md](phase-14-makefile-removal.md) | Makefile removal and docker-compose consolidation |
| [phase-15-monocontainer-tool-expansion.md](phase-15-monocontainer-tool-expansion.md) | Monocontainer tool expansion with audio/music binaries |
| [phase-16-minio-model-storage.md](phase-16-minio-model-storage.md) | MinIO model storage infrastructure |
| [phase-17-haskell-tool-adapters.md](phase-17-haskell-tool-adapters.md) | Haskell tool adapters for audio foundation |
| [phase-18-minio-fixture-seeding.md](phase-18-minio-fixture-seeding.md) | MinIO test fixture seeding infrastructure |
| [phase-19-individual-tool-tests.md](phase-19-individual-tool-tests.md) | Individual tool transformation tests |
| [phase-20-dag-chain-integration-tests.md](phase-20-dag-chain-integration-tests.md) | Complex DAG chain integration tests |
| [phase-21-chaos-engineering.md](phase-21-chaos-engineering.md) | Chaos engineering test suite |
| [phase-22-ses-email-integration.md](phase-22-ses-email-integration.md) | AWS SES email integration |
| [phase-23-tool-documentation.md](phase-23-tool-documentation.md) | Tool documentation and MCP catalog update |
| [phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md) | Whisper runtime shared-library closure |
| [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) | Cleanup and compatibility removal ledger |

## Status Vocabulary

| Status | Meaning |
|--------|---------|
| `Done` | Implemented, validated, docs aligned, no remaining work |
| `Active` | Implemented in part or mostly closed, but remaining work is explicit |
| `Blocked` | Waiting on named prerequisites |
| `Planned` | Ready to start with dependencies already satisfied |

## Definition of Done

A phase can move to `Done` only when all of the following are true:

1. The deliverables exist in the repository worktree.
2. The listed validation gates pass on the supported path.
3. The governed docs listed in `Docs to update` are aligned with the implementation.
4. No `Remaining Work` section remains open.
5. `docker compose run --rm studiomcp studiomcp validate docs` passes after the documentation change.
6. Cleanup promised by the phase is reflected in [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md).

## Phase Overview

| Phase | Name | Status | Document |
|-------|------|--------|----------|
| 1 | Repository, DAG, and Runtime Foundations | Done | [phase-1-repository-dag-runtime-foundations.md](phase-1-repository-dag-runtime-foundations.md) |
| 2 | MCP Surface, Catalog, Artifact Governance, and Observability | Done | [phase-2-mcp-surface-catalog-artifact-governance.md](phase-2-mcp-surface-catalog-artifact-governance.md) |
| 3 | Keycloak Auth and Shared Session Foundations | Done | [phase-3-keycloak-auth-shared-sessions.md](phase-3-keycloak-auth-shared-sessions.md) |
| 4 | Control-Plane and Data-Plane Contract Closure | Done | [phase-4-control-plane-data-plane-contract.md](phase-4-control-plane-data-plane-contract.md) |
| 5 | Browser Session Contract Hardening | Done | [phase-5-browser-session-contract.md](phase-5-browser-session-contract.md) |
| 6 | Cluster Control-Plane Parity | Done | [phase-6-cluster-control-plane-parity.md](phase-6-cluster-control-plane-parity.md) |
| 7 | Keycloak Realm Bootstrap Automation | Done | [phase-7-keycloak-realm-bootstrap.md](phase-7-keycloak-realm-bootstrap.md) |
| 8 | Final Closure and Regression Gate | Done | [phase-8-final-closure-regression-gate.md](phase-8-final-closure-regression-gate.md) |
| 9 | CLI Test and Validate Consolidation | Done | [phase-9-cli-test-validate-consolidation.md](phase-9-cli-test-validate-consolidation.md) |
| 10 | Build Artifact Isolation and Container Configuration | Done | [phase-10-build-artifact-isolation.md](phase-10-build-artifact-isolation.md) |
| 11 | Runtime Readiness and Condition-Driven Startup | Done | [phase-11-runtime-readiness-and-condition-driven-startup.md](phase-11-runtime-readiness-and-condition-driven-startup.md) |
| 12 | Aggregate Test Artifact Isolation and Warning Closure | Done | [phase-12-aggregate-test-artifact-isolation-and-warning-closure.md](phase-12-aggregate-test-artifact-isolation-and-warning-closure.md) |
| 13 | Harbor Push Reliability and MCP HTTP Closure | Done | [phase-13-harbor-push-reliability-and-mcp-http-closure.md](phase-13-harbor-push-reliability-and-mcp-http-closure.md) |
| 14 | Makefile Removal and Docker Compose Consolidation | Done | [phase-14-makefile-removal.md](phase-14-makefile-removal.md) |
| 15 | Monocontainer Tool Expansion | Done | [phase-15-monocontainer-tool-expansion.md](phase-15-monocontainer-tool-expansion.md) |
| 16 | MinIO Model Storage Infrastructure | Done | [phase-16-minio-model-storage.md](phase-16-minio-model-storage.md) |
| 17 | Haskell Tool Adapters | Done | [phase-17-haskell-tool-adapters.md](phase-17-haskell-tool-adapters.md) |
| 18 | MinIO Test Fixture Seeding | Done | [phase-18-minio-fixture-seeding.md](phase-18-minio-fixture-seeding.md) |
| 19 | Individual Tool Transformation Tests | Done | [phase-19-individual-tool-tests.md](phase-19-individual-tool-tests.md) |
| 20 | Complex DAG Chain Integration Tests | Done | [phase-20-dag-chain-integration-tests.md](phase-20-dag-chain-integration-tests.md) |
| 21 | Chaos Engineering Test Suite | Done | [phase-21-chaos-engineering.md](phase-21-chaos-engineering.md) |
| 22 | AWS SES Email Integration | Done | [phase-22-ses-email-integration.md](phase-22-ses-email-integration.md) |
| 23 | Tool Documentation and MCP Catalog Update | Done | [phase-23-tool-documentation.md](phase-23-tool-documentation.md) |
| 24 | Whisper Runtime Shared-Library Closure | Done | [phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md) |

## Current Validation State

**Validated in this review:**
- `docker compose run --rm studiomcp studiomcp --help` exits successfully and prints the current CLI surface, including `email`, `models`, `validate whisper-adapter`, `test`, the `test all` alias, and `test chaos`.
- `docker compose run --rm studiomcp whisper --help` passes on April 14, 2026 without shared-library loader errors.
- `docker compose run --rm studiomcp studiomcp validate whisper-adapter` passes on April 14, 2026.
- `docker compose run --rm studiomcp studiomcp validate docs` passes on April 14, 2026.
- `docker compose run --rm studiomcp studiomcp test unit` passes on April 14, 2026 with `897 examples, 0 failures`.
- `docker compose run --rm studiomcp studiomcp test` passes on April 14, 2026 with `897 examples, 0 failures` in the unit suite, `26 examples, 0 failures` in the integration suite, and `All tests passed.`
- `docker compose run --rm studiomcp studiomcp validate all` passes on April 14, 2026 with `Passed: 36/36`; the current source tree enumerates 36 validators in `src/StudioMCP/CLI/Cluster.hs`.

**Closed Follow-On:**
- Phase 24 is now closed: `docker compose build` rebuilds the outer image with loader-visible `libwhisper.so.1` and companion `libggml*.so` files under `/usr/local/lib`, `whisper --help` runs without manual fixes, and the repaired adapter, aggregate test, and live-validator paths are recorded in [phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md).

**Cluster-Dependent Coverage Surface:**
- `cluster ensure` now waits for shared-service application readiness for MinIO, Pulsar, and Keycloak after workload rollout.
- `cluster deploy server` now blocks on rollout, Kubernetes service endpoint publication, ingress-edge readiness for `/mcp` and `/api`, worker readiness, and reference-model health before live validators proceed.
- The integration harness now preserves validator stdout and stderr when a shared readiness gate fails, so blocking reasons survive into test output.
- Integration tests and aggregate validation continue to exercise Keycloak, MinIO, Pulsar, ingress routing, MCP HTTP, BFF session flows, horizontal scale, observability, and conformance through the live cluster path.

**Closed Historical Follow-On:**
- Phase 13 is now closed: the local kind Harbor registry uses persistent filesystem-backed image storage with relative upload URLs, the Harbor registry PVC is reconciled on the manual-PV path, the CLI waits for PostgreSQL and Redis plus Harbor `/api/v2.0/health` and registry `/v2/` readiness before managed publication, and the managed-registry push path still applies extended retry/backoff with remote-digest confirmation.

## Phase Details

| Phase | Status | Remaining Work | Docs to update |
|-------|--------|----------------|----------------|
| 1 | Done | None | `documents/domain/dag_specification.md`, `documents/architecture/parallel_scheduling.md`, `documents/tools/ffmpeg.md` |
| 2 | Done | None | `documents/architecture/mcp_protocol_architecture.md`, `documents/reference/mcp_surface.md`, `documents/reference/mcp_tool_catalog.md`, `documents/architecture/artifact_storage_architecture.md` |
| 3 | Done | None | `documents/architecture/multi_tenant_saas_mcp_auth_architecture.md`, `documents/engineering/security_model.md`, `documents/engineering/session_scaling.md` |
| 4 | Done | None | `documents/architecture/overview.md`, `documents/reference/web_portal_surface.md` |
| 5 | Done | None | `documents/reference/web_portal_surface.md`, `documents/architecture/bff_architecture.md` |
| 6 | Done | None | `documents/engineering/docker_policy.md`, `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/k8s_storage.md`, `documents/operations/runbook_local_debugging.md` |
| 7 | Done | None | `documents/operations/keycloak_realm_bootstrap_runbook.md` |
| 8 | Done | None | `README.md`, `documents/README.md`, `documents/documentation_standards.md`, `documents/development/testing_strategy.md`, `documents/engineering/testing.md`, `documents/development/local_dev.md`, `documents/engineering/local_dev.md`, plan index files as needed |
| 9 | Done | None | `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `DEVELOPMENT_PLAN/development_plan_standards.md` |
| 10 | Done | None | `README.md`, `documents/engineering/docker_policy.md`, `documents/engineering/k8s_native_dev_policy.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/development/local_dev.md`, `documents/operations/runbook_local_debugging.md` |
| 11 | Done | None | `documents/architecture/overview.md`, `documents/architecture/server_mode.md`, `documents/architecture/bff_architecture.md`, `documents/architecture/mcp_protocol_architecture.md`, `documents/engineering/k8s_native_dev_policy.md`, `documents/engineering/session_scaling.md`, `documents/development/testing_strategy.md`, `documents/reference/cli_reference.md`, `documents/reference/cli_surface.md`, `documents/operations/runbook_local_debugging.md` |
| 12 | Done | None | `documents/engineering/docker_policy.md`, `DEVELOPMENT_PLAN/development_plan_standards.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/phase-10-build-artifact-isolation.md` |
| 13 | Done | None | `documents/engineering/docker_policy.md`, `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/phase-12-aggregate-test-artifact-isolation-and-warning-closure.md` |
| 14 | Done | None | `CLAUDE.md`, `documents/engineering/docker_policy.md`, `DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md` |
| 15 | Done | None | `system-components.md`, `documents/engineering/docker_policy.md` |
| 16 | Done | None | `system-components.md`, `documents/engineering/model_storage.md` |
| 17 | Done | None | `system-components.md`, `documents/reference/mcp_tool_catalog.md`, `documents/tools/*.md` |
| 18 | Done | None | `documents/development/test_fixtures.md` |
| 19 | Done | None | None |
| 20 | Done | None | `documents/reference/mcp_tool_catalog.md` |
| 21 | Done | None | `documents/development/chaos_testing.md` |
| 22 | Done | None | `documents/operations/ses_email.md`, `documents/engineering/email_templates.md` |
| 23 | Done | None | `documents/tools/*.md`, `documents/reference/mcp_tool_catalog.md`, `documents/README.md` |
| 24 | Done | None | `DEVELOPMENT_PLAN/README.md`, `DEVELOPMENT_PLAN/00-overview.md`, `DEVELOPMENT_PLAN/system-components.md`, `DEVELOPMENT_PLAN/phase-8-final-closure-regression-gate.md`, `DEVELOPMENT_PLAN/phase-15-monocontainer-tool-expansion.md`, `DEVELOPMENT_PLAN/phase-17-haskell-tool-adapters.md`, `DEVELOPMENT_PLAN/phase-19-individual-tool-tests.md`, `documents/engineering/docker_policy.md`, `documents/tools/whisper.md` |

## Cross-References

- [development_plan_standards.md](development_plan_standards.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [phase-24-whisper-runtime-closure.md](phase-24-whisper-runtime-closure.md)
- [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)

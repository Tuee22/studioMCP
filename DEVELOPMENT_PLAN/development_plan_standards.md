# File: DEVELOPMENT_PLAN/development_plan_standards.md
# studioMCP Development Plan Standards

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [../documents/documentation_standards.md](../documents/documentation_standards.md#8-documentation-maintenance-checklist)

> **Purpose**: Define how the `studioMCP` development plan is organized, updated, and kept aligned
> with implementation, validation, and governed documentation.

## Core Principles

### A. Continuous Execution-Ordered Narrative

The plan must read as one ordered buildout from repository foundations to final regression closure.

- Each phase assumes the previous phase has already closed.
- The plan should move from repository/runtime foundations to protocol surface, auth, control-plane
  routing, browser contract, cluster parity, bootstrap automation, and final regression closure.
- A reader unfamiliar with the repository should be able to follow the plan from top to bottom
  without reconstructing hidden dependencies from scattered notes.

### B. Detailed, Implementation-Oriented Content

The plan is intentionally concrete.

- Include real files, commands, validation gates, and contract notes where they materially clarify
  what is implemented or still open.
- Command examples should use the canonical binary name `studiomcp`.
- Command examples that invoke `cabal` must either rely on `cabal.project` builddir or pass
  `--builddir=/opt/build/studiomcp` explicitly. Build artifacts must never land in the repo tree.
- Examples do not need to be verbatim copies of implementation files, but they must not contradict
  the supported architecture or validation surface.

### C. Honest Completion Tracking

Status must describe the current repository state, not intended future work.

| Status | Meaning |
|--------|---------|
| `Done` | Implemented and validated; no remaining work |
| `Active` | Partially closed; remaining work is explicitly listed |
| `Blocked` | Waiting on a prerequisite that is named explicitly |
| `Planned` | Not started yet, but dependencies are already satisfied |

Rules:
- `Done` requires passing validation, aligned docs, and no remaining work.
- `Active` requires a `Remaining Work` section.
- `Blocked` requires a `Blocked by` line.
- `Planned` must not hide unmet blockers.

### D. Declarative Current-State Language

Plan documents should describe the intended supported architecture in present-tense declarative
language.

- Say what the system uses, owns, validates, and exposes.
- Do not turn phase docs into migration diaries.
- Compatibility cleanup belongs in the explicit removal ledger, not as the main story of a phase.

### E. One Canonical Folder Model

The `studioMCP` development plan lives in this directory layout:

```text
DEVELOPMENT_PLAN/
├── development_plan_standards.md
├── README.md
├── 00-overview.md
├── system-components.md
├── phase-1-repository-dag-runtime-foundations.md
├── phase-2-mcp-surface-catalog-artifact-governance.md
├── phase-3-keycloak-auth-shared-sessions.md
├── phase-4-control-plane-data-plane-contract.md
├── phase-5-browser-session-contract.md
├── phase-6-cluster-control-plane-parity.md
├── phase-7-keycloak-realm-bootstrap.md
├── phase-8-final-closure-regression-gate.md
├── phase-9-cli-test-validate-consolidation.md
└── legacy-tracking-for-deletion.md
```

The root [../DEVELOPMENT_PLAN.md](../DEVELOPMENT_PLAN.md) file remains a compatibility index for
existing links, but the authoritative plan narrative now lives under `DEVELOPMENT_PLAN/`.

### F. System Component Inventory

[system-components.md](system-components.md) is the authoritative inventory for:

- edge and infrastructure services
- runtime and application binaries
- serialization and trust boundaries
- state and artifact locations

When the plan changes architecture, update the component inventory in the same change.

### G. Phase Document Requirements

Each phase document must include:

```markdown
## Phase Summary

**Status**: Done | Active | Planned | Blocked
**Implementation**: `path/to/file` (required for Done, recommended otherwise)
**Blocked by**: phase id(s) (required for Blocked)
**Docs to update**: `file.md`, `other.md`

### Goal

### Deliverables

### Validation

### Remaining Work

## Documentation Requirements
```

Additional sections such as `Test Mapping`, `Current Validation State`, or `Resolved Regressions`
are encouraged when they materially clarify closure criteria.

### H. Documentation Requirements Section

Every phase document must contain a `Documentation Requirements` section using this format:

```markdown
## Documentation Requirements

**Engineering docs to create/update:**
- `documents/...` - technical contract or implementation notes

**Product docs to create/update:**
- None.

**Cross-references to add:**
- Update the owning index or companion plan docs
```

Rules:
- User-facing behavior changes require product/reference document updates when they exist.
- Architecture, operations, validation, and boundary changes require engineering or architecture
  document updates.
- A phase must not be marked `Done` if the listed docs are stale.

### I. Explicit Cleanup and Removal Ledger

[legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) is the authoritative cleanup
ledger for deprecated compatibility helpers, stale configuration kept only for future work, and
known removal candidates.

- If a deprecated surface still exists in the repository, it must appear in the ledger.
- Each item must name its location, why it remains, and the owning phase.
- When cleanup lands, move the item from `Pending Removal` to `Completed`.

### J. Documentation Harmony

The plan and the governed `documents/` suite must agree.

- [README.md](README.md), [00-overview.md](00-overview.md), all phase documents,
  [system-components.md](system-components.md), and [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md)
  must use the same phase names and status model.
- Governed documents under `documents/` must match the current architecture described by the plan.
- [../documents/README.md](../documents/README.md) and
  [../documents/documentation_standards.md](../documents/documentation_standards.md) must stay
  aligned with the plan entry points.

### K. Mermaid Rendering Contract

If a change adds or edits Mermaid under `DEVELOPMENT_PLAN/`, it must follow the authoring and
rendering rules defined in
[../documents/documentation_standards.md](../documents/documentation_standards.md#7-mermaid-rendering-rules).

### L. Container Execution Context

The supported development workflow uses the outer `studiomcp-env` container. All commands in
`DEVELOPMENT_PLAN/` must specify their execution context.

**Bootstrap** (run on host):
```bash
docker compose up -d
```

**All other commands** (run inside outer container):
```bash
docker compose exec studiomcp-env studiomcp <subcommand>
docker compose exec studiomcp-env cabal <subcommand>
```

Rules:
- Validation tables must use the full `docker compose exec studiomcp-env` invocation pattern.
- The canonical bootstrap is `docker compose up -d` followed by container commands.
- Never show bare `studiomcp` or `cabal` commands without container context in phase docs.
- Cross-reference [../documents/engineering/docker_policy.md](../documents/engineering/docker_policy.md)
  for the complete container workflow and LLM operating rules.

## CLI-First Testing Policy

All test and validation entrypoints are available through the `studiomcp` CLI inside the outer
container:

| Command | Description |
|---------|-------------|
| `docker compose exec studiomcp-env studiomcp test` | Run all tests (unit + integration) |
| `docker compose exec studiomcp-env studiomcp test unit` | Run unit tests only |
| `docker compose exec studiomcp-env studiomcp test integration` | Run integration tests only |
| `docker compose exec studiomcp-env studiomcp validate all` | Run all validators |

Rules:
- The `studiomcp` CLI is the canonical interface for test and validation execution.
- The CLI runs inside the outer `studiomcp-env` container, not on the host.
- The CLI invokes `cabal test` internally for test suites.
- The authoritative CLI reference lives at [../documents/reference/cli_reference.md](../documents/reference/cli_reference.md).

## Cross-Reference Conventions

- Links inside `DEVELOPMENT_PLAN/` use relative paths.
- Links to governed docs use repository-relative paths.
- If a file is renamed, update every plan and governed-doc reference in the same change.
- Keep the compatibility anchors in [../DEVELOPMENT_PLAN.md](../DEVELOPMENT_PLAN.md) usable when the
  authoritative plan structure changes.

## Maintenance Guidelines

1. Update [README.md](README.md), [00-overview.md](00-overview.md), and
   [system-components.md](system-components.md) first when the phase model or architecture changes.
2. Update the affected phase document next.
3. Update governed docs under `documents/` that the phase lists in `Docs to update`.
4. Update [legacy-tracking-for-deletion.md](legacy-tracking-for-deletion.md) whenever compatibility
   cleanup scope changes.
5. Keep [../DEVELOPMENT_PLAN.md](../DEVELOPMENT_PLAN.md) aligned as the compatibility index.
6. Run `docker compose exec studiomcp-env studiomcp validate docs` before closing the work.
7. If Mermaid changed, validate the diagram subset after the edit.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)
- [system-components.md](system-components.md)
- [../documents/documentation_standards.md](../documents/documentation_standards.md#studiomcp-documentation-standards)

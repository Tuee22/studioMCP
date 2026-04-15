# Phase 23: Tool Documentation and MCP Catalog Update

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md)

> **Purpose**: Close the documentation layer for the expanded tool inventory and make the MCP
> catalog explicit about the difference between tenant-facing `tools/list` entries and DAG boundary
> tool names.

## Phase Summary

**Status**: Done
**Implementation**: `documents/tools/*.md`, `documents/reference/mcp_tool_catalog.md`, `documents/README.md`
**Blocked by**: Phase 22 (Done)
**Docs to update**: `documents/tools/*.md`, `documents/reference/mcp_tool_catalog.md`, `documents/README.md`

### Goal

Document the expanded boundary tool inventory and close the catalog gap without misrepresenting the
public MCP surface:

- add governed docs for each tool
- add model, fixture, chaos, and SES supporting docs
- document the workflow boundary registry in the MCP catalog
- keep `tools/list` focused on tenant-facing orchestration tools rather than raw boundary executables

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| Tool docs for SoX, Demucs, Whisper, BasicPitch, FluidSynth, Rubberband, ImageMagick, and MediaInfo | `documents/tools/*.md` | Done |
| Supporting engineering and operations docs | `documents/engineering/model_storage.md`, `documents/engineering/email_templates.md`, `documents/development/test_fixtures.md`, `documents/development/chaos_testing.md`, `documents/operations/ses_email.md` | Done |
| Update docs index | `documents/README.md` | Done |
| Document workflow boundary registry in the MCP catalog | `documents/reference/mcp_tool_catalog.md` | Done |

### Validation

| Check | Command | Expected |
|-------|---------|----------|
| Docs validation | `docker compose run --rm studiomcp studiomcp validate docs` | PASS |
| Full suite regression gate | `docker compose run --rm studiomcp studiomcp test` | PASS |

### Remaining Work

None. The expanded tool inventory is documented, and the MCP catalog now distinguishes between the
public `tools/list` catalog and the workflow boundary registry used inside DAGs.

## Documentation Requirements

**Engineering docs to create/update:**
- all tool docs under `documents/tools/`
- governed support docs listed above

**Product docs to create/update:**
- `documents/reference/mcp_tool_catalog.md`

**Cross-references to add:**
- Keep [phase-17-haskell-tool-adapters.md](phase-17-haskell-tool-adapters.md) and
  [phase-20-dag-chain-integration-tests.md](phase-20-dag-chain-integration-tests.md) aligned when
  the workflow boundary registry changes.
- Keep [../documents/README.md](../documents/README.md) aligned when the governed tool-doc
  inventory changes.

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)

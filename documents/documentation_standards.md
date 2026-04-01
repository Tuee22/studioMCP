# File: documents/documentation_standards.md
# studioMCP Documentation Standards

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md#suite-structure), [../README.md](../README.md#contribution-guidance), [../STUDIOMCP_DEVELOPMENT_PLAN.md](../STUDIOMCP_DEVELOPMENT_PLAN.md#documentation-governance)

> **Purpose**: Single Source of Truth for how the `documents/` suite is structured, written, linked, and maintained in `studioMCP`.

## 1. Philosophy

### SSoT First
- Every concept has exactly one canonical document.
- Canonical documents use `**Status**: Authoritative source`.
- Supporting docs use `**Status**: Reference only` and link back to the canonical source.
- When architecture or policy changes, update the authoritative document first and then update dependent links.

### Current-State Declarative Docs Only
- `documents/` describes the architecture, rules, and public contracts that are currently authoritative for the repo.
- Do not add ADRs, decision logs, or other history-oriented design records to `documents/`.
- If a rule is active, state it directly in the owning authoritative document.
- If a rule changes, update or replace the owning document instead of preserving parallel historical decision files.
- Git history is the chronology and rationale trail.

### Link, Do Not Copy
- Do not duplicate long explanations, standards, diagrams, or procedures.
- Brief reminders are acceptable only when they immediately link back to the SSoT.
- Tool primers may summarize context, but behavior rules still link back to architecture and testing SSoTs.

### Documents Are Code
- Documentation changes must stay consistent with code and configuration.
- `documents/` is part of the deliverable, not an afterthought.
- Do not use recency stamps or dated update markers in docs. Git history is the recency signal.

## 2. Suite Taxonomy

The repository uses `documents/`, not `docs/`.

- `documents/architecture/`: system design, operating modes, storage split, and execution boundaries
- `documents/development/`: local setup, contributor workflows, and testing policy
- `documents/domain/`: DAG schema and execution-domain rules
- `documents/engineering/`: engineering standards such as Kubernetes-native development policy
- `documents/operations/`: runbooks and operability procedures
- `documents/reference/`: public-surface and API-style reference material
- `documents/tools/`: tool and sidecar integration notes

The navigational index for the suite is [README.md](README.md#studiomcp-documentation-index).
There is no ADR category in the governed suite. Historical decision trails belong in git history and code review, not in `documents/`.

## 3. Naming Rules

- Markdown documents in this repo use snake_case filenames.
- Do not mix snake_case and kebab-case in `documents/`.
- Exceptions allowed by repo policy:
  - `README.md`
  - `AGENTS.md`
  - `CLAUDE.md`
- Prefer descriptive names such as `dag_specification.md` over abbreviations.

## 4. Required Header Metadata

Every document in `documents/` must begin with:

```markdown
# File: documents/path/to/file.md
# Document Title

**Status**: [Authoritative source | Reference only | Deprecated]
**Supersedes**: N/A
**Referenced by**: related.md, other.md

> **Purpose**: 1-2 sentence role of the document.
> **📖 Authoritative Reference**: [Canonical Doc](path.md#anchor)
```

Rules:
- `📖 Authoritative Reference` is required for `Reference only` docs.
- `Referenced by` should be filled in when known.
- Authoritative docs should include a `## Cross-References` section near the end.

## 5. Cross-Referencing Rules

- Use relative links and deep anchors when possible.
- Prefer bidirectional links for tightly paired documents.
- When a doc depends on a canonical explanation, link to it instead of rephrasing it.
- After renames or moves, update links immediately.

## 6. Duplication Rules

Allowed:
- short navigational summaries
- index tables
- one-to-three sentence reminders with a canonical link

Not allowed:
- copying full standards into multiple places
- restating architecture policy without attribution
- duplicating Mermaid diagrams across multiple docs unless the diagram itself is the canonical artifact

## 7. Mermaid Rendering Rules

The Mermaid subset in this repo is compatibility-first for GitHub, VSCode, and Mermaid Live.

- Use `flowchart TB` by default.
- Use `flowchart LR` only for short left-to-right flows with three or fewer sequential steps or clearly parallel layouts.
- Use only solid arrows: `-->`.
- Arrow labels may be inline or represented as explicit label nodes, but a diagram must choose one style and stay consistent.
- Keep labels simple words. Avoid punctuation-heavy labels.
- Prefer Mermaid when it clarifies a state machine, DAG, effect boundary, or execution flow.

Forbidden in repo Mermaid diagrams:
- dotted arrows
- subgraphs
- thick arrows
- comments inside diagrams
- mixed arrow styles in one diagram
- right-to-left LR flows
- complex punctuation in labels

Validation checklist for each Mermaid diagram:
- renders in GitHub
- renders in VSCode
- renders in Mermaid Live

## 8. Documentation Maintenance Checklist

- [ ] Update the authoritative source first.
- [ ] Update dependent links and overlays.
- [ ] Retire replaced historical or duplicate docs instead of creating decision-record side files.
- [ ] Validate Mermaid diagrams after edits.
- [ ] Keep `../README.md` and this suite index aligned when the structure changes.
- [ ] Keep the suite index aligned when canonical documents are added, renamed, or retired.
- [ ] Keep `../STUDIOMCP_DEVELOPMENT_PLAN.md` aligned when documentation governance changes.

## Cross-References

- [Documentation Index](README.md#studiomcp-documentation-index)
- [Architecture Overview](architecture/overview.md#architecture-overview)
- [Testing Strategy](development/testing_strategy.md#testing-strategy)

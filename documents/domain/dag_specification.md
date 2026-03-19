# File: documents/domain/dag_specification.md
# DAG Specification

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../architecture/overview.md](../architecture/overview.md#canonical-follow-on-documents), [../architecture/inference_mode.md](../architecture/inference_mode.md#cross-references), [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#implementation-checklist)

> **Purpose**: Canonical description of the current YAML DAG format accepted by the `studioMCP` parser and validator.

## Root Fields

- `name`: human-readable DAG name
- `description`: optional DAG description
- `nodes`: ordered list of node specifications

## Node Fields

- `id`: unique node identifier
- `kind`: `pure`, `boundary`, or `summary`
- `tool`: required for `boundary`, forbidden for `pure` and `summary`
- `inputs`: upstream node ids
- `outputType`: output schema label
- `timeout.seconds`: positive integer timeout budget
- `memoization`: `memoize` or `no-memoize`

## Current Validation Rules

- DAG must have at least one node
- node ids must be unique
- input references must exist
- exactly one summary node must exist
- timeouts must be positive
- pure nodes cannot declare tools
- boundary nodes must declare tools
- graph must be acyclic

## Example

```yaml
name: transcode-basic
description: Simple ingest to FFmpeg transcode flow.
nodes:
  - id: ingest
    kind: pure
    inputs: []
    outputType: media/input
    timeout:
      seconds: 5
    memoization: memoize
  - id: transcode
    kind: boundary
    tool: ffmpeg
    inputs:
      - ingest
    outputType: media/mp4
    timeout:
      seconds: 120
    memoization: memoize
  - id: summary
    kind: summary
    inputs:
      - transcode
    outputType: summary/run
    timeout:
      seconds: 5
    memoization: no-memoize
```

## Cross-References

- [Architecture Overview](../architecture/overview.md#architecture-overview)
- [Testing Strategy](../development/testing_strategy.md#testing-strategy)

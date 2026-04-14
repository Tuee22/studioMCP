# File: documents/development/chaos_testing.md
# Chaos Testing

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [testing_strategy.md](testing_strategy.md#cross-references), [../../DEVELOPMENT_PLAN/phase-21-chaos-engineering.md](../../DEVELOPMENT_PLAN/phase-21-chaos-engineering.md#cross-references)

> **Purpose**: Define the recovery-budget contract and the current chaos-focused test harness used by `studioMCP`.

## Summary

`studioMCP` currently enforces a 60-second recovery budget through test-side recovery polling in
`src/StudioMCP/Test/Chaos.hs`. The current suite is intentionally deterministic: it exercises the
recovery timing helper and the CLI entrypoint without depending on live Kubernetes fault injection.

## Current Coverage

The `test/Integration/ChaosSpec.hs` suite covers:

- recovery before the timeout budget expires
- repeated polling over transient failures
- explicit failure once the budget is exceeded

The supported CLI entrypoint is:

```bash
docker compose run --rm studiomcp studiomcp test chaos
```

## Recovery Contract

- recovery waits poll at 100 ms intervals
- the helper returns a structured timeout failure when the configured budget is missed
- the current default test scenarios use short local budgets to keep the suite fast while still
  exercising the timeout logic that governs future live-chaos cases

## Cross-References

- [Testing Strategy](testing_strategy.md#testing-strategy)
- [CLI Reference](../reference/cli_reference.md#studiomcp-cli-reference)

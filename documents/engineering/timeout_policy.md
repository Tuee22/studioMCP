# File: documents/engineering/timeout_policy.md
# Timeout Enforcement Policy

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [k8s_storage.md](k8s_storage.md#cross-references), [../development/testing_strategy.md](../development/testing_strategy.md#cross-references), [../../DEVELOPMENT_PLAN.md](../../DEVELOPMENT_PLAN.md#current-repo-assessment-against-this-plan)

> **Purpose**: Canonical policy for how `studioMCP` enforces execution timeouts on boundary processes and projects timeout failures into the typed failure model.

## Summary

Every boundary process in `studioMCP` executes under a strict timeout budget. When a process exceeds its budget, the runtime must:

1. Terminate the process
2. Capture any available stdout and stderr
3. Project the timeout into a structured `FailureDetail` with `TimeoutFailure` category
4. Return the failure code `boundary-timeout`

Timeout enforcement is a first-class semantic outcome, not an infrastructure exception.

## Implementation Requirements

### Timeout Mechanism

The boundary runtime must use `System.Timeout.timeout` from the `base` library for reliable cross-platform timeout enforcement.

Polling-based timeout detection is explicitly forbidden because:

- it introduces race conditions between polling intervals and process completion
- it is sensitive to system load and scheduling behavior
- it cannot guarantee timeout precision

### Timeout Projection

When a timeout fires, the runtime must project the failure into a `FailureDetail` value:

- `failureCategory` must be `TimeoutFailure`
- `failureCode` must be `"boundary-timeout"`
- `failureMessage` must describe the timeout condition
- `failureRetryable` must be `True` (timeouts are transient by nature)
- `failureContext` must include:
  - `executable`: the process executable path
  - `arguments`: the process arguments
  - `timeoutSeconds`: the configured timeout budget
  - `stdoutSnippet`: any captured stdout before termination
  - `stderrSnippet`: any captured stderr before termination

### Output Capture Before Termination

The runtime must capture any stdout and stderr written by the process before the timeout fires. This is critical for debugging slow processes. The capture path must be non-blocking and must not delay the timeout termination.

### Process Termination

When the timeout fires:

1. Call `terminateProcess` on the process handle
2. Wait for process exit (the process may not exit immediately)
3. Collect any remaining buffered output
4. Return the structured timeout failure

Do not leave zombie processes. Always wait for the terminated process to fully exit before returning.

## Testing Requirements

The unit test suite must include a deterministic timeout test:

- Run a helper process that writes to stdout and stderr, then sleeps beyond the timeout budget
- Configure a timeout shorter than the sleep duration
- Assert that the result is a `Left` containing a `FailureDetail`
- Assert that `failureCode` is `"boundary-timeout"`
- Assert that `stdoutSnippet` and `stderrSnippet` in the context contain the expected output

This test belongs to the current validated execution-runtime foundation tracked in [../../DEVELOPMENT_PLAN.md](../../DEVELOPMENT_PLAN.md#current-repo-assessment-against-this-plan).

## Timeout Budget Source

The timeout budget for each boundary node comes from the DAG specification. The `timeout.seconds` field in a node definition sets the maximum execution time. See [../domain/dag_specification.md](../domain/dag_specification.md#dag-specification) for the schema.

## Cross-References

- [Testing Strategy](../development/testing_strategy.md#testing-strategy)
- [DAG Specification](../domain/dag_specification.md#dag-specification)
- [Kubernetes Storage Policy](k8s_storage.md#kubernetes-storage-policy)
- [studioMCP Development Plan](../../DEVELOPMENT_PLAN.md#studiomcp-development-plan)

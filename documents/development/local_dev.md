# File: documents/development/local_dev.md
# Local Development

**Status**: Authoritative source
**Supersedes**: legacy `documents/development/local-dev.md`
**Referenced by**: [../README.md](../README.md#canonical-documents), [testing_strategy.md](testing_strategy.md#cross-references), [../engineering/k8s_native_dev_policy.md](../engineering/k8s_native_dev_policy.md#cross-references)

> **Purpose**: Canonical local setup and workflow guide for contributors working on `studioMCP`.

## Tooling Baseline

- GHC 9.12.2
- cabal-install 3.16.0.0
- Docker for image builds
- Helm for deployment rendering
- kind for the local cluster
- Skaffold for the Kubernetes-native dev loop
- Docker Compose only for sidecar-backed integration testing

## Common Commands

- `cabal build all`
- `cabal test unit-tests`
- `STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests`
- `./scripts/kind_create_cluster.sh`
- `./scripts/helm_template.sh kind`
- `./scripts/k8s_dev.sh`
- `./scripts/integration-harness.sh reset`
- `cabal run studiomcp -- validate-dag examples/dags/transcode-basic.yaml`

## Working Rule

From Phase 1 onward, do not proceed to the next implementation phase until `cabal build all` succeeds and the phase-relevant tests pass.

For application runtime development, prefer the Kubernetes-native workflow. Use Compose only when exercising the dedicated sidecar integration harness.

## Cross-References

- [Testing Strategy](testing_strategy.md#testing-strategy)
- [Kubernetes-Native Development Policy](../engineering/k8s_native_dev_policy.md#kubernetes-native-development-policy)
- [Documentation Standards](../documentation_standards.md#studiomcp-documentation-standards)

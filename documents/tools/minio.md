# File: documents/tools/minio.md
# MinIO

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite), [../engineering/k8s_storage.md](../engineering/k8s_storage.md#cross-references)

> **Purpose**: Canonical integration note for MinIO as the immutable storage backend in `studioMCP`.

## Role

This document is the canonical MinIO integration note, but it does not redefine the higher-level storage architecture.

Canonical role definitions live in:

- [Pulsar vs MinIO](../architecture/pulsar_vs_minio.md#pulsar-vs-minio)
- [Artifact Storage Architecture](../architecture/artifact_storage_architecture.md#artifact-storage-architecture)

Within the current repo, MinIO is the S3-compatible object store used for:

- memoized node outputs
- summaries
- manifests
- local and shared-cluster artifact storage
- synced model storage for model-backed adapters
- deterministic test-fixture storage

## Deployment

MinIO must be deployed using the official `minio/minio` Helm chart in high availability mode.

Requirements:

- minimum 3 pods (distributed mode)
- official Helm chart from the MinIO repository
- deployed as a chart dependency in the `studioMCP` Helm release and reconciled by the CLI
- all PVCs must request `studiomcp-manual`, backed by `kubernetes.io/no-provisioner`
- CLI creates rehydratable PVs before chart deployment

Deployment command pattern:

```bash
docker compose run --rm studiomcp studiomcp cluster storage reconcile
docker compose run --rm studiomcp studiomcp cluster ensure
```

The supported path does not use a standalone `helm install` for MinIO. The CLI reconciles the
MinIO chart dependency through the repo-owned Helm release during `cluster ensure` and
`cluster deploy sidecars`.

HA deployment is required in all environments including local kind development. See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#ha-deployment-mode) for the full policy.

## Current Maturity

The repo now includes a real Haskell MinIO adapter that uses the native CLI workflow to round-trip memo objects, manifests, and summaries through the deployed MinIO cluster. `studiomcp validate minio` exercises that live path and asserts the missing-object failure contract. The deployment now uses the official MinIO Helm chart in HA mode. Current implementation status is tracked in [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/00-overview.md#current-repo-assessment-against-this-plan).

## Storage Policy

MinIO is stateful infrastructure. In local kind development, persistent MinIO volumes must follow:

- the `studiomcp-manual` / `kubernetes.io/no-provisioner` storage-class rule
- the rehydratable PV system
- CLI-owned PV lifecycle

See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#kubernetes-storage-policy) for the full storage policy.

## Buckets

The following buckets are created during initialization:

- `studiomcp-memo` - memoized node outputs
- `studiomcp-artifacts` - durable media artifacts
- `studiomcp-summaries` - run summaries and manifests
- `studiomcp-models` - synced model weights and SoundFonts for runtime adapters
- `studiomcp-test-fixtures` - test fixture storage

## Cross-References

- [Pulsar vs MinIO](../architecture/pulsar_vs_minio.md#pulsar-vs-minio)
- [Artifact Storage Architecture](../architecture/artifact_storage_architecture.md#artifact-storage-architecture)
- [Model Storage](../engineering/model_storage.md#model-storage)
- [Testing Strategy](../development/testing_strategy.md#testing-strategy)
- [Kubernetes Storage Policy](../engineering/k8s_storage.md#kubernetes-storage-policy)
- [Local Debugging Runbook](../operations/runbook_local_debugging.md#local-debugging-runbook)

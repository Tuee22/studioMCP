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

## Deployment

MinIO must be deployed using the official `minio/minio` Helm chart in high availability mode.

Requirements:

- minimum 3 pods (distributed mode)
- official Helm chart from the MinIO repository
- CLI deploys via `helm install minio minio/minio`
- null storage class for all PVCs
- CLI creates rehydratable PVs before chart deployment

Deployment command pattern:

```bash
helm repo add minio https://charts.min.io/
studiomcp cluster storage reconcile  # creates PVs
helm install minio minio/minio \
  --set replicas=3 \
  --set persistence.storageClass="" \
  --set persistence.size=20Gi \
  --set rootUser=minioadmin \
  --set rootPassword=minioadmin123
```

HA deployment is the preferred mode where possible. See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#ha-deployment-mode) for the full policy.

## Current Maturity

The repo now includes a real Haskell MinIO adapter that uses the native CLI workflow to round-trip memo objects, manifests, and summaries through the deployed MinIO cluster. `studiomcp validate minio` exercises that live path and asserts the missing-object failure contract. The deployment now uses the official MinIO Helm chart in HA mode. Current implementation status is tracked in [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#current-repo-assessment-against-this-plan).

## Storage Policy

MinIO is stateful infrastructure. In local kind development, persistent MinIO volumes must follow:

- the null storage class rule
- the rehydratable PV system
- CLI-owned PV lifecycle

See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#kubernetes-storage-policy) for the full storage policy.

## Buckets

The following buckets are created during initialization:

- `studiomcp-memo` - memoized node outputs
- `studiomcp-artifacts` - durable media artifacts
- `studiomcp-summaries` - run summaries and manifests
- `studiomcp-test-fixtures` - test fixture storage

## Cross-References

- [Pulsar vs MinIO](../architecture/pulsar_vs_minio.md#pulsar-vs-minio)
- [Artifact Storage Architecture](../architecture/artifact_storage_architecture.md#artifact-storage-architecture)
- [Testing Strategy](../development/testing_strategy.md#testing-strategy)
- [Kubernetes Storage Policy](../engineering/k8s_storage.md#kubernetes-storage-policy)
- [Local Debugging Runbook](../operations/runbook_local_debugging.md#local-debugging-runbook)

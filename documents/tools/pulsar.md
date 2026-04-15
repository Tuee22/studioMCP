# File: documents/tools/pulsar.md
# Pulsar

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite), [../engineering/k8s_storage.md](../engineering/k8s_storage.md#cross-references)

> **Purpose**: Canonical integration note for Pulsar as the in-flight execution-state backend in `studioMCP`.

## Role

This document is the canonical Pulsar integration note, but it does not redefine the higher-level messaging and storage split.

Canonical role definitions live in:

- [Pulsar vs MinIO](../architecture/pulsar_vs_minio.md#pulsar-vs-minio)

Within the current repo, Pulsar carries:

- run submission events
- node lifecycle transitions
- summary emission notifications

## Deployment

Pulsar must be deployed using the official `apache/pulsar` Helm chart in high availability mode.

Requirements:

- minimum 3 pods for each stateful component (ZooKeeper, BookKeeper, Broker)
- official Helm chart from the Apache Pulsar repository
- deployed as a chart dependency in the `studioMCP` Helm release and reconciled by the CLI
- all PVCs must request `studiomcp-manual`, backed by `kubernetes.io/no-provisioner`
- CLI creates rehydratable PVs before chart deployment

Deployment command pattern:

```bash
docker compose run --rm studiomcp studiomcp cluster storage reconcile
docker compose run --rm studiomcp studiomcp cluster ensure
```

The supported path does not use a standalone `helm install` for Pulsar. The CLI reconciles the
Pulsar chart dependency through the repo-owned Helm release during `cluster ensure` and
`cluster deploy sidecars`.

HA deployment is required in all environments including local kind development. See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#ha-deployment-mode) for the full policy.

## Current Maturity

The repo currently includes Pulsar in the deployment topology, pure execution-event contracts, stable topic naming, a tested execution-state transition model, and a real Haskell wrapper that validates publish, consume, ordering, invalid-namespace failure behavior, and end-to-end run lifecycle behavior against the deployed cluster. The deployment now uses the official Apache Pulsar Helm chart in HA mode. Broader messaging features beyond the current runtime remain future expansion work. Current implementation status is tracked in [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/00-overview.md#current-repo-assessment-against-this-plan).

## Storage Policy

Pulsar is stateful infrastructure. Any local persistent Pulsar volume must follow:

- the `studiomcp-manual` / `kubernetes.io/no-provisioner` storage-class rule
- the rehydratable PV system
- CLI-owned PV lifecycle

See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#kubernetes-storage-policy) for the full storage policy.

## Cross-References

- [Pulsar vs MinIO](../architecture/pulsar_vs_minio.md#pulsar-vs-minio)
- [Testing Strategy](../development/testing_strategy.md#testing-strategy)
- [Kubernetes Storage Policy](../engineering/k8s_storage.md#kubernetes-storage-policy)
- [Local Debugging Runbook](../operations/runbook_local_debugging.md#local-debugging-runbook)

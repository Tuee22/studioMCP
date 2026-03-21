# File: documents/tools/pulsar.md
# Pulsar

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite), [../engineering/k8s_storage.md](../engineering/k8s_storage.md#cross-references)

> **Purpose**: Canonical integration note for Pulsar as the in-flight execution-state backend in `studioMCP`.

## Role

Pulsar carries:

- run submission events
- node lifecycle transitions
- summary emission notifications

## Deployment

Pulsar must be deployed using the official `apache/pulsar` Helm chart in high availability mode.

Requirements:

- minimum 3 pods for each stateful component (ZooKeeper, BookKeeper, Broker)
- official Helm chart from the Apache Pulsar repository
- CLI deploys via `helm install pulsar apache/pulsar`
- null storage class for all PVCs
- CLI creates rehydratable PVs before chart deployment

Deployment command pattern:

```bash
helm repo add apache https://pulsar.apache.org/charts
studiomcp cluster storage reconcile  # creates PVs
helm install pulsar apache/pulsar \
  --set zookeeper.replicaCount=3 \
  --set bookkeeper.replicaCount=3 \
  --set broker.replicaCount=3 \
  --set persistence.storageClass=""
```

HA deployment is the preferred mode where possible. See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#ha-deployment-mode) for the full policy.

## Current Maturity

The repo currently includes Pulsar in the deployment topology, pure execution-event contracts, stable topic naming, a tested execution-state transition model, and a real Haskell wrapper that validates publish, consume, ordering, invalid-namespace failure behavior, and end-to-end run lifecycle behavior against the deployed cluster. The deployment now uses the official Apache Pulsar Helm chart in HA mode. Broader messaging features beyond the current runtime remain future expansion work. Delivery status is tracked in [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#phase-6-real-pulsar-adapter-and-lifecycle-integration).

## Storage Policy

Pulsar is stateful infrastructure. Any local persistent Pulsar volume must follow:

- the null storage class rule
- the rehydratable PV system
- CLI-owned PV lifecycle

See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#kubernetes-storage-policy) for the full storage policy.

## Cross-References

- [Pulsar vs MinIO](../architecture/pulsar_vs_minio.md#pulsar-vs-minio)
- [Testing Strategy](../development/testing_strategy.md#testing-strategy)
- [Kubernetes Storage Policy](../engineering/k8s_storage.md#kubernetes-storage-policy)
- [Local Debugging Runbook](../operations/runbook_local_debugging.md#local-debugging-runbook)

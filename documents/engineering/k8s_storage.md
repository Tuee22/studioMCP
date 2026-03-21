# File: documents/engineering/k8s_storage.md
# Kubernetes Storage Policy

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [docker_policy.md](docker_policy.md#cross-references), [k8s_native_dev_policy.md](k8s_native_dev_policy.md#cross-references), [timeout_policy.md](timeout_policy.md#cross-references), [../development/local_dev.md](../development/local_dev.md#cross-references), [../tools/minio.md](../tools/minio.md#cross-references), [../tools/pulsar.md](../tools/pulsar.md#cross-references), [../../README.md](../../README.md#kubernetes-native-development)

> **Purpose**: Canonical storage policy for local kind development, including the null storage class rule, rehydratable PV system, official Helm chart integration, and HA deployment preference.

## Summary

Local Kubernetes storage in `studioMCP` is explicit and CLI-managed with a focus on data durability and high availability.

- only the null storage class may be used
- persistent volumes are created explicitly by the Haskell CLI
- the CLI creates PVs; Helm charts create PVCs
- the backing data lives under host `./.data/` and survives cluster destruction
- MinIO and Pulsar are deployed via their official Helm charts in HA mode

This policy exists to prevent accidental deletion of host data, ensure storage behavior is obvious, and provide production-like HA deployment patterns.

## HA Deployment Mode

High availability deployment is the preferred mode for MinIO and Pulsar where possible.

Requirements:

- MinIO: minimum 3 pods (distributed mode)
- Pulsar: minimum 3 pods for each stateful component (ZooKeeper, BookKeeper, Broker)
- Official Helm charts: `minio/minio` and `apache/pulsar`
- CLI deploys charts separately via `helm install` commands

This ensures local development mirrors production deployment patterns and exercises HA failover semantics.

## Official Helm Chart Integration

MinIO and Pulsar must be deployed using their official Helm charts, not custom templates.

The CLI is responsible for:

1. Adding the official Helm repositories (`helm repo add`)
2. Creating rehydratable PVs before chart deployment
3. Deploying charts with appropriate values (null storage class, HA replicas)
4. Managing chart lifecycle (install, upgrade, uninstall)

The Helm charts are responsible for:

- Creating their own PVCs
- Managing StatefulSet naming and pod scheduling
- Defining service endpoints and configuration

Our chart templates must not duplicate PVC definitions. The CLI creates PVs that match the PVC names the official charts will create.

## Null Storage Class Only

All local PVCs and PVs managed by the repo must use the null storage class:

- PVCs created by Helm charts must specify `storageClassName: ""`
- PVs created by the CLI must set `storageClassName: ""`
- Pass `--set persistence.storageClass=""` or equivalent to official charts

No dynamic provisioner is part of the local development story.

## CLI-Owned PV Lifecycle

The Haskell CLI owns the full lifecycle of manual PVs needed by the local cluster.

That means:

- create the PV definitions explicitly before deploying Helm charts
- choose the backing path under `/.data/` inside the outer container
- ensure the host bind mount exists before cluster creation
- set `claimRef` to match the expected PVC names from official charts
- set `persistentVolumeReclaimPolicy: Retain` for data durability
- reconcile, repair, or delete those PVs only through the CLI

Helm charts create PVCs, but the CLI owns the matching PVs and the deployment sequencing around them.

## Rehydratable PV System

The rehydratable mounting system ensures that persistent data survives destruction of the kind cluster and rebinds exactly as it was on rehydration.

### Data Survival Semantics

- Host `./.data/` contains all persistent storage
- Deleting the kind cluster does not delete `./.data/`
- Recreating the kind cluster and rerunning `cluster storage reconcile` rebinds the same data
- PVs are created with stable names that match the expected PVC names
- `claimRef` in each PV specifies the exact PVC it should bind to

### Rehydration Flow

1. User runs `studiomcp cluster up` to create a fresh kind cluster
2. User runs `studiomcp cluster storage reconcile` to create PVs
3. PVs are created with hostPath pointing to existing `./.data/` subdirectories
4. User runs `studiomcp cluster deploy sidecars` to deploy MinIO and Pulsar
5. Helm charts create PVCs that immediately bind to the pre-created PVs
6. StatefulSets mount the PVCs and find their previous data intact

This is intentional and required for:

- preserving test data across cluster rebuilds
- debugging storage issues without data loss
- matching production deployment patterns

## Bind-Mount Doctrine

Local persistent data must always flow through a two-step bind:

1. host `./.data/` into the outer development container
2. outer development container `/.data/` into the kind node container

This is intentional.

- `docker compose down` must never delete host `./.data/`
- kind node recreation must not imply host data deletion
- the CLI is responsible for ensuring the second bind into the kind node exists before workloads are deployed

## Helm Storage Rule

When the CLI deploys official Helm charts that rely on persistence:

- the null storage class must always be supplied
- the CLI must know the PVC names the chart will create
- the CLI must create or reconcile the matching PVs before deployment
- PVs must have `persistentVolumeReclaimPolicy: Retain`
- PVs must have `claimRef` set to the expected PVC namespace and name

The CLI therefore owns the lifecycle of the Helm release and the manual PV set as one logical operation.

## PV Naming Convention

PVs created by the CLI must follow this naming pattern:

- MinIO: `studiomcp-minio-{0,1,2,...}` matching PVC names from the official chart
- Pulsar ZooKeeper: `studiomcp-pulsar-zookeeper-{0,1,2}`
- Pulsar BookKeeper: `studiomcp-pulsar-bookkeeper-{0,1,2}`
- Pulsar Broker: `studiomcp-pulsar-broker-{0,1,2}` (if stateful)

The exact PVC names depend on the official chart release name and StatefulSet naming convention. The CLI must derive these names correctly.

## Implementation Constraint

The CLI is not a second storage system. It is a typed Haskell wrapper over existing cluster tools.

- use Haskell for orchestration, configuration, and invariants
- call `kind`, `kubectl`, and `helm` from Haskell where needed
- let Helm remain the chart renderer and release mechanism
- do not hide storage behavior behind shell wrappers

## Cross-References

- [Docker Policy](docker_policy.md#docker-policy)
- [Kubernetes-Native Development Policy](k8s_native_dev_policy.md#kubernetes-native-development-policy)
- [Timeout Policy](timeout_policy.md#timeout-enforcement-policy)
- [MinIO](../tools/minio.md#minio)
- [Pulsar](../tools/pulsar.md#pulsar)

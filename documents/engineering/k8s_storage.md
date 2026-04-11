# File: documents/engineering/k8s_storage.md
# Kubernetes Storage Policy

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [docker_policy.md](docker_policy.md#cross-references), [k8s_native_dev_policy.md](k8s_native_dev_policy.md#cross-references), [timeout_policy.md](timeout_policy.md#cross-references), [../development/local_dev.md](../development/local_dev.md#cross-references), [../tools/minio.md](../tools/minio.md#cross-references), [../tools/pulsar.md](../tools/pulsar.md#cross-references), [../../README.md](../../README.md#kubernetes-native-development)

> **Purpose**: Canonical storage policy for local kind development, including the explicit manual storage class, rehydratable PV system, official Helm chart integration, and HA deployment preference.

## Summary

Local Kubernetes storage in `studioMCP` is explicit and CLI-managed with a focus on data durability and high availability.

- only the `studiomcp-manual` StorageClass may be used (no dynamic provisioning)
- persistent volumes are created explicitly by the Haskell CLI
- the CLI creates PVs; Helm charts create PVCs
- the backing data lives under host `./.data/` (project directory) and survives cluster destruction
- all stateful services (MinIO, Pulsar, PostgreSQL-HA, Redis) are deployed via HA Helm charts

This policy exists to prevent accidental deletion of host data, ensure storage behavior is obvious, and provide production-like HA deployment patterns.

## Explicit Storage Class Policy

The `studiomcp-manual` StorageClass enforces explicit-only PV binding:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: studiomcp-manual
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
```

Key properties:

| Property | Value | Effect |
|----------|-------|--------|
| `provisioner` | `kubernetes.io/no-provisioner` | Dynamic provisioning disabled |
| `volumeBindingMode` | `WaitForFirstConsumer` | PVCs stay Pending until pod schedules |
| `reclaimPolicy` | `Retain` | Data survives PV deletion |

The CLI deletes any default StorageClass (e.g., `standard` from kind) and creates `studiomcp-manual` during storage reconciliation. This ensures:

- Empty string `storageClassName: ""` will fail (no default class exists)
- PVCs must explicitly request `studiomcp-manual`
- PVs must be pre-created by the CLI before PVCs can bind
- Silent successes from dynamic provisioning are impossible

## HA Deployment Mode

High availability deployment is required for all stateful third-party services in all environments, including local kind development.

Required HA configurations:

| Service    | Chart                      | HA Requirement        | Rationale                    |
|------------|----------------------------|-----------------------|------------------------------|
| MinIO      | minio/minio (official)     | 3+ replicas           | Native distributed mode      |
| Pulsar     | apache/pulsar (official)   | 3+ per component      | Native HA support            |
| PostgreSQL | bitnami/postgresql-ha      | 3 replicas            | Official chart lacks HA      |
| Redis      | bitnami/redis              | Sentinel mode         | Official chart lacks Sentinel|
| Keycloak   | bitnami/keycloak           | 2+ replicas           | Better HA than official      |

Chart selection priority:

1. Official chart with native HA support (minio/minio, apache/pulsar)
2. Bitnami HA chart when official lacks HA (postgresql-ha, redis, keycloak)
3. Never: custom templates for standard infrastructure

Full HA is required in all environments:

- Local kind development uses the same HA replica counts as production
- No reduced replicas for resource constraints
- This ensures local development mirrors production deployment patterns and exercises HA failover semantics

CLI deploys charts via Helm dependencies in the studioMCP chart, not via separate `helm install` commands.

## Official Helm Chart Integration

All third-party stateful services must be deployed using official or Bitnami HA Helm charts as dependencies, not custom templates.

The studioMCP Helm chart is responsible for:

1. Declaring chart dependencies in `Chart.yaml`
2. Configuring subchart values for HA and null storage class
3. Running `helm dependency build` before deployment so `Chart.lock` and `chart/charts/` are reconciled from `Chart.yaml`

The CLI is responsible for:

1. Creating rehydratable PVs before chart deployment
2. Running Helm install/upgrade with appropriate values files
3. Managing the overall deployment lifecycle

The Helm subcharts are responsible for:

- Creating their own PVCs (with null storage class)
- Managing StatefulSet naming and pod scheduling
- Defining service endpoints and configuration

Our chart templates must not duplicate PVC definitions for third-party services. The CLI creates PVs that match the PVC names the subcharts will create. Custom templates are only allowed for studioMCP-specific workloads (mcp-server, worker, bff).

## Storage Class Usage

All local PVCs and PVs managed by the repo must use the `studiomcp-manual` StorageClass:

- PVCs created by Helm charts must specify `storageClassName: "studiomcp-manual"`
- PVs created by the CLI must set `storageClassName: "studiomcp-manual"`
- Helm values files must configure subchart persistence with `storageClass: "studiomcp-manual"`

Empty string `storageClassName: ""` is explicitly prohibited and will fail because:

1. The CLI deletes the `standard` default StorageClass
2. No default StorageClass exists after CLI initialization
3. PVCs with empty storageClassName get no class and cannot bind

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

- Host `./.data/` (project directory) contains all persistent storage
- Deleting the kind cluster does not delete `./.data/`
- Recreating the kind cluster and rerunning `cluster storage reconcile` rebinds the same data
- PVs are created with stable names that match the expected PVC names
- `claimRef` in each PV specifies the exact PVC it should bind to

### Rehydration Flow

1. User runs `studiomcp cluster up` to create a fresh kind cluster
2. User runs `studiomcp cluster storage reconcile` to create PVs and enforce storage policy
3. StorageClass `studiomcp-manual` is created; default `standard` is deleted
4. PVs are created with hostPath pointing to existing `./.data/` subdirectories
5. User runs `studiomcp cluster deploy sidecars` to deploy all stateful services
6. Helm charts create PVCs that immediately bind to the pre-created PVs
7. StatefulSets mount the PVCs and find their previous data intact

This is intentional and required for:

- preserving test data across cluster rebuilds
- debugging storage issues without data loss
- matching production deployment patterns

## Bind-Mount Doctrine

Local persistent data must always flow through a two-step bind:

1. host `./.data/` (project directory) into the outer development container as `/.data/`
2. outer development container `/.data/` into the kind node container as `/.data/`

This is intentional.

- `docker compose down` must never delete host `./.data/`
- kind node recreation must not imply host data deletion
- the CLI is responsible for ensuring the second bind into the kind node exists before workloads are deployed
- using `./.data/` (project directory) ensures data is explicitly scoped to the project and visible in the working tree

## Helm Storage Rule

When the CLI deploys official Helm charts that rely on persistence:

- the `studiomcp-manual` storage class must always be supplied
- the CLI must know the PVC names the chart will create
- the CLI must create or reconcile the matching PVs before deployment
- PVs must have `storageClassName: studiomcp-manual`
- PVs must have `persistentVolumeReclaimPolicy: Retain`
- PVs must have `claimRef` set to the expected PVC namespace and name

The CLI therefore owns the lifecycle of the Helm release and the manual PV set as one logical operation.

## PV Naming Convention

PVs created by the CLI must follow this naming pattern:

| Service | PV Name | PVC Name | Host Path |
|---------|---------|----------|-----------|
| MinIO | `studiomcp-minio-pv-{0,1,2,3}` | `export-studiomcp-minio-{0,1,2,3}` | `./.data/minio/minio-{0,1,2,3}/` |
| Pulsar ZK | `studiomcp-pulsar-zookeeper-pv-{0,1,2}` | `studiomcp-pulsar-zookeeper-data-studiomcp-pulsar-zookeeper-{0,1,2}` | `./.data/pulsar/zookeeper-{0,1,2}/` |
| Pulsar Journal | `studiomcp-pulsar-bookie-journal-pv-{0,1,2}` | `studiomcp-pulsar-bookie-journal-studiomcp-pulsar-bookie-{0,1,2}` | `./.data/pulsar/bookie-journal-{0,1,2}/` |
| Pulsar Ledgers | `studiomcp-pulsar-bookie-ledgers-pv-{0,1,2}` | `studiomcp-pulsar-bookie-ledgers-studiomcp-pulsar-bookie-{0,1,2}` | `./.data/pulsar/bookie-ledgers-{0,1,2}/` |
| PostgreSQL-HA | `studiomcp-postgresql-ha-pv-{0,1,2}` | `data-studiomcp-postgresql-ha-postgresql-{0,1,2}` | `./.data/postgresql-ha/postgresql-{0,1,2}/` |
| Redis | `studiomcp-redis-node-pv-{0,1,2,3}` | `redis-data-studiomcp-redis-node-{0,1,2,3}` | `./.data/redis/node-{0,1,2,3}/` |

The exact PVC names depend on the official chart release name and StatefulSet naming convention. The CLI must derive these names correctly from the Helm values.

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
- [PostgreSQL](../tools/postgres.md#postgresql)
- [Redis](../tools/redis.md#redis)
- [Keycloak](../tools/keycloak.md#keycloak)

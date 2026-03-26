# File: documents/tools/redis.md
# Redis

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite), [../engineering/k8s_storage.md](../engineering/k8s_storage.md#cross-references)

> **Purpose**: Canonical integration note for Redis as the session store backend in `studioMCP`.

## Role

This document is the canonical Redis integration note, but it does not redefine the higher-level session architecture.

Canonical role definitions live in:

- [Session Scaling](../engineering/session_scaling.md#session-scaling)

Within the current repo, Redis is the session store used for:

- MCP session persistence for non-sticky horizontal scaling
- subscription and stream cursor storage
- session locking for concurrent access
- resumable session metadata

## Deployment

Redis must be deployed using the Bitnami `bitnami/redis` Helm chart in Sentinel mode for high availability.

Requirements:

- Sentinel mode enabled for HA
- Bitnami Helm chart from the Bitnami repository
- Deployed as a subchart dependency in the studioMCP chart
- Null storage class for all PVCs
- CLI creates rehydratable PVs before chart deployment

Deployment via Chart.yaml dependency:

```yaml
dependencies:
  - name: redis
    repository: https://charts.bitnami.com/bitnami
    version: "~18"
    condition: redis.enabled
```

Values configuration pattern:

```yaml
redis:
  enabled: true
  architecture: replication
  sentinel:
    enabled: true
  master:
    persistence:
      storageClass: ""
  replica:
    replicaCount: 3
    persistence:
      storageClass: ""
```

HA deployment is required in all environments including local kind development. See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#ha-deployment-mode) for the full policy.

## Current Maturity

The repo includes Redis in the deployment topology for session storage. Current implementation status is tracked in [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#current-repo-assessment-against-this-plan).

## Storage Policy

Redis is stateful infrastructure. Any local persistent Redis volume must follow:

- the null storage class rule
- the rehydratable PV system
- CLI-owned PV lifecycle

See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#kubernetes-storage-policy) for the full storage policy.

## Cross-References

- [Session Scaling](../engineering/session_scaling.md#session-scaling)
- [Kubernetes Storage Policy](../engineering/k8s_storage.md#kubernetes-storage-policy)
- [Local Debugging Runbook](../operations/runbook_local_debugging.md#local-debugging-runbook)

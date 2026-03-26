# File: documents/tools/postgres.md
# PostgreSQL

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite), [../engineering/k8s_storage.md](../engineering/k8s_storage.md#cross-references)

> **Purpose**: Canonical integration note for PostgreSQL as the Keycloak database backend in `studioMCP`.

## Role

This document is the canonical PostgreSQL integration note.

Within the current repo, PostgreSQL is used for:

- Keycloak identity provider database
- realm, client, and user storage
- session and token persistence

PostgreSQL is deployed as a dedicated instance for Keycloak. It is not used for application data storage.

## Deployment

PostgreSQL must be deployed using the Bitnami `bitnami/postgresql-ha` Helm chart for high availability.

Requirements:

- 3 replicas for HA (primary + 2 standby)
- Bitnami Helm chart from the Bitnami repository
- Deployed as a subchart dependency in the studioMCP chart
- Null storage class for all PVCs
- CLI creates rehydratable PVs before chart deployment

Deployment via Chart.yaml dependency:

```yaml
dependencies:
  - name: postgresql-ha
    repository: https://charts.bitnami.com/bitnami
    version: "~12"
    condition: postgresql.enabled
```

Values configuration pattern:

```yaml
postgresql-ha:
  enabled: true
  postgresql:
    replicaCount: 3
  persistence:
    storageClass: ""
  pgpool:
    replicaCount: 2
```

HA deployment is required in all environments including local kind development. See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#ha-deployment-mode) for the full policy.

## Current Maturity

The repo includes PostgreSQL in the deployment topology for Keycloak. Current implementation status is tracked in [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#current-repo-assessment-against-this-plan).

## Storage Policy

PostgreSQL is stateful infrastructure. Any local persistent PostgreSQL volume must follow:

- the null storage class rule
- the rehydratable PV system
- CLI-owned PV lifecycle

See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#kubernetes-storage-policy) for the full storage policy.

## Cross-References

- [Keycloak](keycloak.md#keycloak)
- [Multi-Tenant Auth Architecture](../architecture/multi_tenant_saas_mcp_auth_architecture.md#multi-tenant-saas-mcp-auth-architecture)
- [Kubernetes Storage Policy](../engineering/k8s_storage.md#kubernetes-storage-policy)
- [Keycloak Realm Bootstrap Runbook](../operations/keycloak_realm_bootstrap_runbook.md#keycloak-realm-bootstrap-runbook)

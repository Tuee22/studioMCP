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
- application-database technology where repo/runtime services require durable relational state, as
  tracked by the authoritative system inventory in
  [../../DEVELOPMENT_PLAN/system-components.md](../../DEVELOPMENT_PLAN/system-components.md#runtime-and-application-components)

On the supported Helm-managed sidecar path documented here, PostgreSQL-HA is deployed specifically
for Keycloak. If additional repo/runtime PostgreSQL-backed application state becomes part of the
governed deployment contract, this document must be updated to match the authoritative development
plan inventory rather than contradict it.

## Deployment

PostgreSQL must be deployed using the Bitnami `bitnami/postgresql-ha` Helm chart for high availability.

Requirements:

- 3 replicas for HA (primary + 2 standby)
- Bitnami Helm chart from the Bitnami repository
- Deployed as a subchart dependency in the studioMCP chart
- all PVCs must request `studiomcp-manual`, backed by `kubernetes.io/no-provisioner`
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
    storageClass: "studiomcp-manual"
  pgpool:
    replicaCount: 2
```

HA deployment is required in all environments including local kind development. See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#ha-deployment-mode) for the full policy.

## Current Maturity

The repo includes PostgreSQL in the deployment topology for Keycloak. Current implementation status is tracked in [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/00-overview.md#current-repo-assessment-against-this-plan).

## Storage Policy

PostgreSQL is stateful infrastructure. Any local persistent PostgreSQL volume must follow:

- the `studiomcp-manual` / `kubernetes.io/no-provisioner` storage-class rule
- the rehydratable PV system
- CLI-owned PV lifecycle

See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#kubernetes-storage-policy) for the full storage policy.

## Cross-References

- [Keycloak](keycloak.md#keycloak)
- [Multi-Tenant Auth Architecture](../architecture/multi_tenant_saas_mcp_auth_architecture.md#multi-tenant-saas-mcp-auth-architecture)
- [Kubernetes Storage Policy](../engineering/k8s_storage.md#kubernetes-storage-policy)
- [Keycloak Realm Bootstrap Runbook](../operations/keycloak_realm_bootstrap_runbook.md#keycloak-realm-bootstrap-runbook)

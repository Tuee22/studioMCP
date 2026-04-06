# File: documents/tools/keycloak.md
# Keycloak

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../README.md](../README.md#documentation-suite), [../engineering/k8s_storage.md](../engineering/k8s_storage.md#cross-references)

> **Purpose**: Canonical integration note for Keycloak as the identity provider in `studioMCP`.

## Role

This document is the canonical Keycloak integration note, but it does not redefine the higher-level authentication architecture.

Canonical role definitions live in:

- [Multi-Tenant Auth Architecture](../architecture/multi_tenant_saas_mcp_auth_architecture.md#multi-tenant-saas-mcp-auth-architecture)

Within the current repo, Keycloak is the identity provider used for:

- OAuth 2.0 and OIDC authentication
- tenant and subject identity management
- JWT token issuance and validation
- realm, client, and scope configuration
- service account management

## Deployment

Keycloak must be deployed using the Bitnami `bitnami/keycloak` Helm chart for high availability.

Requirements:

- 2+ replicas for HA
- Bitnami Helm chart from the Bitnami repository
- Deployed as a subchart dependency in the studioMCP chart
- PostgreSQL-HA as the database backend
- CLI creates rehydratable PVs before chart deployment

Deployment via Chart.yaml dependency:

```yaml
dependencies:
  - name: keycloak
    repository: https://charts.bitnami.com/bitnami
    version: "~17"
    condition: keycloak.enabled
```

Values configuration pattern:

```yaml
keycloak:
  enabled: true
  replicaCount: 2
  auth:
    adminUser: admin
  postgresql:
    enabled: false  # Use external postgresql-ha
  externalDatabase:
    host: studiomcp-postgresql-ha-pgpool
    port: 5432
    database: keycloak
```

HA deployment is required in all environments including local kind development. See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#ha-deployment-mode) for the full policy.

## Realm Configuration

The studioMCP realm must be configured with:

- `studiomcp` realm
- `studiomcp-app` client for browser applications
- `studiomcp-mcp` client for MCP server
- appropriate scopes for tool, resource, and prompt access
- tenant claim mapping

See [../operations/keycloak_realm_bootstrap_runbook.md](../operations/keycloak_realm_bootstrap_runbook.md#keycloak-realm-bootstrap-runbook) for the full bootstrap procedure.

## Current Maturity

The repo includes Keycloak in the deployment topology for authentication. Current implementation status is tracked in [../../DEVELOPMENT_PLAN.md](../../DEVELOPMENT_PLAN.md#current-repo-assessment-against-this-plan).

## Storage Policy

Keycloak relies on PostgreSQL for persistence. The PostgreSQL instance must follow:

- the null storage class rule
- the rehydratable PV system
- CLI-owned PV lifecycle

See [../engineering/k8s_storage.md](../engineering/k8s_storage.md#kubernetes-storage-policy) for the full storage policy.

## Cross-References

- [PostgreSQL](postgres.md#postgresql)
- [Multi-Tenant Auth Architecture](../architecture/multi_tenant_saas_mcp_auth_architecture.md#multi-tenant-saas-mcp-auth-architecture)
- [Security Model](../engineering/security_model.md#security-model)
- [Kubernetes Storage Policy](../engineering/k8s_storage.md#kubernetes-storage-policy)
- [Keycloak Realm Bootstrap Runbook](../operations/keycloak_realm_bootstrap_runbook.md#keycloak-realm-bootstrap-runbook)

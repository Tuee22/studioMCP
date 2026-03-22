# File: documents/operations/keycloak_realm_bootstrap_runbook.md
# Keycloak Realm Bootstrap Runbook

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../architecture/multi_tenant_saas_mcp_auth_architecture.md](../architecture/multi_tenant_saas_mcp_auth_architecture.md#realm-seeding-rule), [../engineering/security_model.md](../engineering/security_model.md#cross-references), [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#documentation-governance)

> **Purpose**: Canonical operational runbook for bootstrapping and validating Keycloak realms, clients, scopes, and tenant mappings for `studioMCP`.

## Summary

Auth in `studioMCP` is not credible unless Keycloak can be bootstrapped reproducibly in local, test, and cluster environments.

This runbook defines the required bootstrap artifacts and the preferred cluster deployment shape.

## Deployment Baseline

Keycloak deployment baseline:

- Keycloak in Kubernetes
- dedicated PostgreSQL database for Keycloak only
- ingress with TLS
- automated realm bootstrap

Helm-first packaging baseline:

- `codecentric/keycloakx` for Keycloak
- dedicated PostgreSQL chart or managed PostgreSQL for Keycloak persistence

## Required Bootstrap Artifacts

- realm definition
- browser client
- BFF client
- MCP resource-server client
- service-account clients
- roles
- scopes
- test users
- tenant membership fixtures

## Bootstrap Rules

- bootstrap artifacts are versioned with the repo
- environment-specific secrets are injected, not checked in
- realm bootstrap is deterministic
- dev and test use the real auth flows, not fake auth shortcuts

## Validation Expectations

- realm exists
- clients exist
- required scopes and roles exist
- test users can authenticate
- wrong-audience tokens are rejected by MCP
- seeded tenant mappings support integration tests

## Cross-References

- [Multi-Tenant SaaS MCP Auth Architecture](../architecture/multi_tenant_saas_mcp_auth_architecture.md#multi-tenant-saas-mcp-auth-architecture)
- [Security Model](../engineering/security_model.md#security-model)
- [Session Scaling](../engineering/session_scaling.md#session-scaling)

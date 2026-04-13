# File: documents/operations/keycloak_realm_bootstrap_runbook.md
# Keycloak Realm Bootstrap Runbook

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../architecture/multi_tenant_saas_mcp_auth_architecture.md](../architecture/multi_tenant_saas_mcp_auth_architecture.md#realm-seeding-rule), [../engineering/security_model.md](../engineering/security_model.md#cross-references), [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md#standards)

> **Purpose**: Canonical operational runbook for bootstrapping and validating Keycloak realms, clients, scopes, and tenant mappings for `studioMCP`.

## Summary

Auth in `studioMCP` is not credible unless Keycloak can be bootstrapped reproducibly in local, test, and cluster environments.

This runbook defines the required bootstrap artifacts and the current automated bootstrap path for kind-backed cluster validation.

## Deployment Baseline

Keycloak deployment baseline:

- Keycloak behind the shared nginx or ingress edge at `/kc`
- kind cluster deployment behind ingress-nginx for development and chart-backed validation
- dedicated PostgreSQL database for Keycloak only
- cluster ingress over HTTP for local kind development; TLS belongs to non-local ingress deployments
- automated realm bootstrap from the checked-in realm JSON

Helm-first packaging baseline:

- Helm values aligned to the `/kc`, `/api`, and `/mcp` public contract
- dedicated PostgreSQL chart or managed PostgreSQL for Keycloak persistence

## Automated Default Paths

### Kind And Helm

The current repo default for kind-backed validation is CLI-driven bootstrap:

```bash
docker compose -f docker-compose.yaml run --rm studiomcp studiomcp cluster ensure
```

`cluster ensure` and the related `cluster deploy sidecars` and `cluster deploy server` paths now:

1. create or reuse the kind cluster
2. apply the pinned ingress-nginx kind manifest
3. install or upgrade the Helm release with `chart/values.yaml` and `chart/values-kind.yaml`
4. wait for Keycloak readiness
5. port-forward `service/studiomcp-keycloak` for admin access
6. import `docker/keycloak/realm/studiomcp-realm.json` if the `studiomcp` realm is missing
7. wait for `http://localhost:8081/kc/realms/studiomcp/.well-known/openid-configuration`

This path is idempotent. Re-running it should leave an already-bootstrapped realm healthy and unchanged.

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

## Realm Export Location

The canonical realm export lives at:

```
docker/keycloak/realm/studiomcp-realm.json
```

This file is version-controlled and used for all environment bootstrapping.

## Realm Configuration

### Realm Settings

```json
{
  "realm": "studiomcp",
  "enabled": true,
  "displayName": "studioMCP",
  "sslRequired": "external",
  "registrationAllowed": false,
  "loginWithEmailAllowed": true,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": true,
  "editUsernameAllowed": false,
  "bruteForceProtected": true,
  "accessTokenLifespan": 300,
  "accessTokenLifespanForImplicitFlow": 300,
  "ssoSessionIdleTimeout": 1800,
  "ssoSessionMaxLifespan": 36000,
  "offlineSessionIdleTimeout": 2592000,
  "accessCodeLifespan": 60,
  "accessCodeLifespanUserAction": 300,
  "accessCodeLifespanLogin": 1800
}
```

### Token Settings

| Setting | Value | Rationale |
|---------|-------|-----------|
| Access Token Lifespan | 5 minutes | Short-lived for security |
| Refresh Token Lifespan | 30 days | Supports the current BFF-managed refresh flow |
| SSO Session Idle | 30 minutes | Browser session timeout |
| SSO Session Max | 10 hours | Daily re-authentication |

## Client Configurations

### MCP Resource Server Client

This is a bearer-only client that validates tokens but does not issue them.

```json
{
  "clientId": "studiomcp-mcp",
  "name": "studioMCP MCP Server",
  "enabled": true,
  "bearerOnly": true,
  "publicClient": false,
  "protocol": "openid-connect",
  "fullScopeAllowed": false,
  "defaultClientScopes": ["openid", "profile"],
  "optionalClientScopes": [
    "workflow:read",
    "workflow:write",
    "artifact:read",
    "artifact:write",
    "artifact:manage"
  ]
}
```

### Interactive CLI Client (Deferred)

The imported realm intentionally does not define a public interactive CLI client. Redirect-based
OAuth/PKCE for external tools remains deferred and is not part of the current supported bootstrap
path.

### BFF Client (Confidential)

For the web portal backend-for-frontend.

```json
{
  "clientId": "studiomcp-bff",
  "name": "studioMCP BFF",
  "enabled": true,
  "publicClient": false,
  "standardFlowEnabled": false,
  "directAccessGrantsEnabled": true,
  "serviceAccountsEnabled": false,
  "authorizationServicesEnabled": false,
  "protocol": "openid-connect",
  "secret": "${BFF_CLIENT_SECRET}",
  "defaultClientScopes": [
    "profile", "email", "roles", "web-origins",
    "workflow:read", "workflow:write",
    "artifact:read", "artifact:write", "prompt:read"
  ],
  "optionalClientScopes": ["artifact:manage"]
}
```

### Service Account Client

For platform automation and internal services.

```json
{
  "clientId": "studiomcp-service",
  "name": "studioMCP Service Account",
  "enabled": true,
  "publicClient": false,
  "serviceAccountsEnabled": true,
  "standardFlowEnabled": false,
  "protocol": "openid-connect",
  "secret": "${SERVICE_CLIENT_SECRET}",
  "defaultClientScopes": ["openid", "workflow:read", "workflow:write"]
}
```

## Client Scopes

### Custom Scopes

```json
{
  "clientScopes": [
    {
      "name": "workflow:read",
      "description": "Read workflow runs",
      "protocol": "openid-connect",
      "attributes": {
        "include.in.token.scope": "true",
        "display.on.consent.screen": "true",
        "consent.screen.text": "View your workflow runs"
      }
    },
    {
      "name": "workflow:write",
      "description": "Submit and cancel workflow runs",
      "protocol": "openid-connect",
      "attributes": {
        "include.in.token.scope": "true",
        "display.on.consent.screen": "true",
        "consent.screen.text": "Submit and manage workflow runs"
      }
    },
    {
      "name": "artifact:read",
      "description": "Download artifacts",
      "protocol": "openid-connect",
      "attributes": {
        "include.in.token.scope": "true",
        "display.on.consent.screen": "true",
        "consent.screen.text": "Download your artifacts"
      }
    },
    {
      "name": "artifact:write",
      "description": "Upload artifacts",
      "protocol": "openid-connect",
      "attributes": {
        "include.in.token.scope": "true",
        "display.on.consent.screen": "true",
        "consent.screen.text": "Upload artifacts"
      }
    },
    {
      "name": "artifact:manage",
      "description": "Manage artifact lifecycle",
      "protocol": "openid-connect",
      "attributes": {
        "include.in.token.scope": "true",
        "display.on.consent.screen": "true",
        "consent.screen.text": "Manage artifact lifecycle (hide, archive)"
      }
    }
  ]
}
```

### Tenant ID Mapper

Add a protocol mapper to include tenant_id in tokens:

```json
{
  "name": "tenant-id",
  "protocol": "openid-connect",
  "protocolMapper": "oidc-usermodel-attribute-mapper",
  "config": {
    "user.attribute": "tenant_id",
    "claim.name": "tenant_id",
    "jsonType.label": "String",
    "id.token.claim": "true",
    "access.token.claim": "true",
    "userinfo.token.claim": "true"
  }
}
```

## Realm Roles

```json
{
  "roles": {
    "realm": [
      {
        "name": "user",
        "description": "Basic user role"
      },
      {
        "name": "operator",
        "description": "Operator with extended access"
      },
      {
        "name": "admin",
        "description": "Administrator with full access"
      }
    ]
  }
}
```

## Test Users

### Test User Configuration

```json
{
  "users": [
    {
      "username": "testuser1",
      "email": "testuser1@example.com",
      "enabled": true,
      "emailVerified": true,
      "credentials": [
        {
          "type": "password",
          "value": "testpassword1",
          "temporary": false
        }
      ],
      "attributes": {
        "tenant_id": ["tenant-acme"]
      },
      "realmRoles": ["user"]
    },
    {
      "username": "testuser2",
      "email": "testuser2@example.com",
      "enabled": true,
      "emailVerified": true,
      "credentials": [
        {
          "type": "password",
          "value": "testpassword2",
          "temporary": false
        }
      ],
      "attributes": {
        "tenant_id": ["tenant-globex"]
      },
      "realmRoles": ["user"]
    },
    {
      "username": "testoperator",
      "email": "operator@example.com",
      "enabled": true,
      "emailVerified": true,
      "credentials": [
        {
          "type": "password",
          "value": "testoperator",
          "temporary": false
        }
      ],
      "attributes": {
        "tenant_id": ["tenant-acme"]
      },
      "realmRoles": ["user", "operator"]
    },
    {
      "username": "testadmin",
      "email": "admin@example.com",
      "enabled": true,
      "emailVerified": true,
      "credentials": [
        {
          "type": "password",
          "value": "testadmin",
          "temporary": false
        }
      ],
      "attributes": {
        "tenant_id": ["tenant-platform"]
      },
      "realmRoles": ["user", "operator", "admin"]
    }
  ]
}
```

### Test Tenants

| Tenant ID | Description | Test Users |
|-----------|-------------|------------|
| `tenant-acme` | Acme Corp test tenant | testuser1, testoperator |
| `tenant-globex` | Globex test tenant | testuser2 |
| `tenant-platform` | Platform admin tenant | testadmin |

## Non-Default Bootstrap Patterns

The canonical repo workflow does **not** ship or support a separate `keycloak/bootstrap.sh` helper,
a compose-era `localhost:18080` bootstrap path, or another repo-owned manual import script.

If an operator chooses to implement a one-off recovery script or a chart-managed Kubernetes Job for
a site-specific environment, treat that as local operational glue rather than part of the governed
repository contract. The active default remains the CLI-driven `cluster ensure` / `cluster deploy`
path documented above.

## Validation Steps

### Manual Validation

```bash
# 1. Provision the cluster edge and bootstrap Keycloak
docker compose -f docker-compose.yaml run --rm studiomcp studiomcp cluster ensure

# 2. Verify realm exists through the kind ingress edge
curl -sf "http://localhost:8081/kc/realms/studiomcp" | jq '.realm'

# 3. Validate the realm through the automated kind-edge path
docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate keycloak

# 4. Validate authenticated MCP access through the kind ingress edge
docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate mcp-auth

# 5. Validate browser session and BFF flows through the kind ingress edge
docker compose -f docker-compose.yaml run --rm studiomcp studiomcp validate web-bff
```

### Automated Validation

`studiomcp validate keycloak` performs live validation against the kind cluster. The validator provisions the cluster if needed, then validates the realm through the published kind ingress edge.

`studiomcp validate mcp-auth`, `studiomcp validate mcp-http`, and `studiomcp validate web-bff` use the same kind ingress edge plus the bootstrapped realm.

When the kind cluster is not available, validation falls back to the fake Keycloak-compatible JWKS harness.

Required automated validation covers:

1. Realm existence check
2. Client existence check for the active MCP, BFF, and service-account clients
3. Scope existence check for all required custom scopes
4. Test user authentication through the simplified login/password path
5. Token claim and subject resolution verification
6. JWKS endpoint availability
7. Idempotent cluster bootstrap when the kind-edge path is selected

## Validation Expectations

- realm exists
- required clients exist
- required scopes and roles exist
- test users can authenticate
- wrong-audience tokens are rejected by MCP
- seeded tenant mappings support integration tests
- re-running the automated bootstrap leaves the realm usable for the same validation set

## Cross-References

- [Multi-Tenant SaaS MCP Auth Architecture](../architecture/multi_tenant_saas_mcp_auth_architecture.md#multi-tenant-saas-mcp-auth-architecture)
- [Security Model](../engineering/security_model.md#security-model)
- [Session Scaling](../engineering/session_scaling.md#session-scaling)

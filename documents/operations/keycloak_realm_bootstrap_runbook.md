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

## Realm Export Location

The canonical realm export lives at:

```
keycloak/realm-export.json
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
| Refresh Token Lifespan | 30 days | Convenience for CLI tools |
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

### CLI Client (Public with PKCE)

For external MCP clients and CLI tools.

```json
{
  "clientId": "studiomcp-cli",
  "name": "studioMCP CLI",
  "enabled": true,
  "publicClient": true,
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": false,
  "protocol": "openid-connect",
  "redirectUris": [
    "http://localhost:*",
    "http://127.0.0.1:*"
  ],
  "webOrigins": ["+"],
  "attributes": {
    "pkce.code.challenge.method": "S256"
  },
  "defaultClientScopes": ["openid", "profile", "workflow:read", "artifact:read"],
  "optionalClientScopes": ["workflow:write", "artifact:write", "artifact:manage"]
}
```

### BFF Client (Confidential)

For the web portal backend-for-frontend.

```json
{
  "clientId": "studiomcp-bff",
  "name": "studioMCP BFF",
  "enabled": true,
  "publicClient": false,
  "standardFlowEnabled": true,
  "serviceAccountsEnabled": true,
  "authorizationServicesEnabled": false,
  "protocol": "openid-connect",
  "secret": "${BFF_CLIENT_SECRET}",
  "redirectUris": [
    "https://app.${DOMAIN}/callback",
    "http://localhost:3001/callback"
  ],
  "webOrigins": [
    "https://app.${DOMAIN}",
    "http://localhost:3001"
  ],
  "defaultClientScopes": [
    "openid", "profile",
    "workflow:read", "workflow:write",
    "artifact:read", "artifact:write"
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

## Bootstrap Script

### docker-compose Bootstrap

```bash
#!/bin/bash
# keycloak/bootstrap.sh

set -e

KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8080}"
ADMIN_USER="${KEYCLOAK_ADMIN:-admin}"
ADMIN_PASS="${KEYCLOAK_ADMIN_PASSWORD:-admin}"

# Wait for Keycloak to be ready
echo "Waiting for Keycloak..."
until curl -sf "${KEYCLOAK_URL}/health/ready"; do
  sleep 2
done

# Get admin token
TOKEN=$(curl -sf -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=admin-cli" \
  -d "username=${ADMIN_USER}" \
  -d "password=${ADMIN_PASS}" \
  -d "grant_type=password" | jq -r '.access_token')

# Import realm
curl -sf -X POST "${KEYCLOAK_URL}/admin/realms" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d @keycloak/realm-export.json

echo "Realm bootstrap complete"
```

### Kubernetes Job Bootstrap

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: keycloak-bootstrap
spec:
  template:
    spec:
      containers:
      - name: bootstrap
        image: curlimages/curl:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          # Bootstrap script here
        envFrom:
        - secretRef:
            name: keycloak-admin-credentials
      restartPolicy: OnFailure
```

## Validation Steps

### Manual Validation

```bash
# 1. Verify realm exists
curl -sf "http://localhost:8080/realms/studiomcp" | jq '.realm'

# 2. Get CLI token (PKCE flow simulated with direct grant for testing)
TOKEN=$(curl -sf -X POST "http://localhost:8080/realms/studiomcp/protocol/openid-connect/token" \
  -d "client_id=studiomcp-cli" \
  -d "username=testuser1" \
  -d "password=testpassword1" \
  -d "grant_type=password" \
  -d "scope=openid workflow:read" | jq -r '.access_token')

# 3. Verify token has expected claims
echo $TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq .

# 4. Test MCP auth validation
curl -sf -X POST "http://localhost:3000/mcp" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

### Automated Validation

The `studiomcp validate keycloak` command performs:

1. Realm existence check
2. Client existence check (all 4 clients)
3. Scope existence check (all custom scopes)
4. Test user authentication
5. Token claim verification
6. JWKS endpoint availability

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

# File: documents/engineering/security_model.md
# Security Model

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../architecture/overview.md](../architecture/overview.md#cross-references), [../architecture/multi_tenant_saas_mcp_auth_architecture.md](../architecture/multi_tenant_saas_mcp_auth_architecture.md#cross-references), [../architecture/artifact_storage_architecture.md](../architecture/artifact_storage_architecture.md#cross-references), [../reference/mcp_surface.md](../reference/mcp_surface.md#cross-references), [../../STUDIOMCP_DEVELOPMENT_PLAN.md](../../STUDIOMCP_DEVELOPMENT_PLAN.md#documentation-governance)

> **Purpose**: Canonical security rules for `studioMCP`, covering authentication, authorization, tenant isolation, token handling, artifact protection, and public runtime hardening.

## Summary

Security in `studioMCP` is not a thin wrapper around the execution runtime. It is a core architecture concern at the MCP boundary, the BFF boundary, the storage boundary, and the operational boundary.

Scope boundary:

- this document defines security controls and enforcement rules
- system topology and actor relationships live in [../architecture/multi_tenant_saas_mcp_auth_architecture.md](../architecture/multi_tenant_saas_mcp_auth_architecture.md#multi-tenant-saas-mcp-auth-architecture)
- artifact lifecycle rules live in [../architecture/artifact_storage_architecture.md](../architecture/artifact_storage_architecture.md#artifact-storage-architecture)

## Current Repo Note

The current repository does not yet implement the full multi-tenant auth model described here. This document defines the target security contract that future code must satisfy.

## Trust Boundaries

Primary trust boundaries:

- browser to BFF
- external MCP client to MCP server
- MCP server to Keycloak
- MCP server to tenant object storage
- BFF to MCP server

Every boundary must validate identity explicitly. No boundary may rely on hidden trusted-network assumptions alone.

## Authentication Rules

- Keycloak is the trusted issuer for public authn
- external identity providers are brokered through Keycloak, not trusted directly
- external MCP clients use OAuth with PKCE
- browser login uses redirect-based auth through Keycloak
- service accounts use confidential client flows with narrow scopes

## Authorization Rules

- every request resolves to a subject and tenant context
- access is granted only after issuer, audience, subject, tenant, scope, and policy checks all pass
- authorization is enforced server-side even if the client already thinks it knows its tenant
- tenant boundaries apply to tools, resources, prompts, artifact metadata, and presigned storage actions

## Token Rules

- access tokens must be short-lived
- refresh tokens must be rotated where supported
- wrong-audience tokens are rejected
- tokens received by the MCP server are not forwarded unchanged to downstream APIs
- downstream API calls use separate server-acquired credentials

## JWKS Integration

### Endpoint Configuration

The MCP server must be configured with the Keycloak JWKS endpoint:

```
STUDIOMCP_KEYCLOAK_ISSUER=https://auth.example.com/realms/studiomcp
STUDIOMCP_KEYCLOAK_AUDIENCE=studiomcp-mcp
```

The JWKS endpoint is derived: `{issuer}/protocol/openid-connect/certs`

### JWKS Caching

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Cache TTL | 5 minutes | Balance freshness vs. request latency |
| Refresh threshold | 1 minute before expiry | Proactive refresh |
| Fetch timeout | 5 seconds | Fail fast on connectivity issues |
| Retry count | 2 | Handle transient failures |

### Key Rotation Handling

```
1. Validate token signature with cached JWKS
2. If signature fails and JWKS is >1 minute old:
   a. Refresh JWKS from Keycloak
   b. Retry signature validation
3. If still fails, reject token with 401
```

### Algorithm Restrictions

| Algorithm | Status |
|-----------|--------|
| RS256 | Required, must support |
| RS384 | Supported |
| RS512 | Supported |
| ES256 | Supported |
| HS256 | Rejected (symmetric keys prohibited) |
| none | Rejected (unsigned tokens prohibited) |

### Haskell Implementation

```haskell
-- Configuration type
data KeycloakConfig = KeycloakConfig
  { kcIssuer :: Text       -- e.g., "https://auth.example.com/realms/studiomcp"
  , kcAudience :: Text     -- e.g., "studiomcp-mcp"
  , kcJwksCacheTtl :: Int  -- seconds
  }

-- JWKS cache
data JwksCache = JwksCache
  { jwksKeys :: JWKSet
  , jwksFetchedAt :: UTCTime
  , jwksExpiresAt :: UTCTime
  }

-- Validation result
validateToken :: KeycloakConfig -> JwksCache -> ByteString -> IO (Either AuthError JwtClaims)
```

## Token Exchange

### When Token Exchange Is Required

Token exchange is used when the MCP server needs to call downstream services that require their own tokens:

| Scenario | Source Token | Target Token |
|----------|--------------|--------------|
| MCP → Storage service | User access token | Service account token |
| BFF → MCP | User session token | MCP access token |
| MCP → External API | User access token | Delegated token |

### Token Exchange Flow (RFC 8693)

```http
POST /realms/studiomcp/protocol/openid-connect/token
Content-Type: application/x-www-form-urlencoded

grant_type=urn:ietf:params:oauth:grant-type:token-exchange
&subject_token=<original_access_token>
&subject_token_type=urn:ietf:params:oauth:token-type:access_token
&requested_token_type=urn:ietf:params:oauth:token-type:access_token
&audience=<target_service>
&client_id=studiomcp-mcp
&client_secret=<service_secret>
```

### No Passthrough Rule Enforcement

The MCP server must never:

```
✗ Forward user's access_token to downstream services unchanged
✗ Embed user's refresh_token in any outbound request
✗ Store user tokens in logs, summaries, or manifests
✗ Include user tokens in error messages
```

The MCP server must:

```
✓ Use its own service account for downstream calls
✓ Use token exchange when user context is needed downstream
✓ Scope downstream tokens narrowly to required operations
✓ Audit downstream token acquisition events
```

## Token Redaction

### Redaction Patterns

These patterns must be redacted from all logs and error messages:

| Pattern | Regex | Replacement |
|---------|-------|-------------|
| Bearer tokens | `Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+` | `Bearer [REDACTED]` |
| Authorization header | `Authorization: .*` | `Authorization: [REDACTED]` |
| Refresh tokens | `refresh_token=[^&]+` | `refresh_token=[REDACTED]` |
| Client secrets | `client_secret=[^&]+` | `client_secret=[REDACTED]` |
| Presigned URLs (signature) | `X-Amz-Signature=[^&]+` | `X-Amz-Signature=[REDACTED]` |

### Haskell Implementation

```haskell
redactSecrets :: Text -> Text
redactSecrets =
    redactBearer
  . redactRefreshToken
  . redactClientSecret
  . redactPresignedSig

-- Must be applied to all log output and error messages
logInfo :: (HasRequestContext m, MonadIO m) => Text -> m ()
logInfo msg = do
  ctx <- askContext
  liftIO $ writeLog $ LogEntry
    { logLevel = Info
    , logCorrelationId = ctxCorrelationId ctx
    , logMessage = redactSecrets msg
    }
```

## Session Rules

- remote listener pods must not require sticky load balancing
- session data required for remote transport lives outside pod memory
- session-store records must contain only the minimum metadata needed for correctness
- durable business state does not live in the session store

## Browser And BFF Rules

- the BFF never asks the browser for a password to relay to Keycloak
- browser uploads and downloads prefer short-lived presigned URLs
- browser sessions and MCP sessions are distinct concerns
- the BFF may call MCP on behalf of the user, but it must do so through explicit auth rules rather than a hidden shared secret

## Artifact Rules

- the MCP server may not permanently delete media artifacts
- storage credentials must be tenant-scoped
- presigned URLs must be short-lived
- summaries and manifests must not embed credentials
- artifact metadata operations must be audited
- storage retention and destructive cleanup, if they exist at all, must happen outside the MCP capability surface

## Logging And Audit Rules

Log:

- correlation id
- subject id
- tenant id
- request class
- authorization decision
- tool or resource name

Never log:

- passwords
- bearer tokens
- raw client secrets
- long-lived presigned URLs

## Runtime Hardening Rules

- TLS at the public ingress
- origin validation for browser-relevant remote flows
- explicit rate limiting and concurrency controls
- strict input validation before tool dispatch
- redaction of secret material in logs and errors
- separate admin endpoints from the MCP endpoint

## Secret Management Rules

- secrets are injected through managed Kubernetes secret mechanisms or approved secret backends
- tenant credentials for object storage must be scoped and rotatable
- no checked-in bootstrap secrets

## Failure Handling Rules

- invalid or missing credentials return `401`
- authenticated but unauthorized requests return `403`
- tenant-mismatch errors are denied without leaking cross-tenant existence details
- security-sensitive failures must be observable without revealing secrets

## Cross-References

- [Multi-Tenant SaaS MCP Auth Architecture](../architecture/multi_tenant_saas_mcp_auth_architecture.md#multi-tenant-saas-mcp-auth-architecture)
- [Artifact Storage Architecture](../architecture/artifact_storage_architecture.md#artifact-storage-architecture)
- [Session Scaling](session_scaling.md#session-scaling)
- [Web Portal Surface](../reference/web_portal_surface.md#web-portal-surface)

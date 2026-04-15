# File: documents/engineering/security_model.md
# Security Model

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../architecture/overview.md](../architecture/overview.md#cross-references), [../architecture/multi_tenant_saas_mcp_auth_architecture.md](../architecture/multi_tenant_saas_mcp_auth_architecture.md#cross-references), [../architecture/artifact_storage_architecture.md](../architecture/artifact_storage_architecture.md#cross-references), [../reference/mcp_surface.md](../reference/mcp_surface.md#cross-references), [../../DEVELOPMENT_PLAN/README.md](../../DEVELOPMENT_PLAN/README.md#standards)

> **Purpose**: Canonical security rules for `studioMCP`, covering authentication, authorization, tenant isolation, token handling, artifact protection, and public runtime hardening.

## Summary

Security in `studioMCP` is not a thin wrapper around the execution runtime. It is a core architecture concern at the MCP boundary, the BFF boundary, the storage boundary, and the operational boundary.

Scope boundary:

- this document defines security controls and enforcement rules
- system topology and actor relationships live in [../architecture/multi_tenant_saas_mcp_auth_architecture.md](../architecture/multi_tenant_saas_mcp_auth_architecture.md#multi-tenant-saas-mcp-auth-architecture)
- artifact lifecycle rules live in [../architecture/artifact_storage_architecture.md](../architecture/artifact_storage_architecture.md#artifact-storage-architecture)

## Current Repo Note

The current repository now implements the live auth model described here for the simplified login/password delivery path. The kind cluster exposes Keycloak, the BFF, and the MCP server behind the ingress-nginx edge, validates live bearer tokens, and exercises real multi-node auth and session routing through that edge.

## Trust Boundaries

Primary trust boundaries:

- browser to BFF
- external MCP client to MCP server
- MCP server to Keycloak
- MCP server to object storage
- BFF to MCP server

Every boundary must validate identity explicitly. No boundary may rely on hidden trusted-network assumptions alone.

## Authentication Rules

- Keycloak is the trusted issuer for public authn
- external identity providers are brokered through Keycloak, not trusted directly
- external MCP clients present Keycloak-issued bearer tokens
- browser login for the current delivery path uses username/password submitted to the BFF on the published edge; published deployments use TLS, while the local kind validation baseline keeps the same route shape on plain HTTP at `localhost`
- service accounts use confidential client flows with narrow scopes
- redirect-based OAuth/PKCE is explicitly deferred from the current delivery plan

## Authorization Rules

- every request resolves to a subject and tenant context
- access is granted only after issuer, audience, subject, tenant, scope, and policy checks all pass
- authorization is enforced server-side even if the client already thinks it knows its tenant
- tenant boundaries apply to tools, resources, prompts, artifact metadata, and presigned storage actions

## Token Rules

- access tokens must be short-lived
- refresh tokens must be rotated where supported
- wrong-audience tokens are rejected
- if a validated access token omits end-user identity claims such as `sub`, the server may recover them from Keycloak `userinfo` before building auth context
- tokens received by the MCP server are not forwarded unchanged to downstream APIs
- downstream API calls use separate server-acquired credentials
- BFF-held Keycloak tokens remain server-side session state and are never exposed in logs

## JWKS Integration

### Endpoint Configuration

The MCP server must be configured with the Keycloak JWKS endpoint:

```
STUDIOMCP_KEYCLOAK_ISSUER=https://auth.example.com/kc/realms/studiomcp
STUDIOMCP_KEYCLOAK_INTERNAL_ISSUER=http://keycloak:8080/kc/realms/studiomcp
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
  { kcIssuer :: Text               -- e.g., "https://auth.example.com/kc/realms/studiomcp"
  , kcInternalIssuer :: Maybe Text -- e.g., "http://keycloak:8080/kc/realms/studiomcp"
  , kcAudience :: Text             -- e.g., "studiomcp-mcp"
  , kcJwksCacheTtl :: Int          -- seconds
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

If a JWT access token omits `sub` or related end-user identity claims after signature, issuer, and audience validation succeed, the implementation may call Keycloak `userinfo` and then continue claim extraction with the recovered subject data.

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
POST /kc/realms/studiomcp/protocol/openid-connect/token
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

- in the current simplified delivery path, the BFF accepts username/password only on the published
  browser login route; published deployments use TLS, while the local kind validation baseline
  preserves the same route shape on plain HTTP at `localhost`
- the BFF relays credentials only to the Keycloak token endpoint
- the BFF never persists raw passwords and never writes them to logs, errors, metrics, or audit records
- browser uploads and downloads prefer short-lived presigned URLs
- browser sessions and MCP sessions are distinct concerns
- browser sessions should prefer HTTP-only cookies for interactive use
- login and refresh responses must expose only browser-safe session summary fields and must not expose session identifiers, access tokens, or refresh tokens
- `GET /api/v1/session/me` is the browser bootstrap surface for authenticated subject, tenant, and expiry state
- Bearer session identifiers, if enabled at all, are compatibility/debug credentials and the cookie wins when both are present
- the BFF may call MCP on behalf of the user, but it must do so through explicit auth rules rather than a hidden shared secret

## Artifact Rules

- the MCP server may not permanently delete media artifacts
- storage credentials must be tenant-scoped
- presigned URLs must be short-lived
- presigned URLs must be rooted at the environment's explicit public object-storage endpoint
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
- durable local runtime state must live under `./.data/`; `.studiomcp-data` and other ad hoc repo-root durability paths are forbidden
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

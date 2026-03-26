{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.MCP.Context
  ( -- * Request Context
    RequestContext (..),
    CorrelationId (..),

    -- * Context Creation
    newRequestContext,
    newRequestContextWithAuth,
    newCorrelationId,

    -- * Context Accessors
    getSessionFromContext,
    getTenantFromContext,
    getSubjectFromContext,
    getAuthContext,

    -- * Context Updates
    withSession,
    withCorrelationId,
    withAuthContext,

    -- * Logging Support
    contextLogFields,
  )
where

import Data.Aeson (ToJSON (toJSON), Value, object, (.=))
import Data.Text (Text)
import qualified Data.Text as T
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUID
import GHC.Generics (Generic)
import StudioMCP.Auth.Types
  ( AuthContext (..),
    Subject (..),
    SubjectId (..),
    Tenant (..),
    TenantId (..),
  )
import StudioMCP.MCP.Session.Types
  ( Session (..),
    SessionId (..),
    SubjectContext (..),
    TenantContext (..),
    TenantId (..),
  )
import qualified StudioMCP.Auth.Types as Auth
import qualified StudioMCP.MCP.Session.Types as Session

-- | Correlation ID for request tracing
newtype CorrelationId = CorrelationId Text
  deriving (Eq, Show, Ord, Generic)

instance ToJSON CorrelationId where
  toJSON (CorrelationId c) = toJSON c

-- | Generate a new correlation ID
newCorrelationId :: IO CorrelationId
newCorrelationId = do
  uuid <- UUID.nextRandom
  pure $ CorrelationId $ UUID.toText uuid

-- | Request context threaded through handlers
data RequestContext = RequestContext
  { ctxCorrelationId :: CorrelationId,
    ctxSession :: Maybe Session,
    ctxAuthContext :: Maybe AuthContext,
    ctxMethod :: Text,
    ctxRequestId :: Maybe Value -- JSON-RPC request ID
  }
  deriving (Eq, Show, Generic)

-- | Create a new request context
newRequestContext :: Text -> Maybe Value -> IO RequestContext
newRequestContext method reqId = do
  corrId <- newCorrelationId
  pure
    RequestContext
      { ctxCorrelationId = corrId,
        ctxSession = Nothing,
        ctxAuthContext = Nothing,
        ctxMethod = method,
        ctxRequestId = reqId
      }

-- | Create a new request context with auth
newRequestContextWithAuth :: Text -> Maybe Value -> AuthContext -> IO RequestContext
newRequestContextWithAuth method reqId authCtx = do
  corrId <- newCorrelationId
  pure
    RequestContext
      { ctxCorrelationId = CorrelationId (acCorrelationId authCtx),
        ctxSession = Nothing,
        ctxAuthContext = Just authCtx,
        ctxMethod = method,
        ctxRequestId = reqId
      }

-- | Get session from context
getSessionFromContext :: RequestContext -> Maybe Session
getSessionFromContext = ctxSession

-- | Get tenant from context (via session)
getTenantFromContext :: RequestContext -> Maybe TenantContext
getTenantFromContext ctx = ctxSession ctx >>= sessionTenant

-- | Get subject from context (via session)
getSubjectFromContext :: RequestContext -> Maybe SubjectContext
getSubjectFromContext ctx = ctxSession ctx >>= sessionSubject

-- | Add session to context
withSession :: Session -> RequestContext -> RequestContext
withSession session ctx = ctx {ctxSession = Just session}

-- | Update correlation ID in context
withCorrelationId :: CorrelationId -> RequestContext -> RequestContext
withCorrelationId corrId ctx = ctx {ctxCorrelationId = corrId}

-- | Add auth context
withAuthContext :: AuthContext -> RequestContext -> RequestContext
withAuthContext authCtx ctx = ctx {ctxAuthContext = Just authCtx}

-- | Get auth context
getAuthContext :: RequestContext -> Maybe AuthContext
getAuthContext = ctxAuthContext

-- | Extract structured log fields from context
contextLogFields :: RequestContext -> [(Text, Value)]
contextLogFields ctx =
  [ ("correlationId", toJSON (ctxCorrelationId ctx)),
    ("method", toJSON (ctxMethod ctx))
  ]
    ++ sessionFields
    ++ authContextFields
    ++ tenantFields
    ++ subjectFields
  where
    sessionFields = case ctxSession ctx of
      Just session -> [("sessionId", toJSON (sessionId session))]
      Nothing -> []

    authContextFields = case ctxAuthContext ctx of
      Just ac ->
        [ ("authTenantId", toJSON (Auth.tenantId (acTenant ac))),
          ("authSubjectId", toJSON (subjectId (acSubject ac)))
        ]
      Nothing -> []

    tenantFields = case getTenantFromContext ctx of
      Just tc -> [("tenantId", toJSON (Session.tcTenantId tc))]
      Nothing -> []

    subjectFields = case getSubjectFromContext ctx of
      Just sc -> [("subjectId", toJSON (Session.scSubjectId sc))]
      Nothing -> []

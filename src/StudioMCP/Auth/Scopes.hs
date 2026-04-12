{-# LANGUAGE OverloadedStrings #-}

module StudioMCP.Auth.Scopes
  ( -- * Scope Enforcement
    checkScopes,
    checkRoles,
    checkPermission,
    checkPermissions,

    -- * Permission Mapping
    permissionToScopes,
    roleToPermissions,

    -- * Authorization Checks
    authorizeToolCall,
    authorizeResourceRead,
    authorizePromptGet,

    -- * Scope Constants
    scopeWorkflowRead,
    scopeWorkflowWrite,
    scopeArtifactRead,
    scopeArtifactWrite,
    scopeArtifactManage,
    scopePromptRead,
    scopeResourceRead,
    scopeTenantRead,

    -- * Role Constants
    roleUser,
    roleOperator,
    roleAdmin,
  )
where

import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import StudioMCP.Auth.Types

-- | Scope constants
scopeWorkflowRead, scopeWorkflowWrite :: Scope
scopeWorkflowRead = Scope "workflow:read"
scopeWorkflowWrite = Scope "workflow:write"

scopeArtifactRead, scopeArtifactWrite, scopeArtifactManage :: Scope
scopeArtifactRead = Scope "artifact:read"
scopeArtifactWrite = Scope "artifact:write"
scopeArtifactManage = Scope "artifact:manage"

scopePromptRead, scopeResourceRead, scopeTenantRead :: Scope
scopePromptRead = Scope "prompt:read"
scopeResourceRead = Scope "resource:read"
scopeTenantRead = Scope "tenant:read"

-- | Role constants
roleUser, roleOperator, roleAdmin :: Role
roleUser = Role "user"
roleOperator = Role "operator"
roleAdmin = Role "admin"

-- | Check if subject has all required scopes
checkScopes :: Set Scope -> Subject -> AuthDecision
checkScopes required subject =
  let present = subjectScopes subject
      missing = Set.difference required present
   in if Set.null missing
        then Allowed
        else Denied $ InsufficientScopes required present

-- | Check if subject has any of the required roles
checkRoles :: Set Role -> Subject -> AuthDecision
checkRoles required subject =
  let present = subjectRoles subject
   in if Set.null (Set.intersection required present)
        then Denied $ InsufficientRoles required present
        else Allowed

-- | Check if subject has permission
checkPermission :: Permission -> Subject -> AuthDecision
checkPermission perm subject =
  let requiredScopes = permissionToScopes perm
   in checkScopes requiredScopes subject

-- | Check if subject has all permissions
checkPermissions :: [Permission] -> Subject -> AuthDecision
checkPermissions perms subject =
  let requiredScopes = Set.unions $ map permissionToScopes perms
   in checkScopes requiredScopes subject

-- | Map permission to required scopes
permissionToScopes :: Permission -> Set Scope
permissionToScopes perm = case perm of
  WorkflowRead -> Set.singleton scopeWorkflowRead
  WorkflowWrite -> Set.singleton scopeWorkflowWrite
  ArtifactRead -> Set.singleton scopeArtifactRead
  ArtifactWrite -> Set.singleton scopeArtifactWrite
  ArtifactManage -> Set.singleton scopeArtifactManage
  PromptRead -> Set.singleton scopePromptRead
  ResourceRead -> Set.singleton scopeResourceRead
  TenantRead -> Set.singleton scopeTenantRead
  AdminAccess ->
    Set.fromList
      [ scopeWorkflowRead,
        scopeWorkflowWrite,
        scopeArtifactRead,
        scopeArtifactWrite,
        scopeArtifactManage,
        scopePromptRead,
        scopeResourceRead,
        scopeTenantRead
      ]

-- | Map role to granted permissions
roleToPermissions :: Role -> Set Permission
roleToPermissions (Role r) = case r of
  "user" ->
    Set.fromList
      [ WorkflowRead,
        WorkflowWrite,
        ArtifactRead,
        ArtifactWrite,
        TenantRead
      ]
  "operator" ->
    Set.fromList
      [ WorkflowRead,
        WorkflowWrite,
        ArtifactRead,
        ArtifactWrite,
        ArtifactManage,
        PromptRead,
        ResourceRead,
        TenantRead
      ]
  "admin" ->
    Set.fromList
      [ WorkflowRead,
        WorkflowWrite,
        ArtifactRead,
        ArtifactWrite,
        ArtifactManage,
        PromptRead,
        ResourceRead,
        TenantRead,
        AdminAccess
      ]
  _ -> Set.empty

-- | Authorize MCP tool call
authorizeToolCall :: Text -> AuthContext -> AuthDecision
authorizeToolCall toolName ctx =
  let subject = acSubject ctx
      requiredPerms = toolPermissions toolName
   in checkPermissions requiredPerms subject

-- | Get required permissions for a tool
toolPermissions :: Text -> [Permission]
toolPermissions toolName
  | "workflow.submit" `T.isPrefixOf` toolName = [WorkflowWrite]
  | "workflow.status" `T.isPrefixOf` toolName = [WorkflowRead]
  | "workflow.list" `T.isPrefixOf` toolName = [WorkflowRead]
  | "workflow.cancel" `T.isPrefixOf` toolName = [WorkflowWrite]
  | "artifact.get" `T.isPrefixOf` toolName = [ArtifactRead]
  | "artifact.upload_url" `T.isPrefixOf` toolName = [ArtifactWrite]
  | "artifact.download_url" `T.isPrefixOf` toolName = [ArtifactRead]
  | "artifact.hide" `T.isPrefixOf` toolName = [ArtifactManage]
  | "artifact.archive" `T.isPrefixOf` toolName = [ArtifactManage]
  | "tenant.info" `T.isPrefixOf` toolName = [TenantRead]
  | otherwise = [ResourceRead] -- Default to resource read permission

-- | Authorize MCP resource read
authorizeResourceRead :: Text -> AuthContext -> AuthDecision
authorizeResourceRead resourceUri ctx =
  let subject = acSubject ctx
      requiredPerms = resourcePermissions resourceUri
   in checkPermissions requiredPerms subject

-- | Get required permissions for a resource
resourcePermissions :: Text -> [Permission]
resourcePermissions uri
  | "studiomcp://history/runs" `T.isPrefixOf` uri = [WorkflowRead]
  | "studiomcp://summaries/" `T.isPrefixOf` uri = [WorkflowRead]
  | "studiomcp://manifests/" `T.isPrefixOf` uri = [WorkflowRead]
  | "studiomcp://artifacts/" `T.isPrefixOf` uri = [ArtifactRead]
  | "studiomcp://metadata/tenant/" `T.isPrefixOf` uri = [TenantRead]
  | "studiomcp://metadata/quotas" `T.isPrefixOf` uri = [TenantRead]
  | "workflow" `T.isInfixOf` uri = [WorkflowRead]
  | "artifact" `T.isInfixOf` uri = [ArtifactRead]
  | "summary" `T.isInfixOf` uri = [WorkflowRead]
  | "manifest" `T.isInfixOf` uri = [WorkflowRead]
  | otherwise = [ResourceRead]

-- | Authorize MCP prompt get
authorizePromptGet :: Text -> AuthContext -> AuthDecision
authorizePromptGet promptName ctx =
  checkPermission PromptRead (acSubject ctx)

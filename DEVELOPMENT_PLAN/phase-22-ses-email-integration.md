# Phase 22: AWS SES Email Integration

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [00-overview.md](00-overview.md)

> **Purpose**: Add the repository-owned SES client, email template surface, and validation coverage
> for verification and password-reset style mail flows.

## Phase Summary

**Status**: Done
**Implementation**: `src/StudioMCP/Email/SES.hs`, `src/StudioMCP/Email/Templates.hs`, `src/StudioMCP/CLI/Email.hs`, `templates/email/*`
**Blocked by**: Phase 21 (Done)
**Docs to update**: `documents/operations/ses_email.md`, `documents/engineering/email_templates.md`

### Goal

Close the email-delivery layer for the supported repository scope:

- AWS SigV4-signed SES outbound request generation
- repository-owned HTML and text templates
- CLI `email send-test`
- integration coverage against a fake SES-compatible endpoint
- IAM policy guidance for the sender address `no-reply@resolvefintech.com`

### Deliverables

| Item | File(s) | Status |
|------|---------|--------|
| SES client wrapper | `src/StudioMCP/Email/SES.hs` | Done |
| Template renderer | `src/StudioMCP/Email/Templates.hs` | Done |
| CLI `email send-test` command | `src/StudioMCP/CLI/Email.hs`, `src/StudioMCP/CLI/Command.hs`, `app/Main.hs` | Done |
| Email templates | `templates/email/*.html`, `templates/email/*.txt` | Done |
| SES IAM policy document | `chart/iam/ses-policy.json` | Done |
| Integration coverage with fake SES endpoint | `test/Integration/EmailFlowsSpec.hs`, `test/Email/TemplatesSpec.hs` | Done |

### Validation

| Check | Command | Expected |
|-------|---------|----------|
| Integration suite | `docker compose run --rm studiomcp studiomcp test integration` | PASS |
| Full suite regression gate | `docker compose run --rm studiomcp studiomcp test` | PASS |
| Docs validation | `docker compose run --rm studiomcp studiomcp validate docs` | PASS |

### Remaining Work

None. The repository-owned SES client, email templates, and fake-endpoint validation path are
implemented and documented.

## Documentation Requirements

**Engineering docs to create/update:**
- `documents/operations/ses_email.md`
- `documents/engineering/email_templates.md`

**Product docs to create/update:**
- None

## Cross-References

- [README.md](README.md)
- [00-overview.md](00-overview.md)

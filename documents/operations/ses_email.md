# File: documents/operations/ses_email.md
# SES Email Operations

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../engineering/email_templates.md](../engineering/email_templates.md#cross-references), [../../DEVELOPMENT_PLAN/phase-22-ses-email-integration.md](../../DEVELOPMENT_PLAN/phase-22-ses-email-integration.md#cross-references)

> **Purpose**: Define the supported SES configuration, sender identity, and operator workflow for transactional email in `studioMCP`.

## Summary

`studioMCP` sends transactional email through AWS SES using sender address
`no-reply@resolvefintech.com`.

## Configuration

| Environment Variable | Purpose |
|----------------------|---------|
| `AWS_ACCESS_KEY_ID` | SES signing identity |
| `AWS_SECRET_ACCESS_KEY` | SES signing secret |
| `STUDIOMCP_SES_REGION` | SES region override; defaults to `us-east-1` |
| `STUDIOMCP_SES_SENDER` | Sender override; defaults to `no-reply@resolvefintech.com` |
| `STUDIOMCP_SES_ENDPOINT` | Endpoint override for tests or SES-compatible gateways |
| `STUDIOMCP_TEST_EMAIL_TO` | Optional recipient override for `email send-test` |

## CLI Workflow

```bash
docker compose run --rm studiomcp studiomcp email send-test
```

The command renders the verification template, uses the configured SES credentials, and prints the
target recipient plus the first part of the SES response body.

## IAM Policy

The checked-in policy scaffold lives at:

- `chart/iam/ses-policy.json`

It constrains sends to the supported sender address and covers standard SES send actions.

## Test Coverage

- `test/Integration/EmailFlowsSpec.hs` uses a fake SES-compatible HTTP endpoint
- `test/Email/TemplatesSpec.hs` verifies template rendering before send

## Cross-References

- [Email Templates](../engineering/email_templates.md#email-templates)
- [CLI Reference](../reference/cli_reference.md#studiomcp-cli-reference)

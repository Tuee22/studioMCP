# File: documents/engineering/email_templates.md
# Email Templates

**Status**: Authoritative source
**Supersedes**: N/A
**Referenced by**: [../operations/ses_email.md](../operations/ses_email.md#cross-references), [../../DEVELOPMENT_PLAN/phase-22-ses-email-integration.md](../../DEVELOPMENT_PLAN/phase-22-ses-email-integration.md#cross-references)

> **Purpose**: Define the template files, placeholder contract, and rendering behavior for SES-backed transactional email in `studioMCP`.

## Summary

Transactional email rendering lives in `src/StudioMCP/Email/Templates.hs` and reads paired
template files from `templates/email/`.

## Supported Templates

| Template Name | Files | Purpose |
|---------------|-------|---------|
| `email-verification` | `email-verification.html`, `email-verification.txt` | New-account verification |
| `password-reset` | `password-reset.html`, `password-reset.txt` | Password reset request |
| `password-changed` | `password-changed.html`, `password-changed.txt` | Post-change confirmation |

## Placeholder Contract

The renderer replaces these placeholders in both HTML and text variants:

- `{{recipient_name}}`
- `{{primary_url}}`
- `{{support_email}}`

## Subjects

Subjects are not stored in the template files. They are versioned in Haskell alongside the
template enum so the CLI and tests share a single subject source of truth.

## Validation Coverage

- `test/Email/TemplatesSpec.hs` checks substitution and subject rendering
- `test/Integration/EmailFlowsSpec.hs` exercises a rendered email through a fake SES endpoint

## Cross-References

- [SES Email Operations](../operations/ses_email.md#ses-email-operations)
- [CLI Reference](../reference/cli_reference.md#studiomcp-cli-reference)

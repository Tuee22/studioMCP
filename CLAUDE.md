# CLAUDE.md

Repository policy for LLM tooling:

- LLMs may create and edit local files.
- LLMs may run local validation commands.
- LLMs may not create git commits.
- LLMs may not push branches or tags.

All git commits and pushes are for the human user only.

## Container Execution Context

Test and validation commands must run through one-off outer `studiomcp` containers using the `studiomcp` CLI:

```bash
# Bootstrap
docker compose build

# Run tests via CLI (not cabal directly)
docker compose run --rm studiomcp studiomcp test           # All tests
docker compose run --rm studiomcp studiomcp test unit      # Unit tests only
docker compose run --rm studiomcp studiomcp test integration  # Integration tests only

# Run validation
docker compose run --rm studiomcp studiomcp validate all   # All validators
docker compose run --rm studiomcp studiomcp validate docs  # Docs only
```

Do NOT use `cabal test` directly. The `studiomcp` CLI is the canonical interface.

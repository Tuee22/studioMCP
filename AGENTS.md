# AGENTS.md

LLM agents working in this repository may edit files, run local builds, and run tests.

LLM agents must not make git commits.
LLM agents must not push to any remote.

Git commits and pushes are reserved for the human user only.

## Container Execution Context

Test and validation commands must run inside the outer `studiomcp-env` container using the `studiomcp` CLI:

```bash
# Bootstrap
docker compose up -d

# Run tests via CLI (not cabal directly)
docker compose exec studiomcp-env studiomcp test           # All tests
docker compose exec studiomcp-env studiomcp test unit      # Unit tests only
docker compose exec studiomcp-env studiomcp test integration  # Integration tests only

# Run validation
docker compose exec studiomcp-env studiomcp validate all   # All validators
docker compose exec studiomcp-env studiomcp validate docs  # Docs only
```

Do NOT use `cabal test` directly. The `studiomcp` CLI is the canonical interface.

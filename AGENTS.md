# AGENTS.md

LLM agents working in this repository may edit files, run local builds, and run tests.

LLM agents must not make git commits.
LLM agents must not push to any remote.

Git commits and pushes are reserved for the human user only.

## Container Execution Context

Test and validation commands must run inside the outer `studiomcp` container using the `studiomcp` CLI:

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

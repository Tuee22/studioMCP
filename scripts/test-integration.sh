#!/usr/bin/env bash
set -euo pipefail

./scripts/integration-harness.sh reset
STUDIOMCP_RUN_INTEGRATION=1 cabal test integration-tests

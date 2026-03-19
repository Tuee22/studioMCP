#!/usr/bin/env bash
set -euo pipefail

cabal build all
cabal test unit-tests
echo "Smoke test completed."

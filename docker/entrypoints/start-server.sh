#!/usr/bin/env bash
set -euo pipefail

cd /workspace
exec cabal run studiomcp -- server

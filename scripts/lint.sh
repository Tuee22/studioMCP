#!/usr/bin/env bash
set -euo pipefail

if command -v hlint >/dev/null 2>&1; then
  exec hlint app src test
fi

echo "hlint is not installed; skipping lint." >&2

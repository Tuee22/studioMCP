#!/usr/bin/env bash
set -euo pipefail

if command -v fourmolu >/dev/null 2>&1; then
  exec fourmolu -m inplace $(find app src test -name '*.hs' -print)
fi

echo "fourmolu is not installed; skipping format." >&2

#!/usr/bin/env bash
set -euo pipefail

url="${1:-http://localhost:8080/admin/v2/clusters}"
attempts="${2:-60}"

for ((i=1; i<=attempts; i++)); do
  if curl -fsS "$url" >/dev/null; then
    exit 0
  fi
  sleep 2
done

echo "pulsar did not become ready: $url" >&2
exit 1

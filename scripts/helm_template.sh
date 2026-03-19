#!/usr/bin/env bash
set -euo pipefail

profile="${1:-base}"

case "$profile" in
  base)
    exec helm template studiomcp chart -f chart/values.yaml
    ;;
  kind)
    exec helm template studiomcp chart -f chart/values.yaml -f chart/values-kind.yaml
    ;;
  prod)
    exec helm template studiomcp chart -f chart/values.yaml -f chart/values-prod.yaml
    ;;
  *)
    echo "usage: $0 {base|kind|prod}" >&2
    exit 1
    ;;
esac

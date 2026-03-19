#!/usr/bin/env bash
set -euo pipefail

if ! command -v skaffold >/dev/null 2>&1; then
  echo "skaffold is required for the Kubernetes-native dev loop." >&2
  echo "Install skaffold, then rerun ./scripts/k8s_dev.sh" >&2
  exit 1
fi

./scripts/kind_create_cluster.sh

exec skaffold dev --profile kind --port-forward

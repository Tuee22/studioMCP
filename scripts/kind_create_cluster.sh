#!/usr/bin/env bash
set -euo pipefail

cluster_name="${STUDIOMCP_KIND_CLUSTER:-studiomcp}"
config_file="kind/kind_config.yaml"

if kind get clusters | grep -qx "$cluster_name"; then
  echo "kind cluster '$cluster_name' already exists."
  exit 0
fi

exec kind create cluster --name "$cluster_name" --config "$config_file"

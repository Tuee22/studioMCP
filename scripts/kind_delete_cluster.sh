#!/usr/bin/env bash
set -euo pipefail

cluster_name="${STUDIOMCP_KIND_CLUSTER:-studiomcp}"

if ! kind get clusters | grep -qx "$cluster_name"; then
  echo "kind cluster '$cluster_name' does not exist."
  exit 0
fi

exec kind delete cluster --name "$cluster_name"

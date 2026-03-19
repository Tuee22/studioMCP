#!/usr/bin/env bash
set -euo pipefail

dag_file="${1:-examples/dags/transcode-basic.yaml}"
exec cabal run studiomcp -- validate-dag "$dag_file"

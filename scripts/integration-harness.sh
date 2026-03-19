#!/usr/bin/env bash
set -euo pipefail

compose_file="docker/docker-compose.yaml"

start() {
  docker compose -f "$compose_file" up -d pulsar minio minio-init
  ./docker/scripts/wait-for-pulsar.sh http://localhost:8080/admin/v2/clusters
  ./docker/scripts/wait-for-minio.sh http://localhost:9000/minio/health/live
}

stop() {
  docker compose -f "$compose_file" down --remove-orphans
}

reset() {
  docker compose -f "$compose_file" down -v --remove-orphans
  start
}

seed() {
  docker compose -f "$compose_file" run --rm minio-init
  ./docker/scripts/seed-example-assets.sh
}

case "${1:-}" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  reset)
    reset
    seed
    ;;
  seed)
    seed
    ;;
  *)
    echo "usage: $0 {start|stop|reset|seed}" >&2
    exit 1
    ;;
esac

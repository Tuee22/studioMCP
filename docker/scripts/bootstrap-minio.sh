#!/bin/sh
set -eu

mc alias set local http://minio:9000 minioadmin minioadmin123

mc mb --ignore-existing local/studiomcp-memo
mc mb --ignore-existing local/studiomcp-artifacts
mc mb --ignore-existing local/studiomcp-summaries
mc mb --ignore-existing local/studiomcp-test-fixtures

#!/usr/bin/env bash

set -euo pipefail

TIMEOUT="${1:-120}"
ELAPSED=0

while ! docker compose -f compose.yml ps --format json | grep -q '"Health":"healthy"'; do
  sleep 2
  ELAPSED=$((ELAPSED + 2))
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "Timed out waiting for healthy services"
    exit 1
  fi
done

echo "At least one service reports healthy status."

#!/usr/bin/env bash

set -euo pipefail

log() {
  echo "[$(date -Iseconds)] $*"
}

wait_for_http() {
  local url="$1"
  local timeout="${2:-30}"
  local elapsed=0

  while ! curl -sf "$url" >/dev/null 2>&1; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [ "$elapsed" -ge "$timeout" ]; then
      log "ERROR: timeout waiting for $url"
      return 1
    fi
  done
}

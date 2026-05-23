#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg is required for cross-client import checks" >&2
  exit 1
fi

check_forbidden() {
  local lane="$1"
  local pattern="$2"
  local hit=0
  while IFS= read -r file; do
    if rg -q '@cross-client' "${file}"; then
      continue
    fi
    if rg -n "${pattern}" "${file}"; then
      hit=1
    fi
  done < <(rg --files "${ROOT_DIR}/test/${lane}" -g '*.ts' -g '*.tsx')
  if [[ "${hit}" -eq 1 ]]; then
    echo "test/${lane} imports another client app outside an @cross-client spec; move shared helpers to test/shared or tag the spec @cross-client" >&2
    exit 1
  fi
}

check_forbidden "igloo-pwa" 'repos/igloo-(chrome|home)|[./]igloo-(chrome|home)/'
check_forbidden "igloo-chrome" 'repos/igloo-(pwa|home)|[./]igloo-(pwa|home)/'
check_forbidden "igloo-home" 'repos/igloo-(pwa|chrome)|[./]igloo-(pwa|chrome)/'

if rg -n 'repos/igloo-(pwa|chrome|home|ui)' "${ROOT_DIR}/test/shared" --glob '*.ts' --glob '*.tsx'; then
  echo "test/shared must not import client app repos; keep it limited to shared/domain helpers" >&2
  exit 1
fi

shared_client_constant_hits=()
while IFS= read -r file; do
  case "${file#${ROOT_DIR}/}" in
    test/shared/repo-paths.ts|test/shared/test-prebuild.ts)
      continue
      ;;
  esac
  shared_client_constant_hits+=("${file}")
done < <(rg -l '\bIGLOO_(PWA|CHROME|HOME)_DIR\b' "${ROOT_DIR}/test/shared" --glob '*.ts' --glob '*.tsx' || true)

if [[ "${#shared_client_constant_hits[@]}" -gt 0 ]]; then
  printf '%s\n' "${shared_client_constant_hits[@]}"
  echo "test/shared helpers must not depend on client app path constants outside allowlisted infrastructure files" >&2
  exit 1
fi

echo "ok: client test lanes do not import other client apps directly"

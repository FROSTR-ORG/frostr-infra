#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

fail() {
  printf 'shared-ui consumption contract failed: %s\n' "$*" >&2
  exit 1
}

clients=(igloo-pwa igloo-chrome igloo-home)

for client in "${clients[@]}"; do
  css="repos/${client}/src/index.css"
  [[ -f "${css}" ]] || fail "missing ${css}"
  grep -Fxq '@import "../../igloo-ui/src/styles.css";' "${css}" ||
    fail "${css} must import ../../igloo-ui/src/styles.css"

  config=""
  for candidate in "repos/${client}/tailwind.config.js" "repos/${client}/tailwind.config.ts"; do
    if [[ -f "${candidate}" ]]; then
      config="${candidate}"
      break
    fi
  done
  [[ -n "${config}" ]] || fail "missing Tailwind config for ${client}"
  grep -Fq "igloo-ui/tailwind.preset" "${config}" ||
    fail "${config} must consume igloo-ui/tailwind.preset"
  if theme_hits="$(rg -n '(^|[^[:alnum:]_])theme[[:space:]]*:|theme[.]extend' "${config}")"; then
    printf '%s\n' "${theme_hits}" >&2
    fail "${config} must not define a client-local theme or theme.extend"
  fi
done

scan_paths=(
  Makefile
  package.json
  package-lock.json
  scripts
  test/package.json
  test/scripts
  repos/igloo-pwa/package.json
  repos/igloo-pwa/scripts
  repos/igloo-pwa/vite.config.ts
  repos/igloo-chrome/package.json
  repos/igloo-chrome/scripts
  repos/igloo-chrome/vite.config.ts
  repos/igloo-home/package.json
  repos/igloo-home/scripts
  repos/igloo-home/vite.config.ts
)

existing_paths=()
for path in "${scan_paths[@]}"; do
  [[ -e "${path}" ]] && existing_paths+=("${path}")
done

if ((${#existing_paths[@]} > 0)); then
  if command_hits="$(rg -n \
    --glob '!test/scripts/check-*' \
    --glob '!test/scripts/test-affected.sh' \
    --glob '!**/node_modules/**' \
    'igloo-ui/dist|build:ui|igloo-ui-styles|igloo-ui run build' \
    "${existing_paths[@]}")"; then
    printf '%s\n' "${command_hits}" >&2
    fail "runtime/build/test command paths must not use old igloo-ui build artifacts"
  fi
fi

printf 'shared-ui consumption contract ok\n'

#!/usr/bin/env bash
set -euo pipefail

has_display() {
  [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]
}

has_xvfb() {
  command -v xvfb-run >/dev/null 2>&1
}

run_playwright() {
  exec npx playwright test -c ./igloo-home/playwright.config.ts "$@"
}

run_playwright_with_xvfb() {
  exec xvfb-run -a -s "-screen 0 1440x940x24" npx playwright test -c ./igloo-home/playwright.config.ts "$@"
}

main() {
  if has_display; then
    run_playwright "$@"
    return 0
  fi

  if has_xvfb; then
    run_playwright_with_xvfb "$@"
    return 0
  fi

  echo "igloo-home E2E requires DISPLAY or WAYLAND_DISPLAY, or xvfb-run installed for headless execution" >&2
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi

#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_SERVICES=(dev-relay igloo-demo)

die() {
  echo "error: $*" >&2
  echo "Run './run.sh help' for the full command list." >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ./run.sh help
  ./run.sh repo init
  ./run.sh repo check
  ./run.sh repo reset
  ./run.sh demo start [--port <port>]
  ./run.sh demo foreground [--port <port>]
  ./run.sh demo stop
  ./run.sh demo logs
  ./run.sh demo onboard
  ./run.sh demo smoke [--port <port>]
  ./run.sh test smoke
  ./run.sh test fast
  ./run.sh test live
  ./run.sh test demo
  ./run.sh test e2e
  ./run.sh test release
  ./run.sh compose start <service> [service...]
  ./run.sh compose stop <service> [service...]
  ./run.sh compose restart <service> [service...]
  ./run.sh compose logs <service> [service...]
  ./run.sh browser <igloo-pwa|igloo-chrome> <dev|build|test:unit|test:e2e>

Notes:
  ./run.sh is the only supported root command interface.
  scripts/ is private implementation detail.

Examples:
  ./run.sh repo check
  ./run.sh demo start --port 8394
  ./run.sh test release
  ./run.sh compose logs dev-relay
  ./run.sh browser igloo-chrome build
EOF
}

usage_repo() {
  cat <<'EOF'
Usage:
  ./run.sh repo init
  ./run.sh repo check
  ./run.sh repo reset
EOF
}

usage_demo() {
  cat <<'EOF'
Usage:
  ./run.sh demo start [--port <port>]
  ./run.sh demo foreground [--port <port>]
  ./run.sh demo stop
  ./run.sh demo logs
  ./run.sh demo onboard
  ./run.sh demo smoke [--port <port>]
EOF
}

usage_test() {
  cat <<'EOF'
Usage:
  ./run.sh test smoke
  ./run.sh test fast
  ./run.sh test live
  ./run.sh test demo
  ./run.sh test e2e
  ./run.sh test release
EOF
}

usage_compose() {
  cat <<'EOF'
Usage:
  ./run.sh compose start <service> [service...]
  ./run.sh compose stop <service> [service...]
  ./run.sh compose restart <service> [service...]
  ./run.sh compose logs <service> [service...]

Supported demo services:
  dev-relay
  igloo-demo
EOF
}

usage_browser() {
  cat <<'EOF'
Usage:
  ./run.sh browser <igloo-pwa|igloo-chrome> <dev|build|test:unit|test:e2e>
EOF
}

docker_compose_demo() {
  docker compose -f "${ROOT_DIR}/compose.test.yml" "$@"
}

run_demo() {
  local action="${1:-}"
  shift || true
  local port="${DEMO_RELAY_PORT:-8194}"

  case "${action}" in
    help|-h|--help|"")
      [[ "$#" -eq 0 ]] || die "demo help does not accept extra arguments"
      usage_demo
      ;;
    start|foreground|smoke)
      while [[ "$#" -gt 0 ]]; do
        case "$1" in
          --port)
            port="${2:-}"
            [[ -n "${port}" ]] || die "missing value for --port"
            shift 2
            ;;
          *)
            die "unknown demo argument: $1"
            ;;
        esac
      done
      case "${action}" in
        start) "${ROOT_DIR}/scripts/demo.sh" start "${port}" ;;
        foreground) "${ROOT_DIR}/scripts/demo.sh" foreground "${port}" ;;
        smoke) RELAY_PORT="${port}" "${ROOT_DIR}/test/scripts/test-demo-harness-onboard.sh" ;;
      esac
      ;;
    stop)
      [[ "$#" -eq 0 ]] || die "demo stop does not accept extra arguments"
      "${ROOT_DIR}/scripts/demo.sh" stop
      ;;
    logs)
      [[ "$#" -eq 0 ]] || die "demo logs does not accept extra arguments"
      "${ROOT_DIR}/scripts/demo.sh" logs
      ;;
    onboard)
      [[ "$#" -eq 0 ]] || die "demo onboard does not accept extra arguments"
      "${ROOT_DIR}/scripts/demo.sh" onboard
      ;;
    *)
      die "unknown demo command: ${action}"
      ;;
  esac
}

run_test() {
  local action="${1:-}"
  shift || true

  case "${action}" in
    help|-h|--help|"")
      [[ "$#" -eq 0 ]] || die "test help does not accept extra arguments"
      usage_test
      ;;
    smoke) npm --prefix "${ROOT_DIR}/test" run test:e2e:smoke ;;
    fast) npm --prefix "${ROOT_DIR}/test" run test:e2e:fast ;;
    live) npm --prefix "${ROOT_DIR}/test" run test:e2e:live ;;
    demo) npm --prefix "${ROOT_DIR}/test" run test:e2e:demo ;;
    e2e) npm --prefix "${ROOT_DIR}/test" run test:e2e ;;
    release) "${ROOT_DIR}/scripts/release-matrix.sh" ;;
    *)
      die "unknown test command: ${action}"
      ;;
  esac
}

run_compose() {
  local action="${1:-}"
  shift || true

  case "${action}" in
    help|-h|--help|"")
      [[ "$#" -eq 0 ]] || die "compose help does not accept extra arguments"
      usage_compose
      ;;
    start|stop|restart|logs)
      [[ "$#" -gt 0 ]] || die "compose ${action} requires at least one service"
      ;;
    *)
      die "unknown compose command: ${action}"
      ;;
  esac

  case "${action}" in
    start) docker_compose_demo up -d "$@" ;;
    stop) docker_compose_demo stop "$@" ;;
    restart) docker_compose_demo restart "$@" ;;
    logs) docker_compose_demo logs -f "$@" ;;
  esac
}

run_browser() {
  local app="${1:-}"
  local action="${2:-}"
  if [[ -z "${app}" || "${app}" == "help" || "${app}" == "-h" || "${app}" == "--help" ]]; then
    usage_browser
    return 0
  fi
  [[ -n "${action}" ]] || die "browser requires <app> and <action>"
  shift 2
  [[ "$#" -eq 0 ]] || die "browser command does not accept extra arguments"
  "${ROOT_DIR}/scripts/run-browser-app.sh" "${app}" "${action}"
}

run_repo() {
  local action="${1:-}"
  shift || true
  case "${action}" in
    help|-h|--help|"")
      [[ "$#" -eq 0 ]] || die "repo help does not accept extra arguments"
      usage_repo
      ;;
    init)
      [[ "$#" -eq 0 ]] || die "repo init does not accept extra arguments"
      (
        cd "${ROOT_DIR}"
        git submodule sync
        git submodule update --init
      )
      echo "Initialized top-level submodules (non-recursive by design)."
      ;;
    check)
      [[ "$#" -eq 0 ]] || die "repo check does not accept extra arguments"
      "${ROOT_DIR}/scripts/check-setup.sh"
      ;;
    reset)
      [[ "$#" -eq 0 ]] || die "repo reset does not accept extra arguments"
      "${ROOT_DIR}/scripts/reset.sh" --force
      ;;
    *)
      die "unknown repo command: ${action}"
      ;;
  esac
}

main() {
  local namespace="${1:-help}"
  shift || true

  case "${namespace}" in
    help|-h|--help)
      usage
      ;;
    repo)
      run_repo "$@"
      ;;
    infra)
      die "infra namespace has been retired; use repo, demo, test, compose, or browser"
      ;;
    demo)
      run_demo "$@"
      ;;
    test)
      run_test "$@"
      ;;
    compose)
      run_compose "$@"
      ;;
    browser)
      run_browser "$@"
      ;;
    *)
      die "unknown command namespace: ${namespace}"
      ;;
  esac
}

main "$@"

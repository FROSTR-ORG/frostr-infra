#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES=(igloo-web)
DEMO_HARNESS_SERVICES=(dev-relay igloo-demo)

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
  ./run.sh infra start [--bg] [service...]
  ./run.sh infra start-prod [--bg]
  ./run.sh infra dev [--bg]
  ./run.sh infra stop
  ./run.sh infra restart
  ./run.sh infra logs
  ./run.sh infra build
  ./run.sh infra build-prod
  ./run.sh infra check
  ./run.sh infra health
  ./run.sh infra setup
  ./run.sh infra reset
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
  ./run.sh compose start <service> [service...]
  ./run.sh compose stop <service> [service...]
  ./run.sh compose restart <service> [service...]
  ./run.sh compose logs <service> [service...]
  ./run.sh browser <igloo-pwa|igloo-chrome> <dev|build|test:unit|test:e2e>

Examples:
  ./run.sh infra dev --bg
  ./run.sh demo start --port 8394
  ./run.sh compose logs igloo-web
  ./run.sh browser igloo-chrome build
EOF
}

usage_repo() {
  cat <<'EOF'
Usage:
  ./run.sh repo init
EOF
}

usage_infra() {
  cat <<'EOF'
Usage:
  ./run.sh infra start [--bg] [service...]
  ./run.sh infra start-prod [--bg]
  ./run.sh infra dev [--bg]
  ./run.sh infra stop
  ./run.sh infra restart
  ./run.sh infra logs
  ./run.sh infra build
  ./run.sh infra build-prod
  ./run.sh infra check
  ./run.sh infra health
  ./run.sh infra setup
  ./run.sh infra reset
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
EOF
}

usage_compose() {
  cat <<'EOF'
Usage:
  ./run.sh compose start <service> [service...]
  ./run.sh compose stop <service> [service...]
  ./run.sh compose restart <service> [service...]
  ./run.sh compose logs <service> [service...]
EOF
}

usage_browser() {
  cat <<'EOF'
Usage:
  ./run.sh browser <igloo-pwa|igloo-chrome> <dev|build|test:unit|test:e2e>
EOF
}

ensure_override_file() {
  if [[ ! -f "${ROOT_DIR}/compose.override.yml" ]]; then
    "${ROOT_DIR}/scripts/setup-dev.sh"
  fi
}

docker_compose_main() {
  docker compose -f "${ROOT_DIR}/compose.yml" "$@"
}

docker_compose_prod() {
  docker compose -f "${ROOT_DIR}/compose.yml" -f "${ROOT_DIR}/compose.prod.yml" "$@"
}

docker_compose_demo() {
  docker compose -f "${ROOT_DIR}/compose.test.yml" "$@"
}

parse_bg_flag() {
  local bg=false
  if [[ "${1:-}" == "--bg" ]]; then
    bg=true
    shift
  fi
  printf '%s\n' "${bg}"
  printf '%s\n' "$#"
}

run_infra() {
  local action="${1:-}"
  shift || true

  case "${action}" in
    help|-h|--help|"")
      [[ "$#" -eq 0 ]] || die "infra help does not accept extra arguments"
      usage_infra
      ;;
    start)
      local bg=false
      if [[ "${1:-}" == "--bg" ]]; then
        bg=true
        shift
      fi
      local services=("${@:-}")
      if [[ "${#services[@]}" -eq 0 ]]; then
        services=("${SERVICES[@]}")
      fi
      if [[ "${bg}" == true ]]; then
        docker_compose_main up -d "${services[@]}"
      else
        docker_compose_main up "${services[@]}"
      fi
      ;;
    start-prod)
      local bg=false
      if [[ "${1:-}" == "--bg" ]]; then
        bg=true
        shift
      fi
      if [[ "$#" -ne 0 ]]; then
        die "infra start-prod does not accept service names"
      fi
      if [[ "${bg}" == true ]]; then
        docker_compose_prod up -d "${SERVICES[@]}"
      else
        docker_compose_prod up "${SERVICES[@]}"
      fi
      ;;
    dev)
      local bg=false
      if [[ "${1:-}" == "--bg" ]]; then
        bg=true
        shift
      fi
      if [[ "$#" -ne 0 ]]; then
        die "infra dev does not accept extra arguments"
      fi
      ensure_override_file
      if [[ "${bg}" == true ]]; then
        docker compose -f "${ROOT_DIR}/compose.yml" -f "${ROOT_DIR}/compose.override.yml" up -d "${SERVICES[@]}"
      else
        docker compose -f "${ROOT_DIR}/compose.yml" -f "${ROOT_DIR}/compose.override.yml" up "${SERVICES[@]}"
      fi
      ;;
    stop)
      [[ "$#" -eq 0 ]] || die "infra stop does not accept extra arguments"
      docker_compose_main down
      ;;
    restart)
      [[ "$#" -eq 0 ]] || die "infra restart does not accept extra arguments"
      docker_compose_main down
      docker_compose_main up "${SERVICES[@]}"
      ;;
    logs)
      [[ "$#" -eq 0 ]] || die "infra logs does not accept extra arguments"
      docker_compose_main logs -f
      ;;
    build)
      [[ "$#" -eq 0 ]] || die "infra build does not accept extra arguments"
      docker_compose_main build
      ;;
    build-prod)
      [[ "$#" -eq 0 ]] || die "infra build-prod does not accept extra arguments"
      docker_compose_prod build
      ;;
    check)
      [[ "$#" -eq 0 ]] || die "infra check does not accept extra arguments"
      "${ROOT_DIR}/scripts/check-setup.sh"
      ;;
    health)
      [[ "$#" -eq 0 ]] || die "infra health does not accept extra arguments"
      docker_compose_main ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
      ;;
    setup)
      [[ "$#" -eq 0 ]] || die "infra setup does not accept extra arguments"
      "${ROOT_DIR}/scripts/setup-dev.sh"
      ;;
    reset)
      [[ "$#" -eq 0 ]] || die "infra reset does not accept extra arguments"
      "${ROOT_DIR}/scripts/reset.sh" --force
      ;;
    *)
      die "unknown infra command: ${action}"
      ;;
  esac
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
        start) "${ROOT_DIR}/scripts/run-demo-stack.sh" start "${port}" ;;
        foreground) "${ROOT_DIR}/scripts/run-demo-stack.sh" foreground "${port}" ;;
        smoke) RELAY_PORT="${port}" "${ROOT_DIR}/scripts/test-demo-harness-onboard.sh" ;;
      esac
      ;;
    stop)
      [[ "$#" -eq 0 ]] || die "demo stop does not accept extra arguments"
      "${ROOT_DIR}/scripts/stop-demo-stacks.sh"
      rm -f "${ROOT_DIR}/data/test-harness/demo-relay-port.txt"
      ;;
    logs)
      [[ "$#" -eq 0 ]] || die "demo logs does not accept extra arguments"
      docker_compose_demo logs -f "${DEMO_HARNESS_SERVICES[@]}"
      ;;
    onboard)
      [[ "$#" -eq 0 ]] || die "demo onboard does not accept extra arguments"
      "${ROOT_DIR}/scripts/print-demo-harness-onboard.sh"
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
    start) docker_compose_main up -d "$@" ;;
    stop) docker_compose_main stop "$@" ;;
    restart) docker_compose_main restart "$@" ;;
    logs) docker_compose_main logs -f "$@" ;;
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
      run_infra "$@"
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

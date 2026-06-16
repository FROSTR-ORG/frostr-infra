#!/usr/bin/env bash
#
# Service control script for runtime error validation.
# Controls individual demo stack services (relay, alice co-signer) for
# VAL-ERR-001 through VAL-ERR-007 assertions.
#
# Usage:
#   service-control.sh stop relay        # Stop the dev relay
#   service-control.sh start relay       # Start the dev relay
#   service-control.sh stop alice        # Stop the alice co-signer
#   service-control.sh start alice       # Start the alice co-signer
#   service-control.sh status            # Show status of all services
#   service-control.sh logs              # Show logs from demo services
#
# Serialization: Assertions that mutate shared demo services must run
# serialized or with isolated demo stack/port. This script enables
# individual service control for that purpose.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/compose.test.yml"
RELAY_PORT="${DEV_RELAY_PORT:-8194}"

# Project name used by demo.sh
COMPOSE_PROJECT="$(basename "${ROOT_DIR}")"

stop_relay() {
    echo "[service-control] Stopping dev-relay (port ${RELAY_PORT})..."
    docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" stop dev-relay 2>/dev/null || true
    echo "[service-control] dev-relay stopped"
}

start_relay() {
    echo "[service-control] Starting dev-relay (port ${RELAY_PORT})..."
    docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" start dev-relay 2>/dev/null || true
    # Wait for relay to be healthy
    local attempt=0
    while [ "${attempt}" -lt 30 ]; do
        if docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" exec -T dev-relay \
            bash -lc "exec 3<>/dev/tcp/127.0.0.1/${RELAY_PORT} && exec 3>&-" >/dev/null 2>&1; then
            echo "[service-control] dev-relay is healthy"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    echo "[service-control] WARNING: dev-relay may not be fully healthy"
    return 0
}

stop_alice() {
    echo "[service-control] Stopping alice co-signer (igloo-demo)..."
    docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" stop igloo-demo 2>/dev/null || true
    echo "[service-control] alice co-signer stopped"
}

start_alice() {
    echo "[service-control] Starting alice co-signer (igloo-demo)..."
    docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" start igloo-demo 2>/dev/null || true
    # Wait for alice to be healthy (socket and onboard files exist)
    local attempt=0
    local socket_path="${FROSTR_TEST_HARNESS_DIR:-${ROOT_DIR}/.tmp/test-harness}/igloo-shell-alice.sock"
    while [ "${attempt}" -lt 60 ]; do
        if [ -S "${socket_path}" ] && \
           [ -s "${FROSTR_TEST_HARNESS_DIR:-${ROOT_DIR}/.tmp/test-harness}/onboard-bob.txt" ]; then
            echo "[service-control] alice co-signer is healthy"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    echo "[service-control] WARNING: alice co-signer may not be fully healthy"
    return 0
}

status() {
    echo "[service-control] Demo stack status:"
    echo ""
    docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" ps 2>/dev/null || \
    echo "  (no running containers)"
    echo ""
}

logs() {
    echo "[service-control] Demo stack logs:"
    docker compose -p "${COMPOSE_PROJECT}" -f "${COMPOSE_FILE}" logs --tail=50 -f 2>/dev/null || \
    echo "  (no running containers)"
}

usage() {
    cat <<'EOF'
Usage: service-control.sh <stop|start|status|logs> <relay|alice>

Controls individual demo stack services for runtime error validation.

Commands:
  stop <service>   Stop the specified service (relay or alice)
  start <service>  Start the specified service (relay or alice)
  status           Show status of all demo services
  logs             Show logs from demo services

Examples:
  service-control.sh stop relay
  service-control.sh start alice
  service-control.sh status

Serialization note:
  VAL-ERR assertions that mutate shared demo services must run serialized.
  Use this script to stop/start individual services between assertions.
EOF
}

main() {
    local action="${1:-}"
    local target="${2:-}"

    case "${action}" in
        stop)
            case "${target}" in
                relay) stop_relay ;;
                alice) stop_alice ;;
                *) echo "Error: unknown target '${target}'. Use 'relay' or 'alice'." >&2; exit 1 ;;
            esac
            ;;
        start)
            case "${target}" in
                relay) start_relay ;;
                alice) start_alice ;;
                *) echo "Error: unknown target '${target}'. Use 'relay' or 'alice'." >&2; exit 1 ;;
            esac
            ;;
        status)
            status
            ;;
        logs)
            logs
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
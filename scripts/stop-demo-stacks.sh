#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT_FILTER="${2:-}"
      shift 2
      ;;
    -*)
      echo "unknown option: $1" >&2
      exit 1
      ;;
    *)
      echo "unexpected argument: $1" >&2
      exit 1
      ;;
  esac
done

mapfile -t PROJECTS < <(
  docker ps \
    --filter "label=com.docker.compose.project.working_dir=${ROOT_DIR}" \
    --filter "label=com.docker.compose.project.config_files=${ROOT_DIR}/compose.test.yml" \
    --format '{{.Label "com.docker.compose.project"}}	{{.Label "com.docker.compose.service"}}	{{.Ports}}' \
    | awk -F '\t' -v port="${PORT_FILTER}" '
        ($2 == "dev-relay" || $2 == "igloo-demo") {
          if (port == "" || index($3, ":" port "->") > 0) {
            print $1
          }
        }
      ' \
    | awk '!seen[$0]++'
)

if [[ "${#PROJECTS[@]}" -eq 0 ]]; then
  exit 0
fi

for project in "${PROJECTS[@]}"; do
  echo "==> Stopping demo compose project ${project}"
  docker compose -p "${project}" -f "${ROOT_DIR}/compose.test.yml" down --remove-orphans >/dev/null
done


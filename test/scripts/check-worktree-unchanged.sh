#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ "${1:-}" != "--" ]]; then
  echo "usage: test/scripts/check-worktree-unchanged.sh -- <command> [args...]" >&2
  exit 1
fi
shift

snapshot() {
  local label
  git -C "${ROOT_DIR}" status --porcelain=v1 --untracked-files=no | sed 's#^#root\t#'
  while IFS= read -r line; do
    if [[ "${line}" != *" repos/"* ]]; then
      continue
    fi
    label="${line##* }"
    if [[ -d "${ROOT_DIR}/${label}" ]]; then
      git -C "${ROOT_DIR}/${label}" status --porcelain=v1 --untracked-files=no | sed "s#^#${label}\t#"
    fi
  done < <(git -C "${ROOT_DIR}" submodule status -- repos 2>/dev/null || true)
}

before="$(mktemp)"
after="$(mktemp)"
trap 'rm -f "${before}" "${after}"' EXIT

snapshot >"${before}"
"$@"
snapshot >"${after}"

if ! cmp -s "${before}" "${after}"; then
  echo "tracked workspace changed while running: $*" >&2
  diff -u "${before}" "${after}" >&2 || true
  exit 1
fi

echo "ok: command left tracked workspace unchanged"

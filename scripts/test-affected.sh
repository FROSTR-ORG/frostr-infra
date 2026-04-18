#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_REF="${FROSTR_AFFECTED_BASE:-origin/master}"
HOME_BINARY="${ROOT_DIR}/repos/igloo-home/src-tauri/target/debug/igloo-home"
DRY_RUN="${FROSTR_AFFECTED_DRY_RUN:-0}"

cd "${ROOT_DIR}"

changed_files=()
if [[ -n "${FROSTR_AFFECTED_FILES+x}" ]]; then
  while IFS= read -r path; do
    if [[ -n "${path}" ]]; then
      changed_files+=("${path}")
    fi
  done < <(printf '%s\n' "${FROSTR_AFFECTED_FILES}")
else
  merge_base="$(git merge-base "${BASE_REF}" HEAD 2>/dev/null || true)"
  if [[ -z "${merge_base}" ]]; then
    echo "error: unable to resolve affected base '${BASE_REF}'" >&2
    exit 1
  fi
  while IFS= read -r path; do
    if [[ -n "${path}" ]]; then
      changed_files+=("${path}")
    fi
  done < <(git diff --name-only "${merge_base}"...HEAD)
fi

run_guards=0
run_bifrost=0
run_shell=0
run_shared=0
run_home=0
run_pwa=0
run_chrome=0

if [[ "${#changed_files[@]}" -eq 0 ]]; then
  run_guards=1
fi

if [[ "${#changed_files[@]}" -gt 0 ]]; then
  for path in "${changed_files[@]}"; do
    case "${path}" in
      README.md|CONTRIBUTING.md|CHANGELOG.md|Makefile|compose.test.yml|scripts/*|test/*|docs/*|dev/*|services/*|.github/*)
        run_guards=1
        ;;
      repos/bifrost-rs/*)
        run_bifrost=1
        ;;
      repos/igloo-shell/*)
        run_shell=1
        ;;
      repos/igloo-shared/*)
        run_shared=1
        ;;
      repos/igloo-paper|repos/igloo-paper/*)
        run_guards=1
        ;;
      repos/igloo-home/*)
        run_home=1
        ;;
      repos/igloo-pwa/*)
        run_pwa=1
        ;;
      repos/igloo-chrome/*)
        run_chrome=1
        ;;
      repos/igloo-ui/*)
        run_home=1
        run_pwa=1
        run_chrome=1
        ;;
    esac
  done
fi

prebuild_targets=()
if [[ "${run_pwa}" -eq 1 ]]; then
  prebuild_targets+=(pwa)
fi
if [[ "${run_chrome}" -eq 1 ]]; then
  prebuild_targets+=(chrome demo)
fi
if [[ "${run_home}" -eq 1 ]]; then
  prebuild_targets+=(home demo)
fi

deduped_targets=()
target_seen() {
  local candidate="$1"
  local existing
  if [[ "${#deduped_targets[@]}" -eq 0 ]]; then
    return 1
  fi
  for existing in "${deduped_targets[@]}"; do
    if [[ "${existing}" == "${candidate}" ]]; then
      return 0
    fi
  done
  return 1
}

if [[ "${#prebuild_targets[@]}" -gt 0 ]]; then
  for target in "${prebuild_targets[@]}"; do
    if ! target_seen "${target}"; then
      deduped_targets+=("${target}")
    fi
  done
fi

print_command() {
  printf 'command: %s\n' "$1"
}

if [[ "${run_guards}" -eq 1 ]]; then
  if [[ "${DRY_RUN}" == "1" ]]; then
    print_command "npm --prefix test run test:guards"
  else
    npm --prefix test run test:guards
  fi
fi

if [[ "${#deduped_targets[@]}" -gt 0 ]]; then
  if [[ "${DRY_RUN}" == "1" ]]; then
    printf 'prep_targets:'
    for target in "${deduped_targets[@]}"; do
      printf ' %s' "${target}"
    done
    printf '\n'
  else
    bash "${ROOT_DIR}/scripts/test-prebuild.sh" "${deduped_targets[@]}"
  fi
fi

if [[ "${run_bifrost}" -eq 1 ]]; then
  if [[ "${DRY_RUN}" == "1" ]]; then
    print_command "cargo test --manifest-path ${ROOT_DIR}/repos/bifrost-rs/Cargo.toml --workspace --offline"
  else
    cargo test --manifest-path "${ROOT_DIR}/repos/bifrost-rs/Cargo.toml" --workspace --offline
  fi
fi

if [[ "${run_shell}" -eq 1 ]]; then
  if [[ "${DRY_RUN}" == "1" ]]; then
    print_command "cargo test --manifest-path ${ROOT_DIR}/repos/igloo-shell/Cargo.toml -p igloo-shell-cli --offline"
  else
    cargo test --manifest-path "${ROOT_DIR}/repos/igloo-shell/Cargo.toml" -p igloo-shell-cli --offline
  fi
fi

if [[ "${run_shared}" -eq 1 ]]; then
  if [[ "${DRY_RUN}" == "1" ]]; then
    print_command "npm --prefix ${ROOT_DIR}/repos/igloo-shared run test:typecheck"
  else
    npm --prefix "${ROOT_DIR}/repos/igloo-shared" run test:typecheck
  fi
fi

if [[ "${run_home}" -eq 1 ]]; then
  if [[ "${DRY_RUN}" == "1" ]]; then
    print_command "npm --prefix ${ROOT_DIR}/repos/igloo-home test"
    print_command "npm --prefix ${ROOT_DIR}/repos/igloo-home run test:visual"
    print_command "FROSTR_TEST_PREPARED=1 IGLOO_HOME_TEST_SKIP_BUILD=1 IGLOO_HOME_TEST_BINARY=${HOME_BINARY} npm --prefix ${ROOT_DIR}/test run test:e2e:igloo-home"
  else
    npm --prefix "${ROOT_DIR}/repos/igloo-home" test
    npm --prefix "${ROOT_DIR}/repos/igloo-home" run test:visual
    env \
      FROSTR_TEST_PREPARED=1 \
      IGLOO_HOME_TEST_SKIP_BUILD=1 \
      IGLOO_HOME_TEST_BINARY="${HOME_BINARY}" \
      npm --prefix "${ROOT_DIR}/test" run test:e2e:igloo-home
  fi
fi

if [[ "${run_pwa}" -eq 1 ]]; then
  if [[ "${DRY_RUN}" == "1" ]]; then
    print_command "FROSTR_TEST_PREPARED=1 npm --prefix ${ROOT_DIR}/test run test:e2e:igloo-pwa"
  else
    env FROSTR_TEST_PREPARED=1 npm --prefix "${ROOT_DIR}/test" run test:e2e:igloo-pwa
  fi
fi

if [[ "${run_chrome}" -eq 1 ]]; then
  if [[ "${DRY_RUN}" == "1" ]]; then
    print_command "FROSTR_TEST_PREPARED=1 npm --prefix ${ROOT_DIR}/test run test:e2e:igloo-chrome"
  else
    env FROSTR_TEST_PREPARED=1 npm --prefix "${ROOT_DIR}/test" run test:e2e:igloo-chrome
  fi
fi

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "affected dry run complete"
else
  echo "affected test run complete"
fi

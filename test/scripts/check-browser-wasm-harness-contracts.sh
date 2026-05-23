#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${ROOT_DIR}/.tmp/browser-wasm-harness-contracts.XXXXXX")"
FAKE_BIN="${TMP_DIR}/bin"
FAKE_RUST_TARGET="${TMP_DIR}/rust-target"
CHECK_DIR="${TMP_DIR}/browser-wasm-check"
LOG_FILE="${TMP_DIR}/calls.log"

cleanup() {
  local status="$?"
  if [[ "${status}" -eq 0 ]]; then
    rm -rf "${TMP_DIR}"
  else
    echo "preserving failed browser wasm harness scratch directory: ${TMP_DIR}" >&2
  fi
  exit "${status}"
}

trap cleanup EXIT

assert_file_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq "${needle}" "${ROOT_DIR}/${file}"; then
    echo "${file}: expected not to contain '${needle}'" >&2
    exit 1
  fi
}

mkdir -p "${FAKE_BIN}" "${FAKE_RUST_TARGET}"

cat >"${FAKE_BIN}/rustc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"--print target-libdir"* ]]; then
  printf '%s\n' "${FROSTR_WASM_CONTRACT_RUST_TARGET}"
  exit 0
fi
echo "unexpected rustc call: $*" >&2
exit 1
EOF

cat >"${FAKE_BIN}/clang" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
exit 0
EOF

cat >"${FAKE_BIN}/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

root="${FROSTR_WASM_CONTRACT_ROOT:?}"
log="${FROSTR_WASM_CONTRACT_LOG:?}"
prefix=""

if [[ "${1:-}" == "--prefix" ]]; then
  prefix="$2"
  shift 2
fi

if [[ "${1:-}" != "run" || "${2:-}" != "build:browser-wasm" ]]; then
  echo "unexpected npm command: $*" >&2
  exit 1
fi

case "${prefix}" in
  "${root}/repos/igloo-shared")
    out="${IGLOO_SHARED_BROWSER_WASM_OUT_DIR:-}"
    if [[ -z "${out}" || "${out}" != "${root}/.tmp/"* ]]; then
      echo "shared wasm output must be under .tmp, got '${out}'" >&2
      exit 1
    fi
    mkdir -p "${out}"
    printf 'bridge-js\n' >"${out}/bifrost_bridge_wasm.js"
    printf 'bridge-wasm\n' >"${out}/bifrost_bridge_wasm_bg.wasm"
    printf 'profile-js\n' >"${out}/bifrost_profile_wasm.js"
    printf 'profile-wasm\n' >"${out}/bifrost_profile_wasm_bg.wasm"
    printf 'shared\t%s\n' "${out}" >>"${log}"
    ;;
  "${root}/repos/igloo-pwa"| "${root}/repos/igloo-chrome")
    source_dir="${IGLOO_BROWSER_WASM_SOURCE_DIR:-}"
    target_dir="${IGLOO_BROWSER_WASM_TARGET_DIR:-}"
    if [[ -z "${source_dir}" || "${source_dir}" != "${root}/.tmp/"* ]]; then
      echo "client wasm source must be under .tmp, got '${source_dir}'" >&2
      exit 1
    fi
    if [[ -z "${target_dir}" || "${target_dir}" != "${root}/.tmp/"* ]]; then
      echo "client wasm target must be under .tmp, got '${target_dir}'" >&2
      exit 1
    fi
    mkdir -p "${target_dir}"
    cp -R "${source_dir}/." "${target_dir}/"
    printf 'client\t%s\t%s\t%s\n' "${prefix}" "${source_dir}" "${target_dir}" >>"${log}"
    ;;
  *)
    echo "unexpected npm prefix: ${prefix}" >&2
    exit 1
    ;;
esac
EOF

chmod +x "${FAKE_BIN}/rustc" "${FAKE_BIN}/clang" "${FAKE_BIN}/npm"

env \
  PATH="${FAKE_BIN}:${PATH}" \
  FROSTR_WASM_CONTRACT_ROOT="${ROOT_DIR}" \
  FROSTR_WASM_CONTRACT_LOG="${LOG_FILE}" \
  FROSTR_WASM_CONTRACT_RUST_TARGET="${FAKE_RUST_TARGET}" \
  FROSTR_BROWSER_WASM_CHECK_DIR="${CHECK_DIR}" \
  WASM_CC="${FAKE_BIN}/clang" \
  "${ROOT_DIR}/scripts/prepare-browser-wasm.sh" check all >/dev/null

if [[ "$(grep -c '^shared' "${LOG_FILE}")" -ne 1 ]]; then
  echo "expected one shared browser wasm build call" >&2
  exit 1
fi
if [[ "$(grep -c '^client' "${LOG_FILE}")" -ne 2 ]]; then
  echo "expected two client browser wasm sync calls" >&2
  exit 1
fi

diff -qr \
  "${CHECK_DIR}/igloo-shared/public/wasm" \
  "${CHECK_DIR}/igloo-pwa/public/wasm" >/dev/null
diff -qr \
  "${CHECK_DIR}/igloo-shared/public/wasm" \
  "${CHECK_DIR}/igloo-chrome/public/wasm" >/dev/null

assert_file_not_contains "test/shared/bridge-wasm.ts" "IGLOO_CHROME_DIR"
assert_file_not_contains "test/shared/profile-wasm.ts" "IGLOO_CHROME_DIR"

echo "ok: browser wasm harness contracts are scratch-based and client-neutral"

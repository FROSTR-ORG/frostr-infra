#!/usr/bin/env bash

set -euo pipefail

resolve_workspace_scratch_dir() {
  local env_name="$1"
  local default_leaf="$2"
  local override="${!env_name:-}"
  local target_dir=""

  if [[ -n "${override}" ]]; then
    # Scratch-discipline guard: an override may point anywhere OUTSIDE the repo
    # working tree, or under <ROOT_DIR>/.tmp/, but it must never resolve to a
    # tracked-looking path inside the repo (e.g. data/). This stops live
    # secrets (daemon tokens, onboarding passwords, sockets) from leaking into
    # the working tree, which is the failure mode that put secrets under the
    # retired `data/` scratch path. Use `realpath -m` so the check works before
    # the directory exists; relative overrides resolve against the current dir.
    local root_abs override_abs tmp_abs
    root_abs="$(realpath -m "${ROOT_DIR}")"
    tmp_abs="${root_abs}/.tmp"
    override_abs="$(realpath -m "${override}")"
    if [[ "${override_abs}/" == "${root_abs}/"* && "${override_abs}/" != "${tmp_abs}/"* ]]; then
      echo "error: scratch directory '${override}' from ${env_name} resolves inside the repo" >&2
      echo "       working tree but outside '${tmp_abs}'. Scratch artifacts must live under" >&2
      echo "       .tmp/ (or a path entirely outside the repo). Refusing to write secrets there." >&2
      exit 1
    fi
    target_dir="${override}"
    mkdir -p "${target_dir}" || {
      echo "error: unable to create scratch directory '${target_dir}' from ${env_name}" >&2
      exit 1
    }
    if [[ ! -d "${target_dir}" || ! -w "${target_dir}" ]]; then
      echo "error: scratch directory '${target_dir}' from ${env_name} is not writable" >&2
      exit 1
    fi
    printf '%s\n' "${target_dir}"
    return
  fi

  local tmp_root="${ROOT_DIR}/.tmp"
  if [[ ! -e "${tmp_root}" ]]; then
    mkdir -p "${tmp_root}" || {
      echo "error: unable to create workspace scratch root '${tmp_root}'" >&2
      exit 1
    }
  fi
  if [[ ! -d "${tmp_root}" ]]; then
    echo "error: workspace scratch root '${tmp_root}' is not a directory" >&2
    exit 1
  fi
  if [[ ! -w "${tmp_root}" ]]; then
    echo "error: workspace scratch root '${tmp_root}' is not writable" >&2
    echo "Run 'make repo-reset' or remove the stale ignored scratch directory." >&2
    exit 1
  fi

  target_dir="${tmp_root}/${default_leaf}"
  mkdir -p "${target_dir}" || {
    echo "error: unable to create workspace scratch directory '${target_dir}'" >&2
    exit 1
  }
  if [[ ! -w "${target_dir}" ]]; then
    echo "error: workspace scratch directory '${target_dir}' is not writable" >&2
    exit 1
  fi
  printf '%s\n' "${target_dir}"
}

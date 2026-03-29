#!/usr/bin/env bash

set -euo pipefail

resolve_workspace_scratch_dir() {
  local env_name="$1"
  local default_leaf="$2"
  local override="${!env_name:-}"
  local target_dir=""

  if [[ -n "${override}" ]]; then
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
    echo "Run './run.sh repo reset' or remove the stale ignored scratch directory." >&2
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

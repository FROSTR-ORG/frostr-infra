#!/usr/bin/env bash
#
# Bump every moved submodule pointer in one parent commit.
#
# The workspace commit flow is submodule-first: you commit inside a submodule,
# then the parent records the new pointer. This collapses the second half of
# that dance — "cd submodule; commit; cd ..; git add repos/X; git commit" across
# N submodules — into a single staged parent commit listing each bump.
#
# It is deliberately strict about the "commit inside first" rule: a submodule
# with uncommitted changes is an error (you would otherwise bump the pointer to a
# commit that does not yet contain your work). Pass --allow-dirty to bump the
# already-committed submodules and leave the dirty ones for later.
#
# Usage: make bump-pointers [MSG="subject"] [PUSH=1] [DRY_RUN=1]
#        scripts/bump-pointers.sh [-m <subject>] [--push-submodules] \
#                                 [--allow-dirty] [--dry-run]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

SUBJECT=""
PUSH=0
ALLOW_DIRTY=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--message) SUBJECT="${2:-}"; shift 2 ;;
    --push-submodules) PUSH=1; shift ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help)
      sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Classify every initialized submodule into "ready to bump" (its checked-out HEAD
# differs from the pointer the parent records) vs "dirty" (uncommitted changes,
# so the commit-inside-first step is not done). `git submodule status` marks a
# moved submodule with a leading '+', uninitialized with '-', conflicts with 'U';
# a clean/in-sync entry starts with the sha itself.
ready=()
dirty=()
while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  flag="${line:0:1}"
  rest="${line:1}"
  path="$(awk '{print $2}' <<<"${rest}")"
  [[ -z "${path}" ]] && continue
  case "${flag}" in
    -) continue ;;                       # uninitialized — nothing to do
    U) dirty+=("${path}"); continue ;;   # merge conflict — not clean
  esac
  if [[ -n "$(git -C "${path}" status --porcelain)" ]]; then
    dirty+=("${path}")
    continue
  fi
  if [[ "${flag}" == "+" ]]; then
    ready+=("${path}")
  fi
done < <(git submodule status)

if [[ ${#dirty[@]} -gt 0 && "${ALLOW_DIRTY}" -ne 1 ]]; then
  echo "error: these submodules have uncommitted changes — commit inside them first" >&2
  printf '  %s\n' "${dirty[@]}" >&2
  echo "       (commit inside each, or re-run with --allow-dirty to skip them)" >&2
  exit 1
fi

if [[ ${#ready[@]} -eq 0 ]]; then
  echo "No submodule pointers to bump (no submodule has moved ahead of its recorded pointer)."
  [[ ${#dirty[@]} -gt 0 ]] && echo "Skipped (dirty): ${dirty[*]}"
  exit 0
fi

# Build the commit body: one line per bump with the old..new short shas and the
# submodule's new HEAD subject, so the parent history says what moved and why.
body=""
for path in "${ready[@]}"; do
  old="$(git rev-parse --short "HEAD:${path}" 2>/dev/null || echo "0000000")"
  new="$(git -C "${path}" rev-parse --short HEAD)"
  subj="$(git -C "${path}" log -1 --format=%s)"
  body+="- ${path}: ${old}..${new}  \"${subj}\""$'\n'
done

if [[ -z "${SUBJECT}" ]]; then
  if [[ ${#ready[@]} -eq 1 ]]; then
    SUBJECT="Bump ${ready[0]#repos/} pointer"
  else
    names=""
    for path in "${ready[@]}"; do names+="${path#repos/}, "; done
    SUBJECT="Bump submodule pointers: ${names%, }"
  fi
fi

echo "==> Pointer bump plan"
echo "    subject: ${SUBJECT}"
printf '%s' "${body}" | sed 's/^/    /'
[[ ${#dirty[@]} -gt 0 ]] && echo "    skipped (dirty): ${dirty[*]}"

if [[ "${PUSH}" -eq 1 ]]; then
  echo "==> Pushing submodule branches first (--push-submodules)"
  for path in "${ready[@]}"; do
    branch="$(git -C "${path}" symbolic-ref --short -q HEAD || true)"
    if [[ -z "${branch}" ]]; then
      echo "error: ${path} is in detached HEAD; check out a branch before --push-submodules" >&2
      exit 1
    fi
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "    would push: git -C ${path} push origin ${branch}"
    else
      echo "    ${path} (${branch})"
      git -C "${path}" push origin "${branch}"
    fi
  done
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "==> Dry run: would stage ${ready[*]} and commit the parent. Nothing changed."
  exit 0
fi

git add -- "${ready[@]}"
git commit -q -m "${SUBJECT}" -m "${body%$'\n'}"
echo "==> Committed pointer bump:"
git log --oneline -1

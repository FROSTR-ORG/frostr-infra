#!/usr/bin/env bash
#
# Install npm dependencies for every JavaScript client in one pass.
#
# The repos/ submodules are independent projects that each build standalone, so
# each keeps its own self-contained node_modules (the file: deps to igloo-shared
# / igloo-ui resolve to per-leaf symlinks on install). This is deliberately NOT
# an npm workspace: hoisting deps to a shared root breaks the leaves' build
# scripts, which assume their dependencies live in their own node_modules. npm's
# content-addressed cache already dedupes downloads across the independent
# installs, so the only cost is symlinks on disk.
#
# Default is `npm ci`: lockfile-exact, reproducible, and it never mutates a
# committed package-lock.json — so a routine `make install` leaves the tree
# clean (important for agents and CI). Pass --update (or INSTALL_UPDATE=1) to run
# an incremental `npm install` instead, e.g. after editing a package.json; that
# may rewrite lockfiles, which you then review and commit per submodule.
#
# Usage: make install                 (preferred)
#        scripts/install.sh [--update]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="ci"
if [[ "${1:-}" == "--update" || "${INSTALL_UPDATE:-0}" == "1" ]]; then
  MODE="install"
fi

# Install order is shared -> ui -> consumers so the file: link targets exist on
# disk before each consumer installs. test/ holds the cross-repo Playwright
# harness. igloo-shell / bifrost-rs are Rust (cargo, not npm); igloo-paper is
# reference-only Python tooling — all excluded here by design.
PACKAGES=(
  "repos/igloo-shared"
  "repos/igloo-ui"
  "repos/igloo-pwa"
  "repos/igloo-chrome"
  "repos/igloo-home"
  "test"
)

echo "==> Installing npm dependencies (npm ${MODE}) for ${#PACKAGES[@]} packages"

for pkg in "${PACKAGES[@]}"; do
  dir="${ROOT_DIR}/${pkg}"
  if [[ ! -f "${dir}/package.json" ]]; then
    echo "  skip ${pkg} (no package.json — submodule not initialized? run make repo-init)" >&2
    continue
  fi
  echo "==> ${pkg}"
  npm --prefix "${dir}" "${MODE}"
done

echo "==> Done. (Playwright browsers, if needed: npm --prefix test run test:install-browsers)"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

npm --prefix repos/igloo-shared run build:bridge-wasm >/dev/null
npm --prefix repos/igloo-chrome run build:bridge-wasm >/dev/null
npm --prefix repos/igloo-pwa run build:bridge-wasm >/dev/null

if ! git diff --quiet -- \
  repos/igloo-shared/public/wasm \
  repos/igloo-chrome/public/wasm \
  repos/igloo-pwa/public/wasm
then
  echo "browser wasm artifacts are out of sync with source" >&2
  git diff -- \
    repos/igloo-shared/public/wasm \
    repos/igloo-chrome/public/wasm \
    repos/igloo-pwa/public/wasm
  exit 1
fi

echo "ok: browser wasm artifacts are in sync"

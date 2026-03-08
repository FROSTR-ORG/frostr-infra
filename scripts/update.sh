#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for service in igloo-web; do
  dir="$ROOT_DIR/repos/$service"
  if [ -f "$dir/package.json" ]; then
    echo "Updating $service..."
    (cd "$dir" && npm install)
  else
    echo "Skipping $service (no package.json found)"
  fi
done

#!/usr/bin/env bash
set -euo pipefail

"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wait-for-condition.sh" --timeout 90 --condition sign_ready_absent

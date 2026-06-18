#!/usr/bin/env bash
set -euo pipefail

# ADR-013: every e2e spec must declare at least one execution-lane tag, so the
# tag-filtered lanes (and the per-PR gate) run it deterministically — never
# "untagged, runs wherever a grep-invert happens to include it". Primary lane
# tags are:
#   @fast          render-only, no relay/harness
#   @live          single-client behavioral, local relay
#   @cross-client  multi-client pairing
#   @demo          Docker 3-way demo harness
#   @visual        storage-seeded snapshot lane
# @agent capture-tool specs are exempt (they are tools run only via make
# screenshot, not gated tests).
#
# Contract is "at least one", not "exactly one": demo pairing specs legitimately
# layer (@live @cross-client @demo), and @visual is orthogonal to @fast/@live.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

lane_re='@(fast|live|cross-client|demo|visual)'
exempt_re='@agent'

missing=()
while IFS= read -r spec; do
  if rg -q "${exempt_re}" "${spec}"; then
    continue
  fi
  if ! rg -q "${lane_re}" "${spec}"; then
    missing+=("${spec}")
  fi
done < <(find test -name '*.spec.ts' | sort)

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "specs missing an execution-lane tag (@fast|@live|@cross-client|@demo|@visual, or @agent for tools):" >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo "tag the spec's describe/test title; the tag is the contract, not the filename." >&2
  exit 1
fi

echo "ok: every e2e spec declares an execution-lane tag"

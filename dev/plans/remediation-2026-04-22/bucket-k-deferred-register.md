# Bucket K — Deferred Work Register

Status: living register, not an execution bucket
Not a release track. Items flagged throughout Buckets A–J as
"out-of-scope" or "deferred to a later bucket" are catalogued here
with rationale and trigger conditions for revival.

## How to read this

Each entry has:
- **Item** — short description.
- **Flagged by** — originating bucket's plan.
- **Rationale for deferral** — why not in the current remediation track.
- **Trigger** — when to pick it back up.
- **Rough priority** — H/M/L for when the trigger fires.

Items are grouped by category. Within a category, ordered by
priority. This is a backlog, not a plan; individual items become
plans when triggers fire.

## Security — deferred

### `RuntimeSnapshotExport.bootstrap` leaks `share.seckey` on every snapshot call

- **Flagged by**: Bucket A out-of-bucket; Bucket D "out-of-bucket flags".
- **Rationale**: Bucket D eliminated the host-side *use* of the leak by
  switching polling to `runtime_status()` (no bootstrap carried) and
  stripping `runtime_snapshot_json` from localStorage. The deeper fix
  (bifrost-rs stops emitting `share.seckey` in `RuntimeSnapshotExport`
  on subsequent snapshots, or splits "bootstrap capture" from "status
  polling" at the WASM ABI) was too cross-cutting for Bucket D's
  scope.
- **Trigger**: any future consumer pattern that legitimately needs
  `snapshot_state()` in a hot path. If one emerges, bifrost-rs owes a
  cleaner boundary.
- **Priority**: M. Contained by Bucket D's use-site mitigation today.

### UnlockSession idle timeout / re-auth

- **Flagged by**: Bucket C out-of-bucket.
- **Rationale**: Bucket C's `UnlockSession` caches the derived
  `FileStoreKey` for daemon lifetime. An idle timeout with passphrase
  re-prompt would reduce the window for memory-extraction attacks, but
  requires dropping and re-deriving the key (meaningful engineering).
  Deferred because attacker-with-memory-access is not currently in the
  threat model.
- **Trigger**: threat-model evolution to include process-memory reads
  (e.g. debugger attached, hibernation dump recovered). Or UX
  feedback that daemon lifetime is "too long".
- **Priority**: L unless threat model shifts.

### Portable-package PBKDF2 → Argon2id migration

- **Status**: **done in Bucket B.** This is not deferred; Bucket B's
  scope was expanded at the user's direction to include this migration.
  Left as an entry here for future-me confirming the register is
  current.

### `.js` wasm-bindgen glue SHA-384 verification

- **Flagged by**: Bucket E out-of-bucket.
- **Rationale**: Bucket E PR20 embeds SHA-384 of the `_bg.wasm` in the
  generated `.mjs` loader. The `.js` glue is referenced by the `.mjs`
  but not hash-verified by it. A swap of the `.js` glue would require
  also tampering with the `.mjs` wrapper, but the `.mjs` itself is
  trust-by-origin, not trust-by-hash.
- **Trigger**: any SRI gap reported. Simple to close: add
  `EXPECTED_JS_SHA384` verification inside the `.mjs` loader.
- **Priority**: L (defense-in-depth).

### Per-relay `connect-src` CSP tightening

- **Flagged by**: Bucket E out-of-bucket.
- **Rationale**: operators configure arbitrary relays; a per-profile
  CSP that re-narrows `connect-src` to only the configured relay
  hostnames would require runtime policy injection (CSP can't be
  updated post-load without reload).
- **Trigger**: a documented attack against the broad `wss:` /
  `https:` scheme — e.g. a compromised DNS entry for a public relay
  redirecting traffic.
- **Priority**: L.

### Multi-user privilege model for `igloo-shell`

- **Flagged by**: Bucket C out-of-bucket.
- **Rationale**: Bucket C assumes "same UID = trusted." Hardening
  against a hostile same-UID process (e.g. another user logged into a
  shared laptop) is a different threat model requiring capability-
  based IPC or a real sandbox.
- **Trigger**: FROSTR deployed in shared-laptop / multi-tenant scenarios.
- **Priority**: L for alpha; potentially M for broader deployment.

### Windows support for daemon mode

- **Flagged by**: Bucket C out-of-bucket (daemon remains `#[cfg(unix)]`-only).
- **Rationale**: named-pipe transport + Windows ACLs + different
  process-credential handling. Substantial.
- **Trigger**: explicit Windows product requirement.
- **Priority**: L unless mandated by product.

### Tauri updater hardening

- **Flagged by**: Bucket E out-of-bucket.
- **Rationale**: updater not currently enabled. When added, Bucket E's
  CSP already disallows outbound HTTP, so the updater needs a pinned
  public-key + allowlisted endpoint at the moment of enablement.
- **Trigger**: decision to enable Tauri updater.
- **Priority**: deferred until trigger.

### Ping correlation via `request_id`

- **Flagged by**: Bucket D out-of-bucket.
- **Rationale**: Bucket D PR14 switched sign/ecdh completions to
  request_id correlation. Ping stayed peer-keyed because
  bifrost-rs may not emit `request_id` on ping completions. Contingent
  on bifrost-rs confirmation.
- **Trigger**: confirmation that bifrost-rs ping completions carry
  `request_id`. Then this is a ≤50-line PR.
- **Priority**: M.

## Reliability — deferred

### Rotation auto-recovery

- **Flagged by**: Bucket C out-of-bucket.
- **Rationale**: Bucket C's rotation intent journal detects incomplete
  rotations at startup and logs a warning. Auto-rollback + auto-commit
  is more engineering, and doing it wrong is worse than the current
  "alert the operator" posture.
- **Trigger**: field reports of operators stuck with ghost profiles
  after crash-during-rotation. Or a repeated-incident pattern in
  testing.
- **Priority**: M. Complexity > urgency today.

### Multi-tab shared-session transport for PWA

- **Flagged by**: Bucket D out-of-bucket.
- **Rationale**: Bucket D's idempotent session lifecycle treats each
  tab as independent — each prompts for passphrase independently. A
  `BroadcastChannel`-based shared-session transport (with explicit user
  consent) would improve UX but requires a fresh threat model (who
  gets to share vs. a cross-tab attacker).
- **Trigger**: UX complaints about passphrase re-entry per tab.
- **Priority**: L for alpha.

## Tooling / dev-experience — deferred

### `test-prebuild.sh` stamp/fingerprint engine rewrite

- **Flagged by**: Bucket F out-of-bucket.
- **Rationale**: the 363-line shell-based fingerprint engine is
  complex but works. Rewriting in a real build tool (just /
  bazel-lite / make-based caching) is a meaningful effort; the current
  cost is maintenance friction, not a functional gap.
- **Trigger**: next major CI-time regression, or a contributor
  genuinely blocked on understanding the stamp logic.
- **Priority**: L.

### `release-matrix.sh` globals cleanup

- **Flagged by**: Bucket F out-of-bucket.
- **Rationale**: audit finding 14. Return values pass via global
  variables in `run_parallel_step`. Works; ugly.
- **Trigger**: bug caused by global-variable clobber.
- **Priority**: L.

### bifrost-rs-side TS type generation (wasm-bindgen / ts-rs)

- **Flagged by**: Bucket G out-of-bucket.
- **Rationale**: Bucket G hand-authors the `wire/` TS types matching
  bifrost-rs Rust structs. A `wasm-bindgen` or `ts-rs`-style derive
  would make the Rust side the single source of truth. Substantial
  tooling to set up; the wire-contract test (Bucket G PR29) catches
  drift in the meantime.
- **Trigger**: a real wire-drift bug that the contract test missed.
- **Priority**: M.

### Fuzzing infrastructure (`cargo-fuzz` / libFuzzer)

- **Flagged by**: Bucket I (uses proptest instead).
- **Rationale**: Bucket I uses `proptest` in-CI for wire fuzzing.
  `cargo-fuzz` with libFuzzer would give structure-aware fuzzing with
  better corpus + crash-reproduction. Harder to integrate into CI (needs
  nightly Rust, separate artifact management).
- **Trigger**: a fuzzing-discovered bug in a downstream project that
  would have been caught by coverage-guided fuzzing but not
  proptest.
- **Priority**: M.

### Storybook for `igloo-ui`

- **Flagged by**: Bucket H out-of-bucket.
- **Rationale**: dev-experience improvement for isolated component
  work. Not a correctness or security concern.
- **Trigger**: onboarding friction for new frontend contributors; or
  visual-regression test-coverage need.
- **Priority**: L.

### Visual regression testing

- **Flagged by**: Bucket H out-of-bucket.
- **Rationale**: Chromatic / Percy / Playwright visual snapshots. Good
  hygiene; not a release gate.
- **Trigger**: CSS regression that slips past manual review.
- **Priority**: L.

## Quality / modularization — deferred

### Host `App.tsx` / `store.tsx` modular splits

- **Flagged by**: Bucket G out-of-bucket.
- **Rationale**: `igloo-home/App.tsx` 1,875 lines, `igloo-pwa/App.tsx`
  1,345 lines, `igloo-pwa/store.tsx` 1,147 lines. Bucket G unblocks
  this by publishing typed runtime projections; the structural split
  is its own significant effort.
- **Trigger**: contributor friction, or a specific bug class caused by
  the monolith shape (e.g. over-rendering due to the `state`-dep
  `useMemo`).
- **Priority**: M. High leverage on contributor velocity; not
  security-urgent.

### `peer-list.tsx` split

- **Flagged by**: Bucket H out-of-bucket.
- **Rationale**: 259-line file mixing layout + policy + ping +
  nonce-meter. Audit finding 4.
- **Trigger**: any bug localized to one of the mixed concerns that
  would be easier to fix after the split.
- **Priority**: L.

### `CreateFlow.tsx` + `OperatorPermissionsPanel.tsx` prop-surface simplification

- **Flagged by**: Bucket H out-of-bucket.
- **Rationale**: large prop contracts (10+, 15+ callback props). Audit
  finding 10. Shape change benefits downstream but requires a clear
  state-event discriminated-union design upfront.
- **Trigger**: next significant feature work touching these
  components.
- **Priority**: L.

### `NodeWithEvents` type alias removal

- **Status**: **done atomically in Bucket G PR31.** Not deferred.
  Included here only to confirm the register is current.

### Removing `Modal`/`ConfirmModal` shims

- **Status**: **no shims exist** — Bucket H PR36 hard-cuts. Included
  only to confirm the register is current.

## Release hygiene — deferred

### CHANGELOG + real semver for `igloo-ui`

- **Flagged by**: Bucket H out-of-bucket.
- **Rationale**: currently `version: 0.0.0`, CHANGELOG is a single
  `[Unreleased]` block. Needs a first dated release entry.
- **Trigger**: first external consumer (not a workspace member) of
  `igloo-ui`.
- **Priority**: L for alpha.

### Architectural-decision docs (ADRs) for remediation

- **Flagged by**: Bucket J out-of-bucket.
- **Rationale**: each hard-cut decision in A–H could be an ADR under
  `dev/adrs/`. Nice historical record; not a release deliverable.
- **Trigger**: a future contributor asks "why did we do X this way?"
  for a decision that the plan files don't fully capture.
- **Priority**: L.

## Scheduling guidance

Post-alpha, once R1+R2+R3 have landed and the next roadmap checkpoint
is reached, the Medium-priority items in this register form a natural
"post-alpha polish" pass:

- Ping correlation via `request_id` (quick win; contingent on
  bifrost-rs).
- Host `App.tsx` / `store.tsx` modular splits (contributor-velocity
  leverage).
- Rotation auto-recovery (operational robustness).
- bifrost-rs-side TS type generation (wire-contract resilience).
- Fuzzing infrastructure upgrade (coverage-guided).

Everything else waits for its trigger.

## Summary

Not a release track. 18 items deferred from A–J with rationale,
trigger conditions, and rough priorities. Living document — update
when a deferred item either (a) fires its trigger and gets a fresh
plan, or (b) becomes irrelevant due to unrelated changes.

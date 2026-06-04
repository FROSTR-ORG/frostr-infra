# FROSTR Remediation Track — 2026-04-22

This directory contains the plan files for the remediation work derived
from the 2026-04-22 workspace audit at `../audit/`. All plans are
approved; execution is in progress.

## Approach

- **Hard-cut**: every rename / version bump / API change lands atomically with its consumer migration. No transitional shims, no back-compat re-export layers. Alpha allows this; fewer moving parts during review.
- **Subagent execution**: one subagent per PR. Each subagent works in a feature branch inside the affected submodule; the user reviews the branch diff before merge.
- **Three coordinated releases**: R1 (security hardening), R2 (structural refactor), R3 (test + docs).

## Release sequencing

### R1 — Security hardening (Buckets A + B + C + D + E + F) — 28 PRs

One operator migration event. Operators re-onboard all profiles
(driven by Bucket A's `DeviceState::VERSION` bump, Bucket B's
`ENCRYPTED_PROFILE_VERSION` + `ProtectedPackageEnvelope::version`
bumps) and switch any CLI scripting from `IGLOO_SHELL_*_PASSWORD` env
vars to stdin piping (Bucket C).

| Bucket | Scope | PRs | Plan |
|---|---|---|---|
| A | `bifrost-rs` crypto primitives — CT MAC compare, envelope bounds, secret newtypes, NIP-44 consolidation | 1–4 | [bucket-a-bifrost-rs-crypto.md](./bucket-a-bifrost-rs-crypto.md) |
| B | KDF + AEAD + AAD — Argon2id 256 MiB / XChaCha20Poly1305 / v2 envelopes for host-local + portable packages | 5–7 | [bucket-b-kdf-aad.md](./bucket-b-kdf-aad.md) |
| C | Host-local secret hygiene — filesystem perms, atomic writes, `Passphrase`/`DaemonToken` newtypes, daemon auth, stdin passphrase, `UnlockSession`, rotation journal | 8–12 | [bucket-c-secret-hygiene.md](./bucket-c-secret-hygiene.md) |
| D | Browser-host secret hygiene — localStorage secret stripping, `Secret<T>` wrapper, allow-list redactor, `request_id` correlation, idempotent session | 13–17 | [bucket-d-browser-secrets.md](./bucket-d-browser-secrets.md) |
| E | Shell hardening — Tauri CSP + capabilities, PWA CSP + COOP/COEP, Chrome CSP tightening, WASM SHA-384 integrity, test-mode server gating, path canon, typed Tauri errors, Tauri passphrase migration | 18–24 | [bucket-e-shell-hardening.md](./bucket-e-shell-hardening.md) |
| F | Workspace hardening — non-root containers + `:ro` mounts, `.env.example` cleanup, `data/` removal, GitHub Actions SHA pinning + permissions + concurrency + `npm ci`, demo entrypoint refactor, script/doc hygiene | 25–28 | [bucket-f-workspace-hardening.md](./bucket-f-workspace-hardening.md) |

### R2 — Structural refactor (Buckets G + H) — 10 PRs

Zero operator impact. Purely internal refactor that unblocks the
host-side modular cleanups deferred to Bucket K.

| Bucket | Scope | PRs | Plan |
|---|---|---|---|
| G | Typed runtime-shape exports — extract wire types, split `browser-runtime-core.ts` monolith, export `BrowserBridgeNode` directly, typed projections, consolidate `browser-profile-*` | 29–33 | [bucket-g-runtime-types.md](./bucket-g-runtime-types.md) |
| H | Shared UI package boundary — rename `igloo-pwa-*` tokens, `SensitiveField`/`SensitiveTextarea`, vendor fonts, named exports, dialog + accessibility primitives, `LogEntry` hardening, test coverage | 34–38 | [bucket-h-ui-hardening.md](./bucket-h-ui-hardening.md) |

### R3 — Tests + docs (Buckets I + J) — 8+ PRs

Zero operator impact. Fills residual test coverage and doc coherence;
re-audits `igloo-chrome` against the 2026-04-02 report.

| Bucket | Scope | PRs | Plan |
|---|---|---|---|
| I | Residual test coverage — FROST KATs, `NoncePool` proptest, wire fuzz, `bifrost-router` integration, post-G TS runtime tests, cross-repo E2E gaps | 39–43 | [bucket-i-test-coverage.md](./bucket-i-test-coverage.md) |
| J | Docs + `igloo-chrome` re-audit — doc cross-link polish, `igloo-shared` JSDoc, Chrome re-audit, Chrome cleanup PRs | 44–46+ | [bucket-j-docs-chrome.md](./bucket-j-docs-chrome.md) |

### Backlog (Bucket K) — not an execution track

18 items deferred from A–J with rationale and trigger conditions.
Scheduled when triggers fire, not on a fixed calendar.

See [bucket-k-deferred-register.md](./bucket-k-deferred-register.md).

## Total scope

**46+ PRs across three releases.** Ballpark touch: ~15,000 lines across
all repos. Most PRs are ≤500 lines; the largest are Bucket G PR30 (split
monolith) and Bucket E PR23 (Tauri IPC typed errors).

## Execution conventions

- Each subagent works in a branch under the naming pattern
  `remediation/pr<N>-<short-slug>` inside the relevant submodule.
- Branches are not pushed automatically; the user reviews and merges.
- Every PR lands with its tests passing and `cargo clippy` / ESLint
  clean. CI gates (`test-release` for R1/R3, `test-e2e` or more
  focused for R2) must pass before merge.
- Cross-repo coordination happens at the release boundary: submodule
  pointer updates in `frostr-infra` happen after all the submodule
  PRs in a given release are merged to their respective master
  branches.

## Related artifacts

- Audit reports: `../audit/` (workspace synthesis + per-repo reports)
- Prior audit: `../reports/igloo-chrome-audit-2026-04-02.md`
- Coordinated release process: `../docs/RELEASE.md`

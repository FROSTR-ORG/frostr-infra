# Hand-off: MED+ backlog program — Phase 1 done, Phases 2–6 open

_Last updated: 2026-06-13_

> **Read this first.** Entry point for a new session in the `frostr-infra`
> workspace. There is an **approved multi-phase plan** in progress:
> [`plans/enchanted-leaping-papert.md`](./plans/enchanted-leaping-papert.md) —
> "Remediate audit findings + complete medium-or-higher backlog (hard-cut)".
> **Phase 1 is complete and landed.** Pick up at **Phase 2**.

## The plan (what we're executing)

Complete every **medium-importance-or-above** backlog item as a hard-cut program
(no compat shims). Three product calls were settled up front:
- **Scope:** remediation + MED+ fixes only. The big L-effort *feature builds*
  (interactive signing-approval queue, peer telemetry, dashboard router) are
  **out of scope** — they stay in `BACKLOG.md`.
- **Lost-device recovery:** **add** a no-passphrase full-threshold reconstruction
  path (Phase 4), on top of the meter-gating fix.
- **Default peer permissions:** **keep permissive**, document the decision
  (Phase 3) — no behavior change.

Full phase breakdown + critical-file anchors live in the plan file.

## ✅ Phase 1 — COMPLETE (correctness / data-loss)

All landed submodule-commit-then-parent-pointer-bump:
- **1.1 onboard data-loss** — `persistProfileToDashboard` flushSync-commits +
  persists synchronously; a just-onboarded device survives an immediate reload
  (was lost in the 250/500 ms debounce). igloo-pwa `0bd1132` → parent `93d87fa`.
- **1.3 typed inbound failures** — inbound sign/ecdh/onboard failures report their
  true op type (not `ping`) + 3 clippy nits. bifrost-rs `2a3e702` → `6c0a55e`.
- **1.2 resilient restore** — bridge re-bootstraps from packages when a snapshot
  fails WASM restore. igloo-shared `ad12f67`. Plus **browser WASM refresh**
  `a3953cc` (blobs were stale at package v1 w/ removed backup API). Parent
  `ca9bc5a`.
- **Backlog audit + cleanup** (50 → 42) and dead relay-backup test removal
  `12162cb`; H4 verified resolved (typecheck + build).

Per-repo checks were green at commit time (igloo-pwa 43/43, bifrost-rs full
suite + clippy/fmt, igloo-shared 142/142 + WASM exports, both apps typecheck).
**Still owed:** behavioral `make test-demo` over the refreshed WASM — run it as
the holistic Phase-1 gate before/while starting Phase 2.

## ▶ Next: Phases 2–6 (open)

- **Phase 2** — `nostr-tools` → peerDependency of igloo-shared + dedupe/version-
  align across apps (`resolve.dedupe`); install + build + cross-app e2e. HIGH.
- **Phase 3** — security/hardening: socket-path-fallback unit test; igloo-home
  nsec file-save parity; chrome multi-context hardening; document permissive
  default-permissions; fold-in `cargo clippy --fix` on the home backlog.
- **Phase 4** — recovery/onboarding UX: recover-collect meter gate + **add the
  lost-device path**; auto-include the device share; onboard→signer seam refactor.
- **Phase 5** — capability/UX gaps + chrome parity: delete-device/Clear-Credentials;
  dashboard error/empty states; chrome Settings `sections`+`ExportPackageModal`+
  `PasswordField`; chrome e2e page-object conversion; quarantine-copy prune;
  Diagnostics→Event Log rename.
- **Phase 6** — test/CI: macOS visual/desktop lanes; recover-key desktop smoke;
  flaky export test; verify chrome `@demo` on colima; `pwa-home-pairing` gate-or-
  retire; close the fast≠behavioral gap; automate multi-PWA-tab signature.

## Working notes (the WHY)

- **Who / how:** maintainer **cmdruid** — moves fast, **no new PRs**; commit
  inside the submodule first, then bump the pointer in the parent; proper fixes
  over patches; capture follow-ups in `BACKLOG.md`.
- **WASM on macOS:** Apple `clang` can't target `wasm32`. Build browser WASM with
  Homebrew LLVM: `CC_wasm32_unknown_unknown=/opt/homebrew/opt/llvm/bin/clang
  AR_wasm32_unknown_unknown=/opt/homebrew/opt/llvm/bin/llvm-ar
  PATH=/opt/homebrew/opt/llvm/bin:$PATH npm --prefix repos/igloo-shared run
  build:browser-wasm`. The committed blobs had drifted from the Rust source —
  a stale-WASM CI guard is now a `BACKLOG.md` item.
- **Obsolete context warning:** relay-backup is **gone**; recurring leftovers keep
  surfacing (dead specs, WASM export allowlist). Do not reintroduce kind-10000 /
  `publish_profile_backup` / `bfshare`-from-relay recovery.
- **Resilient restore is fallback-centric:** correctness comes from re-bootstrap-
  on-restore-failure; the version tag is only a deferred fast-path optimization
  (see `BACKLOG.md`), not required.
- **Pre-existing:** `dev/PAPER-SECURITY-RECONCILE.md` shows as ` D` in parent git
  status — predates this work; leave it untouched.

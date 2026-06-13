# Hand-off: MED+ backlog program — Phases 1–2 done, Phases 3–6 open

_Last updated: 2026-06-13_

> **Read this first.** Entry point for a new session in the `frostr-infra`
> workspace. There is an **approved multi-phase plan** in progress:
> "Remediate audit findings + complete medium-or-higher backlog (hard-cut)".
> **Phases 1 and 2 are complete and landed.** Pick up at **Phase 3**.
>
> NOTE: the plan was never written to disk (`plans/enchanted-leaping-papert.md`
> does not exist — the only git reference is the commit that mentions it). This
> hand-off's phase breakdown below is the sole surviving record of the plan.

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
Phase-1 holistic gate **done**: `make test-demo` green over the refreshed WASM
(chrome demo-harness signs end-to-end; the chrome↔home pairing spec stays a
deliberate Linux-only skip).

## ✅ Phase 2 — COMPLETE (nostr-tools single instance)

Collapsed `nostr-tools` to one instance per app and aligned all repos to 2.23.5,
fixing the split module-level singletons (`useWebSocketImplementation` /
`SimplePool`) caused by the no-hoist + `preserveSymlinks` layout. Landed
submodule-then-pointer:
- **igloo-shared `345e4ac`** — `nostr-tools` `dependency` → `peerDependency`
  (+ devDep for its own vitest), floor `^2.23.3`.
- **igloo-pwa `8d875fd`** — `resolve.dedupe` adds `nostr-tools` (shared by app
  build + vitest via `vite.resolve.ts`); align `^2.23.3`. pwa is the real 2-copy
  case (it imports `nostr-tools/nip49`/`nip19` directly *and* via igloo-shared).
- **igloo-chrome `d97ef04`** — esbuild has no `dedupe`, so an `onResolve` plugin
  re-runs esbuild's resolver anchored at the package root (defers to
  `build.resolve`, preserving browser export conditions); vitest `dedupe` mirror;
  align 2.17.2 → `^2.23.3`. Chrome had no *direct* import (all nostr-tools usage
  is transitive via igloo-shared), so its real fix was the version align; the
  plugin makes chrome's declared dep authoritative + forward-proofs.
- Parent pointer bump **`b7e4a75`**.

Validation: unit + typecheck green (shared 142/142, pwa 43/43, chrome 95/95),
app builds clean, a chrome esbuild **metafile probe** confirmed single-copy
resolution, cross-app `make test-fast` green (pwa 20, chrome 17). Follow-up
logged: pre-existing high-sev **esbuild** advisory (dev-tooling, not runtime) in
`BACKLOG.md`.

## ▶ Next: Phases 3–6 (open)

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

# Hand-off: transition the "recovery" feature across the FROSTR app ecosystem

_Last updated: 2026-06-12_

> **Read this first.** This is the entry point for continuing the recovery-feature
> transition in the `frostr-infra` workspace. It assumes zero prior context.

## ✅ Status: COMPLETE (2026-06-12)

The transition is **finished across the whole workspace** — the "What's pending"
section below is now historical. Native hosts reworked and the dead core code
removed:

- **igloo-shell** (`f1b6c73`, lockfile `9610465`): backup-publish removed; `recover` →
  `recover-key` (local nsec reconstruction, written `0o600`); `rotate-keyset generate`
  sources its group package from the local profile. No relay.
- **igloo-home** (`12119f8`, lockfile `e815954`): backup-publish + bfshare device-restore
  removed; new `recover_group_key` command + recover-key UI (reuses igloo-ui
  `RecoverCollectSharesPanel`); rotation sources its group from the local profile's
  plaintext `group_ref`. "Restore a lost device" = `bfprofile` import.
- **bifrost-rs** (`1ad615c`): deleted `bifrost-profile` `flows/{backup,recovery}.rs`, the
  `native-relay` feature + its deps, `ProfileBackupPublishResult`; deleted the
  `frostr-utils` backup helpers, kind-10000 constants, `EncryptedProfileBackup*`, and the
  backup-only NIP-44 wrappers (they were *not* reused beyond backup — the canonical cipher
  + KATs stay in `bifrost_core::nip44`). This silences the lingering "failed to publish
  encrypted profile backup" warning at its source.

Parent pointer bumps: `528be2a`, `67ca114`, `32dbcd7`, `5bc0ec6`. Validation: all repos
green (bifrost-rs check/clippy/fmt + full test suites; shell CLI+integration; home rust +
frontend tsc/vitest; shell+home re-confirmed compiling against the cleaned bifrost-rs).
Remaining: only the lower-priority follow-ups in `dev/BACKLOG.md` (#4 below).

## TL;DR

FROSTR **dropped the relay-published "encrypted profile backup" feature**. We are
transitioning every app from the **old model** (recover a device's full profile from a
relay-published backup event keyed by its `bfshare`) to the **new model**: no relay —
reconstruct the **group secret key (nsec)** locally from a **threshold of shares**, and
restore a lost device only by importing its self-contained `bfprofile`. The **browser
clients + shared core are done and committed to `dev`** (igloo-shared, igloo-ui,
igloo-pwa, igloo-chrome), the docs are rewritten, and the dead *browser* WASM backup
bindings are removed. **Next up: the native hosts — `igloo-shell` and `igloo-home` —
still actively use the relay-backup feature; rework them to the new model, then delete
the now-unused `bifrost-profile` flows + `frostr-utils` backup code.**

## The user

- GitHub `cmdruid`; email `cscottdev@proton.me`. A **FROSTR maintainer**, deeply technical.
- **Moves fast, dislikes PR ceremony.** "just merge"; **"don't create any new PRs."**
- Wants **proper fixes, not symptom patches**, and wants the dropped feature's remnants
  **fully removed**. Asks to **watch for tech debt** and capture follow-ups in
  `dev/BACKLOG.md`.
- Works on `dev` branches across all repos. Commit **inside the submodule first**, then
  bump the pointer in the parent. No new PRs — `dev` branches reference each other by SHA.

## The project

- **FROSTR** = threshold (FROST) signing for Nostr. A Rust core (`bifrost-rs`) compiles to
  WASM and is wrapped by TypeScript `igloo-*` clients. `frostr-infra` is the coordinating
  workspace (shared docs, cross-repo test harness, `Makefile`, submodule pointers under
  `repos/`). Read `AGENTS.md` (always-loaded routing) and **`docs/RECOVERY.md`** first.
- Repos: `repos/bifrost-rs` (Rust core + WASM crates), `repos/igloo-shared` (shared TS
  runtime + WASM loaders), `repos/igloo-ui` (React UI), `repos/igloo-pwa`, `repos/igloo-chrome`,
  **`repos/igloo-home`** (Tauri desktop host), **`repos/igloo-shell`** (Rust CLI / operator host).

### The new recovery model (the WHY)

- **OLD (removed):** every device published an encrypted profile backup as a Nostr
  **kind-10000** event (NIP-44, key domain `frostr-profile-backup/v1`), authored by the
  share-derived pubkey. "Recovery" = decrypt a `bfshare` → derive the author → fetch the
  latest backup event from relays → rebuild the full device profile.
- **NEW:**
  - **Restore a lost device** = import its self-contained **`bfprofile`** (full group
    package + share). A bare `bfshare` can no longer rebuild a device — it carries only
    `{ shareSecret, relays }`, with **no group package and no member index**.
  - **"Recovery"** now = reconstruct the **group secret key (`nsec`)** from a **threshold
    of shares**, fully local: the recovering device contributes its own share (unlocked
    with its passphrase) + the user pastes `threshold − 1` other `bfshare`s; the local
    profile's group package supplies member indices (each share secret → its member by
    pubkey match). **No relay.**
- Canonical spec: **`docs/RECOVERY.md`** (renamed from `BACKUP.md`, 2026-06-12).

## What's been done (all on `dev`, 2026-06-11/12)

**Recovery transition — browser clients + shared core (DONE):**
- **igloo-shared** (`004bc80` and earlier): deleted `src/profile-backup-host.ts`, the
  persistence backup publisher, and the kind-10000 helpers in `profile-package.ts`; stripped
  the `publishBackup` flag from save/persist. Reworked the reconstruction primitives in
  `src/rotation.ts`: `recoverSecretKeyFromShares` and `buildRotationDraft` now take
  `{ groupPackage, shareSecrets }`. Added **`shareWireFromSecret`** (`browser-profile/core/preview.ts`)
  — maps a share secret to `{ idx, seckey }`, **throwing if it isn't a group member** — and
  `groupPackageFromWireJson` (parse a stored profile's group package).
- **igloo-ui**: `RecoverCollectSharesPanel` gained a **device-passphrase** field + bfshare-only
  copy; recover-key view test-ids.
- **igloo-pwa**: `src/lib/local-adapter/profile-generate.ts` `recoverNsecFromShares` (unlock the
  device share + decode pasted bfshares + local group package) and `createRotatedKeyset` (local
  group package, no relay); store + App wiring; **`test/igloo-pwa/specs/recover.spec.ts`** (`@live`,
  asserts the recovered nsec's x-only pubkey == the group key).
- **igloo-chrome**: dropped the `publishBackup` args (import is `bfprofile`-only).
- **Docs**: `BACKUP.md` → `RECOVERY.md`; purged relay-backup mentions across `docs/`; ADR-008
  superseded note.
- **Phase 6 narrow** (`433ef1e` parent; `bifrost-rs 9621d48`): removed the now-dead **browser**
  WASM backup bindings from `bifrost-profile-wasm` + `bifrost-bridge-wasm`, dropped the TS shims
  (igloo-shared `wasm/types.ts` + `wasm/profile-loader.ts`, pwa/chrome test mocks), and re-vendored
  the WASM blobs.

**Other (this session, not recovery):** P1 behavioral `@live` specs (`permissions.spec.ts`,
`settings.spec.ts`); onboarded-device-can't-sign fix; reload self-heal `@live`
(`test/igloo-pwa/specs/sign-reload.spec.ts`).

Validation: `cargo check --workspace` + clippy/fmt; igloo-shared **141** / igloo-pwa **42** /
igloo-chrome **95** unit; full igloo-pwa `@live` lane green; workspace guards green.

## What's pending (priority order) — the next session's focus

1. **Transition `igloo-shell` to the new model.** It still calls `publish_profile_backup`
   (on import/rotation) and `recover_profile_from_bfshare_value` / `preview_bfshare_recovery`
   (relay recovery). Call sites: `repos/igloo-shell/crates/igloo-shell-cli/src/commands/{imports,rotation,profile}.rs`
   + `main.rs`; `repos/igloo-shell/crates/igloo-shell-core/src/shell/rotation.rs`. Drop
   backup-publish entirely; replace relay-recovery with `bfprofile`-import and/or local
   group-key recovery (per call site).
2. **Transition `igloo-home` (Tauri) the same way.** It has a `publish_profile_backup_command`
   Tauri command + `preview_bfshare_recovery` / `recover_profile_from_bfshare_value` in
   `repos/igloo-home/src-tauri/src/{profiles,session,commands,models,bootstrap,test_dispatch}.rs`,
   plus the `ProfileBackupPublishResult` model and the frontend `src/lib/types.ts` type. Rework its
   import/rotation/recovery flows; remove the command, model, and type.
3. **Then delete the now-unused Rust backup code** (only after #1 and #2 stop calling it):
   `bifrost-profile` `src/flows/{backup.rs,recovery.rs}` (+ the `native-relay` feature and
   `tokio-tungstenite` dep in `bifrost-profile/Cargo.toml`), `flows/types.rs`
   `ProfileBackupPublishResult`, the `mod.rs`/`lib.rs` wiring; `frostr-utils`
   `src/profile_packages.rs` backup fns + `PROFILE_BACKUP_EVENT_KIND` (10000) +
   `PROFILE_BACKUP_KEY_DOMAIN` (`frostr-profile-backup/v1`) + the `EncryptedProfileBackup*`
   structs + their unit tests + `frostr-utils/tests/nip44_profile_packages_kat.rs`. This is the
   change that finally silences the lingering **"failed to publish encrypted profile backup"**
   warning. The backlog item "Remove the relay profile-backup feature from the native hosts"
   tracks #1–#3.
4. (Lower, in `dev/BACKLOG.md`) Investigate the onboard-persistence gap (an onboarded profile may
   not persist until a later profile-mutating action); recover-collect UX polish; the export-modal
   confirm-field test flake.

## Critical considerations (the WHY)

- **Two recovery operations are now distinct.** "Restore a lost device" = import a `bfprofile`
  (self-contained). "Recover the key" = reconstruct the group `nsec` from a threshold of shares.
  The old relay "recover a device's profile from its bfshare" is **gone**. When reworking
  shell/home, decide **per call site** which new operation (if any) replaces the old relay path —
  some flows simply become `bfprofile`-import.
- **A bare `bfshare` cannot rebuild a device** (no group package / index). Reconstruction needs a
  group package (from a local profile) + share secrets mapped to member indices. Mirror
  `shareWireFromSecret`: a wrong-keyset paste must fail loudly. The **native** key-reconstruction
  primitive already exists in `frostr-utils` (`recover_key` + `RecoverKeyInput`); use it for
  shell/home rather than the WASM binding.
- **This is a behavior change, not just code deletion.** The relay-backup feature is **load-bearing**
  in shell/home today. The maintainer deliberately scoped the browser/WASM removal "narrow" to keep
  the native-host rework as its own pass. **Confirm the per-call-site behavior with the maintainer
  before reworking** — it's user-facing.
- **No relay, no publish.** Removing `publish_profile_backup` also removes any "degraded recovery
  posture" framing — there is nothing to publish.
- **Keep the shared NIP-44 helpers.** `frostr-utils` `encrypt_nip44_compatible_payload` /
  `decrypt_nip44_compatible_payload` / `hmac_sha256` are reused beyond backup — do **not** delete
  them with the backup fns.
- **Rust commands** (from `repos/bifrost-rs`): `cargo check --workspace --offline`,
  `cargo clippy --workspace --all-targets --offline --no-deps`, `cargo fmt`,
  `cargo test -p <crate> --offline`. After any WASM change: `make browser-wasm-refresh` re-vendors
  the **tracked** blobs into `igloo-shared/pwa/chrome` `public/wasm` — commit them.
- **Submodule workflow**: commit inside the submodule (on `dev`), then bump the pointer in the
  parent. No new PRs.
- **Pre-existing**: `dev/PAPER-SECURITY-RECONCILE.md` shows as a ` D` (deletion) in the parent git
  status — it predates this work; leave it untouched.

## Suggested first action

In `repos/igloo-shell`, map the current recovery/backup surface: read
`igloo-shell-cli/src/commands/{imports,rotation,profile}.rs` and
`igloo-shell-core/src/shell/rotation.rs` to see exactly how `publish_profile_backup`,
`preview_bfshare_recovery`, and `recover_profile_from_bfshare_value` are used in the operator
flows. For each call site decide the new behavior — drop backup-publish entirely; replace
relay-recovery with `bfprofile`-import and/or local group-key recovery (`frostr_utils::recover_key`
from a threshold of decoded `bfshare` secrets + the device's own profile group package). **Confirm
the plan with the maintainer (it's user-facing), then rework.** Mirror the browser approach:
local reconstruction from a threshold of shares using the device's own group package; no relay.

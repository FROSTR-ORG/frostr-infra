# Hand-off: FROSTR recovery transition + follow-ups (COMPLETE)

_Last updated: 2026-06-13_

> **Read this first.** This is the entry point for a new session in the
> `frostr-infra` workspace. The recovery-feature transition that this doc used to
> track is **finished** — there is **no active in-progress thread**. Pick the
> next piece of work from [`dev/BACKLOG.md`](./BACKLOG.md).

## ✅ Status: COMPLETE

The relay-published "encrypted profile backup" feature is **fully removed across
the whole workspace**, and the follow-up clean-ups are done. Nothing is
half-finished; all trees are clean and submodule pointers are in sync.

**The recovery model now** (canonical spec: [`docs/RECOVERY.md`](../docs/RECOVERY.md)):
- **Restore a lost device** = import its self-contained **`bfprofile`**. A bare
  `bfshare` (`{ shareSecret, relays }`) can't rebuild a device.
- **Recover the key** = reconstruct the group **nsec** locally from a threshold
  of shares (`frostr_utils::recover_key`). No relay.
- **Keyset rotation** sources its group package from a **local profile**, not a relay.

## What shipped (with commit refs)

- **2026-06-12 — relay-backup removal** (HISTORY entry): igloo-shell `f1b6c73`
  (`recover-key` CLI command), igloo-home `12119f8` (`recover_group_key` command +
  recover-key UI), bifrost-rs `1ad615c` (deleted `bifrost-profile`
  `flows/{backup,recovery}.rs`, the `native-relay` feature, `frostr-utils` backup
  helpers/constants/structs). Parent bumps `528be2a`/`67ca114`/`32dbcd7`/`5bc0ec6`.
- **2026-06-13 — recovery follow-ups** (HISTORY entry): bifrost-rs `483a74d`,
  igloo-shell `cf2aedb`, igloo-home `f0238e6`, parent bump `9d6d12d`. Added
  home recover/rotate Rust + frontend tests; a `get_profile_threshold` command for
  an accurate recover-key meter; nsec hardening (zeroize-on-drop + redacted Debug +
  clear-on-navigate); the secure no-`/tmp` daemon socket-path shortener
  (`bifrost-app::native_runtime`); a `recover-key` visual scenario. Plan:
  [`plans/great-suggestions-let-s-draft-kind-canyon.md`](./plans/great-suggestions-let-s-draft-kind-canyon.md).

Full detail: [`dev/HISTORY.md`](./HISTORY.md) (2026-06-12 and 2026-06-13 entries).

## Open follow-ups

Curated in [`dev/BACKLOG.md`](./BACKLOG.md). The ones that fell out of this work:
unit-test the `~/.igloo-shell/run` socket fallback (`bifrost-app`); make the
igloo-home visual/desktop lanes runnable on macOS (Linux-only today); clear the
home clippy backlog; recover-key meter member-count; nsec display-vs-file-save parity.

## Working notes (the WHY)

- **Who / how:** the maintainer is **cmdruid** — moves fast, **no new PRs**;
  commit inside the submodule (`dev`) first, then bump the pointer in the parent;
  proper fixes over patches; capture follow-ups in `dev/BACKLOG.md`.
- **Validation per repo:** Rust `cargo check/clippy/fmt` + `cargo test` (offline);
  igloo-home also `npx tsc --noEmit` + `npx vitest run` + `make igloo-home-test-*`.
  The igloo-shell daemon integration suite needs a short `XDG_RUNTIME_DIR` on hosts
  without `/run/user` (the harness now sets one); the `test-server` feature gates
  igloo-home's `test_dispatch`.
- **Obsolete context warning:** older docs/ADRs/comments still mention the relay
  backup model (kind-10000, `publish_profile_backup`, `bfshare`-from-relay
  recovery) — that is **gone**; do not reintroduce it.
- **Pre-existing:** `dev/PAPER-SECURITY-RECONCILE.md` shows as a ` D` in parent git
  status — predates this work; leave it untouched.

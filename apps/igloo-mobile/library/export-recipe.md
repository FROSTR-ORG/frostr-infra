# Export Recipe (Copy Profile / Copy Share)

Bookmark this file alongside `library/user-testing.md`. It is the canonical
recipe for producing real `bfprofile1` / `bfshare1` artifacts and feeding
them into the Load Profile import / recovery flows. It also lists the
proof panels a validator captures without leaking the package bytes,
passwords, decrypted shares, or private key material.

## Goal

Round 2 of the user-testing validator could not test 27 LOAD /
CROSS / SHELL assertions because real `bfprofile1` / `bfshare1`
exports were unavailable. The recipe below reopens every blocked
assertion by driving the same `Copy Profile` / `Copy Share` button a
real user taps:

1. Open a **sign-ready** dashboard profile (typically `bob`).
2. Tap the **Settings** tab → **Copy Profile** → fill the export
   password (twice) → tap **Copy to Clipboard**.
3. The clipboard now holds a real `bfprofile1...` envelope.
4. The same three-step flow on **Copy Share** puts a real
   `bfshare1...` envelope on the clipboard.
5. The artifacts feed the **Load Profile** → Import / Recover flows,
   which round-trip through the same `frostr-utils::decode_*_package`
   path the user-facing UI uses.

## Why a separate recipe

The two product buttons trigger `AppUpdate::ShowExportPasswordPrompt`
followed by `AppUpdate::PerformCopy{Profile,Share}` (iOS)
or `AppUpdate.PerformCopy{Profile,Share}` (Android). The shell reads
the active `OnboardProfileMaterial` (set during profile open /
Onboard / Recover) and emits a `bfprofile1` (full profile) /
`bfshare1` (share-only) bech32m envelope encrypted with the chosen
export password. The envelope carries:

* the share secret (decoded locally),
* the resolved device name (carried via `material.device_name`,
  defaults to `Igloo Mobile` if the active material was authored before
  the field landed),
* the full group package (group pubkey, threshold, every member
  pubkey), so an imported profile reaches signer readiness rather
  than the single-member fallback,
* the profile id,
* the relay list.

The `bfshare1` envelope is a strictly smaller payload (`share_secret`
plus `relays`) and is suitable for `VAL-LOAD-013/019` recovery
verification when a published kind-10000 backup exists for the
share-derived author pubkey.

## Run scripts

Both focused validators require the demo stack and `make demo-onboard`
artifacts:

* iOS relay: `ws://127.0.0.1:8194`
* Android relay: `ws://10.0.2.2:8194`

Run them through the curated command surface:

```bash
just focus-ios-export
just focus-android-export
```

Each script fresh-installs the debug app, injects bob's real
`bfonboard1` package through diagnostics-gated automation, saves the
resolved onboarded profile, exports `bfprofile1` and `bfshare1`, and
pipes each artifact through `apps/igloo-mobile/scripts/verify-export-artifact.sh`.
The verifier calls the Rust `cargo run --example export_decode` path
and emits a redacted proof panel.

The iOS validator reads the simulator clipboard with `xcrun simctl
pbpaste`. The Android validator calls the same FFI export methods and
Android clipboard code as the product prompt, then fetches the
debug-private artifact with `run-as` because Android API 35 rejects
host-side clipboard reads.

To prove the exported artifacts round-trip through Load Profile, run the load
validators immediately after a fresh export:

```bash
just focus-ios-load-artifacts
just focus-android-load-artifacts
```

These validators feed the latest `bfprofile1` into Import and the latest
`bfshare1` into Recover, confirm the loaded profile, and require a native
private-storage proof file containing `stored=yes`. The recovery leg depends
on a published encrypted kind-10000 backup, so it also verifies that the
native `PublishProfileBackup` side effect reads stored material by
`profile_id` and publishes under the share-derived author pubkey.

## Proof panel

The `cargo run --example export_decode` example emits only shape,
length, prefix, type marker, and structural counts — never the raw
package bytes, password, decrypted share secret, share pubkey, or
group pubkey. A successful profile decode prints:

```
[export-decode] kind=profile
[export-decode] decrypted_kind=BfProfilePayload
[export-decode] device_name_present=yes
[export-decode] device_name_length=NN
[export-decode] group_pubkey_present=yes
[export-decode] group_member_count=3
[export-decode] threshold=2
[export-decode] relay_count=1
[export-decode] manual_peer_policy_overrides_count=0
[export-decode] OK: bfprofile1 decoded
```

A successful share decode prints the equivalent proof with
`kind=share` and `share_secret_present=yes`. A wrong password
produces a `FAIL` line and the verifier returns 2.

## Cargo unit tests

`apps/igloo-mobile/rust/tests/export_recipe.rs` proves the export
properties directly against `FfiApp` without running the UI:

* `export_profile_round_trip_preserves_group_members_and_device_name`
  — the bfprofile1 envelope encodes and decodes to the same
  canonical payload, including the resolved device name and the
  full 3-member group roster so a re-imported profile reaches
  signer readiness.
* `export_share_round_trip_rejects_wrong_password` — bfshare1
  decodes with the right password and rejects any other password
  (VAL-SET-015 parity).
* `export_profile_rejects_wrong_password` — bfprofile1 mirrors the
  share rejection guarantee.
* `export_share_secret_matches_material` — bfshare1's share secret
  is byte-identical to the active material (proves the round-trip).
* `export_profile_falls_back_to_default_device_name_when_carrying_empty`
  — legacy material with empty `device_name` (pre-fix) still
  encodes / decodes, falling back to `Igloo Mobile`.
* `export_profile_with_no_active_material_returns_error_marker` /
  `export_share_with_no_active_material_returns_error_marker` —
  the shells see a parseable `error:no_active_profile` marker.

## Reusing the artifacts for VAL-LOAD

After the export, the timestamped evidence directories leave the
`bfprofile1` and `bfshare1` artifacts at:

* `apps/igloo-mobile/library/evidence/mobile-export-artifact-validation-ios-*/clipboard-profile.txt`
* `apps/igloo-mobile/library/evidence/mobile-export-artifact-validation-ios-*/clipboard-share.txt`
* `apps/igloo-mobile/library/evidence/mobile-export-artifact-validation-android-*/clipboard-profile.txt`
* `apps/igloo-mobile/library/evidence/mobile-export-artifact-validation-android-*/clipboard-share.txt`

The focused Load Profile validators write proof under:

* `apps/igloo-mobile/library/evidence/mobile-load-profile-artifacts-ios-*/import-load-proof.txt`
* `apps/igloo-mobile/library/evidence/mobile-load-profile-artifacts-ios-*/recover-load-proof.txt`
* `apps/igloo-mobile/library/evidence/mobile-load-profile-artifacts-android-*/import-load-proof.txt`
* `apps/igloo-mobile/library/evidence/mobile-load-profile-artifacts-android-*/recover-load-proof.txt`

To feed a Copy Profile artifact into VAL-LOAD-005/006/007/008, do
**not** commit the file to git. Inject the contents at runtime
instead:

```bash
# Read the exported bfprofile1 from the evidence directory
PKG="$(cat apps/igloo-mobile/library/evidence/mobile-export-artifact-validation-ios-*/clipboard-profile.txt | tail -1)"
# Feed it to the Load Profile import screen via Maestro's setClipboard
# (in-app paste affordance; the iOS shim handles the Allow Paste dialog)
maestro --device <udid> test flows/load-profile-import.yaml \
  -e BF_PROFILE="$PKG" \
  -e EXPORT_PASSWORD="$EXPORT_PASSWORD"
```

## Secret safety

* Never commit the exported package bytes, the export password chosen
  at the prompt, the decrypted share secret, the share / group
  pubkeys, or any private key material.
* The Cargo example's output intentionally omits substring values
  longer than 50 characters; the verifier script emits only
  length / prefix markers.
* The focus scripts redact any text node >= 50 chars to
  `[REDACTED-Nchars]` while keeping the surrounding hierarchy
  intact so the validator can still confirm the field exists.

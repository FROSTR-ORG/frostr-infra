# mobile-relay-backup-publication-and-recovery-roundtrip

Implementation evidence for the kind-10000 encrypted relay backup
publication and round-trip behavior in `apps/igloo-mobile`. Drives
`VAL-BACKUP-001` through `VAL-BACKUP-006`.

## Scope

Every materialization path in `igloo-mobile-core`
(`OnboardStored`, `LoadProfileStored`, `CreateKeysetAccepted`,
`RotateShareReplace`) now publishes a NIP-44-encrypted kind-10000
backup event to the profile's configured relay. The same crypto
pipeline (`frostr-utils::create_encrypted_profile_backup` +
`frostr-utils::build_profile_backup_event`) the WASM clients and
harness tooling use is reused unchanged — reimplementation is
explicitly out of policy.

The `FfiApp::recover_profile` path was refactored to fetch the
latest matching event from the relay (filtered by the share-derived
x-only pubkey, kind=10000), decrypt it with
`frostr_utils::parse_profile_backup_event`, and rebuild the full
multi-member `OnboardProfileMaterial` so the round-trip from create
or onboard to recover closes cleanly across `bfshare1`.

## Files Touched

| File | Why |
| --- | --- |
| `apps/igloo-mobile/rust/Cargo.toml` | adds `tokio-tungstenite` + `futures-util` for direct WebSocket publish against the demo relay |
| `apps/igloo-mobile/rust/src/lib.rs` | new `BackupPublishResult` UniFFI record; new combined side-effect variants for create + rotate; new `FfiApp::publish_backup` method; reworked `recover_profile` to fetch from the relay |
| `apps/igloo-mobile/rust/src/state/dashboard.rs` | surfaces the last backup publish result via `BackupPublishStatus` on the dashboard |
| `apps/igloo-mobile/rust/src/actions.rs` | `BackupPublishCompleted` action to mirror publish results into the dashboard |
| `apps/igloo-mobile/rust/src/updates.rs` | four materialization handlers now emit the publish side-effect |
| `apps/igloo-mobile/rust/tests/rotate_share_flow.rs` | updated to expect the combined `ReplaceProfileFromRotateAndPublishBackup` side-effect with `source="rotate"` correlation |
| `apps/igloo-mobile/rust/tests/backup_publication_and_recovery.rs` (new) | 4 unit tests covering the encryption envelope and the bfshare1/bfonboard1 sanity paths; 3 live `#[ignore]`'d integration tests covering publish + relay query + round-trip recovery |
| `apps/igloo-mobile/scripts/verify-relay-backup.py` (new) | black-box Python helper for the validator to replay Nostr REQ filtered by share-derived author + kind=[10000] against the demo relay |

## Unit-test Surface (no relay)

| Test | Verifies |
| --- | --- |
| `kind_10000_event_content_is_encrypted_with_no_plaintext_leak` | VAL-BACKUP-003 leak check |
| `backup_round_trips_through_event_and_share_secret_decrypt` | envelope round-trip via parse + share-secret decode |
| `bfonboard_encode_decode_roundtrip_produces_share_secret` | `bfonboard1` sanity |
| `bfshare_decode_with_wrong_password_returns_decrypt_error` | `bfshare1` negative path |

Captured log: [`unit-tests.log`](./unit-tests.log) — `4 passed; 0 failed`.

## Live integration-surface (gated behind `--ignored`)

| Test | Verifies |
| --- | --- |
| `live_relay_is_reachable_diagnostic` | relay reachable at `ws://127.0.0.1:8194`; baseline probe |
| `live_relay_publish_backup_creates_kind_10000_event_with_share_author` | VAL-BACKUP-001 + VAL-BACKUP-002: relay-side filtered proof that a freshly-published event from this app appears, with the share-derived author (`event.pubkey` is the x-only compressed share pubkey) |
| `live_relay_published_backup_round_trips_via_bfshare_recovery` | VAL-BACKUP-005: `FfiApp::recover_profile` from a freshly-minted `bfshare1` against the live relay rebuilds the originating `OnboardProfileMaterial` |

Captured log: [`live-tests.log`](./live-tests.log) — `3 passed; 0 failed`.

## Validator Replay Path

```bash
# from the host (or change --relay for android emulator's 10.0.2.2:8194)
apps/igloo-mobile/scripts/verify-relay-backup.py \
    --author <64-char share-derived pubkey> \
    --mode latest

# exit code:
#   0 -> at least one matching event
#   1 -> no events (assertion would fail)
#   2 -> relay unreachable
#   3 -> relay NOTICE / unexpected error frame
```

The script connects to the relay with the same JSON protocol
(`["REQ", sub_id, {"authors": [...], "kinds": [10000]}]`) the test
harness uses, so validator-side replay matches the in-app publish
behavior byte-for-byte.

Latest captured relay query:

[`relay-req-share-author.txt`](./relay-req-share-author.txt) —
`matched_events=8` for the bob-style share-derived author; this count
grows each time the live test publishes.

## Side-effect → Source Correlation

The combined side-effects carry an immutable `source` tag the
dashboard mirrors so a validator trace can correlate the state-based
proof with the originating flow:

| Materialization source | Side-effect variant |
| --- | --- |
| `onboard` | `PublishProfileBackup` (independent of signer) |
| `import` | `PublishProfileBackup` |
| `recover` | `PublishProfileBackup` |
| `create` | `StartKeysetSignerRuntimeAndPublishBackup` (combined: signer start + backup publish) |
| `rotate` | `ReplaceProfileFromRotateAndPublishBackup` (combined: storage swap + backup publish under the new share's derived author) |

The dashboard's `last_backup_publish.source` always matches the
table above; the existing rotate-share test was updated to enforce
the correlation explicitly.

## Crypto Provenance

- `create_encrypted_profile_backup(&BfProfilePayload) -> EncryptedProfileBackup`
  derives an AES-256 key from NIP-44-style ECDH between the device's
  ephemeral key and the share's `xonly_pubkey`, then encrypts the
  canonical payload under NIP-44 v2. The share secret itself never
  crosses the encryption boundary as plaintext.
- `build_profile_backup_event(share_secret, &encrypted, created_at)`
  embeds only the encrypted blob plus a NIP-44 `tag[pubkey]` marker;
  the resulting Nostr event is signed by the share's NIP-43
  schnorr key over the canonical NIP-01 preimage.
- `parse_profile_backup_event(share_secret, &event)` is the
  inverse and is what `FfiApp::recover_profile` consumes; it
  reconstructs the original `BfProfileDevice` and
  `GroupPackageWire`.

The unit-test `kind_10000_event_content_is_encrypted_with_no_plaintext_leak`
asserts that the resulting `event.content` does not start with `{`,
does not contain the canonical `bfonboard1` prefix, does not
contain the share secret hex, does not contain the device name, and
does not contain any `ws://`/`wss://` URL in cleartext.

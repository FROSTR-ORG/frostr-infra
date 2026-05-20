# FROSTR Workspace Audit — Synthesis

Date: 2026-04-22

Scope: cross-cutting synthesis of the seven per-repo audits completed on 2026-04-22
and a follow-up reference to the 2026-04-02 `igloo-chrome` audit. Source reports:

- [`frostr-infra-audit-2026-04-22.md`](./frostr-infra-audit-2026-04-22.md)
- [`bifrost-rs-audit-2026-04-22.md`](./bifrost-rs-audit-2026-04-22.md)
- [`igloo-shell-audit-2026-04-22.md`](./igloo-shell-audit-2026-04-22.md)
- [`igloo-shared-audit-2026-04-22.md`](./igloo-shared-audit-2026-04-22.md)
- [`igloo-home-audit-2026-04-22.md`](./igloo-home-audit-2026-04-22.md)
- [`igloo-pwa-audit-2026-04-22.md`](./igloo-pwa-audit-2026-04-22.md)
- [`igloo-ui-audit-2026-04-22.md`](./igloo-ui-audit-2026-04-22.md)
- `../reports/igloo-chrome-audit-2026-04-02.md` (prior; not re-audited this pass)

## Framing

FROSTR's cryptographic core (`bifrost-rs`) is competent at the primitive
level — FROST invariants, threshold gating, `OsRng`-sourced nonces, and strict
wire validation are all in place. The problems surface at the *seams*: (1)
secret material escapes its encryption envelope almost everywhere it flows
after signing — plain `String`/`Vec` buffers, plain `localStorage` records,
plain DOM text, plain `/proc/*/cmdline`, plain world-readable files; (2) the
defenses that are supposed to prevent tampering with the signer core itself
(CSP, SRI, container privilege, daemon-socket permissions) are either absent
or unenforced; (3) each host has grown a monolithic control-plane file
(2k–4k lines) that reimplements `bifrost-rs` wire shapes locally with `as`
casts, guaranteeing drift; and (4) the adversarial test surface is almost
empty — 5 of 11 `bifrost-rs` crates have no tests at all, and every host's
test suite is happy-path. Across the seven repos there are roughly 93
findings, of which 29 are High, 43 Medium, 21 Low.

Two patterns are specifically worth naming because they recur without
coordination:

- **The "one type zeroizes" pattern.** `bifrost-rs` zeroizes exactly one
  struct (`SharePackage`). `igloo-shell`, `igloo-home`, and `igloo-pwa` then
  each independently carry secret material in plain `String`/`Vec`/`string`
  through their own process or page. No repo has adopted `zeroize`/`secrecy`
  (Rust) or a typed-array `fill(0)` convention (TS). The result is that the
  reconstructed Nostr secret key, the ECDH shared secret, the device
  passphrase, the onboarding password, and the WASM runtime snapshot all
  survive in heap or localStorage long after the caller stops using them.
- **The "monolith per host" pattern.** `bifrost-signer/src/lib.rs` (3,770 l.),
  `browser-runtime-core.ts` (2,189 l.), `igloo-home/src/App.tsx` (1,875 l.),
  `igloo-pwa/src/App.tsx` (1,345 l.) + `store.tsx` (1,147 l.), and
  `igloo-shell/src/shell.rs` (1,062 l.) each own a different slice of the
  same control plane. The prior `igloo-chrome` audit named the same
  pattern in `background.ts` and `extension-runtime-host.ts` 20 days ago;
  none of it has been refactored since.

## Executive Summary — Highest-Signal Cross-Cutting Items

Ordered by "fix first" impact — items touching the cryptographic primitive
layer come before items that only break when a defence-in-depth layer is
bypassed.

### C1. Non-constant-time MAC comparison in one of three NIP-44-style decrypt paths

- [`bifrost-rs` finding 2](./bifrost-rs-audit-2026-04-22.md) — `decrypt_nip44_compatible_payload` uses `!=` while sibling paths use a hand-rolled `ct_eq_32`.
- Direct timing oracle on encrypted profile-backup decrypts. Low effort to fix; the `ct_eq_32` primitive already exists in the same repo twice and should be consolidated through `subtle::ConstantTimeEq`.

### C2. Systemic secret-material-at-rest leakage across the entire stack

- [`bifrost-rs` finding 1](./bifrost-rs-audit-2026-04-22.md) — `NoncePool.seckey`, full `RecoveredKeyMaterial.signing_key32`, `EncryptedFileStore.key`, `EcdhSharedSecret` all non-zeroizing.
- [`igloo-shell` findings 1 + 3 + 4](./igloo-shell-audit-2026-04-22.md) — ciphertext files + daemon metadata + socket paths written with default umask; passphrase propagated via inherited env var (`/proc/<pid>/environ`); passphrase carried in plain `String` with many `.clone()` sites.
- [`igloo-home` finding 6](./igloo-home-audit-2026-04-22.md) — every Tauri command input that carries a secret uses plain `String` with `serde::Deserialize`; `zeroize` not a direct dep.
- [`igloo-pwa` finding 1 + 3](./igloo-pwa-audit-2026-04-22.md) — cleartext `share_package_json`, `stored_password`, `unlockPhrase`, `runtime_snapshot_json` persisted in `localStorage` under a single key; `stored_password !== unlockPhrase` is plain string equality.
- [`igloo-shared` findings 3 + 4 + 7](./igloo-shared-audit-2026-04-22.md) — raw WASM completion envelope passed to a substring-based deny-list redactor; `prepareOperation` timeout throws `JSON.stringify(readiness)` into an `Error.message`; secret-key-name detection is substring-match only.
- [`igloo-ui` finding 2](./igloo-ui-audit-2026-04-22.md) — `nsec`, hex signing keys, raw share JSON, and onboarding payloads rendered as plain DOM text with no reveal gate or masking primitive.

**Common root cause:** no single convention for "what is secret" and no
enforced wrapper type. A `bifrost-core::secret` module (Rust) plus an
`igloo-shared::secret` module (TS) with matching naming, combined with an
allow-list redactor keyed off the type, would close five unrelated findings
in one pass.

### C3. Local-UID privilege-escalation chain in `igloo-shell` + `bifrost-app`

- [`igloo-shell` findings 1 + 2 + 3](./igloo-shell-audit-2026-04-22.md) combined with [`bifrost-app::host::daemon`](./igloo-shell-audit-2026-04-22.md) code in `bifrost-rs`.
- Default umask leaves `daemon.json` world-readable → token is the predictable `daemon-<profile_id>-<unix_secs>` → Unix socket has no `chmod 0600` → token compare is non-constant time → passphrase is available in `/proc/<pid>/environ` regardless. Any local process in the same UID can drive `Sign`, `Ecdh`, `WipeState`, `SetPolicyOverride` without the passphrase.
- Single-repo fix landscape overlaps `bifrost-app`: socket perms and token compare live there; file modes and env-var handoff live in `igloo-shell`. Coordination is required.

### C4. Defence-in-depth at the browser / desktop shell boundary is effectively absent

- [`igloo-pwa` finding 2](./igloo-pwa-audit-2026-04-22.md) — no CSP, no SRI, no COOP/COEP; WASM loaded via same-origin fetch with no integrity.
- [`igloo-home` finding 1](./igloo-home-audit-2026-04-22.md) — `"csp": null` in `tauri.conf.json`; no updater endpoint/key.
- [`igloo-home` finding 3](./igloo-home-audit-2026-04-22.md) — Tauri `capabilities/default.json` uses `core:default` + `dialog:default` + `autostart:default` with no narrowing, and no `fs` scope.
- [`igloo-shared` finding 5](./igloo-shared-audit-2026-04-22.md) — WASM loader is a `/* @vite-ignore */` dynamic import of a host-supplied URL with no integrity contract.
- [`igloo-pwa` finding 9](./igloo-pwa-audit-2026-04-22.md) — `scripts/sync-bridge-wasm.mjs` is a plain `fs.copyFile`; no digest captured at sync time.
- [`igloo-home` finding 2](./igloo-home-audit-2026-04-22.md) — the `IGLOO_HOME_TEST_MODE` TCP server exposes the full command dispatcher on loopback with no token or handshake.

The WASM blob is the single most security-critical binary in the product and
has no integrity gate anywhere along its path from `bifrost-rs` build output →
`igloo-shared` sync → host public dir → browser fetch.

### C5. Workspace-level container and scratch hygiene

- [`frostr-infra` finding 1](./frostr-infra-audit-2026-04-22.md) — demo containers run as root, mount `repos/` `:rw`, and `chmod 0777` onboarding artifacts.
- [`frostr-infra` finding 2](./frostr-infra-audit-2026-04-22.md) — `.env.example` advertises a retired `igloo-server` / `igloo-web` / `igloo-cli` stack with `IGLOO_SERVER_ADMIN_SECRET=change-me`; the legacy-surface guard does not scan `.env.example`.
- [`frostr-infra` finding 3](./frostr-infra-audit-2026-04-22.md) — CLAUDE.md and CONTRIBUTING.md forbid `data/` but `data/.gitkeep` is tracked and `data/test-harness/` exists on disk at 0777; the legacy-surface guard's allow-list silently whitelists the exact path it claims to forbid.

These are workspace-process issues, not protocol issues, but they frame the
posture of the rest of the system: "secure defaults" is not how the demo
harness and local scratch are configured.

### C6. Correlation and request-id discipline in the TS runtime

- [`igloo-shared` finding 2](./igloo-shared-audit-2026-04-22.md) — pending `sign`/`ecdh`/`ping` completions are matched by *kind*, not by `request_id`. The bridge envelope already carries `request_id` everywhere; the TS side simply isn't using it. A stale completion (peer that answered late, runtime that cancelled after JS timeout) can resolve the next command with the wrong result.
- [`igloo-shared` finding 4](./igloo-shared-audit-2026-04-22.md) — timeout errors stringify the readiness blob into `Error.message`, which hosts routinely log un-redacted.
- [`igloo-shared` finding 10](./igloo-shared-audit-2026-04-22.md) — `bfonboard` envelope validation post-decrypt is shape-only; no TS-side check that `group.members` is consistent with the authorized onboarding peer. Delegates adversarial validation to the WASM layer without contract comments.

C6 is a correctness concern more than a security concern, but one of the
three items (finding 2) is a latent "sign the wrong thing under race"
hazard in a signer.

### C7. Adversarial / KAT test coverage is absent at the crypto layer

- [`bifrost-rs` finding 3](./bifrost-rs-audit-2026-04-22.md) — `bifrost-core`, `bifrost-codec`, `bifrost-router`, `bifrost-bridge-wasm`, `bifrost-profile` have **no** `tests/` directories, no property tests, no FROST KATs. The crypto primitives rely entirely on inline happy-path unit tests.
- [`igloo-shell` finding 11](./igloo-shell-audit-2026-04-22.md) — 32 integration tests, none of which cover wrong-passphrase, corrupted ciphertext, partial-write recovery during `remove_profile`/`finalize_rotation_update_import`, or stale `daemon.json`.
- [`igloo-shared` finding 12](./igloo-shared-audit-2026-04-22.md) — no unit tests for `browser-runtime-core.ts` at all; no tests for stale-completion dispatch, adversarial ciphertext reaching `nip44.v2.decrypt`, or redaction invariants.
- [`igloo-pwa` finding 11](./igloo-pwa-audit-2026-04-22.md) — one `App.test.tsx`, mostly happy-path flows; normalizer hides drift.
- [`igloo-ui` finding 9](./igloo-ui-audit-2026-04-22.md) — 6 of 13 flow components tested; 22 primitives untested; no jest-axe; no keyboard-interaction tests.

A FROST implementation with no KAT vectors is the single biggest unfunded
correctness risk in the workspace. Everything else is a question of whether
the code can be trusted to do what the tests say it does — this is a question
of whether the tests cover the thing that matters.

### C8. Monolithic control-plane files in every host

- [`bifrost-rs` finding 10](./bifrost-rs-audit-2026-04-22.md) — `bifrost-signer/src/lib.rs` 3,770 lines (state, policy, readiness, pending, inbound, outbound, I/O encoding all in one file, with the tests co-located at line 2,440+).
- [`igloo-shared` finding 1](./igloo-shared-audit-2026-04-22.md) — `browser-runtime-core.ts` 2,189 lines (WASM bridge, relay I/O, NIP-44, session orchestration, public API, and ~20 `NodeWithEvents` runtime-guard functions).
- [`igloo-home` finding 8](./igloo-home-audit-2026-04-22.md) — `App.tsx` 1,875 lines; locally re-expressed runtime types; event subscriptions + 2-second poll doing the same work.
- [`igloo-pwa` finding 5 + 6](./igloo-pwa-audit-2026-04-22.md) — `App.tsx` 1,345 lines + `store.tsx` 1,147 lines; `state` as a memo dep so every consumer re-renders on every state change.
- [`igloo-shell` findings 9 + 10](./igloo-shell-audit-2026-04-22.md) — `shell.rs` 1,062 lines (re-export hub + test suite for five other modules); `main.rs` 900+ lines (clap definitions + parser tests + `unsafe { set_var }`).
- [`igloo-chrome` 2026-04-02 audit](../reports/igloo-chrome-audit-2026-04-02.md) — same pattern in `background.ts` and `extension-runtime-host.ts`.

The shared cause is the absence of typed, versioned runtime-shape exports
from `igloo-shared` (and from `bifrost-rs` WASM bindings). Every host has
rebuilt the same projections locally because there is nowhere else to put
them.

### C9. `bifrost-codec` envelope boundary has no outer-size ceiling

- [`bifrost-rs` finding 4](./bifrost-rs-audit-2026-04-22.md) — `decode_bridge_envelope(raw: &str)` calls `serde_json::from_str(raw)` with no limit on `raw.len()`; per-field string caps are also missing. An authenticated group member (the only party that can reach this path post-NIP-44 decrypt) can DoS a long-running signer with a multi-megabyte inner JSON.

This is the one clearly missing *guard* in the otherwise-strict codec layer.

### C10. `igloo-ui` is leaking host-specific names and runtime policy through the shared surface

- [`igloo-ui` finding 1](./igloo-ui-audit-2026-04-22.md) — `HostShell` and friends ship `igloo-pwa-entry-*` class tokens and the compiled `styles.css` ships matching rules. The "shared" package advertises a product-specific visual.
- [`igloo-ui` finding 4](./igloo-ui-audit-2026-04-22.md) — `NonceBar` hardcodes `20` as the progress-bar denominator (a runtime policy constant living in a shared UI primitive).
- [`igloo-ui` finding 7](./igloo-ui-audit-2026-04-22.md) — shared `styles.css` `@import`s a Google Fonts URL at runtime; every host pays an external network request.
- [`igloo-ui` finding 8](./igloo-ui-audit-2026-04-22.md) — `src/index.ts` re-exports via `export *` over 38 modules.

Each one is small. Collectively, the package surface is broader and more
coupled than the README claims.

## Theme Map

| Theme | Findings |
|---|---|
| **T1. Secret material lifecycle** | `bifrost-rs` 1, 6, 13 · `igloo-shell` 1, 3, 4, 5, 6 · `igloo-home` 6 · `igloo-pwa` 1, 3 · `igloo-shared` 3, 4, 7 · `igloo-ui` 2 |
| **T2. Crypto primitive hardening asymmetry** | `bifrost-rs` 2, 7, 8 · `bifrost-rs` 6 (PBKDF2 pre-digest) · `igloo-shell` 2 (non-CT token cmp) · `igloo-shell` 5 (Argon2 defaults, no AAD) |
| **T3. Defense-in-depth at shell boundary** | `frostr-infra` 1 · `igloo-home` 1, 2, 3 · `igloo-pwa` 2, 9 · `igloo-shared` 5 |
| **T4. IPC and daemon authentication** | `igloo-shell` 2 · `igloo-home` 2 · `igloo-shared` 2 · `igloo-shell` 3 |
| **T5. Wire / envelope validation** | `bifrost-rs` 4 · `igloo-shared` 10 · `igloo-shared` 8 |
| **T6. Test coverage — adversarial & KAT** | `bifrost-rs` 3 · `igloo-shell` 11 · `igloo-shared` 12 · `igloo-pwa` 10, 11 · `igloo-ui` 9 |
| **T7. Monolithic control-plane files** | `bifrost-rs` 10, 11 · `igloo-shared` 1 · `igloo-home` 8 · `igloo-pwa` 5, 6 · `igloo-shell` 9, 10 |
| **T8. Package/module boundary violations** | `igloo-ui` 1, 4, 7, 8 · `igloo-home` 8 (local runtime types) · `igloo-pwa` 5 (local runtime types) · `igloo-shared` 6 (5 overlapping profile-save packages) · `igloo-shared` 14 (hex-helper duplication) |
| **T9. Duplicated helpers across the workspace** | `bifrost-rs` 7 (three NIP-44 copies), 11 (bridge-command surface) · `igloo-shared` 14 · `frostr-infra` 4 (duplicated polling stanzas) |
| **T10. Doc drift from code** | `frostr-infra` 2, 3, 11 · `bifrost-rs` 13 (CRYPTOGRAPHY.md, WIRE.md) · `igloo-shell` 13 (PROFILE.md, BACKUP.md silent on host-local encryption) · `igloo-shared` 13 · `igloo-home` 13 · `igloo-pwa` 12 · `igloo-ui` 11 (CHANGELOG, version) |
| **T11. Panic / `unwrap` / `expect` discipline** | `bifrost-rs` 5, 15 · `igloo-home` 4 (bootstrap + every mutex lock) |
| **T12. Error taxonomy** | `bifrost-rs` 9 (stringly-typed error variants) · `igloo-home` 9 (`Result<T, String>` + regex on messages in the frontend) · `igloo-shared` 4 (Error.message carries structured payloads) |
| **T13. Legacy / dead code** | `bifrost-rs` 12 (`contrib/example` references removed crates) · `frostr-infra` 6 (`test:run-sh` alias, fossil name) · `frostr-infra` 13 (`test/igloo-web/` empty dir) · `igloo-pwa` 7 (dead `startCreateChoice`, orphan view states) |

## Per-Repo Severity Rollup

| Repo | High | Medium | Low | Total | Report |
|---|---|---|---|---|---|
| `bifrost-rs` | 5 | 6 | 4 | 15 | [link](./bifrost-rs-audit-2026-04-22.md) |
| `igloo-shell` | 5 | 6 | 3 | 14 | [link](./igloo-shell-audit-2026-04-22.md) |
| `frostr-infra` | 4 | 7 | 3 | 14 | [link](./frostr-infra-audit-2026-04-22.md) |
| `igloo-shared` | 5 | 5 | 4 | 14 | [link](./igloo-shared-audit-2026-04-22.md) |
| `igloo-home` | 4 | 6 | 3 | 13 | [link](./igloo-home-audit-2026-04-22.md) |
| `igloo-pwa` | 3 | 6 | 3 | 12 | [link](./igloo-pwa-audit-2026-04-22.md) |
| `igloo-ui` | 3 | 6 | 2 | 11 | [link](./igloo-ui-audit-2026-04-22.md) |
| **Totals** | **29** | **42** | **22** | **93** | |

## `igloo-chrome` 2026-04-02 Follow-Up

The extension was audited on 2026-04-02 and not re-audited in this pass. The
three headline findings from that audit were:

1. **High**: `background.ts` is a control-plane monolith that also persists a derived app-state cache.
2. **High**: onboarding lifecycle reporting is misleading (synthetic progress stages), and the failure path contained a real bug (undefined `messageText`).
3. **High**: `extension-runtime-host.ts` is a second monolith with polling, snapshot churn, and repeated state-publication patterns.

This pass did not verify whether any of those findings have been addressed
since 2026-04-02. Given that the same *pattern* (per-host monolith) is
flagged in every other host audited today, a re-audit is likely to find
some or all of those issues still present. Actioning C8 (typed runtime-shape
exports from `igloo-shared`) would be the best cross-cutting way to reduce
the surface for all of them, including the Chrome extension.

## Recommended Prioritization

Grouped by "where the change lives" to minimize coordination cost. Each
bucket lists the findings it closes and which bucket(s) it depends on.

### Bucket A — Crypto primitives (hardening at the lowest layer)
Lives in `bifrost-rs`. No downstream coordination needed.

- A1. Replace `!=` with `ct_eq_32` in `decrypt_nip44_compatible_payload`; then adopt `subtle::ConstantTimeEq` across all three NIP-44 paths. → C1, T2
- A2. Introduce secret newtypes (`SharePrivateKey`, `NoncePoolSecret`, `RecoveredSigningKey`, `EcdhSharedSecret`) with `ZeroizeOnDrop`; drop `Debug`/`Serialize` on secret-bearing types in favor of redacted impls. → C2, T1
- A3. Add outer-size ceiling in `decode_bridge_envelope` plus per-field string caps. → C9, T5
- A4. Replace `.expect()` in `recovery.rs:verifying_key_to_group_pk` with a propagated error. → T11
- A5. Consolidate the three duplicated NIP-44-style cipher stacks into one module. → T2, T9

### Bucket B — KDF / envelope / AD bindings
Lives in `bifrost-profile`, consumed by `igloo-shell` and `igloo-home`.

- B1. Record `argon2::Params` (m/t/p) in `EncryptedProfileRecord`; add AAD binding the envelope to its metadata; bump version byte. → C2, T2
- B2. Document the scheme in `docs/CRYPTOGRAPHY.md` and `docs/PROFILE.md` or a new `docs/HOST-STORAGE.md`. → T10
- B3. Add a KAT test fixture for `derive_package_encryption_key` so the JS/WASM compatible path is pinned. → T2, T6

### Bucket C — Host-local secret hygiene (Rust side)
Lives in `bifrost-app` and `igloo-shell`. Coordinate with Bucket A.

- C1. Generate daemon token from `OsRng`; pass out-of-band (pipe or env inherited then closed); `chmod 0600` on socket, `chmod 0700` on parent; constant-time compare. → C3, T4
- C2. Chmod all `ProfilePaths` dirs `0o700` and all ciphertext / daemon-metadata / log files `0o600`. → C3, T1
- C3. Migrate passphrase handoff off `PROFILE_PASSPHRASE_ENV`; use a pipe the child reads once. → C3, T1
- C4. Introduce `Zeroizing<String>` (or `secrecy::SecretString`) at the CLI prompt and thread it through to decryption. → C2, T1
- C5. Introduce atomic manifest writes (`tempfile::persist`) in `bifrost-profile` and use them everywhere a manifest is replaced; add a rotation-intent journal. → `igloo-shell` 8

### Bucket D — Browser host secret hygiene (`igloo-pwa`, `igloo-shared`)
Coordinate with Bucket A.

- D1. Strip `share_package_json`, `stored_password`, `unlockPhrase`, `generatedKeyset`, `pending*Connection.profile_payload`, and `runtime_snapshot_json` from the `localStorage` persist path. Encrypt any residue with WebCrypto keyed off the passphrase (never the passphrase itself). → C2, T1
- D2. Introduce a TS-side `Secret<T>` wrapper type and a type-aware redactor (allow-list, not substring match). → T1
- D3. Switch completion dispatch to `request_id` correlation; drop kind-only matching. → C6
- D4. Make `stopSession` / `refreshSession` idempotent. → `igloo-pwa` 8

### Bucket E — Browser / desktop shell hardening
Coordinated across `igloo-home`, `igloo-pwa`, `igloo-shared`.

- E1. Set a tight CSP in `tauri.conf.json` (no `null`); set a tight CSP + COOP in `igloo-pwa/index.html` (or serve via headers). → C4, T3
- E2. Narrow Tauri `capabilities/default.json` to the specific permissions actually used; add `fs` scope. → C4, T3
- E3. Require content-integrity (SHA-384) on both WASM blobs; capture at `igloo-shared` sync time and verify at load. → C4, T3
- E4. Gate the `IGLOO_HOME_TEST_MODE` TCP server behind a bootstrap token + `#[cfg(feature = "test-server")]` that is absent in release builds. → C4, T3, T4
- E5. Canonicalize paths in `export_profile_command` / `ListSessionLogsInput` and verify they are inside the scoped root. → `igloo-home` 5

### Bucket F — Workspace hardening
Lives in `frostr-infra`.

- F1. Add `USER` + non-root runtime to both demo Dockerfiles; narrow `repos/*` bind-mount from `:rw` to `:ro` where possible. → C5, T3
- F2. Strip `.env.example` down to the variables `compose.test.yml` actually uses; add `.env.example` to `check-doc-surfaces.sh`. → C5, T10
- F3. Decide whether `data/` exists or not; remove `.gitkeep` + `.gitignore` allow-list if not; extend the legacy-surface guard to match structure, not just content. → C5, T10
- F4. Pin GitHub actions to SHAs; add `permissions: contents: read`; add a `concurrency:` key; use `npm ci` everywhere. → `frostr-infra` 7
- F5. Replace demo-harness JSON parsing in `services/igloo-demo/entrypoint.sh` with a stable CLI contract from `igloo-shell`. → `frostr-infra` 4

### Bucket G — Typed runtime-shape exports from `igloo-shared`
High-leverage, unblocks C8 across every host. Coordinate with `bifrost-rs` WASM bindings.

- G1. Move the inline wire-shape types out of `browser-runtime-core.ts` into a `wire.ts` module; generate or import them from a canonical source next to the WASM bindings. → C8, T7, T8
- G2. Split `browser-runtime-core.ts` into `wasm-bridge-node.ts`, `relay-transport.ts`, `onboarding-transport.ts`, `runtime-pump.ts`, `runtime-api.ts`. → C8, T7
- G3. Export `BrowserBridgeNode` directly; remove the `NodeWithEvents` runtime-guard pattern. → C8, T7
- G4. Expose typed `RuntimeStatus` / `PeerState` / `PendingOp` projections so `igloo-home/App.tsx` and `igloo-pwa/App.tsx` can drop their local re-declarations and `as` casts. → C8, T7, T8
- G5. Collapse the five overlapping `browser-profile-*` packages into one flow per source (`bfprofile`, `bfshare`, `bfonboard`, `rotation`). → `igloo-shared` 6, T8

### Bucket H — Shared UI package boundary
Lives in `igloo-ui`.

- H1. Rename `igloo-pwa-entry-*` class tokens to neutral names; adjust consumers. → C10, T8
- H2. Introduce a `SensitiveField` / `SensitiveTextarea` primitive; default `nsec`, hex keys, raw share JSON, and onboarding payloads to the masked variant. → C2, T1
- H3. Remove `@import url(...)` for Google Fonts from `styles.css`; vendor or leave to the host. → C10, T8
- H4. Replace `export *` barrel with explicit named exports. → C10, T8
- H5. Hoist `NonceBar`'s `20` denominator into a prop. → C10
- H6. Collapse `Modal` and `ConfirmModal` onto one primitive with `role="dialog"`, `aria-modal`, focus trap, return-focus. → `igloo-ui` 5

### Bucket I — Test coverage build-out
Spans every repo. Can run in parallel with Buckets A–H but benefits from Bucket G (typed shapes) first.

- I1. Add FROST-secp256k1-tr KAT fixtures to `bifrost-core/tests/`; cross-check against an independent implementation if available. → C7, T6
- I2. Add `bifrost-codec/tests/wire_fuzz.rs` (arbitrary-driven) for each `TryFrom<*Wire>` impl. → C7, T6
- I3. Add `bifrost-router` integration tests for queue-overflow / dedupe / phase transitions. → C7, T6
- I4. Add `browser-runtime-core.test.ts` covering stale completion dispatch, request-id correlation, redaction invariants, WASM-decode failure. → C7, T6
- I5. Add adversarial CLI tests: wrong passphrase, corrupted ciphertext, partial-write rotation, stale `daemon.json`. → C7, T6
- I6. Add jest-axe + keyboard-interaction tests for every click-dismissible surface in `igloo-ui`. → C7, T6

### Bucket J — Doc coherence sweep
Lives in `docs/` and per-repo READMEs.

- J1. Cross-reference `docs/CRYPTOGRAPHY.md` with the actual `frostr-utils::profile_packages` constants (`SHA-256 pre-digest`, `PBKDF2 600k`, `"sha256" marker`); add a CI check that constants and docs agree. → C5, T10
- J2. Specify `MAX_BRIDGE_ENVELOPE_BYTES` and per-field ceilings in `docs/WIRE.md` once Bucket A (A3) lands. → T10, T5
- J3. Add a "Host-local Encryption" section to `docs/PROFILE.md` covering envelope layout, KDF parameters, AD binding. → T10
- J4. Add a "Runtime integration" section to `igloo-shared/README.md` showing the `configureWasmBridgeLoader` → `createSignerNode` → `connectSignerNode` lifecycle; JSDoc every exported runtime function. → T10
- J5. Reconcile `AGENTS.md` with the full Makefile surface (or shrink the guard to match). → T10
- J6. Re-audit `igloo-chrome` against 2026-04-02 findings; file new findings or close old ones. → C8, T7

## Suggested Sequence

If work is single-threaded, this is the order with the highest marginal
signal per week:

1. **Bucket A** (crypto primitives) — 1 week. Closes C1, C9; half of T1/T2.
2. **Bucket G** (typed runtime-shape exports) — 2 weeks. Unblocks every host;
   closes C8 and most of T7/T8.
3. **Bucket D + E** (browser/desktop shell + secret hygiene) in parallel — 2 weeks.
   Needs G1/G4 before starting D3; can start D1/D2 and E1/E2/E3 immediately.
4. **Bucket C + B** (host-local secrets, KDF/AD) — 2 weeks. Can start in parallel
   with D/E.
5. **Bucket F** (workspace hardening) — 3 days. Low-risk, decoupled.
6. **Bucket H** (UI primitives) — 1 week. Depends on nothing.
7. **Bucket I** (tests) — ongoing, 1 engineer-month. Benefits from G first so
   shapes are typed.
8. **Bucket J** (docs) — running alongside each feature bucket.
9. **igloo-chrome follow-up** — 2 days of re-audit, then folds into the appropriate
   bucket above.

## What This Audit Did Not Cover

- `cargo audit` / `npm audit` against registries — noted as a recommendation, not performed.
- Fuzzing or property-based testing against real inputs — several findings call for adding this but no fuzzing was done during the audit.
- `igloo-paper` (reference-only; submodule uninitialized in the working tree).
- Live `igloo-chrome` re-audit — the 2026-04-02 audit is the most recent source of truth for that repo.
- Tauri updater surface — not configured today (which is itself flagged in `igloo-home` finding 1).
- Production deployment surfaces (CDN headers, release signing, package publication chain). The audit is bounded to what is checked into the submodules.
- Any kind of penetration testing, network probing, or live attack against a running demo harness.

## Bottom Line

The cryptographic primitives are individually solid. The product around them
is not yet built to protect what those primitives guarantee: the reconstructed
key escapes the signer, the passphrase escapes the host, the share JSON
escapes to `localStorage` and to the DOM, the WASM blob reaches the browser
without integrity, and every host has a giant file that re-expresses
`bifrost-rs` shapes by hand. Fixing C1 and C2 first, then G (typed exports
from `igloo-shared`), then C4 (CSP + SRI + Tauri capabilities) eliminates
most of the highest-severity findings and removes the structural conditions
that caused them to accumulate.

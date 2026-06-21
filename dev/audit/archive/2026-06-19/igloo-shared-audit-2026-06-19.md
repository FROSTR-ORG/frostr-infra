# `igloo-shared` audit

Date: 2026-06-19

Scope: `/Users/cscott/Repos/frostr/frostr-infra/repos/igloo-shared` (all `src/**`
TypeScript, `wire/`, `browser-profile/**`, `wasm/**`, README/CHANGELOG; tests
read for coverage, not audited for style). Cross-repo `PeerPolicy` /
`toErrorMessage` / `shareSecret` patterns checked against `igloo-ui`,
`igloo-pwa`, `igloo-chrome`. `npx tsc --noEmit` runs clean (exit 0); `bunx`
script-runner aside, the type surface is honest, so this pass spends its effort
on structural and semantic quality, not surface metrics.

`igloo-shared` is the TypeScript runtime layer between the bifrost WASM bridge
and the `igloo-*` hosts. Its dominant shape is healthy: the package was
deliberately de-`export *`'d into an explicit barrel (`index.ts`), the wire
shapes were extracted into a `wire/` module, and the 2026-06-13 High-severity
crypto finding (NIP-44 conversation-key KDF) was fixed and over-delivered with a
real interop test. The debt that remains is concentrated and durable: one
1656-line god class (`BrowserBridgeNode`) that every host's signing path routes
through and whose four bootstrap modes + pump + command-chain share one mutable
`this`; a `Secret<T>` discipline that was threaded into the onboarding flow but
stops dead at the rotation/recovery and snapshot-wire surfaces (bare
`shareSecrets: string[]`, `seckey: string`); the same low-level helper
(`toErrorMessage`, `normalizeHex32`, `hexToBytes`, `normalizeRelays`) defined 2–3
times with divergent semantics; a `PeerPolicy` type that collides by name with a
structurally-different one in `igloo-ui` and is produced via `as` casts; and a
README that documents an export (`recoverProfileFromSharePackage`) and a doc
(`BACKUP.md`) and a crate (`frostr-utils`) that do not exist. None of these are
on fire; all of them are the kind of debt that makes the next change to the
signing path slower and riskier than it should be.

## Findings

### 1. High: `BrowserBridgeNode` is a 1656-line god class carrying six separable concerns on one `this`

Rule: `ARC-01` (Architecture & boundaries)

Files:
- `igloo-shared/src/wasm-bridge-node.ts:122-1656` (the class)
- `igloo-shared/src/wasm-bridge-node.ts:365-557` (`connect`, 193 lines)
- `igloo-shared/src/wasm-bridge-node.ts:1399-1544` (`pumpRuntime`, 145 lines)
- `igloo-shared/src/wasm-bridge-node.ts:1177-1360` (`requestOnboardResponse`, 183 lines)

Why this matters:
- This is the single class every host (pwa, chrome, home) drives the signing,
  ECDH, ping, and onboarding paths through — the highest-traffic change surface
  in the package. It grew from 1559 → **1656** LOC since 2026-06-13 (worse, per
  the reconcile pass); the header comment at `:1-12` asserts the concerns "are
  not separable without a behavior-changing rewrite," which is a documented
  waiver but also the exact thing this rule exists to re-test.
- The test net under it is thin relative to its surface: `wasm-bridge-node.test.ts`
  covers construction, the emitter, not-initialized guards, shutdown, the
  connect-error path, and relay-health back-off — but **none** of the four
  bootstrap modes, `signNostrEvent`, `nip44Encrypt/Decrypt`, `pingPeer`, or
  `pumpRuntime`'s completion/failure dispatch. So a seam-cutting refactor cannot
  lean on unit tests; it would lean on `@live`/E2E only.

Smells:
- One file holds: (a) relay lifecycle + health re-probe + visibility back-off
  (`:132-363`), (b) three distinct bootstrap paths — persisted/profile/onboarding
  — inlined into one `connect` (`:365-557`, `:1026-1175`), (c) the onboarding
  relay round-trip (`:1177-1360`), (d) the tick/drain pump (`:1399-1544`), (e)
  the request-id command chain (`:1546-1655`), (f) NIP-44 enc/dec (`:842-874`).
- `connect` at 193 lines and `pumpRuntime` at 145 each exceed the ~60-line
  readability bar (RS-02) and branch four ways on `config.mode` / drain kind.

Streamline:
- Cut along the seams that do *not* share mutable `this` first — they are
  mechanically extractable as pure helpers taking explicit inputs:
  `requestOnboardResponse` (already takes a `decoded` + `pool`, returns a
  result — extract to an `onboarding-relay-roundtrip` module), the
  `runtimeConfig.device` builder (`:414-432`, pure over `signerSettings`), and
  `buildProfileBootstrap` (`:1133-1175`, already pure). Then split `connect`'s
  `mode` switch into three named bootstrap methods (`bootstrapPersisted` /
  `bootstrapProfile` / `bootstrapOnboarding`) so the shared relay/tick setup is
  visible once and each mode reads top-to-bottom. Treat the relay-lifecycle
  cluster (pool, probe, health interval, visibility) as the natural second class
  (`RelayLifecycle`) the node owns rather than is. Payoff: every host's signing
  change routes through this file; risk: high behavior-coupling and event wiring
  (`emit`/`emitLog` side effects throughout `pumpRuntime`), so each extraction
  needs a unit test added as it lands (see finding 6).

### 2. High: `Secret<T>` discipline stops at the onboarding flow; rotation/recovery and the snapshot wire carry bare-string secrets

Rule: `SEC-01` (Security — secret lifecycle)

Files:
- `igloo-shared/src/rotation.ts:78-84` (`buildDistinctShareWires(…, shareSecrets: string[])`)
- `igloo-shared/src/rotation.ts:87-96,150-157` (`buildRotationDraft` / `recoverSecretKeyFromShares` take `shareSecrets: string[]`)
- `igloo-shared/src/rotation.ts:139-173` (`BrowserRecoveredKey { nsec: string; signingKeyHex: string }` returned bare)
- `igloo-shared/src/rotation.ts:131-135,189,212` (rotated `shareSecret: string` flows into payloads/onboard encode)
- `igloo-shared/src/wire/runtime.ts:240,251,262` (`seckey: string` ×2, `shareSecret: string`)
- Contrast — already wrapped: `igloo-shared/src/wire/onboarding.ts:18` (`share_secret: ShareSecretHex`), `wasm-bridge-node.ts:953,967` (`Secret.of(...)`)

Why this matters:
- The onboarding path correctly wraps its crown-jewel share secret
  (`OnboardingDecoded.share_secret: ShareSecretHex`, with a comment at
  `wire/onboarding.ts:16-17` explaining the wrap). But the rotation and
  *recovery* path — which reconstructs the full group nsec from a threshold of
  shares — passes those shares as a plain `string[]` and returns the
  reconstructed `nsec` and `signingKeyHex` as bare strings. Recovery handles
  strictly *more* secret material (the whole signing key, not one share) with
  *less* hygiene than onboarding.
- The asymmetry is the "only one type zeroizes" anti-pattern this rule names: a
  reader threading a secret can't tell from the type whether a given string is
  meant to be redacted/greppable, because the package uses both conventions.
  `Secret<T>` is type-hygiene + log-safety (per `secret.ts:9-41`), not
  zeroization — which is exactly why it's cheap to thread everywhere and
  expensive to leave half-applied.

Smells:
- `recoverSecretKeyFromShares` returns `{ nsec, signingKeyHex }` as bare strings
  with a comment ("shares are never persisted; callers own auto-clearing") that
  pushes the secret-lifecycle contract onto every caller instead of encoding it
  in the type.
- `RuntimeSnapshotWire.bootstrap.share.seckey` and
  `ProfileBootstrapState.shareSecret` are `string`, so the snapshot-restore path
  (`wasm-bridge-node.ts:1035-1040`) reads a raw seckey out of a parsed snapshot
  with no Secret boundary.

Streamline:
- Extend the onboarding precedent: type the rotation/recovery inputs as
  `ShareSecretHex[]` (or a `Secret`-wrapped equivalent) and return
  `recoverSecretKeyFromShares` as a `Secret`-wrapped nsec, forcing an explicit
  `.expose()` at the (single, UI) display site. Decide the snapshot-wire
  `seckey` policy deliberately — either wrap it or write a one-line rationale at
  `wire/runtime.ts:238` for why the persisted-snapshot seckey is exempt. This is
  the cross-cutting half of the gap the reconcile pass flagged at BACKLOG:786.

Cross-repo note: the same bare-`shareSecret: string` surface is consumed
unwrapped by `igloo-pwa/src/lib/local-adapter/profile-generate.ts` and
`igloo-chrome/src/background/router-profiles.ts` — wrapping at the shared
boundary is what would propagate the discipline outward. Mirror into NOTES.md.

### 3. Medium: `toErrorMessage` defined three times with three different signatures and return contracts

Rule: `CQ-04` (Code quality — duplicated logic)

Files:
- `igloo-shared/src/runtime-internal.ts:81` — `toErrorMessage(value, fallback = 'Request failed'): string` (richest: also reads `.error`/`.reason` off records)
- `igloo-shared/src/browser-profile/save/common.ts:14` — `toErrorMessage(error, fallback): string` (fallback *required*, no record-field probing)
- `igloo-shared/src/browser-profile/session-orchestration/warning.ts:3` — `toErrorMessage(error)`: returns **`string | null`** (different contract entirely)

Why this matters:
- Three copies of "coerce unknown error to a message," each subtly different: one
  has a default fallback, one requires it, one returns `null` instead of a
  string. A bug fixed in one (e.g. the `.reason` probing the canonical copy added)
  silently does not reach the other two.
- The reconcile pass found the first two and missed that the
  `session-orchestration/warning.ts` copy returns `null` — confirming the dedup
  map was incomplete. The `null`-returning variant is the most divergent and the
  easiest to misuse.

Smells:
- Same name, same intent, three bodies; the canonical one is already exported
  (`runtime-internal.ts:81`) and importable, so the two private copies are pure
  drift.

Streamline:
- Make the `runtime-internal.ts` version the one home. The `warning.ts` caller
  wants "message-or-undefined for an optional `detail` field" — express that at
  the call site (`?? undefined` on the canonical result) rather than forking the
  helper's return type. Note `runtime-internal` is in-repo-only today; if the
  helper shouldn't widen the public barrel, route the shared copy through an
  internal-utils path rather than re-defining it per subtree.

### 4. Medium: low-level hex/relay helpers (`normalizeHex32`, `hexToBytes`, `normalizeRelays`) each defined twice with divergent behavior

Rule: `CQ-04` (Code quality — duplicated logic)

Files:
- `igloo-shared/src/runtime-internal.ts:110` `normalizeHex32` vs `browser-profile/core/keys.ts:12` `normalizeHex32` (canonical message `Invalid X` vs `Invalid X.` — trailing period diverges error text)
- `igloo-shared/src/runtime-internal.ts:118` `hexToBytes` (validates `^[0-9a-f]+$`, even length) vs `browser-profile/core/keys.ts:3` private `hexToBytes` (delegates to `normalizeHex32`, so silently **only accepts 32-byte** hex)
- `igloo-shared/src/relay-transport.ts:20` `normalizeRelays(): { relays; errors }` vs `rotation.ts:63` private `normalizeRelays()` (throws on empty, returns bare `string[]` — different shape *and* error behavior)

Why this matters:
- These are validation primitives on key/relay material; divergence is a latent
  correctness risk, not just style. `keys.ts`'s `hexToBytes` quietly rejects any
  hex that isn't exactly 64 chars (it routes through `normalizeHex32`), whereas
  the `runtime-internal` one accepts any even-length hex — two functions with the
  same name and opposite acceptance sets.
- `rotation.ts`'s private `normalizeRelays` throws where the canonical one
  collects errors; a caller moving between them gets different failure modes for
  the same input.

Smells:
- Two `normalizeHex32`, two `hexToBytes`, two `normalizeRelays`; the canonical
  ones are exported (`normalizeHex32` is even on the public barrel,
  `index.ts:100`) yet sub-trees keep private re-implementations.

Streamline:
- Collapse to the exported homes. Where a caller genuinely needs the
  throw-on-empty `normalizeRelays` shape (`rotation.ts`), build that on top of
  the canonical `{ relays, errors }` result (`if (errors.length) throw`) rather
  than re-implementing the normalize loop. Fold `keys.ts`'s 32-byte-only
  `hexToBytes` into a clearly-named `hexToBytes32` if the length constraint is
  intended, so the name stops lying about its acceptance set.

### 5. Medium: `PeerPolicy` is a different shape in `igloo-shared` than in `igloo-ui`, and `fetchPeers` produces the ui shape via `as` casts

Rule: `ARC-06` (Architecture — cross-repo contract drift)

Files:
- `igloo-shared/src/wasm-bridge-node.ts:108-113` — `PeerPolicy = { pubkey; send; receive; [key: string]: unknown }` (loose, index-signature)
- `igloo-shared/src/wasm-bridge-node.ts:688-742` — `fetchPeers` builds `{ alias, state, statusLabel, lastSeen, … }` and returns them as `as PeerPolicy` / `as PeerPolicy[]` (`:732,738`)
- `igloo-ui/src/components/ui/peer-list.tsx:7-19` — `PeerPolicy = { alias; pubkey; send; receive; state: StatusState; statusLabel?; lastSeen?; incomingAvailable?; … }` (structured, exported `igloo-ui/src/index.ts:119`)

Why this matters:
- Two packages export a public type with the same name and a structurally
  different (but overlapping) shape. `fetchPeers` clearly intends to produce the
  *ui* shape — it sets `alias`, `state`, `statusLabel`, `lastSeen` — but is typed
  as the loose shared `PeerPolicy`, so the index signature `[key: string]:
  unknown` plus `as PeerPolicy` casts are what bridge the gap. The compiler is
  not checking that `fetchPeers` actually produces the fields the ui consumer
  reads; a field rename in `peer-list.tsx` would not red-flag here.
- This is the canonical "host re-models a shape locally with `as` casts" drift —
  there is no single typed source both sides consume; there are two `PeerPolicy`s
  and a cast in between.

Smells:
- `[key: string]: unknown` on `PeerPolicy` exists specifically to let
  `fetchPeers` attach ui fields the declared type doesn't name.
- `as PeerPolicy` at `:732` and `as PeerPolicy[]` at `:738` paper over the
  shape the function really returns.

Streamline:
- Pick one home for the peer-readiness projection. `igloo-ui` already owns the
  consumer shape and (per the `igloo-ui` reconcile) a `buildPeerReadinessRows`
  projection; the cleanest direction is for `igloo-shared` to return a typed
  `RuntimePeerStatus[]`/permission-state read model and let the ui projection
  build its `PeerPolicy` from that — removing both the index signature and the
  casts. At minimum, rename one of the two `PeerPolicy`s so the collision is
  visible.

Cross-repo note: `PeerPolicy` name collision spans `igloo-shared/src/wasm-bridge-node.ts:108`
and `igloo-ui/src/components/ui/peer-list.tsx:7`; the `igloo-ui` audit's dual
peer-model finding is the other half of this. Mirror into NOTES.md.

### 6. Medium: the bridge node's core orchestration (connect/sign/ecdh/ping/pump) has no unit coverage — only happy paths through KDF and dispatch are tested

Rule: `TST-02` (Testing — happy-path-only / adversarial gaps)

Files:
- `igloo-shared/src/wasm-bridge-node.test.ts` (9 tests: construction, emitter, guards, shutdown, connect-error, relay-health — no command/crypto/bootstrap path)
- `igloo-shared/src/nip44-interop.test.ts` (covers the KDF + `nip44.v2` round-trip, **not** the node's `nip44Encrypt/Decrypt` orchestration over the WASM ECDH command)
- `igloo-shared/src/wasm-bridge-node.ts:842-874` (`nip44Encrypt/Decrypt` — untested), `:819-840` (`signNostrEvent` — untested), `:1399-1544` (`pumpRuntime` failure/stale dispatch — untested at this layer)

Why this matters:
- The crypto *primitive* is well-tested: `nip44-interop.test.ts` proves the
  conversation-key KDF matches nostr-tools both directions, and
  `bridge-dispatch.test.ts` proves request-id correlation rejects stale
  completions. But the node methods that *orchestrate* those primitives — gate on
  readiness, run the ECDH bridge command, derive the key, encrypt — have no unit
  test; they're covered only by `@live`/E2E (which the reconcile pass notes is
  the render-only `@fast` lane's blind spot). The adversarial paths
  (`signNostrEvent` verify-fail at `:835`, ECDH command rejection, ping timeout,
  `pumpRuntime` failure-drain rejecting a pending sign at `:1522-1534`) are
  exactly the security-relevant failure paths this rule targets, and none are
  asserted.

Smells:
- The two strongest tests in the package sit *beside* the node, not *on* it —
  the dispatch logic was extracted to `runtime-pump.ts` to be testable, but the
  node's use of it is not exercised.
- No test asserts what `nip44Encrypt` does when the ECDH command rejects, or
  what `signNostrEvent` does when `verifyEvent` returns false.

Streamline:
- This finding is the safety net finding 1's refactor needs. As each seam is
  extracted (onboarding round-trip, bootstrap modes, the device-config builder),
  add a focused unit test for its failure path — they become testable precisely
  because extraction gives them explicit inputs. Prioritize the ECDH-reject and
  sign-verify-fail paths since they are the security-relevant ones.

### 7. Medium: README documents an export, a doc, and a crate that do not exist

Rule: `DOC-02` (Documentation — README drift)

Files:
- `igloo-shared/README.md:89-90` — "Recovery — `recoverProfileFromSharePackage(...)` reconstructs a profile from a `bfshare` plus the relay backup."
- `igloo-shared/README.md:81-83` — "canonical crypto lives in the `frostr-utils` crate … specified in … `BACKUP.md`"

Why this matters:
- `recoverProfileFromSharePackage` exists nowhere in `src/` (grep: zero hits);
  the actual export is `recoverSecretKeyFromShares` (`rotation.ts:150`,
  `index.ts:323`). "the relay backup" is doubly stale: recovery is relay-free now
  (the backup feature was dropped), so the README documents a removed mechanism.
- `BACKUP.md` does not exist under `docs/`; the `frostr-utils` crate does not
  exist under `repos/bifrost-rs/` (the crate is `bifrost-*`). A new contributor
  following the README to find the recovery API or the crypto spec lands nowhere.

Smells:
- A doc that names a function, a file, and a crate, none of which a reader can
  find — the literal "do exactly what the README says and it fails" case.

Streamline:
- Rewrite the Recovery bullet to `recoverSecretKeyFromShares(...)` reconstructing
  the signing key from a threshold of `bfshare` inputs (no relay), matching
  `rotation.ts`. Repoint the crate/spec references to the crates and docs that
  exist (`bifrost-*`, `docs/CRYPTOGRAPHY.md`). Drop the `BACKUP.md` reference.

### 8. Medium: bifrost-rs device config is re-derived in the host as an inline block of unexplained magic numbers

Rule: `CQ-06` (Code quality — magic values) / adjacent `ARC-03`

Files:
- `igloo-shared/src/wasm-bridge-node.ts:414-432` (`runtimeConfig.device` literal)

Why this matters:
- Half the `device` block is settings-driven via named fallbacks
  (`signerSettings.sign_timeout_secs`, etc., from `signer-settings.ts`), but the
  other half is raw literals with no constant and no comment:
  `ecdh_timeout_secs: 30`, `onboard_timeout_secs: 30`, `max_future_skew_secs: 30`,
  `request_cache_limit: 2048`, `ecdh_cache_capacity: 256`, `ecdh_cache_ttl_secs:
  300`, `sig_cache_capacity: 256`, `sig_cache_ttl_secs: 120`. These are
  protocol/runtime tuning params owned by the signer core, hand-copied into the
  host with no record of where the values came from or whether they must match a
  bifrost-rs default.
- A reader cannot tell which of these are safe to change, which mirror a core
  constant, or why three of them are `30`.

Smells:
- A wall of bare numeric literals inside an object literal; the values that *do*
  have a source (settings) are named, making the un-named ones look accidental.

Streamline:
- Name them as constants with a one-line origin comment (e.g. "matches
  bifrost-rs `DeviceConfig` default" with the source path), or — better, per
  ARC-03 — read them from a single bifrost-rs-owned default the host doesn't
  re-state. At minimum, group the settings-driven and host-fixed fields so a
  reader sees which axis owns each value.

### 9. Low: three `as never` / `as unknown as` casts at the WASM/nostr-tools boundary lack a "why" and bypass shape-checking on drained events

Rule: `CQ-03` (Code quality — type escapes) / `DOC-04`

Files:
- `igloo-shared/src/wasm-bridge-node.ts:412` — `new SimplePool({ enableReconnect: true } as never)`
- `igloo-shared/src/wasm-bridge-node.ts:1410` — `event as unknown as RuntimeEvent`
- `igloo-shared/src/wasm-bridge-node.ts:1428` — `event as unknown as Event`

Why this matters:
- `as never` at `:412` silences the `SimplePool` ctor not accepting
  `enableReconnect` — a real library-typing gap, but undocumented, so a reader
  can't tell if the option is even honored. The two `as unknown as` casts coerce
  a `drain_*` JSON-parse result straight to a typed wire shape after only an
  `isRecord` check — the `isRecord(event)` guard at `:1409`/`:1427` confirms it's
  an object but not that it has the `RuntimeEvent`/`Event` fields the code then
  reads (`.status.readiness`, `.id`).
- These are at a genuine serialization boundary (the rule's pass condition), so
  Low severity — but a double-cast through `unknown` with only a shape-lite guard
  is the kind that hides a real drift if bifrost-rs renames a drained field.

Smells:
- `as unknown as` is the maximal escape hatch; paired with an `isRecord`-only
  guard it asserts a shape it hasn't checked.

Streamline:
- Add a one-line comment at `:412` on the SimplePool option (or drop it if it's
  inert). For the drain casts, narrow with a field-level guard (the package
  already has `completionKind`/`failureRequestId`-style parsers in
  `runtime-pump.ts` — mirror that for runtime/outbound events) so the cast
  follows a real check rather than replacing it.

### 10. Low: no enforced formatter; package version and CHANGELOG frozen at 0.1.0 since 2026-03-27

Rule: `AES-06` (Aesthetics — no enforced formatter) / `DOC-06`

Files:
- `igloo-shared/package.json` (no `prettier`/`eslint` dep or config; no config file in repo root)
- `igloo-shared/package.json:3` (`"version": "0.1.0"`)
- `igloo-shared/CHANGELOG.md:7` (top entry `## [0.1.0] - 2026-03-27`; no `[Unreleased]` accumulating the since-March work)

Why this matters:
- Style is per-author, so the hand-tunable aesthetic findings (vertical rhythm in
  `pumpRuntime`, the device-config block) are doomed to recur and reviews
  re-argue formatting. This is the cross-cutting all-five-targets gap the
  reconcile pass names.
- The package shipped substantial behavior since March (Secret threading, KDF
  fix, the PR29/PR30 barrel + wire + module split) with no version bump and no
  changelog entry — a consumer can't tell from the manifest that anything
  changed. No `[Unreleased]` section is accruing the work.

Smells:
- Zero formatter tooling in a TS package; a CHANGELOG whose newest line predates
  three months of documented PRs.

Streamline:
- Adopt one shared formatter config across the five TS targets (a single
  root-level prettier config the leaves extend) and gate it in `verify`. Open an
  `[Unreleased]` CHANGELOG section and log the KDF fix / Secret threading / module
  split under it; bump the version when the next consumer pulls.

## Summary

| Severity | Count |
|---|---|
| High | 2 |
| Medium | 6 |
| Low | 2 |
| **Total** | **10** |

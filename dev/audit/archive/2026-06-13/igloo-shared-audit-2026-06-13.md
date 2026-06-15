# `igloo-shared` audit

Date: 2026-06-13

Scope: `repos/igloo-shared` — all TypeScript source under `src/`, tests under `src/` and `tests/`, and package-level docs (`README.md`, `CHANGELOG.md`, `TESTING.md`). WASM blobs under `public/wasm/` and `node_modules/` were not audited.

`igloo-shared` is the shared signer runtime and contract layer consumed by every Igloo browser and desktop host. Its dominant concerns are the WASM bridge boundary (loading, calling, and draining `bifrost_bridge_wasm`), the NIP-44 encrypt/decrypt seam, profile packaging, onboarding transport, and a family of browser-profile persistence helpers. The codebase has clearly been through a disciplined refactor (PR29/PR30 extraction of the original monolith), and most of the observable-security machinery (observability allow-list, decrypt budget, typed errors, `Secret`/`SecretBytes` wrappers) is well-considered. The outstanding debt clusters in three places: one broken cryptographic primitive in the ECDH→NIP-44 path, a class that remains too large despite the extraction pass, and secret material that bypasses the wrapper infrastructure that was built for exactly this purpose.

## Findings

### 1. High: NIP-44 conversation-key derivation on the ECDH path uses the wrong KDF

Rule: `SEC-03` (Security — crypto correctness)

Files:
- `repos/igloo-shared/src/runtime-internal.ts:134-145`
- `repos/igloo-shared/src/wasm-bridge-node.ts:757-776` (consume)

Why this matters:
- `nip44Encrypt` and `nip44Decrypt` (the host-facing threshold-ECDH encrypt/decrypt) derive the NIP-44 conversation key via `HMAC-SHA-256(key='nip44-v2', data=hexToBytes(sharedSecretHex32))`. This is wrong in three ways: the algorithm is HMAC not HKDF-Extract; the key and IKM roles are swapped relative to NIP-44; and the input is the hex-encoded string converted to bytes rather than the raw 32-byte EC shared secret.
- NIP-44's `getConversationKey` does `HKDF-Extract(sha256, ikm=sharedX_bytes, salt=b'nip44-v2')`. The bug means any message encrypted by `nip44EncryptWithNode` cannot be decrypted by any standard NIP-44 implementation — not even by the same node using its own `nip44DecryptWithNode`, because the ECDH shared secret for the same pair will hash differently on the outgoing vs. incoming side unless both sides symmetrically use this broken derivation.
- The onboarding path in the same file (line 1107) correctly uses `nip44.v2.utils.getConversationKey(shareSecret_bytes, peerXOnly)`, making the inconsistency visible and suggesting the `deriveConversationKeyFromSharedSecret` helper was authored independently without cross-checking the NIP-44 spec.

Smells:
- `crypto.subtle.importKey('raw', new TextEncoder().encode('nip44-v2'), { name: 'HMAC', hash: 'SHA-256' }, ...)` — 'nip44-v2' is the salt/IKM label in the NIP-44 HKDF-Extract call; using it as the HMAC key reverses the roles.
- Input is `new TextEncoder().encode('nip44-v2')` for the HMAC key, and `hexToBytes(sharedSecretHex32)` as the message — NIP-44 expects the raw EC shared secret as IKM and the label as salt (HKDF-Extract convention).
- No KAT test for `nip44Encrypt`/`nip44Decrypt`; the round-trip (encrypt then decrypt with the same wrong key) would appear to pass even though neither side is NIP-44-compatible.

Streamline:
- Replace `deriveConversationKeyFromSharedSecret` with `nip44.v2.utils.getConversationKey(hexToBytes(sharedSecretHex32), counterpartyPubkey)`, matching the onboarding path on line 1107. The `counterpartyPubkey` must be threaded from the call site into the derivation. Alternatively, if the threshold-ECDH output is already a derived conversation key (not a raw shared secret), document that contract explicitly with a cross-reference to the bifrost-rs ECDH handler.
- Add known-answer tests that verify `nip44Encrypt` output is decryptable by `nip44.v2.decrypt` called independently with the standard key derivation.

### 2. High: `BrowserBridgeNode` remains a 1 559-line god class after the PR30 extraction

Rule: `ARC-01` (Architecture — god file)

Files:
- `repos/igloo-shared/src/wasm-bridge-node.ts:1-1559`

Why this matters:
- Despite the PR30 extraction pass that moved helpers into `runtime-pump.ts`, `onboarding-transport.ts`, `relay-transport.ts`, and `runtime-internal.ts`, the class itself still holds: (a) relay lifecycle (WebSocket probe, SimplePool connect, subscription management), (b) three WASM bootstrap paths (`tryRestoreRuntime`, `bootstrapFromProfilePackages`, onboarding), (c) the tick/drain loop (`pumpRuntime`), (d) the pending-ping dispatch, (e) the bridge-command enqueue/dispatch chain, and (f) NIP-44 encrypt/decrypt using the threshold ECDH path.
- The class has at least six distinct reasons to change: relay transport behavior, WASM bootstrap protocol, ping round-trip semantics, sign/ecdh command serialization, NIP-44 cipher path, and tick/drain scheduling.
- Every other module in the package must navigate the full class to find any one of these concerns; tests of one concern are expensive to write because the class requires mocking the WASM runtime, relay pool, and timer infrastructure together.

Smells:
- `private probeRelayWebSocket()`, `private connectActiveRelays()`, `private subscribeRelayIngress()` — relay concerns not separable from signer state without a behavior-changing rewrite (per the PR30 comment at line 11).
- `private requestOnboardResponse()` — 185-line async function containing its own subscription and promise lifecycle inside the class method.
- `private pumpRuntime()` — 145-line method handling runtime events, outbound publish, completion dispatch, and failure dispatch in one block.

Streamline:
- The `pumpRuntime` method is the most self-contained candidate for extraction: it already delegates to `matchBridgeCompletion`, `parsePingCompletion`, etc. A `RuntimePump` helper that takes a `WasmBridgeRuntimeApi` reference and callback hooks could be exercised without the relay pool.
- The relay subscription/probe lifecycle could become a `RelayPool` wrapper that emits events the node subscribes to, removing the direct `SimplePool` dependency from the class.
- Near-term: split the 145-line `pumpRuntime` and 185-line `requestOnboardResponse` into named private helper classes or free functions, even if they still live in the same file, to make each sub-flow unit-testable.

### 3. High: Share secrets flow as plain `string` throughout; the `Secret<T>` wrapper is unused in production paths

Rule: `SEC-01` (Security — secret material lifecycle)

Files:
- `repos/igloo-shared/src/wire/onboarding.ts:15` (`OnboardingDecoded.share_secret: string`)
- `repos/igloo-shared/src/wire/runtime.ts:170` (`RuntimeSnapshotWire.bootstrap.share.seckey: string`)
- `repos/igloo-shared/src/profile-package.ts:38,51` (`BrowserSharePackagePayload`, `BrowserProfilePackagePayload`)
- `repos/igloo-shared/src/wasm-bridge-node.ts:857,870,991,1067,1072,1086` (share secret usage sites)
- `repos/igloo-shared/src/secret.ts` (the unused wrapper)

Why this matters:
- `Secret<T>` and `SecretBytes` were designed to prevent accidental log leakage and make every secret exposure greppable. The module header is explicit: "Every exposure is greppable and reviewable." Yet `shareSecret` is typed as `string` in every wire type and payload type, and no production call site wraps it in `Secret.of()` or `SecretBytes.fromHex()`.
- The observability allow-list (`observability-schema.ts`) correctly excludes `share_secret` and `seckey` from log payloads, but that is the only active defence. A new `emitLog` call site that accidentally passes the wrong `detail` object would fail closed silently, but a `console.log` call in a future PR would leak the secret with no type-system protection.
- `RuntimeSnapshotWire.bootstrap.share.seckey` and `OnboardingDecoded.share_secret` are passed into WASM (`restore_runtime`, `build_onboarding_runtime_snapshot`, `create_onboarding_request_bundle`) as raw strings across the JS↔WASM boundary, with no attempt to zero the strings afterward.

Smells:
- `Secret` class is exported from `src/index.ts` and is well-designed, but `src/secret.test.ts` is the only file that uses `Secret.of()` or `SecretBytes.fromHex()`.
- `share_secret: shareSecret` appears verbatim at lines 870, 991, and 1090 of `wasm-bridge-node.ts` — the secret is passed around as a plain struct field.
- `rotation.ts:77-84` takes `shareSecrets: string[]` at the public API surface and constructs wire objects from them with no wrapping.

Streamline:
- Apply `Secret<string>` (or `ShareSecretHex`) to the share-secret fields in `BrowserSharePackagePayload`, `BrowserProfilePackagePayload`, `OnboardingDecoded`, and `RuntimeSnapshotWire`. Every call to `.expose()` becomes the greppable audit boundary.
- Apply `SecretBytes` to the byte-array representation used in `requestOnboardResponse` (line 1086) so the bytes are zeroed after the WASM call.
- Note: the boundary at WASM is a true FFI boundary where the JS runtime cannot control memory; document that the WASM call is the terminal exposure and the string is not further propagated beyond that point.

### 4. Medium: `normalizeRelays` is defined twice with divergent semantics

Rule: `CQ-04` (Code quality — duplicated logic)

Files:
- `repos/igloo-shared/src/relay-transport.ts:20-33` (canonical — validates `wss?://`, deduplicates, falls back to defaults)
- `repos/igloo-shared/src/rotation.ts:62-68` (private copy — only trims/filters, throws on empty, no scheme validation, no deduplication)

Why this matters:
- The rotation copy silently accepts `http://` or bare-domain relay URLs that the canonical version would reject. A rotation distribution artifact built with invalid relay URLs would produce onboard packages that fail to connect.
- The two implementations will drift independently; a fix to relay normalization (e.g. enforcing `wss://` in production) must be applied to both or will miss the rotation path.

Smells:
- `function normalizeRelays(relays: string[])` at `rotation.ts:62` — a private function with the same name as a public export from a sibling module, shadowing the import that could have been used.
- `rotation.ts` already imports from `./profile-package`, `./bridge-wasm-runtime`, and `./browser-profile/core`; importing `normalizeRelays` from `./relay-transport` would be one more line.

Streamline:
- Delete the private `normalizeRelays` in `rotation.ts` and use the canonical import from `relay-transport`. If rotation needs a "require at least one" guarantee, add that invariant as a named check on top of the canonical function's output.

### 5. Medium: `hexToBytes` and `normalizeHex32` are duplicated between `runtime-internal.ts` and `browser-profile/core/keys.ts`; `toErrorMessage` is duplicated in `browser-profile/save/common.ts`

Rule: `CQ-04` (Code quality — duplicated logic)

Files:
- `repos/igloo-shared/src/runtime-internal.ts:107-126` (`normalizeHex32`, `hexToBytes`)
- `repos/igloo-shared/src/browser-profile/core/keys.ts:3-18` (private `hexToBytes` and `normalizeHex32`)
- `repos/igloo-shared/src/runtime-internal.ts:78-90` (`toErrorMessage`)
- `repos/igloo-shared/src/browser-profile/save/common.ts:14-20` (private `toErrorMessage`, simpler variant)

Why this matters:
- `normalizeHex32` in `keys.ts` and `runtime-internal.ts` have slightly different error messages (`"Invalid ${label}."` vs `"Invalid ${label}"`), meaning a caller using the wrong version would see inconsistent error text. If the hex-validation regex changes (e.g. adding length checks for different key sizes), it must be fixed in both.
- `runtime-internal.ts` is not part of the public export surface but is importable in-repo. The `browser-profile/core/keys.ts` version could simply import from it.

Smells:
- `browser-profile/core/keys.ts:3`: `function hexToBytes(hex: string)` calls `normalizeHex32` from the same file; there is an identical `hexToBytes` in `runtime-internal.ts:115` that validates with `!/^[0-9a-f]+$/` rather than calling `normalizeHex32`.
- `browser-profile/save/common.ts:14`: `function toErrorMessage(error, fallback)` is a simpler version (no `reason`/`error` field extraction) of the more capable variant in `runtime-internal.ts:78`.

Streamline:
- Move `hexToBytes`, `normalizeHex32`, and `toErrorMessage` from `runtime-internal.ts` into a shared internal utility module (e.g. `src/utils-internal.ts`) and import from there. The `browser-profile/core/keys.ts` and `save/common.ts` copies can then be deleted.

### 6. High: `nip44Encrypt`/`nip44Decrypt` — and the full connect/sign/ECDH path on `BrowserBridgeNode` — have no unit-level tests

Rule: `TST-01` (Testing — core journey not covered)

Files:
- `repos/igloo-shared/src/wasm-bridge-node.test.ts:1-85`
- `repos/igloo-shared/src/wasm-bridge-node.ts:751-777` (the tested-nowhere encrypt/decrypt path)

Why this matters:
- The NIP-44 encrypt/decrypt functions (`nip44Encrypt`, `nip44Decrypt`) have no tests at all — not unit, not integration, not E2E. The KDF bug found in finding 1 would not be caught by any automated check.
- The existing `wasm-bridge-node.test.ts` covers only construction, event-emitter wiring, pre-connect guard clauses, and the unconfigured-loader error path. The entire `connect()` success flow, `pingPeer`, `signNostrEvent`, and `nip44Encrypt`/`nip44Decrypt` are covered only by the cross-repo E2E harness (which requires a real WASM build and relay).
- The `rotation.ts` functions (`buildRotationDraft`, `recoverSecretKeyFromShares`) have only guard-clause tests; no test exercises the successful rotation or recovery path against a mock WASM API.

Smells:
- `wasm-bridge-node.test.ts:13-15` comment explicitly acknowledges "zero direct tests" for the connect + sign round-trip, citing WASM build dependency.
- No `deriveConversationKeyFromSharedSecret` test exists; a KAT (known-answer test) against a reference NIP-44 vector would have caught the KDF error immediately.
- `rotation.test.ts` tests only the "below-threshold" and "wrong-keyset" guard paths; the success path (`buildRotationDraft` returning a valid draft) is untested.

Streamline:
- `deriveConversationKeyFromSharedSecret` / `nip44Encrypt` / `nip44Decrypt` are pure enough to test without WASM: inject a mock WASM bridge that returns a known shared secret hex, then verify the produced ciphertext is decryptable by `nip44.v2.decrypt` with the reference conversation key. Add a KAT against a known NIP-44 test vector.
- For `buildRotationDraft`/`recoverSecretKeyFromShares`, inject a mock `WasmKeysetApi` (the same pattern used in `bridge-dispatch.test.ts` for the bridge module) to test the success path without a real WASM build.

### 7. Medium: README references the removed `recoverProfileFromSharePackage` API and the dropped relay-backup flow

Rule: `DOC-02` (Documentation — README drift)

Files:
- `repos/igloo-shared/README.md:89-91`

Why this matters:
- The README documents a `recoverProfileFromSharePackage(...)` function under "Package flows" that does not exist in the codebase. The workspace memory notes that relay-backup recovery was dropped and recovery is now relay-free, but the README still describes the old relay-backup-based flow.
- A developer following the README's recovery flow would find no matching function and have no guidance on the actual recovery path (which is `recoverSecretKeyFromShares` + local share packages).

Smells:
- `README.md:89`: `recoverProfileFromSharePackage(...)` — no such export in `src/index.ts` or any other module.
- `README.md:90`: "from a `bfshare` plus the relay backup" — relay backup was removed.

Streamline:
- Replace the recovery bullet with a description of the actual current path: `recoverSecretKeyFromShares({ groupPackage, shareSecrets })` reconstructs the signing key from a threshold of local share secrets, with no relay involvement.

### 8. Medium: No enforced formatter (no Prettier/ESLint config)

Rule: `AES-06` (Aesthetics — no enforced formatter)

Files:
- `repos/igloo-shared/package.json` (no `prettier`/`eslint` script or peer dep)
- `repos/igloo-shared/` (no `.prettierrc`, `.eslintrc`, `eslint.config.js`)

Why this matters:
- Without an enforced formatter, style consistency is per-author and re-argued per PR. The code is fairly consistent today, but the absence of enforcement means any inconsistency (import ordering, trailing commas, line-break style) can creep in without a tool catching it.
- The `test:typecheck` gate only checks types, not style; PRs can introduce formatting drift with no automated pushback.

Smells:
- `package.json` has no `lint`, `format`, or `prettier` script entry. The `devDependencies` list only `nostr-tools` and `vitest`.
- The workspace `dev/docs/STYLES.md` references style expectations but there is no tooling to enforce them in this package.

Streamline:
- Add `prettier` as a devDependency and a `.prettierrc` (or `prettier` key in `package.json`), plus a `format:check` script in the CI gate alongside `test:typecheck`.

### 9. Low: Several magic numbers in `connect()` runtimeConfig are unnamed inline literals

Rule: `CQ-06` (Code quality — magic values)

Files:
- `repos/igloo-shared/src/wasm-bridge-node.ts:361-375` (runtimeConfig object)
- `repos/igloo-shared/src/wasm-bridge-node.ts:218,283` (WebSocket probe timeout `3_000`)

Why this matters:
- `ecdh_timeout_secs: 30`, `onboard_timeout_secs: 30`, `max_future_skew_secs: 30`, `request_cache_limit: 2048`, `ecdh_cache_capacity: 256`, `ecdh_cache_ttl_secs: 300`, `sig_cache_capacity: 256`, `sig_cache_ttl_secs: 120` are all unexplained inline values. The WebSocket probe timeout (`3_000`) is duplicated between the probe `setTimeout` and `pool.ensureRelay`.
- These values govern bifrost-rs runtime behaviour (nonce cache size, skew tolerance, operation timeouts) and are likely derived from the bifrost-rs defaults or protocol constraints, but there is no comment or named constant pointing back to the source of truth.

Smells:
- `ecdh_timeout_secs: 30` on line 361, `onboard_timeout_secs: 30` on line 363, `max_future_skew_secs: 30` on line 365 — three undocumented `30`s in adjacent lines with different meanings.
- `3_000` appears on lines 218 and 283 for the WebSocket probe timeout; if one is changed, the other may be missed.

Streamline:
- Extract the cache/timeout constants into a named `RUNTIME_DEVICE_DEFAULTS` object (or individual named constants) in `runtime-internal.ts` alongside the existing `ONBOARD_TIMEOUT_MS`, `PING_TIMEOUT_MS`, etc., with a short comment citing the bifrost-rs setting name or the reasoning for each value.
- Extract the probe timeout into a named constant (e.g. `RELAY_PROBE_TIMEOUT_MS = 3_000`) next to `RELAY_CONNECT_TIMEOUT_MS`.

### 10. Low: Changelog stops at the first entry; version has not moved off `0.1.0`

Rule: `DOC-06` (Documentation — changelog / version hygiene)

Files:
- `repos/igloo-shared/CHANGELOG.md`
- `repos/igloo-shared/package.json:3`

Why this matters:
- `CHANGELOG.md` has a single `[0.1.0] - 2026-03-27` entry. The codebase has clearly seen significant changes since (PR29 barrel re-export curation, PR30 module extraction, PR32 runtime projections, the Secret/SecretBytes security module, the onboarding defences, the observability allow-list). None of these are recorded.
- Consumers (other Igloo repos) cannot tell what changed between a pinned version and the current tip without reading commit history.

Smells:
- `package.json:"version": "0.1.0"` — unchanged since the initial changelog entry.
- `CHANGELOG.md` has no entries after March 2026 despite extensive refactoring visible in PR comments throughout the source files.

Streamline:
- Add `[Unreleased]` entries for each PR-pass (PR29–PR32 plus the security additions). Even a one-line-per-PR summary allows consumers to track what changed without reading raw commits.

### 11. Low: Three undocumented type-escape casts at the WASM boundary

Rule: `CQ-03` (Code quality — type escapes)

Files:
- `repos/igloo-shared/src/wasm-bridge-node.ts:355` (`as never` for `SimplePool` constructor options)
- `repos/igloo-shared/src/wasm-bridge-node.ts:1313` (`event as unknown as RuntimeEvent`)
- `repos/igloo-shared/src/wasm-bridge-node.ts:1331` (`event as unknown as Event`)

Why this matters:
- The two `as unknown as` casts in `pumpRuntime` skip type narrowing on JSON-parsed WASM output after only a shallow `isRecord(event)` guard; a future bifrost-rs schema change could silently produce a differently-shaped `RuntimeEvent` or outbound `Event` without a type error catching it.
- The `as never` on `SimplePool` hides an API mismatch between the `nostr-tools` `SimplePool` constructor type and the `enableReconnect` option the code relies on.

Smells:
- The guards at lines 1312 (`!isRecord(event) || !isRecord(event.status)`) and 1330 (`!isRecord(event)`) are shallow — they do not validate `event.kind`, `event.id`, `event.sig`, etc.
- `as never` is a stronger escape than `as unknown as` and typically signals a type definition is out of date.

Streamline:
- For the `RuntimeEvent`/`Event` casts: add narrower guards or a typed parse function (similar to `parseSignCompletion`) that validates the critical fields before the cast.
- For the `SimplePool` cast: either update the local type augmentation to include `enableReconnect`, or open an issue against `nostr-tools` and add an inline comment with a link.

## Summary

| Severity | Count |
|---|---|
| High | 4 |
| Medium | 4 |
| Low | 3 |
| **Total** | **11** |

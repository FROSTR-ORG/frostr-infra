# `igloo-chrome` audit

Date: 2026-06-13

Scope: `repos/igloo-chrome` (Chrome MV3 extension: background service worker, options/popup pages, content-script provider bridge, WASM runtime host)

`igloo-chrome` is the thinnest of the three client hosts — it has no offscreen document, no Tauri shell, no daemon socket. The signer runtime lives directly inside the MV3 service worker as a WASM node, reached via a well-structured layered stack: `background.ts` → `background/*-service.ts` → `lib/runtime-host/*` → `lib/igloo.ts` (igloo-shared). The overall architecture is sound and the layering is consciously maintained. The dominant debt pattern is narrower than the god-file risk common elsewhere: the big concerns here are (1) an implemented-but-intentionally-broken NIP-04 surface that ships exposed to websites, (2) wildcard postMessage origins at the page-content boundary that allow any co-loaded page script to sniff or spoof provider messages, (3) two parallel implementations of the same `toErrorMessage` / `profileKey` helpers in separate sub-trees, and (4) a test suite that, while impressively broad, has a visible gap for adversarial/wrong-credential paths on crypto flows. Documentation is clean; no dead-code or compat-shim debt was found.

## Findings

### 1. High: NIP-04 methods accepted, routed, and then unconditionally thrown at the crypto layer

Rule: `LEG-03` (Legacy & deprecation)

Files:
- `repos/igloo-chrome/src/extension/provider-types.ts:10-11` — `NIP04_ENCRYPT` / `NIP04_DECRYPT` in `PROVIDER_METHOD` constant and `ProviderMethod` union
- `repos/igloo-chrome/src/nostr-provider.ts:94-109` — `nip04.encrypt` / `nip04.decrypt` implemented in the injected provider
- `repos/igloo-chrome/src/lib/runtime-host/provider-execution.ts:28` — `throw new Error('NIP-04 is not planned for the v2 runtime path')`

Why this matters:
- A website calling `window.nostr.nip04.encrypt()` gets a full permission prompt, the user approves, and then the operation hard-fails with a developer-level error message. This is confusing and arguably misleading to users.
- NIP-04 appears in `isProviderMethod`, `getPermissionLabel`, the stored-permission schema, and the injected provider. Every one of these sites must be coordinated to truly retire the surface — right now retire is the throw but all the wiring remains live.
- Because `ProviderMethod` still includes NIP-04 values, any stored permission record can reference them, and any future caller can attempt them without a type-system error.

Smells:
- A throw with the exact text "NIP-04 is not planned for the v2 runtime path" inside a switch case that otherwise executes real crypto work — this is a placeholder, not a real decision.
- No removal trigger documented anywhere; the CLAUDE.md note says the extension is beta and compatibility layers should not be added, but this is already wired.

Streamline:
- If NIP-04 is permanently dropped, remove the methods from `PROVIDER_METHOD`, `ProviderMethod`, `isProviderMethod`, the `getPermissionLabel` switch, the `nostr-provider.ts` implementation, and the `ExtensionCommandResultByType` map in one coordinated pass. The content-script already validates `isProviderMethod`, so removal there is the cut point.
- If NIP-04 is a future feature, document the trigger (e.g. "re-enable when bifrost-rs NIP-04 lands") and at minimum short-circuit the permission prompt before the flow reaches the throw.

---

### 2. High: `window.postMessage('*')` at the page-content trust boundary

Rule: `SEC-04` (Security — input/envelope validation)

Files:
- `repos/igloo-chrome/src/content-script.ts:57-65` — `window.postMessage({ source: ..., direction: 'provider_response', ... }, '*')`
- `repos/igloo-chrome/src/nostr-provider.ts:36-44` — `window.postMessage({ source: ..., direction: 'provider_request', ... }, '*')`

Why this matters:
- The wildcard target origin `'*'` means responses containing signed events, public keys, or encryption results are broadcast to any frame or co-loaded script on the page. A malicious frame in a cross-origin iframe on the same document, or a page script that loads before the injected provider, can observe all NIP-07 responses.
- Conversely, the `nostr-provider.ts` listener (line 49) validates `event.source === window` and `data.source === EXTENSION_SOURCE`, but the identifier `EXTENSION_SOURCE = 'igloo-chrome'` is a hard-coded well-known string in the published bundle. A page script that knows this string can inject a spoofed `provider_response` back into the pending-request map, resolving an in-flight `signEvent` with arbitrary content before the real content-script reply arrives.
- This is a systemic property of injected NIP-07 providers, but it's worth flagging because the current code has no nonce-based or channel-based mechanism to distinguish legitimate content-script responses from spoofed ones.

Smells:
- `window.postMessage(..., '*')` where a targeted origin or a `MessageChannel` port would be architecturally correct.
- No per-request nonce or sequence number that only the content-script knows.

Streamline:
- Consider replacing the page-script ↔ content-script channel with a `MessageChannel` established at inject time; the content-script holds one port and hands the other to the provider script. All subsequent messages go over the private channel, eliminating both the wildcard broadcast and the spoofing surface.
- If `MessageChannel` is not feasible under MV3, at minimum use `window.location.origin` as the postMessage target instead of `'*'` for same-origin responses.

---

### 3. Medium: `toErrorMessage` and `profileKey` duplicated between `background/utils` and `lib/runtime-host/helpers`

Rule: `CQ-04` (Code quality — duplicated logic)

Files:
- `repos/igloo-chrome/src/background/utils.ts:16-21` — `toErrorMessage` (background layer)
- `repos/igloo-chrome/src/lib/runtime-host/helpers.ts:9-16` — `toErrorMessage` (runtime-host layer)
- `repos/igloo-chrome/src/background/utils.ts:36-51` — `profileKey` (hashes group key + relay list)
- `repos/igloo-chrome/src/lib/runtime-host/helpers.ts:18-20` — `profileKey` (just `profile.id.toLowerCase()`)

Why this matters:
- The two `toErrorMessage` functions have nearly identical logic but are maintained independently. A bug fix or new edge-case (e.g. handling `AggregateError`) must be applied in both places.
- The two `profileKey` functions are semantically different: the background version hashes group public key + relays, the runtime-host version uses only the profile ID. They are both named `profileKey`, so a reader switching contexts can easily conflate them. The background version is used in log messages; the runtime-host version is the session deduplication key. Using the wrong one in either place would silently change behaviour.

Smells:
- Same function name, same file-level export structure, different implementations in sibling sub-trees.
- `toErrorMessage` is imported from two different paths across the source tree (`@/background/utils` vs `@/lib/runtime-host/helpers`), with no structural signal that they are the same concept.

Streamline:
- Factor the shared `toErrorMessage` to a single location (e.g. `src/lib/utils.ts`) and have both layers import from it.
- Rename `profileKey` in `lib/runtime-host/helpers` to `sessionKey` (or similar) to disambiguate it from the background `profileKey`; document each one's deduplication semantics in a comment so callers know which key to use.

---

### 4. Medium: `sessionKeyB64!` non-null assertion at runtime access build — silent failure if key is absent

Rule: `CQ-02` (Code quality — panic/unwrap discipline)

Files:
- `repos/igloo-chrome/src/background/runtime-service/access.ts:26`

Why this matters:
- `buildRuntimeProfile` guards `!activeProfile?.runtimeProfile || !activeProfile.payload` and returns `null` if absent, but does not guard `activeProfile.sessionKeyB64`. The `!` assertion silently casts `undefined` to a non-null type.
- `loadActiveRuntimeProfile` can return a record where `sessionKeyB64` is `null` (locked profile — see `loading.ts:22-26`). The outer guard only checks `runtimeProfile` and `payload`, not `sessionKeyB64`, so a locked active profile could pass the guard and produce a `null` session key type-cast to `string`.
- The caller passes this key to `ensureRuntimeForBuiltProfile`, which passes it to the WASM layer; passing a `null` silently would cause a runtime error deep in the WASM stack rather than a legible service error.

Smells:
- `activeProfile.sessionKeyB64!` without an explicit `if (!activeProfile.sessionKeyB64) return null` guard immediately above it.

Streamline:
- Add `!activeProfile.sessionKeyB64` to the early-return guard (aligned with the existing `!activeProfile.runtimeProfile` check), and remove the `!` assertion. This makes the locked-profile case explicit and returns a `null` build just like any other unavailable profile.

---

### 5. Medium: No enforced formatter (TypeScript / ESLint / Prettier absent)

Rule: `AES-06` (Aesthetics — no enforced formatter)

Files:
- `repos/igloo-chrome/package.json` (no `eslint`, `prettier`, or lint script)
- No `.eslintrc*` or `.prettierrc*` in the directory root

Why this matters:
- Style consistency is enforced only by convention. The codebase is currently quite clean, but per-PR style debates will return as the team grows or as unrelated contributors touch the files.
- The unit test scripts run `tsc --noEmit` but no lint step, so type safety is gated but style is not.

Smells:
- `typecheck:local` runs `bunx tsc --noEmit`, but there is no parallel `lint` or `format:check` script.
- The `test:ci` script chains typecheck → unit tests → E2E → build but skips any formatting gate.

Streamline:
- Add `prettier` (or `biome`) and an `eslint` config at minimum to `devDependencies`, with a `format:check` step in `test:ci`. A `.prettierrc` at the project root is sufficient to prevent future drift.

---

### 6. Medium: Protocol barrel re-exports entire interior — no curation

Rule: `ARC-04` (Architecture — leaky package boundary)

Files:
- `repos/igloo-chrome/src/extension/protocol.ts:1-5` — `export * from` five sub-modules
- `repos/igloo-chrome/src/lib/nip44-normalize.ts:1` — `export * from 'igloo-shared'`
- `repos/igloo-chrome/src/lib/igloo.ts:3-4` — `export * from 'igloo-shared'`
- `repos/igloo-chrome/src/lib/observability.ts:1` — `export * from 'igloo-shared'`
- `repos/igloo-chrome/src/lib/bridge-wasm-runtime.ts:1` — `export * from 'igloo-shared'`
- `repos/igloo-chrome/src/lib/signer-settings.ts:1` — `export * from 'igloo-shared'`

Why this matters:
- `src/extension/protocol.ts` re-exports five full modules. Any symbol added to any of those modules becomes immediately importable from `@/extension/protocol` without the author of `protocol.ts` making a deliberate decision to expose it.
- Five separate files that are each just `export * from 'igloo-shared'` create an artificial aliasing layer. The purpose of each alias file is not clear (`nip44-normalize`, `bridge-wasm-runtime`, `observability`, and `signer-settings` all do the same thing: re-export igloo-shared). This forces a reader to follow an extra hop per import.

Smells:
- `export * from` in a file named after a concern (`nip44-normalize`, `observability`) that does not otherwise narrow or shape the surface.
- Multiple one-liner re-export shims that are indistinguishable from each other.

Streamline:
- For files that are pure igloo-shared re-exports, either consolidate them into one `lib/igloo-shared.ts` alias, or remove the alias and import directly from `igloo-shared`. Reserve per-file aliases for cases where the file adds something (like `configure-igloo-shared.ts` does).
- For `protocol.ts`, consider naming explicit re-exports where possible so the module boundary is visible.

---

### 7. Low: NIP-04 test gap — no adversarial / denied path asserted

Rule: `TST-02` (Testing — happy-path-only coverage)

Files:
- `repos/igloo-chrome/tests/unit/nostr-provider.test.ts` (82 lines, three test cases)
- `repos/igloo-chrome/src/nostr-provider.ts:94-109` — nip04 implementation

Why this matters:
- The `nostr-provider.test.ts` suite tests `getPublicKey` (happy + error), `getRelays` (validation), but does not exercise `signEvent`, `nip04.encrypt/decrypt`, or `nip44.encrypt/decrypt` paths through the provider bridge. These are the crypto-critical paths.
- Because NIP-04 currently throws unconditionally in the runtime, a test asserting the right error shape would also serve as a regression guard if that throw were accidentally removed.

Smells:
- Only three tests in the provider test file, none of them touching the crypto methods.
- `nip44.encrypt` and `nip44.decrypt` in the provider script have identical structure to `nip04.encrypt/decrypt` but are never tested at the bridge level.

Streamline:
- Add provider-bridge tests for `signEvent`, `nip44.encrypt`, and `nip44.decrypt` (at minimum: one success path, one rejection from the extension). Given the NIP-04 finding, also add a test that asserts `nip04.encrypt` produces a legible error (not a silent hang or wrong-shape response).

---

### 8. Low: `snapshot-persistence.ts` retry loop uses bare `setTimeout` with magic delays

Rule: `CQ-06` (Code quality — magic values)

Files:
- `repos/igloo-chrome/src/lib/runtime-host/snapshot-persistence.ts:49-62`

Why this matters:
- The retry loop (`for attempt = 0; attempt < 3`) waits `50 * (attempt + 1)` ms between attempts. The constant `3` (max retries) and `50` (base delay ms) are inline and unexplained. A reader maintaining this code cannot tell whether these were chosen from measurement or guessed.
- This is the hot path that persists WASM runtime nonce state across service-worker restarts. If the retry budget is wrong, onboarding sessions can lose nonce state silently (errors are suppressed by the callers with `suppressErrors: true`).

Smells:
- Two numeric literals `3` and `50` inline in the retry loop with no named constants or comments.

Streamline:
- Extract `SNAPSHOT_PERSIST_MAX_ATTEMPTS = 3` and `SNAPSHOT_PERSIST_RETRY_BASE_MS = 50` as named constants with a brief comment on why these values were chosen.

---

### 9. Low: `profileKey` (background) and `sessionKey` naming divergence vs domain vocabulary

Rule: `RS-06` (Readability — inconsistent terminology vs domain)

Files:
- `repos/igloo-chrome/src/background/utils.ts:36-51` — `profileKey` returns a JSON string of `{groupPublicKey, relays}`
- `repos/igloo-chrome/src/lib/runtime-host/helpers.ts:18-20` — `profileKey` returns `profile.id.toLowerCase()`
- `repos/igloo-chrome/src/lib/runtime-host/controller.ts:177` — uses `profileKey` from helpers as a signer-session deduplication key

Why this matters:
- The system docs use "profile" to mean the stored credential and "session" or "runtime" to refer to the live WASM signer context. The runtime-host's `profileKey` is used as a signer session key, not a profile discriminator. This naming mismatch becomes important if a developer uses the wrong key function when deduplicating sessions.

Smells:
- Two exported symbols with the same name, at two different import paths, returning different things.

Streamline:
- Rename `helpers.profileKey` to `sessionKey` (to reflect its role as the session deduplication handle) and update the one callsite in `controller.ts` to match.

## Summary

| Severity | Count |
|---|---|
| High | 2 |
| Medium | 4 |
| Low | 3 |
| **Total** | **9** |

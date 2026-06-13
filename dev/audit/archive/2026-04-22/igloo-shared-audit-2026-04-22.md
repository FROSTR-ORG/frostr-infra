# `igloo-shared` Audit

Date: 2026-04-22

Scope: `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared`

This audit covers the WASM bridge boundary, the shared signer node, the NIP-44 path, profile/rotation helpers, observability/redaction, and the tangle of `browser-profile*` modules. Security posture is reasonable: key material flows through WASM and stays out of structured logs thanks to a name-based redactor. The main hazards are concentrated in `browser-runtime-core.ts` (one ~2200-line module that owns relay I/O, WASM ingest, session orchestration, NIP-44, pending-op bookkeeping, and public exports), in a few places where the redactor is the only line of defense against leaking secrets into console breadcrumbs, and in module sprawl across five overlapping `browser-profile*` packages that each re-wrap the same finalize/save/persist flow.

## Findings

### 1. High: `browser-runtime-core.ts` is a 2189-line monolith that owns relay I/O, WASM ingest, NIP-44, session orchestration, and the whole public runtime surface

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts:1-2190`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts:607-1886` (`BrowserBridgeNode` class)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts:1960-2189` (public free functions)

Why this matters:
- This file defines the `BrowserBridgeNode` class (relay pool, WASM runtime, onboarding request, inbound subscription, tick pump, pending command queue, NIP-44 encrypt/decrypt, snapshot accessor) plus ~20 free functions that type-narrow `NodeWithEvents` back to `BrowserBridgeNode` just to call a method on it.
- It is the single integration seam with `bifrost-rs` wire semantics. Every wire shape (`OnboardingRequestBundleWire`, `RuntimeSnapshotWire`, `RuntimeBootstrapWire`, `OnboardResponseWire`, `BridgeEnvelope`, policy overrides) is re-declared inline.
- Any change to bifrost-rs wire format, any new operation type, and any tweak to pending-op semantics all funnel through this file, raising merge-conflict risk and making review expensive.

Smells:
- `BrowserBridgeNode` mixes orchestration, state, and IO in one class.
- 20+ `isBrowserBridgeNode(node) && typeof node.X === 'function'` guards that exist only because the exported type is `NodeWithEvents` instead of `BrowserBridgeNode`.
- Wire-shape types duplicated here instead of being shared with bifrost-rs TS bindings.

Streamline:
- Split into `wasm-bridge-node.ts` (class), `relay-transport.ts` (pool/probe/subscribe), `onboarding-transport.ts` (request/response), `runtime-pump.ts` (tick/drain), `runtime-api.ts` (public free functions), and a `wire.ts` for the wire shapes.
- Export `BrowserBridgeNode` directly; kill the `NodeWithEvents` runtime-guard pattern.

Cross-repo note: every new field bifrost-rs emits in `runtime_status`/`drain_runtime_events`/completion JSON lands here first. A drift detector (contract test against fixture JSON from bifrost-rs) would de-risk this boundary.

### 2. High: pending `sign`/`ecdh` completions are matched only by kind, not by request id

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts:536-562` (`parseSignCompletion`, `parseEcdhCompletion` ignore `request_id`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts:1765-1779` (completion dispatch matches only `pendingCommand.kind`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts:1840-1885` (`runBridgeCommand` stores only `kind`)

Why this matters:
- The WASM runtime may emit a sign or ecdh completion for a prior operation (e.g. after a timeout in JS but before WASM cancels), and the dispatcher will resolve the current pending command with the wrong result.
- `commandChain` serialises new commands but does not serialise the WASM runtime's internal view of in-flight operations. A late completion for the previous op can be matched against the new pending.
- The ping path has an analogous issue at `browser-runtime-core.ts:1789-1805`: `pendingPings.shift()` pops FIFO on any ping failure, regardless of which peer failed.

Smells:
- Completion correlation is implicit. The bridge envelope has `request_id` everywhere except the place it is needed.
- No test exercises "stale completion arrives after local timeout" or "failure round affects the wrong pending ping".

Streamline:
- Record `requestId` when dispatching; reject completions whose `request_id` does not match.
- For pings, store pending entries by `{peer, requestId}` and drop failures that don't match a live pending entry.

Cross-repo note: bifrost-rs already includes `request_id` in completion payloads. The TS side just isn't using it. An interface contract test would catch if the field goes away.

### 3. High: debug-level observability logs the raw completion envelope

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts:1749` (`this.emitLog('debug', 'runtime', 'completion', { completion })`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/observability.ts:58-77` (`redactField` substring match)

Why this matters:
- When `VITE_IGLOO_DEBUG=1`, every completion is passed into `sanitizeDetails`. The redactor is the only defence that keeps fields like `shared_secret_hex32`, `seckey`, and `state_hex` out of structured console output.
- Redaction is substring-based on lowercased keys. Any new bifrost-rs completion payload that uses a different naming convention (e.g. `derivedKey`, `sessionMaterial`) would be logged verbatim.
- `parseEcdhCompletion` returns `shared_secret_hex32` which the JS side then hashes into a NIP-44 conversation key — exactly the material a developer would set `VITE_IGLOO_DEBUG=1` to inspect.

Smells:
- Allow-list would be safer than deny-list for debug completion dumps.
- The sink is `console.*`, which in an extension host or service worker can be captured by devtools extensions or crash reports.

Streamline:
- Replace `{ completion }` with a shape summary: `{ completion_keys: Object.keys(...), op_type }`.
- Convert `redactField` to an allow-list for the `runtime.completion` / `runtime.failure` domains.

### 4. High: the runtime exception path inlines the readiness blob into an `Error` message via JSON.stringify

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts:1357-1366` (`prepareOperation` throw)

Why this matters:
- When `prepareSign()` or `prepareEcdh()` times out, the thrown message is `${reason}: ${JSON.stringify(lastReadiness)}`.
- `RuntimeReadiness` today only carries counts and flags, but the host-facing contract does not guarantee that. If a future bifrost-rs adds richer fields (peer secrets, cached nonces, device ids) to `readiness()`, those will land inside an `Error.message`, which hosts frequently log un-redacted.
- Errors propagate to `igloo-chrome` / `igloo-pwa` / `igloo-home`, each of which has its own logging and telemetry surface.

Smells:
- Free-form `Error.message` concatenation is outside the redactor's control.
- String-based error taxonomy: callers must regex on the reason prefix.

Streamline:
- Introduce a typed `PrepareOperationTimeoutError` with named fields; stringify only counts and the reason code.
- Keep `lastReadiness` off the message entirely; attach via a structured `cause` if needed.

Cross-repo note: hosts should treat readiness snapshots as non-loggable until this is bounded.

### 5. High: WASM loader has no content integrity check and uses `/* @vite-ignore */` dynamic import of a host-supplied URL

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/wasm/loader-core.ts:5-57`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/wasm/bridge-loader.ts:38-46` (`configureWasmBridgeLoader` stores the config without validation)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/wasm/profile-loader.ts:56-64`

Why this matters:
- `dynamicImportModule(url)` uses `@vite-ignore` and imports whatever URL the host passes. There is no SRI, no checksum, and no scheme check.
- Hosts are expected to configure a same-origin URL, but nothing in the shared layer enforces that. An extension or PWA host with a misconfigured CSP plus a bad config could end up loading a third-party WASM loader.
- Integrity for the `.wasm` binary itself is also absent. Bifrost-rs crypto correctness depends on this blob.

Smells:
- Loader config accepts a `loaderImportUrl: string` or a `preloadedModule: unknown` with no shape assertions beyond `typeof default === 'function'`.
- `loader-core.ts:23-33` logs the `loader_import_url` at `console.warn` unconditionally (bypasses `shouldEmit`), making the URL visible even in release builds.

Streamline:
- Require hosts to pass a hash (sha-256 hex) of the loader JS and the wasm bytes; verify before `init` is called.
- Restrict `loaderImportUrl` to same-origin URLs by default; require an explicit opt-out for cross-origin.
- Route the loader log through the shared `createLogger('igloo.wasm-loader')` so verbosity gating applies.

Cross-repo note: bifrost-rs publishes the wasm blob via `scripts/build-bridge-wasm.sh` (`scripts/build-bridge-wasm.sh:54-56`). That script is the natural place to emit and pin a checksum file that loaders verify.

### 6. Medium: five `browser-profile-*` packages re-wrap the same finalize/save/persist flow

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile-persistence/bundle.ts:12-50`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile-store/finalize.ts:32-75` (`createFinalizedBrowserStoredProfile` wraps `createBrowserPersistedProfileBundle`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile-save/common.ts:22-72` (`saveBrowserProfileAndMaybeActivate` wraps `completeBrowserProfileSave`; `saveFinalizedBrowserProfileAndMaybeActivate` wraps that)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile-save/imports.ts:12-136` (two near-identical functions for `bfprofile` vs `bfshare`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile-recovery/save.ts:13-63` (`importAndSaveBrowserProfilePackage` / `recoverAndSaveBrowserProfilePackage` are a thinner duplicate of the above)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-session-orchestration/save.ts:4-34`

Why this matters:
- There are at least three entry points that a host can reasonably pick to "save an imported profile and maybe start the runtime": `importAndSaveBrowserProfilePackage`, `saveImportedBrowserProfileAndMaybeActivate`, and the low-level `createFinalizedBrowserStoredProfile` + `saveBrowserProfileAndMaybeActivate` pair. They differ subtly in which logger domain the failure routes to and whether `finalized` is exposed to the `persistProfile` callback.
- The `saveRotatedBrowserProfileAndMaybeActivate` and `saveConnectedBrowserProfileAndMaybeActivate` variants in `browser-profile-save/onboarding.ts:15-135` are similar enough that hosts have to read both carefully to pick one.
- Each duplicate path is a place where failure-taxonomy (`logSharedSaveFailure`) has to be kept in sync.

Smells:
- Overlapping module names: `browser-profile-save`, `browser-profile-recovery`, `browser-profile-persistence`, `browser-profile-store`, `browser-session-orchestration` all participate in the save path.
- Each wrapper is thin and mostly threads arguments.

Streamline:
- Collapse to one flow function per source (`bfprofile`, `bfshare`, `bfonboard`, `rotation`) with a single `persistProfile` hook, and drop the recovery-layer duplicate.
- Fold `browser-session-orchestration` and `browser-runtime-session` back into `browser-profile-save` (they are one-file re-exports anyway).

### 7. Medium: secret-path flows rely entirely on a substring-based redactor

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/observability.ts:58-77` (`redactField`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/observability.ts:42-56` (`sanitizeValue`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile-save/common.ts:36-42` (catches arbitrary `error` into `error_message`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile-store/reconstruct.ts:120-127`

Why this matters:
- The redactor matches keys containing `password`, `secret`, `seckey`, `nonce`, `onboardpackage`, `state_hex`, `snapshot*`. It is a substring match (`normalized.includes(...)`), which will over-match friendly keys (`newPasswordStrength`) and miss near-miss keys that bifrost-rs or a future host may introduce (`share_ikm`, `ephemeral_key`, `handshake_state`).
- Errors are lowered to `error_message` via `toErrorMessage`, which walks arbitrary `unknown`. If a host rejects a promise with an object containing a secret-bearing `message`, it lands in the log text after redaction-by-key has already been applied to the outer envelope only.
- There is no test ensuring that new fields in the runtime status / completion / failure shapes are either tagged as secret or explicitly allow-listed.

Smells:
- Deny-list redaction for an open-schema payload (runtime events, completions, failures).
- No fuzz-style test that asserts known-secret substrings never appear in emitted JSON.

Streamline:
- Switch to a domain-scoped allow-list of loggable keys per event, or to a typed-event catalogue with per-event redaction rules.
- Add a vitest that feeds a sample payload containing every known secret field and asserts the serialised event contains no hex string of length 64.

Cross-repo note: bifrost-rs should own a canonical list of "secret" field names and TS should import it.

### 8. Medium: onboarding listener decrypts every matching relay event under the filter, then discards

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts:1585-1636` (`subscribeMany` onevent)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts:1595-1625` (calls `nip44.v2.decrypt` before validating envelope)

Why this matters:
- `requestOnboardResponse` filters `kinds:[BIFROST_EVENT_KIND], authors:[peer], '#p':[share_pubkey], since: now-30`. Any event matching those tags gets passed through `nip44.v2.decrypt` with the conversation key derived from the local share secret.
- A malicious relay (or any peer that shares the same author pubkey by accident in a misconfigured deployment) can force arbitrary bytes through the decrypt path. `nip44-normalize.ts:1-10` is permissive: it pads the base64 to length %4 without validating characters.
- Failures are swallowed at line 1620-1626 and logged at `debug`; a flood of adversarial events during onboarding would show up only in verbose logs.

Smells:
- Untrusted input reaches the cryptographic path with only filter-level gating.
- `normalizeNip44PayloadForJs` cannot be reached with obviously-invalid input without first round-tripping through `trim()`.

Streamline:
- Validate `event.content` as base64url-ish before calling `nip44.v2.decrypt`.
- Rate-limit or cap the number of decrypt attempts per onboarding request.
- Emit a metric when decrypt failures exceed a threshold for an onboarding request.

### 9. Medium: `browser-runtime-core.ts` caches runtime state in module-level singletons across the WASM loader pair

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/wasm/bridge-loader.ts:12-16` (`cachedBridgeModule`, `loadingBridgeModulePromise`, `injectedBridgeModuleForTests`, `configuredBridgeLoader`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/wasm/profile-loader.ts:10-13` (mirror singletons)

Why this matters:
- Module singletons cannot be reset per host instance. An `igloo-chrome` extension hot-reload that re-runs the init code paths but does not re-load the module script will keep the previous WASM heap around.
- `setInjectedWasmBridgeModuleForTests` exists precisely because the singleton is not testable otherwise; there are two parallel copies (bridge, profile) that must be kept consistent.
- Any future need to instantiate two signer runtimes in one tab (for rotation handshakes or side-by-side profile comparison) is blocked.

Smells:
- Three pieces of mutable top-level state across two files, duplicated by discipline.
- Test-only mutators live in the production surface.

Streamline:
- Replace module singletons with a `WasmLoader` object that hosts construct explicitly; have tests inject via constructor.
- Consider sharing one `WasmLoader<T>` generic with a module-kind discriminator.

### 10. Medium: `bfonboard` envelope validation after decryption is shape-only; there is no signature / membership check

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts:1600-1619` (post-decrypt envelope check)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts:479-497` (`parseBridgeEnvelope`)

Why this matters:
- Once `nip44.v2.decrypt` returns anything at all, the code only checks that `envelope.request_id` matches, `payload.type === 'OnboardResponse'`, and the `group` is an object.
- There is no check that the returned `group.members` corresponds to what the peer was authorized to hand out. Any peer who knows the local share secret (which, pre-onboard, is part of the `bfonboard` package) could, in principle, hand back a group with extra members or a different `group_pk` and the onboarding snapshot would be built from it (`build_onboarding_runtime_snapshot` at line 948-956).
- bifrost-rs likely validates membership/signatures inside the WASM call. The TS layer should not assume that.

Smells:
- Only implicit validation delegated to `build_onboarding_runtime_snapshot` without a contract comment pointing to the bifrost-rs invariant.
- Normal-path validation and adversarial-path validation are the same path.

Streamline:
- Add a TS-side pre-flight check: `threshold <= members.length`, no duplicate pubkeys, share pubkey is in `members`.
- Add a contract comment citing the bifrost-rs function that owns the stronger validation.

Cross-repo note: if bifrost-rs ever relaxes that WASM-side check, TS becomes the last line of defence.

### 11. Low: relay-URL normalization accepts any `wss?://.+` including plaintext `ws://` on non-loopback

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts:443-445` (`isRelayUrl`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts:1945-1958` (`normalizeRelays`)

Why this matters:
- `ws://` is accepted for any host, not just loopback. A profile whose relays were accidentally stored as plaintext URLs will happily transmit encrypted onboarding traffic over TCP — confidentiality is preserved by NIP-44, but traffic metadata (share pubkey, peer pubkey, timing) is not.
- The repo's CLAUDE.md explicitly prefers `localhost` for loopback; production URLs should be `wss://`.

Smells:
- No scheme-host heuristic.

Streamline:
- Downgrade-warn on `ws://` when the host is not `127.0.0.1`/`localhost`/`::1`.

### 12. Low: test suite covers happy paths and does not exercise concurrent, adversarial, or WASM-boundary failure cases

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-onboarding.test.ts:1-136`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile-persistence.test.ts:1-137`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile-save.test.ts:1-241`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-session.test.ts:1-79`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-session-orchestration.test.ts:1-37`

Why this matters:
- There are no unit tests for `browser-runtime-core.ts`. The heart of the signer runs with no direct coverage at this layer; it relies entirely on downstream host E2E.
- There are no tests for:
  - stale / mismatched completion dispatch (finding 2)
  - adversarial ciphertext reaching `nip44.v2.decrypt` (finding 8)
  - redaction invariants on the runtime completion / failure events (finding 7)
  - `prepareOperation` timeout error shape (finding 4)
  - WASM loader rejecting a malformed module
- `browser-profile-recovery.test.ts:12-13` and `browser-profile-save.test.ts:12-13` use `as any` on mock return values, disabling type checking on the exact contract the tests exist to lock in.

Smells:
- Tests assert "happy path produces expected shape" and "failure logs an event", but not "boundary behaves correctly under adversarial input".
- Heavy use of `vi.hoisted` with `vi.fn(async () => ...)` mocks that bypass actual wire contracts.

Streamline:
- Add a `browser-runtime-core.test.ts` with a mock `WasmBridgeRuntimeApi` exercising tick/drain/completion dispatch.
- Add a redaction property test (finding 7).
- Replace `as any` mocks with typed partial stubs.

### 13. Low: README and TESTING do not document the public runtime API or the loader-injection contract

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/README.md:1-43`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/TESTING.md:1-27`

Why this matters:
- `README.md` lists ownership at the module level but does not enumerate the runtime API surface (`createSignerNode`, `connectSignerNode`, `configureWasmBridgeLoader`, `configureWasmProfileLoader`, the injection API) that hosts must call in a specific order.
- There is no JSDoc on the exported `createSignerNode` / `connectSignerNode` / `configureWasmBridgeLoader` functions, despite these being the two entry points every host has to wire up correctly.
- `docs/INTERFACES.md` treats the `host ↔ runtime` seam at the shared-system level but does not cross-reference the `igloo-shared` entry points.

Smells:
- No canonical "how a host integrates igloo-shared" document.
- Public-surface consistency is the first guardrail listed in `TESTING.md` but is not specified anywhere.

Streamline:
- Add a "Runtime integration" section to `README.md` that shows the `configureWasmBridgeLoader` → `createSignerNode` → `connectSignerNode` → `stopSignerNode` lifecycle.
- JSDoc every exported runtime/session API function with expected caller order and thrown errors.
- Cross-link from `docs/INTERFACES.md` into the shared runtime entry points.

### 14. Low: duplicate hex / pubkey normalization helpers across five files

Files:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts:447-477` (`normalizePubkey32Hex`, `normalizeHex32`, `hexToBytes`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile/keys.ts:3-33` (`hexToBytes`, `normalizeHex32`, `normalizeGroupMemberSharePublicKey`, `publicKeyFromSecret`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/profile-package.ts:99-144` (`hexToBytes`, `normalizeCompressedPubkey`, `xOnlyFromCompressedPubkey`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-profile-store/reconstruct.ts:79-129` (reimplements member pubkey normalization inline)

Why this matters:
- Three separate `hexToBytes` implementations with slightly different validation. `browser-runtime-core.ts:466-477` accepts any even-length hex; `browser-profile/keys.ts:3-10` requires 32 bytes; `profile-package.ts:99-109` requires 32 bytes. A refactor that swaps one import for another would silently change the validation contract.
- Member-pubkey reconstruction logic is inlined in `reconstruct.ts:108-116` and again in `browser-profile/runtime.ts:69-78`.

Smells:
- Divergent validation rules for the same concept.
- Callers pick whichever import is already in scope.

Streamline:
- One `hex.ts` with `hexToBytes`, `normalizeHex32`, `normalizePubkey32Hex`, `normalizeCompressedPubkey`, `xOnlyFromCompressedPubkey`.
- Remove in-file helpers in favour of the shared module.

## Bottom Line

`igloo-shared` does not have a glaring security hole; the redactor, typed exports, and WASM module boundary all work. The load-bearing concerns are:

- one module (`browser-runtime-core.ts`) that is simultaneously the WASM boundary, the relay transport, and the public API — too much concentrated in one place
- weak completion correlation and error-shape hygiene in the signer command path
- a loader that trusts host-supplied URLs without integrity
- sprawl across five `browser-profile*` packages that re-implement the same save flow
- tests that prove shapes hold on the happy path but never stress the adversarial or concurrent paths

Tightening completion correlation (finding 2), bounding error-message blobs (finding 4), adding WASM integrity (finding 5), and consolidating the `browser-profile*` flow (finding 6) would produce the highest signal per unit of churn.

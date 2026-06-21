# `igloo-chrome` audit

Date: 2026-06-19

Scope: `/Users/cscott/Repos/frostr/frostr-infra/repos/igloo-chrome` (all of `src/` and `tests/`; build/manifest scripts skimmed, `dist/` and `node_modules/` excluded). Typecheck (`npx tsc --noEmit`) passes clean. Heavy/stateful lanes (e2e, demo, dev) intentionally not run.

`igloo-chrome` is in good shape on the surface metrics the 2026-06-13 pass flagged: strict TS compiles, no `nip04`/`NIP-04` anywhere in `src/` or `public/` (the dead-but-wired provider surface is fully pruned — permission labels, `PROVIDER_METHOD`, the result map, and `getPermissionLabel` all dropped it), no TODOs, and the page bridge is origin-pinned on both send and receive (`nostr-provider.ts:42,49`). The module layout is genuinely good: the old monolithic background has been decomposed into focused services (`permission-service`, `onboarding-service`, `runtime-service/*`, `profile-service/*`, `runtime-host/*`), the largest source file is 509 LOC, and there is no god file. Test breadth is strong (24 unit suites).

The debt that remains is **semantic, not structural**, and it clusters at the secret/crypto seam. The standout is a hand-rolled PBKDF2 + AES-GCM profile-blob cipher (`lib/profile-blob.ts`) that lives entirely outside igloo-shared's `Secret<T>` / Argon2id machinery, deliberately exports its derived master key to a bare base64 string, and is **mocked out of every test** — so the one piece of real crypto this host owns has no real-crypto coverage and no adversarial coverage. Around it sit a cluster of bare-string secret handles (`password`, `sessionKeyB64`), a triple-overloaded `profileKey` identifier (two functions with different semantics plus an object field, all named `profileKey`), a wall of uncurated `export *` barrels, and the workspace-wide misses (no formatter, stale changelog). Findings below are ordered High → Medium → Low.

## Findings

### 1. High: Hand-rolled profile-blob cipher exports its derived master key to a bare string and diverges from the shared crypto stack

Rule: `SEC-03` (security) — also implicates `SEC-01`, `ARC-05`

Files:
- `igloo-chrome/src/lib/profile-blob.ts:34,71-109,151-189`
- `igloo-chrome/src/extension/storage.ts:159-186` (where the exported key lands at rest)
- `igloo-chrome/src/lib/runtime-host/snapshot-persistence.ts:25-34` (decrypt→reencrypt cycle)

Why this matters:
- This file is a complete, independent cipher stack: PBKDF2-SHA-256 at 200k iterations (`:34`) deriving an AES-256-GCM key, with its own base64/utf8 helpers — none of it routed through igloo-shared's `Secret<T>` or the workspace's Argon2id KDF (the same KDF the co-signer commit `171ac1f` treats as the canonical, security-relevant choice). Two KDF regimes now coexist in one product with no note on why the at-rest blob gets the weaker PBKDF2 one.
- `deriveAesKey` creates the key `extractable: true` (`:89`) **specifically so** `exportSessionKey` (`:107`) can serialize it to raw base64. That `sessionKeyB64` is the unlock master key for the share-bearing blob, and it is then held and persisted as a plain JS string (`storage.ts:164-171`, `runtime-service/types.ts:17`, `SignerSession.sessionKeyB64`). This is the exact "secret escapes its non-extractable envelope into a bare string" pattern SEC-01 polices — the WebCrypto `CryptoKey` opacity is intentionally thrown away.
- Every `runtime-status` event triggers `persistSessionSnapshot`, which **decrypts the full profile blob (share secret in cleartext JS) and re-encrypts it** (`snapshot-persistence.ts:25-34`) just to stamp a snapshot JSON — so the share plaintext is reconstructed in memory on a high-frequency path, not only at unlock.

Smells:
- Home-rolled cipher stack parallel to a vetted shared one.
- `extractable: true` + `exportKey('raw')` to deliberately defeat key opacity.
- Master key and password both live as bare `string` with no zeroizing wrapper.
- Secret plaintext reconstructed on a per-status-event cadence.

Streamline:
- Decide one KDF/cipher home: either thread the local blob through igloo-shared's secret machinery, or write down (DOC-04) why this host keeps a separate PBKDF2 regime and what the threat model is. Keep the derived key non-extractable and pass the `CryptoKey` handle through `SignerSession` instead of a base64 string; if a serialized form is unavoidable, wrap it in a zeroizing type and scrub on logout. Separate the snapshot-persist path so a status tick can stamp a snapshot without round-tripping the share plaintext.

Cross-repo note: this PBKDF2/AES-GCM stack is unique to chrome — `igloo-pwa/src/lib/storage.ts` has no parallel (its `sessionKeyFor` is a localStorage namespace string, not a crypto key), so this is divergence by omission: the share-at-rest story is solved differently in each host. Mirror into NOTES.md.

### 2. High: The host's only real crypto (profile-blob + provider methods) is mocked out of every test — no real-crypto, no adversarial coverage

Rule: `TST-05` (testing) — also `TST-02`, `TST-03`

Files:
- `igloo-chrome/tests/unit/background/profile-service.test.ts:19-20,49-50,81-82` (blob crypto vi.fn-mocked)
- `igloo-chrome/src/lib/profile-blob.ts` (no test imports it directly — zero KAT/round-trip/adversarial)
- `igloo-chrome/src/lib/runtime-host/provider-execution.ts:18-42` (shape-guard rejection arms)
- `igloo-chrome/src/nostr-provider.ts:78-107` (response-shape rejection arms)

Why this matters:
- `decryptLocalProfileBlobWithPassword` / `decryptLocalProfileBlobWithSessionKey` are replaced by `vi.fn()` in the profile-service suite, and nothing else imports `profile-blob.ts` — so PBKDF2 derivation, AES-GCM round-trip, **wrong-password rejection, and corrupted-ciphertext (GCM tag failure) behavior are entirely unasserted**. A subtly-wrong-but-self-consistent change (wrong iteration count, IV reuse, salt mishandling) would pass green. This is precisely the TST-03 "crypto rests on nothing" gap, on the host's own cipher.
- `executeProviderMethodOnSession` has real input-validation guards (`provider-execution.ts:20,27,34` throw on missing/mistyped `event`/`pubkey`/`plaintext`) and `nostr-provider.ts` has response-shape guards (`:78,85,96,103`) — the security-relevant rejection paths of the signEvent/nip44 bridge — and none of them are exercised. The reconcile already flagged "provider crypto paths untested"; the deeper read is that even the *non-crypto* validation arms have no test.
- `make test-fast` is render-only (per the rules), so a green pre-push can coexist with a broken cipher or a bypassed guard.

Smells:
- The single most security-critical module has zero direct tests.
- Mocks stand in for the exact behavior that matters; mock-vs-real drift is undetectable.
- Only happy paths asserted; wrong-passphrase / corrupted-blob / malformed-params untested.

Streamline:
- Add a direct `profile-blob.test.ts`: encrypt→decrypt round-trip, wrong-password rejects, single-bit ciphertext flip rejects (GCM tag), and a recorded KAT vector to pin the KDF/cipher params. Add unit tests for each `executeProviderMethodOnSession` reject arm and each `nostr-provider` response-shape guard. These belong here (cheapest layer that proves them), not in the Playwright lane.

Cross-repo note: the reconcile noted igloo-pwa also lacks wrong-passphrase/corrupted-blob tests and igloo-home lacks frontend typed-error tests — the "adversarial crypto/unlock path untested" gap is shared across all three hosts. Mirror into NOTES.md.

### 3. Medium: `profileKey` names three different things — two functions with divergent semantics plus an object field

Rule: `RS-01` (readability) — also `CQ-04`, `RS-04`

Files:
- `igloo-chrome/src/background/utils.ts:36-51` (`profileKey(profile)` → JSON of `{groupPublicKey, relays}` — a content/identity hash)
- `igloo-chrome/src/lib/runtime-host/helpers.ts:18-20` (`profileKey(profile)` → `profile.id.trim().toLowerCase()` — an id slug)
- `igloo-chrome/src/lib/runtime-host/controller.ts:69,72,116` (`profileKey: session.key` — an object *field*, third meaning)

Why this matters:
- Three distinct concepts share one searchable name. The two functions return different values from the same-shaped input: one is a stable group+relays fingerprint, the other a lowercased id. A reader who greps `profileKey` and lands on the wrong one will reason about identity incorrectly — and these feed cache keys (`signerSessionKey === nextKey` in `controller.ts:179`) and log fields (`profile_key` everywhere), so a mix-up is a silent session-reuse / dedup bug.
- The reconcile flagged this twice (items #3 and #9, "still open") and the rename was never applied — it is the canonical low-risk, high-clarity cleanup for this repo.

Smells:
- One identifier, three meanings, no disambiguation.
- Same input shape, different output, same name — a foot-gun for cache/log keys.

Streamline:
- Rename by meaning: `utils.ts` → `profileFingerprint` (or `groupRelaysKey`); `helpers.ts` → `profileIdKey` (or just inline `profile.id` normalization); the `SignerSession` field that carries the latter → `profileIdKey`. Pick one term per concept and use it everywhere, including the `profile_key` log fields.

### 4. Medium: Six bare-string password states live in one onboarding page that also owns five unrelated flows

Rule: `ARC-02` (architecture) — also `SEC-01`, `RS-02`

Files:
- `igloo-chrome/src/pages/Onboarding.tsx:50-66` (6 `useState('')` password/secret slices + ~11 other slices)
- `igloo-chrome/src/pages/Onboarding.tsx:111-225` (onConnect / onSave / onImport / onActivate / onUnlock / onDelete)

Why this matters:
- `OnboardingPage` (471 LOC) is the largest page and interleaves six independent flows — connect-onboard, save-onboard, import-bfprofile, activate-existing, unlock-existing, delete-existing — each with its own loading flag, sharing one `error` slot. You can't change the unlock flow without reading the import and onboard wiring (ARC-02), and the per-flow loading booleans (`connecting`/`saving`/`importingProfile`/`activatingProfileId`/...) are a mutation-heavy state pile.
- `onboardPassword`, `localProfilePassword`, `bfprofilePassword`, `unlockPassword` (and two more secret-ish slices) sit in raw React component state as plain strings for the component's lifetime, with no scrub on submit/unmount (SEC-01). Combined with finding #1, the passphrase is bare-string from keystroke to KDF.

Smells:
- One page, five-to-six unrelated submit flows, a shared error slot.
- Multiple long-lived bare-string passphrase fields in component state.

Streamline:
- Split per flow (e.g. `OnboardConnect`, `ImportProfile`, `UnlockProfile`, `ProfileList`) so each owns its own state and the page composes them — the codebase already favors this decomposition style. Clear password state on submit and on unmount; route it into the secret wrapper chosen in finding #1 rather than holding raw strings.

### 5. Medium: `sessionKeyB64!` non-null assertion sidesteps a guard that never checks it

Rule: `CQ-03` (code quality) — also `CQ-02`

Files:
- `igloo-chrome/src/background/runtime-service/access.ts:26` (`sessionKeyB64: activeProfile.sessionKeyB64!`)
- `igloo-chrome/src/background/runtime-service/access.ts:19` (guard checks `runtimeProfile` + `payload`, not `sessionKeyB64`)

Why this matters:
- `LoadedActiveRuntimeProfile.sessionKeyB64` is typed `string | null` (`profile-service/types.ts:11`). The `!` at `:26` asserts it is present, but the guard one line up at `:19` only verifies `runtimeProfile` and `payload`. A profile whose session was cleared (logout/expiry) but whose payload is still loaded would pass the guard and hand `null as string` to the runtime, which then attempts a decrypt with a null key — converting a recoverable "needs unlock" into a downstream crash.
- The reconcile flagged this (#4, "still open"). The `!` is lying about an invariant the surrounding code does not actually enforce.

Smells:
- Non-null assertion on a `| null` field that the adjacent guard doesn't cover.
- Recoverable "locked profile" state can reach a crypto path as a null key.

Streamline:
- Extend the `:19` guard to require `activeProfile.sessionKeyB64`, returning `null` (locked) when absent, and drop the `!`. Let the caller surface "unlock required" instead of asserting.

### 6. Medium: Uncurated `export *` barrels re-export entire packages and internal module sets

Rule: `ARC-04` (architecture) — also `RS-05`

Files:
- `igloo-chrome/src/lib/igloo.ts:1-5`, `nip44-normalize.ts:1`, `signer-settings.ts:1`, `bridge-wasm-runtime.ts:1`, `observability.ts:1` (each `export * from 'igloo-shared'`)
- `igloo-chrome/src/extension/protocol.ts:1-5` (re-barrels 5 internal modules)
- `igloo-chrome/src/background/profile-service.ts:1` (`export * from './profile-service/index'`)

Why this matters:
- Five separate local modules each do `export * from 'igloo-shared'`, re-exposing the shared package's entire surface under five different local aliases. The only one carrying real intent is `igloo.ts`, whose value is the side-effecting `ensureIglooSharedConfigured()` call (`:1-3`) before the re-export — the others are pure pass-throughs that obscure where a symbol actually comes from. Importers can't tell a designed surface from the whole drawer, and "where is `X` defined" takes extra hops (RS-05).
- `protocol.ts` re-barrels messages/provider-types/lifecycle/runtime-types/state-types into one namespace, so any consumer pulls the union and the real owner of a type is hidden behind the barrel.

Smells:
- Five `export *` aliases of the same upstream package.
- Pass-through barrels with no curation and no added value beyond a name.

Streamline:
- Keep `igloo.ts` as the single configured entry (it has a reason), and have the others import from it or from the specific upstream module rather than re-`export *`. Where a barrel is genuinely a public surface (`protocol.ts`), make the re-exports explicit named lists so the owning module of each type stays greppable.

### 7. Low: PBKDF2 iteration count and snapshot-retry constants are unexplained magic values

Rule: `CQ-06` (code quality) — also `DOC-04`

Files:
- `igloo-chrome/src/lib/profile-blob.ts:34` (`PBKDF2_ITERATIONS = 200_000`)
- `igloo-chrome/src/lib/runtime-host/snapshot-persistence.ts:49,59` (`attempt < 3`, `50 * (attempt + 1)`)

Why this matters:
- `200_000` is named but carries no rationale for why this count (vs the Argon2id the rest of the workspace uses) — a future contributor can't tell if it's a deliberate floor or an arbitrary pick (ties to finding #1's KDF-divergence question).
- The snapshot retry `3` and backoff `50 * (attempt + 1)` ms are inline literals with no comment on why three attempts or this backoff shape; the reconcile flagged these (#8, "still open").

Smells:
- Security-relevant KDF cost with no recorded "why this value."
- Retry/backoff magic numbers inline.

Streamline:
- Name the retry/backoff constants (`SNAPSHOT_PERSIST_ATTEMPTS`, `SNAPSHOT_RETRY_BASE_MS`) with a one-line why. Add a comment on the PBKDF2 cost citing the threat model / the decision behind finding #1.

### 8. Low: No enforced TypeScript formatter

Rule: `AES-06` (aesthetics)

Files:
- `igloo-chrome/package.json` (no `prettier`/`eslint` dependency or config; no format gate)

Why this matters:
- Style is per-author, so aesthetic consistency is re-argued per PR and any formatting finding here is doomed to recur. This is a workspace-wide condition, not chrome-specific.

Smells:
- No `prettier`/`eslint` config in a TS repo; no `format:check` script.

Streamline:
- Adopt the workspace-level formatter decision (this is one of five identical findings); gate it in CI. Tracked as cross-cutting, not a per-repo fix.

Cross-repo note: identical absence in igloo-shared, igloo-ui, igloo-pwa, igloo-home — a single workspace decision, not five. Mirror into NOTES.md.

### 9. Low: CHANGELOG and version stagnant despite shipped behavior changes

Rule: `DOC-06` (documentation)

Files:
- `igloo-chrome/CHANGELOG.md:7` (newest entry `[0.3.0] - 2026-03-27`)
- `igloo-chrome/package.json:4` (`"version": "0.3.0"`)

Why this matters:
- Since 2026-03-27 the repo landed the NIP-04 removal, the page-bridge origin pin, and other behavior changes (per the reconcile/commit log) with no changelog entry and no version bump. A consumer can't tell what changed between two checkouts.

Smells:
- Newest changelog entry predates multiple shipped behavior changes.
- Version pinned across a security-relevant change (origin pin).

Streamline:
- Log shipped changes against versions; bump on the next release. Cross-cutting with the other hosts.

### 10. Low: Whole-store context value is a single memo — every status tick re-renders all consumers

Rule: `CQ-07` (code quality)

Files:
- `igloo-chrome/src/lib/store.tsx:351-382` (one `useMemo` packing 25 actions + state, dep `[route, isHydratingProfile, appState, profile, lastOnboardingFailure]`)

Why this matters:
- `appState` and `profile` change on every runtime-status update, so the memo recomputes and every `useStore()` consumer re-renders even when it reads only a stable action. For a dashboard driven by frequent `runtime_status` events this is avoidable churn. It's the textbook CQ-07 "context whose whole value is a memo dependency" shape.

Smells:
- 25 stable callbacks bundled with hot state in one context value.
- Any hot-state change re-renders all consumers regardless of what they read.

Streamline:
- Split the stable action surface from the hot state (two contexts, or move actions to a ref/stable object) so action-only consumers don't re-render on status ticks.

## Summary

| Severity | Count |
|---|---|
| High | 2 |
| Medium | 4 |
| Low | 4 |
| **Total** | **10** |

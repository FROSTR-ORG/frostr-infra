# Bucket D — Browser-Host Secret Hygiene (Hard-Cut Plan)

Status: draft, pending user approval
Related: `bucket-a-bifrost-rs-crypto.md` (closes the bootstrap-leak flag), `bucket-b-kdf-aad.md` (provides the encrypted-artifact primitives used for at-rest persistence), ships in the same coordinated release.

## Context

The 2026-04-22 `igloo-pwa` audit found cleartext share secrets, device
passwords, `unlockPhrase`, `generatedKeyset`, and `runtime_snapshot_json`
(containing `bootstrap.share.seckey` hex) written to `localStorage` under
a single key, with a 1-second poll loop that re-persists the full state
every tick. The `igloo-shared` audit found pending completions matched by
kind-only (not `request_id`), a substring-based deny-list redactor as the
sole defense against bifrost-rs field-name changes, runtime-exception
paths that inline structured readiness blobs into `Error.message`,
shape-only validation of onboarding envelopes post-decrypt, and no rate
limit on decrypt attempts during the onboarding window. Bucket A's synthesis
further flagged that `RuntimeSnapshotExport.bootstrap` leaks `share.seckey`
hex every time `snapshot_state` is called — a concern that Bucket D can
close at the browser-host level by switching poll paths to the existing
`runtime_status` API (which already omits the bootstrap).

Bucket D closes all of these. We are in alpha with a directive to prefer
strong, secure defaults and not worry about operator burden. The plan is
hard-cut: bump the localStorage schema (`v1` → `v2`), strip every secret
from the persist surface, and require passphrase re-entry on page reload.
No back-compat for the old shape.

## Scope

**In:**
- D.1 — Strip every secret from the `localStorage` persist path. `v2`
  schema carries only public metadata. Hard-cut: `v1` data is dropped on
  first boot of the new code.
- D.2 — Introduce `Secret<T>` / `SecretBytes` wrappers in `igloo-shared`
  and migrate every known secret-carrier to them. Replace the substring
  deny-list redactor with a per-event allow-list.
- D.3 — Switch completion dispatch to `request_id` correlation. Convert
  `pendingCommand` from a single slot to `Map<string, PendingBridgeCommand>`.
- D.4 — Make session lifecycle idempotent. Convert module-global singleton
  to per-instance (or epoch-guarded) ownership. Stop throwing on drift
  from legitimate callers.
- D.5 — Close the `RuntimeSnapshotExport.bootstrap` leak at the host level
  by using `runtime_status()` for polls and reserving `snapshot_state()`
  for rare persistence. Combined with D.1 (no persisted snapshot), the
  leak path is eliminated from browser-host code.
- D.6 — Onboarding-time defenses: rate-limit decrypt attempts, validate
  base64 alphabet before `nip44.v2.decrypt`, add post-decrypt membership
  / threshold / pubkey-uniqueness checks, bound the decrypt budget per
  onboarding window.
- D.7 — Replace `throw new Error(\`${reason}: ${JSON.stringify(readiness)}\`)`
  patterns with typed errors carrying named, scalar fields only.

**Out of scope for Bucket D:**
- CSP / SRI / WASM-integrity loader — **Bucket E** (browser/desktop shell hardening).
- Multi-tab state synchronization / shared unlocked-session transport.
  Each tab is independent; each prompts for passphrase independently.
  Explicit non-goal for alpha.
- `igloo-chrome` — the 2026-04-02 audit is still unresolved. Bucket D
  fixes what it can in shared code; a targeted re-audit + cleanup of
  `igloo-chrome`-specific code lives in Bucket J.
- Removing `bootstrap.share.seckey` from `RuntimeSnapshotExport` at the
  bifrost-rs side. D.5 closes the browser-host *use* of the leak; a
  deeper fix (bifrost-rs stops emitting the field) is deferred and flagged
  for Bucket K.
- True in-memory secret wiping on strings. JS strings are immutable; the
  `Secret<T>` wrapper is type-level hygiene plus log-path safety. Real
  zeroization is only possible for `Uint8Array`. Documented in D.2.

## Execution Order

Five PRs. Numbering continues from Bucket C (PR8–PR12).

| PR | Items | Submodule | Depends on |
|---|---|---|---|
| PR13 | D.2 (Secret<T>, allow-list redactor) + D.7 (typed readiness errors) | `igloo-shared` | none |
| PR14 | D.3 (request_id correlation) | `igloo-shared` | none |
| PR15 | D.6 (bfonboard deep validation + rate limit + base64 gate) | `igloo-shared` | none |
| PR16 | D.1 (localStorage secret stripping) + D.5 (runtime_status for polls) | `igloo-pwa` | PR13 (Secret<T>) |
| PR17 | D.4 (idempotent session lifecycle) | `igloo-pwa` | PR13 (typed errors) |

PR13, PR14, PR15 are independent and can run in parallel. PR16 and PR17
land after PR13. Rough touch: ~2,000 lines, mostly in `igloo-pwa/src/lib/`
and `igloo-shared/src/browser-runtime-core.ts`.

Ships in the same coordinated release as Buckets A + B + C.

---

## D.1 — Strip secrets from `localStorage`

### Current secret surface (from Phase 1 exploration)

Persisted in `localStorage` key `igloo-pwa.state.v1` today:
- `profiles[].stored_password` — the user's device password, compared with `===` to `unlockPhrase`
- `profiles[].runtime_snapshot_json` — WASM `snapshot_state` output with `bootstrap.share.seckey` hex
- `unlockPhrase` — current session passphrase
- `generatedKeyset` — all N members' `share.seckey` during generation
- `pendingLoadConfirmation.stored_password`
- `pendingOnboardConnection.runtime_snapshot_json`
- Any draft form field containing `password` (persisted via `drafts: PwaDraftState`)

### Target shape (v2)

Rename the storage key to `igloo-pwa.state.v2`. Remove every secret field.

Persisted v2 fields (metadata only):
- `profiles[]`: `id`, `label`, `created_at`, `relay_profile`, `state_path`,
  `group_ref`, `encrypted_profile_ref`, `relays`, `group_public_key`,
  `share_public_key`, `group_package_json` (public), `share_package_json`
  (public; audit confirmed these are public-only JSON), `signer_settings`,
  `peer_pubkey`, `manual_peer_policy_overrides`, `source`,
  `encrypted_bfshare_artifact` (NEW — see below).
- `peerPermissionStates`, `selectedProfileId`, `activeView`,
  `activeDashboardTab`, `settings`.
- `drafts` — explicitly without password fields. Every `password` field in
  every draft form (`profileForm.password`, `onboardSaveForm.password`,
  `importProfileForm.password`, `rotateConnectForm.password`) is
  non-persistable and lives only in React state.

Removed v2 fields:
- `stored_password` — gone. Replaced by "decrypt the encrypted artifact"
  as the auth check (see below).
- `runtime_snapshot_json` — gone. Signer bootstraps fresh from public
  metadata + user passphrase on session start.
- `unlockPhrase` — gone. Lives only in React state for the lifetime of
  the tab.
- `generatedKeyset` — gone. In-progress keyset generation is ephemeral;
  if the user navigates away, the generation is lost. Acceptable.
- `pendingLoadConfirmation` and `pendingOnboardConnection` — gone.
  Pending flows don't survive reload. Acceptable for alpha.

### Encrypted artifact persistence (replacement for `stored_password`)

On successful onboarding / import, persist `encrypted_bfshare_artifact`
(the Bucket B v2 bech32m string — Argon2id m=256 MiB, XChaCha20Poly1305,
passphrase-AEAD) on the profile record. The bech32m string is opaque
ciphertext; safe at rest in `localStorage`.

Session start flow post-D.1:
1. User selects a profile.
2. UI prompts for passphrase.
3. `decode_bfshare_package(encrypted_bfshare_artifact, passphrase)` (via
   WASM). Success proves the passphrase. No separate `stored_password`
   check.
4. Decrypted share material goes into an in-memory-only `PwaUnlockedProfile`
   (React state, never persisted). Contains `SecretBytes` for the share
   secret.
5. Signer bootstraps from the decrypted share + public group metadata.

Wrong passphrase → `decode_bfshare_package` returns `PackageError::Decrypt`
(from Bucket B's new error taxonomy) → UI shows "Incorrect passphrase."
No timing side-channel because the AEAD is the authenticator.

### Storage helper changes

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/storage.ts`:
- Bump key to `igloo-pwa.state.v2`.
- On load: `localStorage.getItem('igloo-pwa.state.v2')`; if absent, start
  from defaults. If `v1` is present, **delete it** (hard-cut cleanup) —
  prevents v1 secrets from lingering on disk.
- Add a lint/unit test: `PwaPersistedState` TypeScript type must not
  contain any of the stripped field names. CI grep:
  `rg 'stored_password|runtime_snapshot_json|unlockPhrase|generatedKeyset|pendingLoadConfirmation|pendingOnboardConnection' src/lib/types.ts` returns no matches.
- Debounce persist writes: `leading: false, trailing: true, maxWait: 500ms`.
  The 1-second poll loop goes away with D.5, but even without the poll
  a typing-heavy draft flow shouldn't saturate `localStorage`.

### Save-path audit

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/store.tsx`:
- Remove the effect that does `savePersistedState(state)` on every state
  change (lines ~256-262). Replace with a debounced save that sifts
  persistable fields through a narrow `toPersistable(state)` function —
  explicit allow-list of fields that are safe to persist.
- No field is persisted unless it's in the allow-list. Adding a new field
  defaults to non-persisted.

### Test coverage

- `v1_localStorage_migrated_to_v2_drops_secrets` — seed `localStorage`
  with a v1 blob containing `stored_password` and `runtime_snapshot_json`;
  boot the app; assert v1 key is gone and v2 key exists with neither
  secret.
- `persist_allowlist_rejects_new_secret_fields` — assert `toPersistable(state)`
  does not include any field matching the forbidden names.
- `session_start_prompts_for_passphrase_when_no_stored_password` — boot,
  click "Start Signer", assert passphrase prompt appears.
- `wrong_passphrase_on_decrypt_surfaces_clean_error` — bad passphrase,
  assert UI shows "Incorrect passphrase", no partial state write, no
  thrown `Error` leaks.

---

## D.2 — `Secret<T>` wrapper + allow-list redactor

### The realistic threat model

JavaScript strings are immutable. The string engine may retain copies in
string interning, GC generations, or V8 representation caches. `string`
cannot be zeroized after use. `Uint8Array` **can** be zeroized via
`.fill(0)`.

`Secret<T>` is therefore NOT a zeroization guarantee — it is:
1. **Type-level hygiene**: you can't accidentally pass a `Secret<string>`
   to a function expecting `string` without an explicit `expose()` call.
2. **Log safety**: `JSON.stringify(secret)` returns `"<redacted>"`.
   `toString()` returns `"Secret(<redacted>)"`.
3. **Accidental-copy prevention**: `expose()` is named to make call sites
   greppable and reviewable.

For material that IS wipeable (`Uint8Array`), add `SecretBytes` with an
actual `wipe()` method that calls `.fill(0)`. Document the threat-model
gap loudly in the module header.

### API sketch

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/secret.ts`
(NEW):

```ts
/**
 * Type-level hygiene for secret-bearing strings.
 *
 * LIMITATIONS:
 * - JavaScript strings are immutable. This wrapper does NOT zeroize
 *   underlying memory. Use SecretBytes for material that can be wiped.
 * - Prevents accidental stringification, JSON serialization, and
 *   console logging via toJSON/toString overrides.
 */
export class Secret<T extends string = string> {
  private constructor(private readonly value: T) {}
  static of<T extends string>(value: T): Secret<T> { return new Secret(value); }
  expose(): T { return this.value; }
  toString(): string { return 'Secret(<redacted>)'; }
  toJSON(): string { return '<redacted>'; }
}

export type Passphrase = Secret<string>;
export type ShareSecretHex = Secret<string>;

/**
 * Wipeable byte-array secret. `wipe()` fills the underlying buffer
 * with zero. After wipe, `expose()` returns a zero-filled array.
 */
export class SecretBytes {
  private readonly buf: Uint8Array;
  private wiped = false;
  constructor(bytes: Uint8Array) { this.buf = new Uint8Array(bytes); }
  static fromHex(hex: string): SecretBytes { /* ... */ }
  expose(): Uint8Array {
    if (this.wiped) throw new Error('SecretBytes: already wiped');
    return this.buf;
  }
  wipe(): void {
    this.buf.fill(0);
    this.wiped = true;
  }
  toString(): string { return 'SecretBytes(<redacted>)'; }
  toJSON(): string { return '<redacted>'; }
}
```

### Migration targets

Wrap these carriers (file:line from Phase 1):
- `browser-runtime-core.ts:71` — `share_secret: string` → `Passphrase` or `ShareSecretHex` at the boundary
- `browser-runtime-core.ts:952` — share secret passed to WASM; accept `ShareSecretHex`, call `.expose()` once at the WASM call site
- `browser-onboarding/connect.ts:34,38` — `BrowserOnboardingConnection.storedPassword` → `Passphrase`
- All TS state types carrying a password / passphrase / share_secret (grep
  `rg 'password|passphrase|share_secret|seckey' repos/igloo-shared/src/ repos/igloo-pwa/src/` and migrate the carriers)

### Allow-list redactor

Replace `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/observability.ts` `redactField` substring matcher with an allow-list keyed by event type.

```ts
// observability-schema.ts (NEW)
type EventSchema = {
  readonly [domain in string]: {
    readonly [action in string]: ReadonlyArray<string>; // allowed field names
  };
};

export const EVENT_SCHEMAS: EventSchema = {
  runtime: {
    completion: ['request_id', 'kind', 'op_status', 'elapsed_ms'],
    failure: ['request_id', 'kind', 'reason_code', 'elapsed_ms'],
    status_event: ['kind', 'peer_count', 'sign_ready', 'ecdh_ready'],
    // ...
  },
  wasm: {
    loader_init: ['source'],
    // ...
  },
  // ...
};

export function sanitizeDetails(
  domain: string,
  action: string,
  details: Record<string, unknown>,
): Record<string, unknown> {
  const allowed = EVENT_SCHEMAS[domain]?.[action] ?? [];
  const out: Record<string, unknown> = {};
  for (const key of allowed) {
    if (key in details) out[key] = details[key];
  }
  return out;
}
```

Behavior:
- If an event type has no schema entry, `sanitizeDetails` returns `{}` (empty object). Fail closed.
- Any field not in the allow-list is dropped, regardless of its name or
  content. New bifrost-rs fields can't leak unless explicitly added to
  the schema.
- Adding a field to the schema is a visible code change; reviewable.

Migrate every `emitLog(...)` call that passes structured payload to go
through `sanitizeDetails(domain, action, details)`. Grep for `emitLog`
across `igloo-shared/src/` and audit each call.

### Test coverage

- `secret_jsonstringify_returns_redacted` — `JSON.stringify({p: Secret.of('abc')})` → `{"p":"<redacted>"}`.
- `secret_tostring_returns_redacted` — `String(secret)` → `"Secret(<redacted>)"`.
- `secretbytes_wipe_zeroes_buffer` — create, observe expose-before-wipe, wipe, expose throws.
- `redactor_drops_unknown_field` — feed `{ request_id: 'x', seckey: 'LEAK' }` to `sanitizeDetails('runtime', 'completion', ...)`; assert only `request_id` appears in output.
- `redactor_missing_schema_returns_empty` — feed to an unknown event type; assert `{}`.
- **Red-team test**: fuzz the serialized log output against a corpus of
  known secret fixture values (`seckey_fixture = '11'.repeat(32)` etc.);
  assert no fixture value appears in any log line. Runs across a mocked
  session with sign + ecdh + failure + readiness + onboarding events.

---

## D.3 — `request_id` correlation

### Current state

`browser-runtime-core.ts:407-412`: `pendingCommand: PendingBridgeCommand | null`. Single slot. Stored by `kind`.

`browser-runtime-core.ts:1765-1779`: dispatch matches only `kind`.

`browser-runtime-core.ts:1863-1868`: `runBridgeCommand` stores `{ kind, resolve, reject, timeoutHandle }`; no `request_id`.

Bridge envelope ALREADY has `request_id` (bifrost-codec/bridge.rs:24-28, validated non-empty ≤256 chars). Every completion event carries it.

### Target

Convert `pendingCommand` to a map:

```ts
private pendingCommands: Map<string, PendingBridgeCommand>;

// Each PendingBridgeCommand carries requestId, kind (for observability),
// resolve, reject, timeoutHandle, createdAt.
```

`runBridgeCommand(command, options)`:
1. Generate `requestId` via `crypto.randomUUID()` (or a counter + process
   prefix; but UUID is simpler and avoids local-counter collisions).
2. Pass `request_id` into the WASM call.
3. Store the command in the map keyed by `requestId`.

`dispatch(completion)`:
1. Extract `completion.request_id` (already parsed at line 1600+).
2. Look up `pendingCommands.get(request_id)`.
3. If found: resolve; delete from map.
4. If not found: emit a `runtime.stale_completion` observability event (no
   throw). Stale completions are not a bug; they happen on timeout + late
   arrival.

Kind-matching is retained only for observability logs and typed event
routing (e.g., an Ecdh completion goes to the ecdh code path even though
resolution is id-based). Kind is not used for correlation anymore.

### Ping dispatch

Current: `pendingPings: PendingPing[]`, FIFO via `.shift()`.

Verify whether bifrost-rs emits `request_id` in Ping completions. If yes,
apply the same map-based dispatch.

If no (old API): ping correlation stays peer-based (`entry.peer`).
Document as a known limitation; flag for bifrost-rs follow-up.

### Concurrency

The new shape allows multiple in-flight ops of the same kind. Current
shape allowed only one. Downstream callers must be audited for any
assumption of single-op ordering. Expected: none (operators queue ops
serially today anyway). If any turn up, fix in place.

### Test coverage

- `stale_sign_completion_does_not_resolve_next_command` — issue sign A,
  time out, issue sign B, late completion for A arrives; assert B's
  promise has not resolved.
- `concurrent_sign_and_ecdh_dispatched_correctly` — issue sign and ecdh
  back-to-back; assert each resolves with its own result even if completions
  arrive out of order.
- `unknown_request_id_emits_observability_event` — simulate a completion
  with a never-issued request_id; assert `runtime.stale_completion` event
  emitted; assert no exception thrown.

---

## D.4 — Idempotent session lifecycle

### Current state

`profile-runtime.ts:15-16`: two module globals.

Five methods (`stopSession`, `refreshSession`, `readSession`, `applyPeerPolicy`,
`clearPeerPolicies`) throw "No active browser signer session is attached
to this profile" when `activeRuntimeProfileId` drifts.

Legitimate drift under:
- React StrictMode double-mount (common in dev; the React docs explicitly
  recommend code tolerate it).
- Multi-tab (each tab has its own module globals; `stored_password`
  currently papers over this and we're removing it per D.1).
- Page reload mid-session.

### Target

Convert module globals into an object owned by the React context / store.
Each `PwaStore` instance creates a `SessionController`:

```ts
// page-runtime-host.ts
export class SessionController {
  private session: BrowserRuntimeSession | null = null;
  private profileId: string | null = null;
  private epoch = 0;

  async start(profile: PwaProfile, passphrase: Passphrase): Promise<SessionEpoch>;

  // Returns false if no session to stop, or the session is for a different
  // profile. Never throws.
  async stop(): Promise<boolean>;

  // Returns null if session is inactive. Never throws.
  async read(profileId: string, epoch: SessionEpoch): Promise<RuntimeStatus | null>;

  async refresh(profileId: string, epoch: SessionEpoch): Promise<void>;
  async applyPeerPolicy(profileId: string, epoch: SessionEpoch, policy: PeerPolicy): Promise<void>;
  async clearPeerPolicies(profileId: string, epoch: SessionEpoch): Promise<void>;
}

export type SessionEpoch = number;
```

Epoch is a monotonic counter. Every `start` bumps it. Every read/refresh/
applyPeerPolicy/clearPeerPolicies takes the caller's epoch and silently
returns `null` / no-op if the controller's current epoch is different.

### Non-throwing contract

- `stop()` is idempotent. Calling twice = second call returns `false`.
- `read()` / `refresh()` return null / no-op when inactive. Caller
  handles null naturally (UI shows "not connected").
- Only the `start()` method can throw, and only for genuine programming
  errors (bad profile, decrypt failure).

### React StrictMode handling

`useEffect` cleanup: when the effect unmounts, call `controller.stop()`.
When it re-mounts, call `controller.start()`. StrictMode double-mount
becomes start → stop → start, which is now safe.

### Multi-tab

Each tab gets its own `SessionController` via React context. No cross-tab
coordination. Each tab prompts for passphrase independently. Documented
as alpha constraint.

### Test coverage

- `stop_then_stop_returns_false` — idempotent stop.
- `read_on_stopped_session_returns_null` — no throw.
- `stale_epoch_read_returns_null` — start, stop, start (new epoch), call
  read with old epoch; assert null.
- `strictmode_double_mount_does_not_throw` — simulate start/stop/start
  sequence under fake timers; assert no unhandled rejection.

---

## D.5 — Close the bootstrap leak at the browser host

### What changes

Every poll path currently using `getRuntimeSnapshot(node)` switches to
`getRuntimeStatus(node)`. The distinction (verified in Phase 1):

- `runtime_status()` returns `RuntimeStatusSummary` — no bootstrap, no
  share.seckey.
- `snapshot_state()` returns `RuntimeSnapshotExport` — carries bootstrap.

### Call-site migration

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/page-runtime-host.ts`:
- Poll loop (1-second interval): switch from `getRuntimeSnapshot` to
  `getRuntimeStatus`.
- `buildSessionSnapshot()`: this function is only called when persisting;
  with D.1 in place, there is no persistence target for snapshot JSON.
  Delete `buildSessionSnapshot()` and its callers.

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/local-adapter/common.ts`:
- `runtime_snapshot_json` assembly — deleted along with `buildSessionSnapshot`.

### Eliminate the poll entirely (stretch)

Subscribe to `node.on('message', ...)` events and invalidate the React
state on meaningful transitions (readiness change, peer count change,
completion emitted). Poll only as a fallback every 5 seconds for
drift detection.

If the event-based approach is too risky for one bucket's scope, keep
the poll but lengthen to 5 seconds and use `runtime_status`. Leak is
closed either way.

### Test coverage

- `poll_path_never_calls_snapshot_state` — mock the WASM bridge, run the
  poll for 10 ticks, assert `snapshot_state` never called; `runtime_status`
  called each tick.
- `runtime_status_response_contains_no_seckey` — against a real WASM
  init, call `getRuntimeStatus`, assert the JSON has no `seckey` /
  `bootstrap` / `share` field.

---

## D.6 — Onboarding decrypt defenses

### Rate limit

In `subscribeMany` onevent path (browser-runtime-core.ts:1585-1636), add
a per-onboarding-request counter:

```ts
const MAX_ONBOARDING_DECRYPTS = 50;
const ONBOARDING_DECRYPT_WINDOW_MS = 30_000;

// Inside the onevent handler:
if (attemptCount >= MAX_ONBOARDING_DECRYPTS) {
  this.emitLog('warn', 'onboarding', 'decrypt_cap_reached', {
    request_id: requestId,
  });
  return;
}
attemptCount += 1;
```

The limit closes in 30 seconds (window end = onboarding timeout); after
the window, future events for the same request are ignored anyway.

### Base64 validation

`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/nip44-normalize.ts`:
Replace permissive `trim() + pad to %4` with strict validation:

```ts
const BASE64_ALPHABET = /^[A-Za-z0-9+/]+=*$/;

export function normalizeNip44PayloadForJs(value: string): string {
  const trimmed = value.trim();
  if (trimmed.length > MAX_NIP44_PAYLOAD_LEN) {
    throw new Nip44NormalizeError('payload_too_long');
  }
  if (!BASE64_ALPHABET.test(trimmed)) {
    throw new Nip44NormalizeError('invalid_base64');
  }
  const mod = trimmed.length % 4;
  return mod === 0 ? trimmed : `${trimmed}${'='.repeat(4 - mod)}`;
}
```

Invalid base64 rejected before the decrypt path — saves the decrypt
attempt, makes failure mode observable.

`MAX_NIP44_PAYLOAD_LEN`: match bifrost-codec's envelope limit from Bucket
A PR1 (64 KiB, base64-encoded → ~88 KiB string). Document the constant.

### Post-decrypt validation

Add to the onboarding receive path (`browser-runtime-core.ts:1600-1619`):

```ts
// After shape checks:
const members = envelope.payload.data.group.members;
if (!Array.isArray(members) || members.length < 1) {
  return; // bad group
}
if (!members.includes(sharePublicKey)) {
  this.emitLog('warn', 'onboarding', 'peer_not_in_group', {
    request_id: requestId,
  });
  return;
}
const uniqueMembers = new Set(members);
if (uniqueMembers.size !== members.length) {
  this.emitLog('warn', 'onboarding', 'duplicate_members', {
    request_id: requestId,
  });
  return;
}
const threshold = envelope.payload.data.group.threshold;
if (typeof threshold !== 'number' || threshold < 1 || threshold > members.length) {
  this.emitLog('warn', 'onboarding', 'bad_threshold', {
    request_id: requestId,
  });
  return;
}
```

### Validation-contract comment

Add a comment at the top of the onboarding receive path explaining the
TS/Rust split:

```
// Input validation (this function): structural shape, base64 alphabet,
// member-list consistency, threshold bounds.
// Cryptographic validation (bifrost-rs build_onboarding_runtime_snapshot):
// signature verification, group_pk derivation correctness, share validity.
// Both sides must pass; this function enforces defense-in-depth on inputs
// that cannot be validated cryptographically until decrypt succeeds.
```

### Test coverage

- `decrypt_cap_rejects_after_50_attempts` — simulate 51 adversarial relay
  events; assert only 50 decrypt attempts; assert cap-reached event
  emitted.
- `invalid_base64_rejected_before_decrypt` — feed non-alphabet chars;
  assert `Nip44NormalizeError` thrown; assert `nip44.v2.decrypt` never
  called.
- `peer_not_in_group_rejected` — construct an envelope where
  `group.members` excludes the signing peer; assert rejected with
  observability event.
- `duplicate_members_rejected`.
- `threshold_out_of_bounds_rejected` — `threshold: 0`, `threshold: members.length + 1`.

---

## D.7 — Typed readiness errors

`browser-runtime-core.ts:1357-1366`: replace the `JSON.stringify(lastReadiness)`
throw with a typed error:

```ts
// errors.ts (NEW or extended)
export class RuntimeReadinessTimeoutError extends Error {
  constructor(
    public readonly reason: 'sign' | 'ecdh',
    public readonly threshold: number,
    public readonly signingPeerCount: number,
    public readonly ecdhPeerCount: number,
    public readonly degradedReasonCount: number,
  ) {
    super(`${reason}_readiness_timeout`);
    this.name = 'RuntimeReadinessTimeoutError';
  }
}
```

No open-ended object in `message`. Callers can type-switch on the error.
If bifrost-rs later adds secret-bearing fields to `RuntimeReadiness`, they
don't appear in thrown errors by default — only the explicit scalar
fields surfaced via the typed class.

Audit the rest of `igloo-shared/src/` for other `throw new Error(\`${...}: ${JSON.stringify(obj)}\`)` patterns; migrate each to a typed class with
named scalar fields.

### Test coverage

- `prepareOperation_timeout_throws_typed_error` — trigger timeout; assert
  `err instanceof RuntimeReadinessTimeoutError`; assert `err.message` is
  `'sign_readiness_timeout'` (stable string), no embedded JSON.
- `readiness_blob_not_in_error_message` — seed readiness with a synthetic
  `secret_field = 'LEAK'` (simulating a future bifrost-rs regression);
  assert `err.message` does not contain `'LEAK'`.

---

## Critical Files

Modify (`igloo-shared`):
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/secret.ts` (NEW — `Secret<T>`, `SecretBytes`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/observability.ts` (replace deny-list with allow-list; adapt `sanitizeDetails` signature)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/observability-schema.ts` (NEW — per-event allow-list registry)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/errors.ts` (NEW or extend — `RuntimeReadinessTimeoutError` and siblings)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-runtime-core.ts` (lots — `pendingCommand` → map, `request_id` dispatch, redactor calls, bfonboard validation, rate limit, typed errors)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/nip44-normalize.ts` (strict base64 validation; `Nip44NormalizeError`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/browser-onboarding/connect.ts` (migrate `storedPassword` to `Passphrase`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/src/index.ts` (export new types)

Modify (`igloo-pwa`):
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/storage.ts` (key `v1` → `v2`; v1 cleanup; debounced save)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/types.ts` (strip secret fields from `PwaPersistedState`, `PwaProfile`, `PwaDraftState`; add `encrypted_bfshare_artifact`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/store.tsx` (replace effect with `toPersistable(state)` allow-list; remove polled snapshot persist)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/page-runtime-host.ts` (`SessionController` class; switch poll to `runtime_status`)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/local-adapter/profile-runtime.ts` (delete module globals; delegate to `SessionController`; idempotent stop/read)
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa/src/lib/local-adapter/common.ts` (delete `buildSessionSnapshot`; `runtime_snapshot_json` goes away)

Reuse (do not re-invent):
- `decode_bfshare_package` / `encode_bfshare_package` (Bucket B v2 — provides the encrypted artifact at-rest format).
- `getRuntimeStatus` WASM export — already exists, currently unused by PWA poll path.
- `crypto.randomUUID()` — standard browser API; available in all target environments.

## Verification

Per PR:

**PR13 (D.2 + D.7 — Secret + redactor + typed errors, `igloo-shared`):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared
npm run test:typecheck
npm run test
```
Plus the red-team test: `npm run test -- secret-leak-fuzz`.

**PR14 (D.3 — request_id correlation, `igloo-shared`):**
```bash
npm run test
```
Plus new correlation tests (stale completion, concurrent ops, unknown request_id).

**PR15 (D.6 — onboarding defenses, `igloo-shared`):**
```bash
npm run test
```
Plus new onboarding tests (rate limit, base64 gate, membership, threshold).

**PR16 (D.1 + D.5 — localStorage + bootstrap leak, `igloo-pwa`):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra/repos/igloo-pwa
npm run test
npm run build
```
Plus:
- Manual `rg 'stored_password|runtime_snapshot_json|unlockPhrase|generatedKeyset' src/` returns no matches in types or persisted shapes.
- Manual browser test: open dev tools → Application → localStorage → verify v2 key present, no secret-bearing fields; verify v1 key absent.
- Load, trigger session, open `node.poll` mock → assert only `runtime_status` calls, no `snapshot_state`.

**PR17 (D.4 — idempotent session, `igloo-pwa`):**
```bash
npm run test
```
Plus React StrictMode dev run: open the app with StrictMode on, trigger
session start → assert no thrown errors in console across the double-mount.

**Full-bucket verification:**
```bash
cd /home/cscott/Repos/frostr/frostr-infra
make test-prep
make test-demo
```
The `test-demo` lane exercises the full onboard → sign path end-to-end;
confirms Bucket D changes haven't regressed the demo harness.

## Cross-Repo Coordination

Bucket D ships in the **same coordinated release** as Buckets A + B + C.
No new version bumps specific to D (localStorage schema is client-only;
v1 is cleaned up on first boot of the new code).

Release notes call out:
- PWA now requires passphrase entry on every session start. No memoized
  `stored_password`.
- PWA `localStorage` schema bumped to `v2`; v1 data dropped on upgrade.
  No secrets persist between sessions.
- Each browser tab prompts independently. No shared-session transport.

Downstream submodules affected by D:
- `igloo-pwa` — primary target.
- `igloo-shared` — primary target.
- `igloo-chrome` — benefits from D.2 (allow-list redactor) and D.3
  (request_id correlation) transitively. No direct Chrome-side changes
  in Bucket D; targeted Chrome re-audit + cleanup lives in Bucket J.
- `igloo-home` — benefits from D.2 and D.3 transitively via `igloo-shared`.
  Tauri-side secret hygiene is Bucket E's domain.

## Out-of-Bucket Flags

- **Bootstrap leak at the bifrost-rs side** — `RuntimeSnapshotExport`
  still emits `bootstrap.share.seckey` hex on every `snapshot_state()`
  call. Bucket D eliminates the *use* of the leak in `igloo-pwa`; a
  deeper fix (bifrost-rs stops emitting the field on subsequent snapshots
  or splits "bootstrap capture" from "status polling" at the ABI level)
  is **Bucket K**.
- **Multi-tab shared-session transport** — each tab prompts independently
  for passphrase. If UX feedback demands cross-tab session sharing, a
  `BroadcastChannel`-based design with explicit consent is a future
  bucket.
- **True string zeroization** — JS string immutability makes this
  infeasible. `SecretBytes` is the only wipeable carrier. Documented in
  the `Secret<T>` module header.
- **Ping correlation via `request_id`** — contingent on bifrost-rs
  emitting `request_id` on ping completions. If it doesn't, flag for a
  bifrost-rs follow-up.
- **`igloo-chrome` re-audit + cleanup** — Bucket J.

## Summary

Five PRs, ~2,000 lines, across `igloo-shared` and `igloo-pwa`. Alpha, no
operator-burden concerns.

- **localStorage schema bumped to `v2`**. Every secret stripped from the
  persist path. Encrypted Bucket B artifacts replace memoized
  `stored_password`. Each session requires passphrase re-entry.
- **`Secret<T>` + `SecretBytes`** newtypes in `igloo-shared` provide
  type-level log safety and, for byte arrays, real wipe. Strings
  documented as non-zeroizable.
- **Allow-list observability redactor** replaces substring deny-list.
  New bifrost-rs fields can't leak without explicit schema opt-in.
- **`request_id`-keyed completion dispatch** replaces kind-only matching.
  Stale completions emit observability events, don't resolve the wrong
  promise.
- **Idempotent `SessionController`** replaces module-global singleton.
  React StrictMode double-mount is safe. Multi-tab operation is
  independent.
- **Bootstrap-leak use closed**: poll path moves to `runtime_status`;
  `snapshot_state` is no longer called in the hot path. With
  `runtime_snapshot_json` gone from persistence, the host never receives
  `share.seckey` on subsequent snapshot requests.
- **Onboarding-path defenses**: base64 alphabet validation, post-decrypt
  membership + threshold checks, per-request decrypt rate limit.
- **Typed readiness errors** replace `JSON.stringify(readiness)` in
  throw paths.

Ships in the same coordinated release as Buckets A + B + C.

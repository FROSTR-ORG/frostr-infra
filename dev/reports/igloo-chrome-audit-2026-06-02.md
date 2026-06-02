# igloo-chrome Re-Audit — 2026-06-02

Follow-up to [`igloo-chrome-audit-2026-04-02.md`](./igloo-chrome-audit-2026-04-02.md).
Ships in R3 (Bucket J.3). Read-only re-audit of `repos/igloo-chrome` on
`security-hardening`, verifying every 2026-04-02 finding against the current
code and checking for net-new issues introduced by the intervening refactor.

## What changed since 2026-04-02

Between the original audit and now, `igloo-chrome` underwent a substantial
structural refactor (much of it absorbed while Buckets D/E/G/H landed
shared-side). The two monoliths the original audit centered on are gone:

- `src/background.ts`: **966–1424-line monolith → 84 lines**. The control-plane
  logic moved into bounded services under `src/background/`
  (`onboarding-service.ts`, `permission-service.ts`, `runtime-service/*`,
  `profile-service/*`, `router-profiles.ts`, `state-projector.ts`).
- `src/lib/extension-runtime-host.ts`: **→ 61 lines**, now a thin facade over
  `src/lib/runtime-host/controller.ts` (~500 lines) plus focused helpers
  (`readiness.ts`, `snapshot-persistence.ts`, `diagnostics.ts`).
- `src/extension/protocol.ts`: **325-line grab-bag → 5-line re-export barrel**
  over `messages.ts` / `provider-types.ts` / `lifecycle.ts` / `runtime-types.ts`
  / `state-types.ts`, with shared types imported from `igloo-shared`.

Because of this, most of the original report's file:line references are
obsolete; this re-audit re-maps each finding to the current code.

## Disposition of 2026-04-02 findings

Legend: **Closed** = pattern eliminated. **Reduced** = still present but with
materially smaller blast radius / cleaner structure.

| # | 2026-04-02 finding | Sev | Status | Current evidence |
|---|---|---|---|---|
| 1 | `background.ts` control-plane monolith + persists derived `ExtensionAppState` | High | **Closed** | `background.ts` is 84 lines; `state-projector.ts:24-60` derives app-state **on demand** (`buildAppState()`), no persisted derived snapshots. |
| 2 | Onboarding lifecycle misleading + undefined `messageText` error path | High | **Closed** | Fixed in `background/onboarding-service.ts:149-152` (`messageText = toErrorMessage(error)` before use); lifecycle now emitted during progress, not reconstructed after. |
| 3 | `extension-runtime-host.ts` second monolith (polling, snapshot churn, state-publication) | High | **Reduced** | Now a 61-line facade over `runtime-host/controller.ts`. Singleton session state consolidated in one file (`controller.ts:54-57`); snapshot writes deduplicated (`snapshot-persistence.ts:65-80`, `persistInFlight`/`persistQueued`); polling now confined to bounded nonce readiness (`readiness.ts:25-36`, 100 ms / 5 s cap), not general sequencing. |
| 4 | App-state/lifecycle sync overhead + O(n) unlock probing | Med | **Closed** | Lifecycle is the primary store; app-state is a pure projection. `loadUnlockedProfileIds()` called once per build (`state-projector.ts:35`), not per-profile-per-publish. |
| 5 | Half-migrated long-task transport (`sendPortMessage` + `onConnect`) | Med | **Closed** | Port path retired; onboarding uses the unified `sendMessage()` with a timeout wrapper (`extension/client.ts:140-144`). No `sendPortMessage`/`onConnect` references remain. |
| 6 | UI-as-controller + `console.*` breadcrumbs in onboarding | Med | **Closed** | UI uses the store/hooks model; no `console.info`/`console.error` in the onboarding UI; diagnostics route through the structured `igloo-shared` logger. |
| 7 | Store polling + whole-app refetch + optimistic mutation | Med | **Closed** | `store.tsx` is listener-driven with an explicit `refreshAppState()`; no poll loop; logout no longer pre-emptively mutates local state. |
| 8 | `protocol.ts` monolith (unrelated concepts) | Med | **Closed** | Split into focused modules behind a 5-line re-export; shared types imported from `igloo-shared`. |
| 9 | Playwright compatibility RPC shim + duplicated readiness logic | Med | **Reduced** | Fixture down to ~312 lines; no `runtime.snapshot`/`runtime.status` RPC shim (native fetch calls only); `canProceedWhileDegraded()` centralized in `support/runtime.ts`, not duplicated. |
| 10 | Chrome test-harness size / embedded business logic | Low | **Reduced** | Leaner fixtures, helpers consolidated; residual size is genuine signer simulation (`live-signer.ts`), not duplicated orchestration. |

**No 2026-04-02 finding is left open.** Five are fully closed; four were reduced
to acceptable, well-bounded forms; the remaining one (test-harness size) is an
acceptable maintenance cost.

## Transitive adoption of Buckets A–I (shared-side hardening)

| Mechanism | igloo-chrome status |
|---|---|
| Typed runtime projections / shared wire types (G) | **Adopted** — `runtime-types.ts` / `state-types.ts` import `RuntimeStatusSummary`, `BrowserProfilePackagePayload`, etc. from `igloo-shared`; local types are thin projections. |
| Allow-list redactor `sanitizeDetails` / `EVENT_SCHEMAS` (D) | **Adopted by re-export** — `src/lib/observability.ts` re-exports `igloo-shared`; redaction is schema-driven and **fail-closed** (unknown fields dropped, not leaked). |
| Masked-by-default sensitive UI (H, igloo-ui) | **Adopted at the component level** — secret rendering is deferred to `igloo-ui` components, not reimplemented. |
| `Secret<T>` / `SecretBytes` (D) | **Not consumed.** Session unlock keys live only in memory / `session` storage (never `storage.local`); acceptable given they are never persisted. |
| `request_id` correlation (D) | **Not consumed** in the provider dispatch path. Acceptable — correlation is owned shared-side; informational only. |

**`storage.local` secret check:** only **encrypted** profile blobs
(`profile-blob.ts`) plus public metadata (active-profile id, lifecycle stage,
permission policies) are written to `storage.local`. Session keys are ephemeral.
No unencrypted secret material is persisted. This independently re-confirms the
Bucket-D-class posture for the extension.

## Net-new findings

All low-severity; none is a production security defect.

| # | Issue | Sev | Location | Action |
|---|---|---|---|---|
| N1 | `observability.test.ts` "redacts sensitive fields" asserts redaction **markers** (`[redacted:password:len=15]`), but the shared redactor **drops** unknown fields fail-closed (the field becomes `undefined`). Stale expectation — the secret is dropped, **not** leaked. | Low (test) | `tests/unit/lib/observability.test.ts:8-21` | Update the expectation to assert the field is omitted (fail-closed), or target a real `EVENT_SCHEMAS` event. → **J.4** |
| N2 | Two test mocks deep-import `igloo-shared`'s internal `src/` path. `browser-runtime-core.test.ts` is also mis-named (the monolith it referenced was split in G.2 into `runtime-api.ts`). | Low (test hygiene) | `tests/unit/lib/browser-runtime-core.test.ts:32` (`igloo-shared/src/bridge-wasm-runtime`); `tests/unit/background/router-profiles.test.ts:19` (`igloo-shared/src/profile-backup-host.ts`) | Repoint to a public/stable path where possible; rename the stale test file. → **J.4** |
| N3 | Bounded nonce-readiness polling remains (`readiness.ts:25-36`, 100 ms / 5 s). | Low (design) | `src/lib/runtime-host/readiness.ts` | Acceptable trade-off; document the rationale (no readiness event from the shared runtime yet) in a code comment. |
| N4 | Provider method dispatch carries no `request_id` correlation context. | Info | `src/background/runtime-service/mutations.ts` | No action required; correlation is owned shared-side. |

## Conclusion and J.4 scope

The original audit's central thesis — two control-plane monoliths plus a
lifecycle/state-derivation bug — is **resolved**. The extension is
security-hardening-ready. The 2026-04-02 High findings were closed not by this
re-audit's work but by the intervening refactor; this report verifies and pins
that closure.

The follow-up cleanup bucket (**J.4**) therefore collapses to the two
test-hygiene items (N1, N2) plus the optional doc comment (N3) — it is **not**
the multi-PR `background.ts`/`extension-runtime-host.ts` split that the
2026-04-02 report anticipated, because that split has already happened.

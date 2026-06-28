# igloo-home C4 Handler Error Coverage Design

_Status: Implemented 2026-06-28._
_Relates to: `dev/docs/2026-06-26-public-beta-release-plan.md` C4._
_Builds on: `dev/plans/igloo-shared-c4-adversarial-nip44-2026-06-28-design.md`._

> **For agentic workers:** this is a small feature design. Keep the
> implementation centered on `repos/igloo-home` TS-side handler tests. Do not
> add Rust crypto tests, real-WASM package tests, or cross-client E2E coverage in
> this slice.

## Problem

C4 still has a home-specific tail after the shared NIP-44 wrapper tests landed:
the Rust/Tauri backend owns real decrypt/package validation, and
`src/lib/api.ts` already maps typed `HomeError` payloads into user-facing
messages. The remaining thin point is the React handler layer that calls those
API wrappers.

If a wrong passphrase or corrupted package reaches the UI, the operator must see
the failure at the workflow surface that submitted it. Existing home tests cover
some onboard-save and API wrapper failures, but not the landing unlock modal,
the rotate-keyset generate handler, or the recover-key handler.

Grounding also found a likely unlock-modal gap: `submitWelcomeUnlock()` has a
modal-specific incorrect-password catch, but `handleStartProfileSession()`
catches start failures internally to show the dashboard load-failed panel. That
can prevent the unlock modal from surfacing the friendly retry message.

## Goal

Cover the `igloo-home` TS-side C4 handler tail by proving decrypt/package
failures surface through the unlock, rotate, and recover workflows, fixing only
the minimal handler behavior required by failing tests.

## Chosen Approach

Add focused frontend tests using the existing mocked `@/lib/api` pattern:

- landing unlock modal: `startProfileSession()` rejecting with
  `Incorrect passphrase.` should keep the modal open and show
  `Incorrect password. Please try again.`;
- rotate keyset generation: `createRotatedKeyset()` rejecting with
  `Invalid package: corrupted` should show the app error banner;
- recover key: `recoverGroupKey()` rejecting with `Incorrect passphrase.` should
  show the app error banner and avoid rendering recovered material.

Production changes are allowed only where a red-first test proves the handler
swallows or misroutes a failure.

## Alternatives Rejected

**API wrapper expansion only.** Rejected because `api-decrypt.test.ts` already
covers important wrapper mapping. The remaining release-plan wording calls out
TS-side handlers, so handler tests give higher confidence.

**Rust adversarial tests in this slice.** Rejected because the repo already
notes real decrypt lives in `src-tauri` tests. Repeating crypto-level coverage
would be broader than the TS handler tail.

**Cross-client or real-WASM E2E.** Rejected because the real-WASM
wrong-password/corrupted-package path belongs to the remaining `igloo-pwa` C4
tail.

## Scope

In scope:

1. Add focused tests in `repos/igloo-home/test/frontend/App.test.tsx` and
   `repos/igloo-home/test/frontend/RecoverKey.test.tsx`.
2. Patch `repos/igloo-home/src/App.tsx` only if the unlock modal or another
   handler fails to surface the mapped error correctly.
3. Update C4 release-plan/backlog wording after verification to show the home
   handler tail is covered.

Out of scope:

- Rust/Tauri crypto or package parser tests.
- `igloo-pwa` real-WASM wrong-password/corrupted-package tests.
- Visual or desktop harness changes.
- New shared UI components.

## Mechanism

Use the existing visual-scenario test setup:

- `App.test.tsx` already mocks all `@/lib/api` calls and renders the landing,
  dashboard, and create/rotate views.
- `RecoverKey.test.tsx` already renders the recover view with one local profile
  and a pasted `bfshare` source.

If the unlock modal failure is confirmed, make `handleStartProfileSession()`
optionally rethrow start failures for call sites that have their own localized
catch. The dashboard start button should keep the existing load-failed panel
behavior.

## Verification

Use focused checks first:

- `npm --prefix repos/igloo-home run test:unit:raw -- test/frontend/App.test.tsx`
- `npm --prefix repos/igloo-home run test:unit:raw -- test/frontend/RecoverKey.test.tsx`
- `npm --prefix repos/igloo-home run test:unit:raw`
- `npm --prefix test run test:guards:docs`

## Done When

- Unlock wrong-passphrase failures stay in the unlock modal with retry-friendly
  copy.
- Rotate and recover package/decrypt failures surface in the app error banner.
- No recovered key material renders after a recover failure.
- C4 docs track only the remaining `igloo-pwa` real-WASM tail.

## Self-Review

Placeholder scan: no TBD/TODO placeholders.

Internal consistency: tests target UI handlers, not crypto internals.

Scope check: one small `igloo-home` feature slice; `igloo-pwa` remains separate.

Ambiguity check: production code changes are conditional on red-first test
evidence.

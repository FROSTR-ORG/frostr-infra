# Hand-off: igloo-pwa Playwright `@live` integration test build-out

_Last updated: 2026-06-11_

> **Read this first.** This is the entry point for continuing the Playwright-driven
> integration-test work in the `frostr-infra` workspace. It assumes zero prior context.

## TL;DR

We are building genuine **behavioral** Playwright `@live` coverage for **igloo-pwa**
(the FROSTR threshold-signing PWA), in the cross-repo `frostr-infra` workspace. The
routinely-run lane (`make test-fast`) is dominated by `@visual` specs that seed fake
state and screenshot — they prove *rendering*, not *behavior* — so a green suite was
hiding real breakage. While building coverage we found and fixed **three** real product
bugs (a broken welcome-page UI, an onboarded device being unable to co-sign, and — newest
— operator peer-policy overrides being silently dropped on every signer restart). All are
**fixed and validated**; the first two are merged to `master`, the third is committed on
`dev` (see below). Next up: keep adding `@live` specs — **recover** execution, and a
browser-**reload** sign self-heal test.

## The user

- GitHub `cmdruid`; email `cscottdev@proton.me`. A **FROSTR maintainer**, deeply
  technical — engaged directly in nonce-protocol design trade-offs.
- **Moves fast, dislikes PR ceremony.** Explicit preferences observed: "I don't want to
  be slowed down by PRs… just merge" the existing PRs; "don't create any new PRs."
- Wants **proper fixes, not symptom patches** (he rejected a "tolerate the waste" nonce
  approach in favor of preserving state). Asks to **watch for tech debt** and capture it.
- Works on `dev` branches across all repos; merges existing PRs to `master`.

## The project

- **FROSTR** = threshold (FROST) signing for Nostr. A Rust core (`bifrost-rs`) compiles
  to WASM and is wrapped by TypeScript `igloo-*` clients. `frostr-infra` is the
  coordinating workspace: shared docs, the cross-repo test harness, `Makefile` command
  surface, and git submodule pointers under `repos/`.
- Root: `/Users/cscott/Repos/frostr/frostr-infra`. Submodules: `repos/bifrost-rs`,
  `repos/igloo-shared`, `repos/igloo-ui`, `repos/igloo-pwa`, `repos/igloo-chrome`,
  `repos/igloo-home`, `repos/igloo-shell`. Read `AGENTS.md` (always-loaded routing) and
  `test/README.md` first.
- **igloo-pwa is responder-only**: it holds a share and *answers* sign requests but
  cannot self-initiate one. To produce a real signature in a test, something else must
  initiate — we use a headless **`igloo-shell`** daemon (CLI, no desktop display).

### Test-harness shape (the important part for the next session)

- Specs: `test/igloo-pwa/specs/*.spec.ts`. Support: `test/igloo-pwa/support/{ui,pages,state,flows,shell-signer,onboard-diagnostics}.ts`. Shared infra: `test/shared/*`.
- **Tags** (in `test.describe` titles): `@live` (real relay + WASM runtime), `@visual`
  (seed-and-screenshot), `@cross-client` (multi-client; currently run by **no CI lane**).
- **Lanes** (`test/package.json` scripts, wrapped by `make`): `test-fast` =
  `--grep-invert "@live|@cross-client"` (render-only); `test-live` = `--grep @live`;
  `test-demo`. CI `release-validation.yml` runs `make test-live` + `make test-demo` on
  PRs touching these paths and on `master`.
- **Run one spec locally** (from `test/`): `npx playwright test -c ./igloo-pwa/playwright.config.ts igloo-pwa/specs/<name>.spec.ts --reporter=line`. Set `VITE_IGLOO_DEBUG=1` to surface the PWA runtime's structured logs to the browser console (capture via `page.on('console', …)`).
- **Guardrails** (`test/scripts/check-e2e-selector-contracts.sh`, `check-cross-client-imports.sh`):
  specs MUST route through `support/pages` page objects — **no raw `getByTestId`, `getByRole('button'|'tab')`, `getByLabel`, `getByPlaceholder`, or CSS-class locators in specs** (`getByText` and `getByRole('heading')` are allowed). Test-ids live in `repos/igloo-ui/src/lib/e2e-test-ids.ts` (`CRITICAL_E2E_TEST_IDS`), imported ONLY by `support/ui.ts`. An igloo-pwa spec must not reference `repos/igloo-(chrome|home)/` paths **even in a comment** (the guard greps text).
- **Key helpers** (`support/ui.ts`): `expectPwaRuntimeConnected(page)` (Tier-1: runtime started/connected, single device); `expectPwaSignerSignReady(page, expectedPeers)` (Tier-2: a peer reports `sign-ready` in the live dashboard — needs a cooperating signer online). The runtime snapshot is **not** persisted to localStorage, so read live state from the DOM, never from the partition.
- **`support/shell-signer.ts`**: `startShellSigner({ bfprofile, packageSecret, relayUrl })` builds + runs an `igloo-shell` daemon that imports a share and can `requestSign(messageHex)` (returns `signatures_hex`). Used to drive a real signature the PWA co-signs. `sign-shell.spec.ts` schnorr-verifies the result with `@noble/curves/secp256k1.js`.
- **After any `bifrost-rs` change, rebuild WASM**: `make browser-wasm-refresh` (re-vendors the bridge WASM into `igloo-shared/pwa/chrome` `public/wasm` — those blobs are tracked and must be committed).

## What's been done (2026-06-11; merge status noted per item)

- **Welcome resumable-device fix** (igloo-ui `0a93749`, igloo-pwa welcome wiring): saved
  devices from other browser partitions now render as centered Paper device cards with a
  "Resume" action inside the welcome hero, instead of an orphaned block stuck at the page
  bottom. Regression test in `repos/igloo-pwa/test/frontend/App.test.tsx`.
- **`@live` coverage added/strengthened**: promoted a shared sign-ready helper; added
  `create-keyset.spec.ts` and `sign-shell.spec.ts` (real shell-driven signature, now over
  the **onboard** path, hard-asserting a verified schnorr signature); strengthened
  import/inventory/onboarding/rotation specs. A manual multi-tab demo: `make pwa-multisig-demo`
  (`test/scripts/pwa-multisig-demo.sh`) + docs in `test/README.md`.
- **Onboarded-device-can't-sign bug FIXED** (the big one):
  - *Root cause*: the onboard handshake exchanges nonces so a new device is sign-ready in
    one round, but `startSession` relaunched the signer **fresh** (`init_runtime`),
    discarding the recipient's just-exchanged nonce pool and stranding the inviter's
    nonces → `NonceUnavailable`.
  - *Fix 1 — preserve the pool* (igloo-pwa `513af7c`): thread the ephemeral onboard
    runtime snapshot (in-memory ONLY, never persisted — its `state_hex` embeds the share
    secret, per security decision **D.1**) into the signer launch so it `restore_runtime`s
    the exchanged pool. No waste, immediate 1-round sign.
  - *Fix 2 — self-heal genuine resets* (bifrost-rs `7eeed2e`): each `NoncePool` carries a
    random 128-bit **generation id** (minted on fresh init, preserved on restore). A
    signer that truly resets (browser **reload**, where the in-memory pool is gone) bumps
    its generation; peers detect the change, discard the dead nonces, and re-sync. Adds no
    bytes to the `bfonboard` QR package (rides the live ping wire); steady-state signing
    stays 1-round. `DeviceState::VERSION` bumped 6→7. 6 new Rust unit tests.
  - Validated: full `@live` lane **8/8 green**; all `bifrost-rs` tests pass.
- **P1 Permissions + Settings `@live` specs DONE + peer-policy-override-restore bug FIXED**
  (committed on `dev`, not yet on `master`):
  - Added e2e test-ids on the peer-policy toggles (`data-peer-pubkey`/`-direction`/`-method`
    + `data-allowed` for the live effective policy, `data-override` for the operator's manual
    tri-state) and the Settings Device Profile form, plus `support/pages.ts` methods
    (igloo-ui `8ee3f38`).
  - `settings.spec.ts` (`@live`): create keyset → edit signer name/relay/timeout → Save against
    a live runtime (Save is gated on `runtimeSnapshot.active`) → reload → assert the form
    rehydrates from the persisted profile. NOTE: a reload does **not** return to a locked
    welcome — `remember_browser_state` restores the (stopped) dashboard directly, so the
    settings form reads public profile fields with no re-unlock.
  - `permissions.spec.ts` (`@live`): onboard against a headless `igloo-shell` co-signer →
    toggle a live peer policy → reload → **log out → unlock** to re-boot the signer (peer rows
    only render for an *active* runtime) → assert the override persisted. Assert on the
    **manual override** (`data-override`), NOT the effective `data-allowed` — the latter tracks
    the live negotiated capability and need not flip when you set an override.
  - *Bug found + fixed* (igloo-pwa `7339d53`): `manual_peer_policy_overrides` persist on the
    profile (and travel in export packages) but `startSession` never re-applied them to the
    runtime on restart, so every reload silently dropped the operator's overrides. Fixed at the
    host-adapter layer — `startSession` now re-applies them after boot (no `bifrost-rs`/WASM
    change). Parent commit `d9c9243` carries the specs + pointer bumps.
  - Validated: full igloo-pwa `@live` lane **10/10 green**; igloo-ui 120 + igloo-pwa 42 unit
    tests green; selector/cross-client guards pass.

## What's pending (priority order)

1. **`recover.spec.ts`** (`@live`, P2): reconstruct a real nsec from threshold shares
   (today `recover-visual` injects a fake key via `window.__IGLOO_TEST_RECOVERED_KEY__`).
2. **Browser-reload `@live` sign test**: sign, reload the PWA tab (fresh nonce generation),
   sign again — validates the generation self-heal end-to-end (currently only unit-tested).
3. Decide whether to gate `@cross-client` (`pwa-home-pairing`) in CI — it runs in no lane today.
4. Housekeeping: the three repos with work on `dev` only (`bifrost-rs`, `igloo-shared`,
   `igloo-chrome` from earlier, now also `igloo-ui` + `igloo-pwa` from this pass) still need
   their `dev` → `master` merge whenever the maintainer chooses.

All of the above are tracked in `dev/BACKLOG.md` under "Test harness / CI".

## Critical considerations (the WHY)

- **`make test-fast` proves rendering, not behavior.** It excludes `@live`. A green fast
  run is fully consistent with a broken demo — that's the gap this whole effort exists to
  close. Don't trust fast alone; the behavioral truth is in `test-live`.
- **Specs go through page objects.** The selector-contract guard will fail CI otherwise.
  New interactive elements need a `CRITICAL_E2E_TEST_IDS` entry (igloo-ui) + a `support/pages`
  method. Adding test-ids means an igloo-ui submodule change + pointer bump.
- **No secrets in localStorage (D.1).** The runtime snapshot embeds the share secret; it
  is captured and used only in-memory and never persisted. Any test or fix that touches
  the snapshot must keep it in-memory. This is why reads of live signer state come from
  the **DOM**, not the persisted partition.
- **Two hard product constraints the maintainer stated:** the `bfonboard` package must
  stay small enough for a QR code (no nonce payloads in it), and signing between two
  running devices must converge to **one round** (don't add per-signature nonce exchange).
- **Rebuild WASM after `bifrost-rs` edits**, or the PWA runs stale crypto. The prebuild
  cache watches `bifrost-bridge-wasm` but **not** its `bifrost-core`/`signer` deps, so
  force it with `make browser-wasm-refresh`.
- **Submodule workflow**: commit inside the submodule first, push its `dev`, then bump the
  pointer in the parent. Three repos (`bifrost-rs`, `igloo-shared`, `igloo-chrome`) currently
  have their work on `dev` only (no PRs, per the maintainer); the merged parent `master`
  references those `dev` commits by SHA (reachable, functional). Their `master` trails `dev`.
- **`igloo-shell` is the test sign-initiator** because the PWA is responder-only. It's a
  headless Rust daemon (no `DISPLAY`), unlike `igloo-home`. Its binary is built by the
  `shared` prebuild target; `sign-shell.spec.ts` calls `runTestPrebuild(['shared'])`.

## Suggested first action

Start the **P2 `recover.spec.ts`** (`@live`). Today `recover-visual` injects a fake key via
`window.__IGLOO_TEST_RECOVERED_KEY__` and only screenshots the success screen — there is no
real reconstruction. Drive the recover flow through the welcome profile menu
(`welcomeProfileMenuRecover`) and the `RecoverCollectSharesPanel` (collect ≥ threshold real
source packages), then assert the genuinely reconstructed nsec — not the injected stub. Use
`create-keyset.spec.ts` / `rotation-create.spec.ts` as templates for generating real threshold
artifacts via `createGeneratedBrowserArtifacts`, and `settings.spec.ts` / `permissions.spec.ts`
(just landed) as templates for the reload + page-object patterns. Run one spec from `test/`:
`npx playwright test -c ./igloo-pwa/playwright.config.ts igloo-pwa/specs/recover.spec.ts --reporter=line`.

Reusable gotchas from the permissions/settings pass: (1) a `page.reload()` lands back on the
**stopped dashboard** (not a locked welcome) because `remember_browser_state` persists the view —
log out to reach the welcome when you need a fresh runtime boot; (2) the per-instance localStorage
partition (`igloo-pwa.state.v2::<sessionStorage instanceId>`) survives a same-tab reload, so scan
all `igloo-pwa.state.v2*` keys when gating on persisted state.

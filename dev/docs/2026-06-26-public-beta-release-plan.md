# FROSTR Public Beta — Release-Prep Plan

- **Status:** Draft (awaiting maintainer review)
- **Date:** 2026-06-26
- **Owner:** cmdruid
- **Scope of this spec:** Phase 0 + Phase 1 in implementation-ready detail (the
  first ship). Phases 2–3 are captured as a scoped map and will each get their
  own spec/plan cycle. The post-beta passkey feature is recorded as deferred.

## Goal

Get FROSTR ready for a **public beta** launching with three clients —
`igloo-pwa`, `igloo-chrome`, `igloo-home` — staggered, PWA first. "Ready"
means: the workspace and client repos can go public without leaking live
vulnerabilities, the known security-correctness findings are closed or
consciously accepted, each client has a working public distribution channel,
and end users have the docs to install and recover safely.

This is a **hardening and packaging** effort, not new product work. The codebase
is solid beta: the three clients are functional and tested at the
render/happy-path level, `bifrost-rs` sits ~80% covered, and the architecture is
well-documented. The gaps cluster into three buckets — security correctness,
public-repo/distribution hygiene, and end-user docs.

## Locked decisions (the framing)

| Decision | Choice |
|----------|--------|
| Maturity bar | **Public beta**, clearly labeled. Security-correctness is non-negotiable; distribution polish (auto-update, etc.) has a lower bar. |
| Security appetite | **Self-audit and fix**, then ship with a beta/security disclaimer. No external-audit gate before launch. |
| Repo strategy | **Workspace + clients all go public together** (`frostr-infra` and the launch client repos). |
| Sequencing | **Staggered, PWA first**: Phase 0 → PWA → Chrome → Home. |
| Structure | **Approach C** — a deliberately minimal shared gate (Phase 0), then self-contained per-client verticals. |
| License | **MIT, workspace-wide**, copyright "2025 FROSTR Protocol" (matches `igloo-chrome`). |
| `dev/` exposure | Fix-or-disqualify all open audit findings, then `.gitignore` the findings/archive output. Git history accepted (findings will be terminal-state by launch). |
| PWA hosting | **GitHub Pages origin + Cloudflare** (custom domain) injecting COOP/COEP/CORP via a Transform Rule. No service worker. |
| Home platforms | **macOS first.** Windows signing deferred; Linux AppImage may ship unsigned. Auto-update deferred for beta. |
| Passkey feature | **Shelved to post-beta fast-follow** (see Deferred section). |

### Open ratifications (decide at spec review)

- **Versioning scheme.** Proposed default: **per-client semver** (0.x is fine for
  beta) plus a dated workspace tag (`workspace-beta-YYYY-MM-DD` precedent), bump
  `igloo-ui` off `0.0.0` to `0.1.0`, adopt `[Unreleased]` changelog accrual in
  every package. Ratify or override before Phase 0 executes.

## Why Approach C

The shared bugs (plaintext nsec in `igloo-ui`, `Secret<T>` discipline in
`igloo-shared`) physically live in shared packages — fixing them per-client would
duplicate and drift. Flipping `frostr-infra` public *also* forces the root
hygiene work (LICENSE/SECURITY/versioning) on you regardless of client. So a thin
foundation that does exactly that cross-cutting set once, then staggered
verticals, fixes shared code once and still gets PWA out the door soon. The
discipline cost is keeping Phase 0 **minimal** — anything client-specific is
pushed down into its vertical (explicitly: Chrome's cipher → Phase 2; Home's
panic sites → Phase 3).

---

## Phase 0 — Shared release gate

The minimal cross-cutting set that the public flip forces, that fixes shared-package
security bugs, and that can't be done per-client.

### 0.1 Ground-truth two discrepancies first (cheap, removes ambiguity)

The survey sub-agents disagreed on two points; resolve them by reading the actual
lines before scoping fixes:

- nsec masking state at `repos/igloo-pwa/src/App.tsx:469` — masked or leaked?
- whether Chrome's profile master key is actually extractable
  (`repos/igloo-chrome` `profile-blob.ts`).

The skeptical reads come from the audit framework, so treat them as true until
proven otherwise.

### 0.2 Shared-layer security fixes (cross-cutting only)

- **C1 — plaintext nsec.** Mask the recovered nsec in the *shared*
  `repos/igloo-ui` `CreateImportPanel.tsx:300` (consumed by all three hosts) and
  add a masking/scrub regression test. Per-host leak surfaces (`igloo-pwa
  App.tsx`, `igloo-home App.tsx`) are verified in their own verticals.
- **C5 — `Secret<T>` discipline.** Thread `Secret<T>` through rotation/recovery
  at the `igloo-shared` boundary; decide and document the snapshot-wire `seckey`
  policy.
- **Explicitly NOT here:** C2 (Chrome cipher) → Phase 2; C9 (Home `lock().unwrap()`
  panic sites) → Phase 3. Client-local.

### 0.3 Drain the audit record

- Triage **every** open audit finding to a terminal state: fixed,
  disqualified-with-rationale, or accepted-risk. The lever is *disqualify* — not
  all 53 findings (12H/25M/16L, 2026-06-19) warrant beta code changes, but each
  needs a written terminal disposition.
- Remove live-hole enumeration from `dev/BACKLOG.md` (security section) and
  `dev/HISTORY.md` so the public trackers don't reintroduce the leak.

### 0.4 `dev/` disclosure handling

- `git rm --cached` the currently-tracked audit output under
  `dev/audit/findings/` and `dev/audit/archive/` (a `.gitignore` alone won't hide
  already-tracked files).
- Add `.gitignore` rules for `dev/audit/findings/` and `dev/audit/archive/`,
  preserving the framework (`rules/`, `templates/`, `README.md`, `RUNNER.md`,
  `TASKS.md`, the existing `NOTES.md` negations).
- **Accept git history** — past commits that added findings remain readable after
  the flip; since every finding is terminal-state by launch, this reads as
  found-and-fixed transparency. Ratified; no history rewrite.

### 0.5 Public-repo hygiene

- **LICENSE** — add MIT (`2025 FROSTR Protocol`) at the workspace root and to
  every repo missing it (`igloo-pwa`, `igloo-home`; `igloo-chrome` already has
  it; verify shared repos).
- **Root `SECURITY.md`** with a real, monitored reporting channel. Must be live
  *before* the flip — a public crypto tool with no disclosure path is a liability.
- **`CODE_OF_CONDUCT.md`** at root.
- **Beta disclaimer** banner in the root README: self-audited, no external audit
  yet, report security issues to the SECURITY.md channel, use-at-own-risk.

### 0.6 Versioning (per ratified scheme)

Bump `igloo-ui` off `0.0.0`, align frozen package versions, adopt `[Unreleased]`
changelog accrual, gate version mutation in the release process.

### 0.7 Root README outside-audience pass

`frostr-infra` becomes the public front door — make the root README read for
newcomers, not just internal contributors.

### 0.8 Cross-phase early start

**Enroll in the Apple Developer Program** now (~1 day, $99/yr) so the account
exists when Phase 3 needs Developer ID signing + notarization. With Windows
deferred, this is the only signing prerequisite with any lead time.

### Phase 0 gate

`make verify` green + new masking/`Secret` regression tests + `SECURITY.md`
reachable + zero live findings in tracked docs.

---

## Phase 1 — `igloo-pwa` to public beta (first ship)

PWA is closest to ready. With Phase 0's shared fixes landed, this vertical is
mostly distribution + docs.

1. **Verify the C1 fix flows through** to `igloo-pwa src/App.tsx:469` — confirm
   masking lands on the PWA's own surface, closing the discrepancy for real.
2. **LICENSE** file (MIT).
3. **`DEPLOYMENT.md`** — document the hosting stack: **GitHub Pages** (origin) +
   **Cloudflare** (custom domain) injecting `Cross-Origin-Opener-Policy:
   same-origin`, `Cross-Origin-Embedder-Policy: require-corp`,
   `Cross-Origin-Resource-Policy: same-origin` via a Transform Rule, HTTPS
   enforcement, no service worker. (Headers are hardening, not functional — the
   app has no `SharedArrayBuffer`/threaded WASM today — but Cloudflare preserves
   full cross-origin isolation as designed.) Soften the README's "MUST" framing
   to reflect that the isolation is delivered by the front layer.
4. **End-user docs** — install / first-run walkthrough / troubleshooting /
   "what if I lost a share" recovery guidance. The app is solid but currently has
   zero user-facing docs.
5. **npm audit** — clear the 4 dev-dependency advisories (esbuild/undici);
   confirm zero production-dep vulns.
6. **Ship** — tag, deploy to Pages, point the Cloudflare domain at it, validate
   headers on the live deploy, announce as beta.

The custom domain provisioned here also hosts the **privacy policy** and
**security contact** that Chrome needs in Phase 2.

### Phase 1 gate

`make verify` + the PWA fast E2E lane green, COOP/COEP/CORP validated on the live
Cloudflare-fronted deploy, user docs published.

---

## Phase 2 — `igloo-chrome` to Web Store beta (scoped map)

Gets its own spec/plan cycle.

**Distribution channel: fresh Web Store listing; deprecate `frost2x`.**
igloo-chrome is effectively a rewrite of the signer internals, so it launches as
a **new listing** rather than as a silent auto-update to the published `frost2x`
item. This makes the move **opt-in** (no silently-swapped signer guts for
existing key-holders) and eliminates the auto-update lockout risk, the
version-monotonicity constraint, and forced permission re-consent. The trade is
starting at zero installs without frost2x's reviews/ranking — an accepted cost,
since the clean break is the honest posture for software that holds keys.

`frost2x` must be **actively deprecated**, not abandoned — an unmaintained
published signing extension is itself a liability:

- Ship a **final `frost2x` update** that marks it deprecated, points to the new
  igloo-chrome listing, and provides a **key/seed export path** so users move
  deliberately.
- **Unpublish** `frost2x` after a grace window (or leave listed-but-deprecated,
  then remove).
- igloo-chrome versions per the Phase 0 scheme — no forced jump.

Scope:

1. **C2 — profile cipher.** Write `profile-blob.test.ts` (round-trip,
   wrong-password, GCM-tag-flip, known-answer vector), unwrap the mocks, make the
   master key **non-extractable** (stop exporting it as base64). Already a
   BACKLOG item.
2. **Strip dev-only surface from the production build** — gate/remove the
   `DEBUG_COMMAND_TYPE` handlers (RELOAD, CLEAR_PROFILE_UNLOCKS) and the
   `localhost`/`127.0.0.1` dev-relay CSP rules.
3. **Scope or justify host permissions** — narrow the broad `*://*/*` set or
   document the rationale in the store listing.
4. **frost2x deprecation** — final pointer release with key/seed export; unpublish
   on a grace timeline.
5. **Privacy policy** (required by the Web Store) — host on the Phase 1 domain.
6. **Store assets** — new listing: name, screenshots, description, category,
   support contact.
7. **Submit** — budget for multi-day review latency.

### Phase 2 gate

Chrome fast E2E green, cipher tests green (un-mocked), production build verified
free of debug commands + localhost CSP, `frost2x` deprecation release shipped,
privacy policy live.

---

## Phase 3 — `igloo-home` to signed-installer beta (scoped map)

Heaviest vertical; its own spec/plan cycle. **macOS first.** Scope:

1. **C9 — triage the 25 `lock().unwrap()` IPC-reachable panic sites;** harden the
   ones that crash the backend, accept-risk the rest with rationale.
2. **Verify C1 fix** at `igloo-home App.tsx:1719–1740` and the per-host nsec
   surface.
3. **`Cargo.toml edition = "2024"`** — *verify* against the pinned
   `rust-toolchain.toml`, don't blindly downgrade (edition 2024 is valid on
   recent toolchains).
4. **Code signing + notarization (macOS)** — Apple Developer ID + notarization
   via `tauri-action`. Unsigned installers throwing Gatekeeper warnings would
   undermine trust for a security tool, so signing is required even for beta.
   Windows Authenticode **deferred**; Linux AppImage may ship unsigned.
5. **Auto-update — deferred.** Manual updates via GitHub Releases are acceptable
   for a labeled beta; document the path.
6. **Installer distribution** — GitHub Releases with signed DMG (+ unsigned
   AppImage) + checksums, plus the Makefile/CI target to build-sign-publish.

### Phase 3 gate

Home Rust + frontend tests green, signed macOS installer verified (notarization
staple check), checksums published.

---

## Deferred — Passkey (WebAuthn) unlock — post-beta fast-follow

Add opt-in passkey/biometric unlock to `igloo-pwa`, `igloo-chrome`, and (if
feasible) `igloo-home`, so users can unlock the signing device with a fingerprint
instead of a passphrase. **Shelved to a post-beta fast-follow** because it
modifies the exact encryption boundary Phases 0/2 are hardening, needs a
non-trivial secure design, and has unresolved per-client feasibility.

Design constraints to carry into its own brainstorm → spike → spec → build →
audit cycle:

- **PRF-based envelope encryption, not an auth gate.** A WebAuthn assertion is a
  boolean; gating decryption on it leaves the key in plaintext on disk. Use the
  **WebAuthn PRF extension** (CTAP2 `hmac-secret`) to derive a high-entropy secret
  (released only after user verification, never on disk) and use it to wrap the
  data-encryption key (KEK/envelope pattern).
- **Passphrase fallback is mandatory** — a passkey is device-bound; keep the
  passphrase unwrap path or a lost device = lost shares. Passkey unlock is
  *additive* UX, never a replacement.
- **Per-client feasibility spike first:**
  - PWA — solid; PRF well-supported in Chromium; the maintainer's prior
    web/electron prototype largely transfers.
  - Chrome MV3 — *uncertain*; WebAuthn from a `chrome-extension://` origin
    (RP-ID handling; only a user-gesture page like popup/options can invoke it,
    not the offscreen/background context) needs verification.
  - Home (Tauri) — likely *not* WebAuthn; system webviews (WKWebView) don't
    expose it like Safari does. The better desktop path is probably native Touch
    ID via macOS LocalAuthentication / Secure Enclave from the Rust signer — a
    different implementation.

---

## Plan-readiness summary

| Phase | Status | Next step |
|-------|--------|-----------|
| Phase 0 — shared gate | **Plan-ready** | Implementation plan (this spec) |
| Phase 1 — PWA ship | **Plan-ready** | Implementation plan (this spec) |
| Phase 2 — Chrome ship | Scoped map | Own brainstorm/spec when reached |
| Phase 3 — Home ship | Scoped map | Own brainstorm/spec when reached |
| Passkey unlock | Deferred | Own cycle post-beta; starts with feasibility spike |

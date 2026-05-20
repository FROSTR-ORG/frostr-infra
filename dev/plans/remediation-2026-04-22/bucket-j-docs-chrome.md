# Bucket J — Docs + `igloo-chrome` Re-Audit (Hard-Cut Plan)

Status: draft, pending user approval
Related: ships in R3 alongside Bucket I.

## Context

The 2026-04-22 audit synthesis identified two residual items not
covered by Buckets A–I:

1. **Doc coherence sweep.** Buckets A–H landed per-bucket doc updates
   (Bucket B wrote the new `docs/CRYPTOGRAPHY.md` sections for
   host-local v2 and portable v2 envelopes; Bucket A updated `docs/WIRE.md`
   for `MAX_BRIDGE_ENVELOPE_BYTES`; Bucket F aligned `AGENTS.md`).
   Residual: cross-link the pieces, add a "How a host integrates
   `igloo-shared`" section that didn't exist before, JSDoc every
   public export surface in `igloo-shared` post-G, and ratify the
   `docs/INDEX.md` reading order against the post-remediation state.

2. **`igloo-chrome` re-audit.** The extension was audited 2026-04-02
   and the three highest-severity findings (`background.ts` control-plane
   monolith, misleading onboarding lifecycle + undefined-variable bug,
   `extension-runtime-host.ts` second monolith) have not been verified
   since. Buckets A–I land some of the same patterns shared-side
   (typed runtime shapes, request_id correlation, allow-list redactor,
   `Secret<T>`), which may or may not cascade into `igloo-chrome`.
   A targeted re-audit determines what's still present vs. what
   transitively closed. Findings that remain get PR treatment in this
   bucket.

Alpha; hard-cut throughout.

## Scope

**In:**
- J.1 — Docs cross-link polish. Consolidate the per-bucket doc updates
  into a coherent, navigable spec set.
- J.2 — `igloo-shared` public-API documentation: JSDoc every exported
  runtime / session / flow function with expected caller order,
  thrown errors, and the cross-repo contract. New "Runtime Integration"
  section in `igloo-shared/README.md`.
- J.3 — `igloo-chrome` re-audit: produce a new dated audit report
  under `dev/reports/` that verifies which 2026-04-02 findings remain
  post-Bucket-A-through-I. Flag net-new findings if any.
- J.4 — `igloo-chrome`-specific cleanup: address findings from J.3 that
  are still present. Scope and PR count depend on what J.3 finds.

**Out of scope for Bucket J:**
- New shared-docs additions unrelated to the remediation track
  (architecture evolution notes, roadmap, etc.). Out of the remediation
  frame.
- Translation / i18n passes.
- Storybook / component gallery for `igloo-ui`. Flagged in Bucket K.

## Execution Order

Four PRs. Numbering continues from Bucket I (PR39–PR43).

| PR | Items | Submodule |
|---|---|---|
| PR44 | J.1 (doc cross-link polish) + J.2 (igloo-shared README + JSDoc) | `frostr-infra/docs/`, `repos/igloo-shared/` |
| PR45 | J.3 (igloo-chrome re-audit report) | `frostr-infra/dev/reports/` |
| PR46+ | J.4 (chrome-specific cleanup) — PR count determined by J.3 | `repos/igloo-chrome` |

PR44 and PR45 are independent. PR46+ depends on PR45's findings.

Rough touch for PR44: ~400 lines of docs + JSDoc. PR45 produces a
~250-line audit report. PR46+ unbounded — likely 3–6 PRs at Medium/High
density, fewer if Buckets A–I transitively closed most findings.

Ships in R3.

---

## J.1 — Docs cross-link polish

### Scope

After Buckets A–I, the shared docs should present a coherent picture
of the current system. Residual work:

- `docs/INDEX.md` reading order: verify every document it lists still
  exists and its section numbering matches the current content. Add
  the new `docs/CRYPTOGRAPHY.md` sections (Host-Local v2, Portable
  Package Encryption v2) and cross-link from `docs/BACKUP.md`,
  `docs/PROFILE.md`, `docs/WIRE.md`.
- `docs/WIRE.md`: include the `MAX_BRIDGE_ENVELOPE_BYTES = 65_536`
  constant and the per-field string caps (Bucket A PR4). Describe
  `request_id` correlation (Bucket D).
- `docs/PROTOCOL.md`: update any peer-messaging semantics that the
  NIP-44 consolidation (Bucket A A.5) touched. Confirm the HKDF salt
  `b"nip44-v2"` is documented as the canonical constant.
- `docs/GLOSSARY.md`: add entries for `Passphrase`, `DaemonToken`,
  `Secret<T>`, `SecretBytes`, `UnlockSession` (Bucket C terms);
  `Argon2Params`, `EncryptedProfileRecord` v2 (Bucket B); the
  `wire/` module organization (Bucket G).
- `docs/PROFILE.md`: add the "Host-Local Security Model" section
  specified in Bucket C, cross-linking `docs/CRYPTOGRAPHY.md`.
- `docs/BACKUP.md`: cross-link the Portable Package Encryption section
  in `docs/CRYPTOGRAPHY.md`; retire any language that mentions PBKDF2
  or `Aes256Gcm24` (Bucket B migrated to Argon2id + XChaCha20Poly1305).

### CI check

Extend `test/scripts/check-doc-surfaces.sh` to assert:
- Every constant named in `docs/WIRE.md` (`MAX_BRIDGE_ENVELOPE_BYTES`,
  per-field caps) exists in `bifrost-rs/crates/bifrost-codec/src/` with
  matching value.
- Every Argon2 parameter in `docs/CRYPTOGRAPHY.md` matches the defaults
  in `bifrost-core::secret::Argon2Params::default()`.
- Every bech32m HRP named in `docs/CRYPTOGRAPHY.md` exists in
  `frostr-utils/src/profile_packages.rs` and vice versa.

The check fails CI on drift. This is the enforcement mechanism for
doc-vs-code coherence — docs become the canonical spec, code must
match or CI breaks.

### Acceptance

- `npm --prefix test run test:guards` passes with the new doc-constant
  assertions.
- `docs/INDEX.md` reading order is the quick-start path for a new
  contributor; verify by having someone follow it through `make
  repo-init && make demo-onboard`.
- Every doc file cross-references every other doc file it references.

---

## J.2 — `igloo-shared` public-API documentation

### Scope

After Bucket G's structural refactor, `igloo-shared` has a well-defined
public surface (explicit named exports in `index.ts`). Add:

- JSDoc on every exported function in `runtime-api.ts` describing:
  - Parameter types and constraints.
  - Return type and success shape.
  - Thrown error types (from the typed error taxonomy in Bucket D PR13).
  - Required caller order (e.g. "must call `configureWasmBridgeLoader`
    before `createSignerNode`").
  - Cross-repo contract (e.g. "consumes the bfshare artifact produced
    by `frostr-utils::encode_bfshare_package`").
- JSDoc on every exported type in `wire/` describing:
  - Canonical field shape.
  - Which bifrost-rs crate owns the source of truth.
  - Secret-field flags (for the Bucket D allow-list redactor).

- New "Runtime Integration" section in
  `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/README.md`
  showing the canonical lifecycle:

  ```
  configureWasmBridgeLoader({ loaderImportUrl, wasmBinaryUrl })
    → configureWasmProfileLoader({ ... })
      → createSignerNode(config, adapters) : Promise<BrowserBridgeNode>
        → node.sign(...) / node.ecdh(...) / node.onboard(...)
      → stopSignerNode(node)
  ```

  Plus minimal code samples for each major flow:
  - Onboarding (bfonboard import).
  - Profile import (bfprofile).
  - Recovery (bfshare).
  - Rotation.
  - Signing (runtime).

- Cross-link from `docs/INTERFACES.md` to the new README section so the
  shared system spec points at the concrete entry points.

### Acceptance

- Every exported symbol in `igloo-shared/src/index.ts` has JSDoc.
  CI check: TypeScript `--declaration` generates `.d.ts` with
  populated doc comments.
- `igloo-shared/README.md` has a "Runtime Integration" section with
  complete lifecycle + 4 flow samples.
- `docs/INTERFACES.md` cross-references the new README section.

---

## J.3 — `igloo-chrome` re-audit

### Input

The 2026-04-02 audit at
`/home/cscott/Repos/frostr/frostr-infra/dev/reports/igloo-chrome-audit-2026-04-02.md`.
Three High-severity findings:

1. **`background.ts` control-plane monolith** + persists derived
   `ExtensionAppState` back to storage.
2. **Onboarding lifecycle synthetic progress stages** + undefined
   `messageText` in the error path (`background.ts:861-862`).
3. **`extension-runtime-host.ts` second monolith** with polling,
   snapshot churn, and repeated state-publication patterns.

Plus eight Medium/Low findings in the same report.

### Method

A focused Explore-agent pass under
`/home/cscott/Repos/frostr/frostr-infra/repos/igloo-chrome/` that:

1. **For each 2026-04-02 finding**: grep for the specific file:line
   references. Verify whether the pattern still exists.
2. **Cross-reference with Buckets A–I outcomes**: the `Secret<T>`
   wrapper (D), allow-list redactor (D), typed runtime projections (G),
   request_id correlation (D), masked-by-default sensitive primitives
   (H), typed errors (E). For each, check whether `igloo-chrome` now
   benefits transitively.
3. **New findings**: any new issues that emerged or that the
   2026-04-02 audit missed.

### Output

New file
`/home/cscott/Repos/frostr/frostr-infra/dev/reports/igloo-chrome-audit-2026-05-{DD}.md`
(date set at time of re-audit). Same format as the 2026-04-02 audit:

- Framing paragraph describing what changed since 2026-04-02.
- **Carry-forward findings**: 2026-04-02 findings that are still
  present, with updated severity (if the shared-side changes reduced
  blast radius) and updated file:line references.
- **Transitively-closed findings**: 2026-04-02 findings that Buckets
  A–I eliminated.
- **New findings**: net-new issues identified in this pass.
- **Scoped cleanup recommendations**: one-paragraph-each, mapped to
  concrete PR proposals.

### Acceptance

- Audit report committed to `dev/reports/`.
- Every 2026-04-02 finding is either carry-forward or transitively-
  closed; no finding is left undiscussed.
- Report length: 250–350 lines following prior-art format.

---

## J.4 — `igloo-chrome` cleanup PRs

### Scope

Depends entirely on J.3's carry-forward findings.

**Expected scope** (based on the 2026-04-02 findings and the transitive
closure likely from Buckets A–I):

- `background.ts` monolith split — still required. Likely transitively
  reduced because the typed runtime projections (G.4) and `Secret<T>`
  (D.2) mean `background.ts` carries less state-derivation logic now,
  but the file is structurally one giant function and needs the same
  split treatment as `browser-runtime-core.ts` got.
- Derived `ExtensionAppState` persistence — should be closable
  analogously to Bucket D's `igloo-pwa` localStorage stripping. Strip
  every secret-bearing field from the extension's `storage.local`
  writes; persist only public metadata; derive runtime state on demand.
- Onboarding lifecycle + `messageText` bug — directly fixable;
  one small PR.
- `extension-runtime-host.ts` monolith — analogous split to
  `browser-runtime-core.ts` (Bucket G PR30). Likely a 2–3 PR mini-bucket.

### PR structure (tentative, contingent on J.3)

| PR | Likely scope |
|---|---|
| PR46 | Fix `messageText` bug + rewrite onboarding lifecycle stages to reflect actual runtime transitions (not retrospective bookkeeping). |
| PR47 | Strip secret-bearing fields from extension `storage.local`; analog to Bucket D PR16. |
| PR48 | Split `background.ts` into focused modules: `ProfileService`, `RuntimeCommandService`, `PermissionPromptService`, `AppStateProjector`. |
| PR49 | Split `extension-runtime-host.ts` analogously to Bucket G PR30. Drop polling; subscribe to runtime events. |

Exact PR count and scope confirmed after J.3 lands.

### Acceptance per PR

- `make igloo-chrome-test-e2e` passes.
- `make test-demo` (the required CI gate) passes.
- Line counts drop: expect `background.ts` from its audit-cited size
  down to ≤500 lines; `extension-runtime-host.ts` similarly.

---

## Critical Files

Modify (`frostr-infra/docs/` and tests):
- `/home/cscott/Repos/frostr/frostr-infra/docs/INDEX.md` (reading order, cross-links)
- `/home/cscott/Repos/frostr/frostr-infra/docs/WIRE.md` (post-A constants, post-D request_id)
- `/home/cscott/Repos/frostr/frostr-infra/docs/PROTOCOL.md` (post-A.5 consolidation notes)
- `/home/cscott/Repos/frostr/frostr-infra/docs/GLOSSARY.md` (new terms from C, D, G)
- `/home/cscott/Repos/frostr/frostr-infra/docs/PROFILE.md` (Host-Local Security Model section)
- `/home/cscott/Repos/frostr/frostr-infra/docs/BACKUP.md` (cross-link; retire old KDF language)
- `/home/cscott/Repos/frostr/frostr-infra/docs/INTERFACES.md` (cross-link to igloo-shared README)
- `/home/cscott/Repos/frostr/frostr-infra/test/scripts/check-doc-surfaces.sh` (new doc-vs-code constant assertions)

Modify (`igloo-shared`):
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-shared/README.md` (Runtime Integration section)
- Every exported source file in `igloo-shared/src/` — add JSDoc on public exports.

Add:
- `/home/cscott/Repos/frostr/frostr-infra/dev/reports/igloo-chrome-audit-2026-05-{DD}.md` (NEW — J.3)

Modify (`igloo-chrome`) — scope contingent on J.3:
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-chrome/src/background.ts`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-chrome/src/lib/extension-runtime-host.ts`
- `/home/cscott/Repos/frostr/frostr-infra/repos/igloo-chrome/src/extension/storage.ts`
- Plus whatever J.3 surfaces.

## Verification

**PR44 (J.1 + J.2):**
```bash
cd /home/cscott/Repos/frostr/frostr-infra
npm --prefix test run test:guards
# Regression: every doc-constant match passes.
cd repos/igloo-shared
npm run build  # confirms .d.ts generation picks up JSDoc.
```

**PR45 (J.3):**
- Manual review of the new audit report against the 2026-04-02 report.
- Report committed.

**PR46+ (J.4):**
- Per PR: `make igloo-chrome-test-e2e` passes.
- Final: `make test-release` passes with the chrome E2E lane
  upgraded to cover the new split modules.

## Cross-Repo Coordination

Ships in R3 alongside Bucket I. No operator impact from docs/tests.
`igloo-chrome` cleanup PRs may change the observable extension state
shape (stripping secrets from `storage.local`); users with existing
extension state will re-enter their passphrase post-upgrade. Alpha;
no operator burden.

## Out-of-Bucket Flags

- Architectural evolution docs (roadmap, ADRs for the remediation
  decisions) — nice to have but not a remediation deliverable. Defer.
- Translation / i18n of docs — defer; English-only for alpha.
- Storybook / igloo-ui component gallery — Bucket K.
- `igloo-chrome` structural cleanup beyond what J.3 identifies — if
  additional refactoring is useful but not covered by the re-audit,
  defer to Bucket K.

## Summary

Four + PRs, docs-heavy. J.1/J.2 is bounded (doc polish + JSDoc).
J.3 produces an audit report; J.4's scope is determined by J.3's
findings but likely 3–6 PRs closing out the 2026-04-02 `igloo-chrome`
High-severity findings.

- **Docs cross-linked**: every constant in `docs/WIRE.md` /
  `docs/CRYPTOGRAPHY.md` has a CI check confirming it matches the
  code; every shared doc cross-references the related docs;
  `docs/INDEX.md` reading order verified end-to-end.
- **`igloo-shared` API documented**: JSDoc on every exported symbol;
  new "Runtime Integration" section in `README.md`; cross-link from
  `docs/INTERFACES.md`.
- **`igloo-chrome` re-audited**: fresh report in `dev/reports/`
  distinguishing carry-forward from transitively-closed findings.
- **`igloo-chrome` cleanup**: 3–6 PRs closing carry-forward findings.
  Analogous to Buckets D (storage) and G (module split) but scoped to
  the extension.

Ships in R3.

# Audit notes — shared scratchpad

Append-only shared memory for the agents running the current audit pass. Use it
for cross-cutting observations that don't belong to a single target's report:
patterns seen in more than one repo, "this looks like the same issue as X",
questions for the synthesis step, and dead-ends worth not repeating.

**Conventions**

- **Append only.** Don't edit or delete others' entries; add a new one.
- **One entry per observation**, newest at the bottom.
- **Header format:** `## YYYY-MM-DD HH:MM — <agent/target> — <topic>`
- Cite evidence as `repo/path:line` and the relevant rule ID (e.g. `ARC-03`).
- Cross-link with `[[anchor]]`-style references to other entries' topics when
  one observation builds on another.
- This file is reset at the start of each run; the prior run's copy is frozen in
  `archive/<date>/NOTES.md`. See [`TASKS.md`](./TASKS.md) Lifecycle.

---

<!-- Entries begin below. Template:

## 2026-06-13 14:30 — igloo-pwa finder — secret persistence
`igloo-pwa/src/lib/store.tsx:NNN` writes share secrets to localStorage in clear
(SEC-01). Same shape likely in igloo-chrome — flag for that finder to confirm.

-->

## 2026-06-13 09:05 — bifrost-rs finder — Argon2Params lockstep duplication

`bifrost-rs/crates/frostr-utils/src/argon2_params.rs` and
`bifrost-rs/crates/bifrost-profile/src/argon2_params.rs` carry identical
`Argon2Params` kept "in lockstep" by comment only, because of a dep cycle
(`ARC-05`). If `igloo-shared` carries its own copy of KDF params, the same
silent-divergence risk extends there — flag for that finder. Cross-platform
WASM (`frostr-utils`) vs native (`bifrost-profile`) divergence would be a silent
crypto inconsistency.

## 2026-06-13 09:20 — bifrost-rs finder — version-suffixed test files

`_v2`-suffixed test filenames (`run_marker_v2.rs`, `encryption_v2.rs`,
`package_v2.rs`) appear across multiple crates with no `_v1` counterpart and no
removal trigger (`LEG-02`). Same "named legacy in a comment but never scheduled
for removal" habit may recur in igloo-* targets — see [[compat shims without
retirement triggers]].

## 2026-06-13 09:35 — bifrost-rs finder — crypto KAT vectors absent

FROST signing tests are verify-roundtrip-only, no pinned known-answer vectors
(`TST-03`), because keygen/nonce use `OsRng` with no deterministic seam. NIP-44
in `bifrost-core::nip44` should be separately checked for pinned vectors — and
this directly connects to the igloo-shared NIP-44 path; see [[NIP-44 KDF
correctness + missing tests]].

## 2026-06-13 10:10 — igloo-shared finder — NIP-44 KDF correctness + missing tests

`igloo-shared/src/runtime-internal.ts:134-145` derives the NIP-44 conversation
key with `HMAC-SHA-256` (label as key, hex-as-bytes as message) where NIP-44
requires `HKDF-Extract(ikm=raw_shared_secret, salt='nip44-v2')` (`SEC-03`). The
onboarding path on line 1107 uses the correct `getConversationKey`, so the bug
is localized. No unit tests exist for `nip44Encrypt`/`nip44Decrypt` (`TST-01`),
so a self-consistent-but-wrong round-trip passes — a KAT would have caught it.
Pairs with the bifrost-rs KAT gap; see [[crypto KAT vectors absent]].

## 2026-06-13 10:30 — igloo-shared finder — zero rustdoc/jsdoc on bridge surfaces

bifrost-rs `bifrost-router` and `bifrost-bridge-tokio` have 0 `///` lines on
their public integration surfaces (`DOC-01`); the same undocumented-bridge
pattern was expected in the igloo-shared TS bridge layer and largely holds. The
`BrowserBridgeNode` class is the TS analogue of the god-surface problem.

## 2026-06-13 11:00 — igloo-shared / igloo-home / igloo-ui / bifrost-rs finders — secret wrappers exist but bypassed at consumers

Shared theme across SEC-01 findings: the hardened secret-lifecycle primitives
exist and are correct but are not applied at the consuming sites.
- `igloo-shared`: `Secret<T>`/`SecretBytes` exported but unused in production —
  every `shareSecret`/`seckey` is a bare `string`.
- `igloo-home`: `GeneratedKeyset.nsec` is a plain `String` with no
  `ZeroizeOnDrop`, while sibling `RecoveredGroupKey` models the correct pattern;
  the same `nsec` also lingers in React state with no scrub-on-leave.
- `bifrost-rs`: `derive_profile_encryption_key_v2` returns a bare `[u8; 32]`
  with a "caller must zeroize" comment instead of a `ZeroizeOnDrop` newtype.
- `igloo-ui`: the optional-nsec input renders unmasked plaintext while every
  other secret field uses `type="password"`.
One contract decision ("thread the existing wrapper to consumers") closes all
four. The gap likely also appears in igloo-pwa/igloo-chrome wherever they accept
`shareSecret` strings.

## 2026-06-13 11:25 — igloo-shared / igloo-chrome / igloo-shell / igloo-home / frostr-infra / igloo-ui finders — duplicated helpers, sometimes divergent

Widespread `CQ-04`/`ARC-05` duplication; the dangerous ones diverge silently:
- `igloo-shared`: two `normalizeRelays` — the rotation copy accepts
  `http://`/bare-domain URLs the canonical version rejects; also `hexToBytes`/
  `normalizeHex32`/`toErrorMessage` triplicated.
- `igloo-chrome`: two `toErrorMessage`, and two `profileKey` that mean different
  things under the same name (group-hash vs `profile.id`).
- `igloo-shell`: `profile_domain` triplicated across sibling modules;
  `resolve_profile_runtime` body duplicates `_for_passphrase`.
- `igloo-home`: `ShellPaths` struct literal copied verbatim across four test
  modules — same `bifrost-profile` path conventions shared with igloo-shell.
- `frostr-infra`: clang/wasm toolchain detection duplicated across
  `check-setup.sh` and `prepare-browser-wasm.sh`; `port_in_use` uses Linux-only
  `ss` and silently false-negatives on macOS where `igloo-pwa-dev.sh` already
  has the correct lsof-first probe.
- `igloo-ui`: parallel peer-data models (`PeerPolicy` vs `PeerReadinessRowModel`),
  duplicated clipboard helper, copied `setup-dom.ts` kept in sync by a manual
  script. The timestamp magic constant `10_000_000_000` is repeated inline and
  likely spread to igloo-pwa/igloo-chrome.

## 2026-06-13 11:50 — all-TS-targets finders — no enforced formatter (AES-06)

No Prettier/ESLint config in any TypeScript target: `frostr-infra` (`test/`),
`igloo-shared`, `igloo-ui`, `igloo-pwa`, `igloo-chrome`, `igloo-home`.
`igloo-shell` is the Rust analogue (no `rustfmt.toml`/CI gate, manual `cargo
fmt` only). Workspace-wide single decision. Adopting `eslint react-hooks` would
also retire the cargo-culted stale `eslint-disable` in `igloo-ui`
`CreateFlow.tsx:628` that currently suppresses a warning with no eslint present.

## 2026-06-13 12:15 — frostr-infra / bifrost-rs finders — CI / supply-chain drift

- `frostr-infra`: `release-validation.yml` `push` trigger targets `main` in a
  repo whose default branch is `master`, so the full release matrix never fires
  post-merge (`SEC-05`/`TST-01`). Separately, the highest-frequency workflow
  (`client-scoped-validation.yml`) uses floating `@v5`/`@stable` action pins
  while the lower-priority workflows are SHA-pinned — asymmetry worth checking
  in other submodule workflow files.
- `bifrost-rs`: CI jobs `cargo test -p` three crates that do not exist in the
  workspace (`bifrost-node`, `bifrost-transport-ws`, `bifrost-dev`) (`DOC-02`).
Both silently void coverage operators believe they have; both are ~one-line
fixes.

## 2026-06-13 12:35 — frostr-infra / bifrost-rs finders — world-broad perms + passphrase on argv/env

- Passphrase delivery: `frostr-infra` has `--passphrase <value>` on two
  `entrypoint.sh` exec calls plus a literal in the Playwright fixture
  (`SEC-05`); `bifrost-rs` devtools sets `command.env("IGLOO_SHELL_TEST_
  PASSPHRASE", ...)` — the exact inheritable-env path production already removed.
  Both visible in `/proc/<pid>/cmdline`/`/environ`. Production already knows the
  right channel (stdin pipe / `--passphrase-env` / `--passphrase-file`).
- Perms: `frostr-infra` does `chmod 0777` on the daemon socket+dir and
  `chmod -R a+rwX` on the artifact dir holding `onboard-*.password.txt`
  (`SEC-06`); `bifrost-rs` writes the encrypted device-state file with
  `File::create` (umask-dependent) while `bifrost-profile` already has
  `write_restricted_bytes_atomic(..., 0o600)`. Same "hardened helper exists,
  not used" shape as [[secret wrappers exist but bypassed at consumers]]. The
  `chmod -R a+rwX` pattern may recur in igloo-shell devnet/smoke scripts.

## 2026-06-13 13:00 — all-host finders — god file per host/crate (ARC-01)

One oversized module per target, each a named coordination bottleneck:
bifrost-rs `bifrost-signer/src/lib.rs` (4554 LOC), igloo-pwa `store.tsx` (2067)
+ `App.tsx` (1724), igloo-home `App.tsx` (~1945), igloo-ui `CreateFlow.tsx`
(1723), igloo-shared `BrowserBridgeNode` (1559, even post-PR30 extraction),
frostr-infra `test/.../live-signer.ts` (799, just under threshold). Same
extraction shape each: split along the flow seams the routing/index surface
already implies.

## 2026-06-13 13:20 — compat shims without retirement triggers

`LEG-01`/`LEG-03`/`LEG-04` cluster — something named "legacy"/"shim"/dead in a
comment but never scheduled for removal: igloo-chrome NIP-04 wired through
provider+permission surface then unconditionally throwing; igloo-ui `Modal`→
`Dialog` shim, `KeyField` "legacy" fallback, and three dead distribution-banner
props; igloo-pwa `PwaView` union members with no render branch and a never-read
`onboarding_package` field; igloo-shell exported `resolve_profile_runtime` with
no live callers; frostr-infra dead `IGLOO_SHELL_DEMO_CONTROL_TOKEN` env var with
a predictable-looking default. See also [[version-suffixed test files]].

## 2026-06-13 13:40 — igloo-chrome / igloo-pwa finders — browser page-boundary message trust

`igloo-chrome` uses `window.postMessage(..., '*')` (wildcard origin) at the
page-content boundary with no per-request nonce, allowing co-loaded scripts to
sniff/spoof NIP-07 responses (`SEC-04`). `igloo-pwa` appends the last-20 runtime
log lines into a thrown error message on onboarding failure (`SEC-02`), an
allow-list-by-assumption that leaks if bifrost-rs ever emits key material in an
`error_message`; and binds the dev server on `0.0.0.0` with no auth (`SEC-07`).
Any other host that injects a provider script shares the wildcard-origin
surface.

## 2026-06-13 13:55 — all shared-package finders — changelog/version hygiene (DOC-06)

Stalled across shared packages: bifrost-rs empty `[Unreleased]`; igloo-shared
stuck at `0.1.0`; igloo-ui at `0.0.0` with a single `[Unreleased]`; igloo-home
`0.2.0` work sitting under `[Unreleased]`. Directly at odds with the
coordinated-release / submodule-pointer-bump workflow — consumers cannot tell
what changed between pinned versions.

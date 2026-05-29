# FROSTR Remediation Handoff — 2026-05-20

This document captures the live state of the remediation track derived
from the 2026-04-22 workspace audit. Use it to resume work on a different
machine without re-deriving context.

## What this work is

A multi-bucket, multi-PR remediation track that lands hard-cut security +
quality fixes across the FROSTR workspace. The driver document is
`/home/cscott/Repos/frostr/frostr-infra/dev/plans/remediation-2026-04-22/README.md`.
The audit it remediates lives in `dev/audit/`.

**Hard-cut style:** every rename / version bump / API change lands
atomically with its consumer migration. No transitional shims, no
back-compat re-export layers. Operators re-onboard once per coordinated
release.

**Subagent execution:** one subagent per PR. Each subagent works in a
feature branch inside the affected submodule; the user reviews the branch
diff before merge.

**Three coordinated releases:** R1 (security hardening, Buckets A–F),
R2 (structural refactor, Buckets G+H), R3 (tests + docs, Buckets I+J).

## Release sequencing

| Release | Buckets | PRs | Status |
|---|---|---|---|
| R1 | A + B + C + D + E + F | 28 (some +follow-ups) | **✅ Complete — integrated on `security-hardening` 2026-05-29** |
| R2 | G + H | ~10 | Not started |
| R3 | I + J | 8+ | Not started |
| Backlog | K | 18 deferred items | Not scheduled |

## R1 Bucket status

### Bucket A — `bifrost-rs` crypto primitives (PRs 1–4) — ✅ Complete

All four PRs merged to `bifrost-rs/master`. Earliest commit `f6c4df7`,
latest `0983f98`. Adds `bifrost-core::secret` newtypes (`SharePrivateKey`,
`NoncePoolSecret`, `EcdhSharedSecret`, `RecoveredSigningKey`,
`FileStoreKey`), CT MAC compare via `subtle`, envelope bounds in
`bifrost-codec`, `DeviceState` split with `DeviceStatePersisted` DTO
(`VERSION` 5→6), and consolidates the three NIP-44 stacks into
`bifrost-core::nip44` with frozen KATs.

### Bucket B — KDF + AEAD + AAD (PRs 5–7) — ✅ Complete

All three PRs merged to `bifrost-rs/master`. Argon2id (256 MiB / t=4) +
XChaCha20Poly1305 envelope v2; explicit `Argon2Params` with `#[non_exhaustive]`;
domain-separated length-prefixed AAD; raw 16-byte salt; v1 readers removed.
Bumps `ENCRYPTED_PROFILE_VERSION` 1→2 and `BF_PACKAGE_VERSION` 1→2.

### Bucket C — host-local secret hygiene (PRs 8–12 + 12b) — ✅ Complete

| PR | Submodule | Status |
|---|---|---|
| PR8 — fs_guard helpers + atomic writes | `bifrost-rs` | ✅ merged (`50d758c`) |
| PR9 — `Passphrase` + `DaemonToken` newtypes | `bifrost-rs` | ✅ merged (`1c3d059`) |
| PR10 — daemon auth + stdin passphrase | `bifrost-rs` | ✅ merged (`0f96098`) |
| PR11 — `UnlockSession` + rotation intent journal | `bifrost-rs` | ✅ merged (`55e75c4`) |
| PR12b — bifrost-profile env-fallback removal | `bifrost-rs` | ✅ merged (`1414d6b`) |
| PR12 — consumer migration | `igloo-shell` | ✅ verified; `security-hardening` tip at `cb29a14` |

PR12 verification (full workspace, 2026-05-20):
- 57 tests across 5 binaries — **all green, 0 failures**.
- Slowest binary: `managed_integration` — 24 tests in 1381s (~23 min).
  See the slow-test investigation note below; it's not a correctness
  issue but should be fixed before R2 if test-cycle pain becomes a
  blocker.

### Bucket D — browser-host secret hygiene (PRs 13–17) — ✅ Complete

Five PRs landed across `igloo-shared` (PR13), `igloo-pwa` (PR14, 16, 16b,
17), and `igloo-chrome` (PR15). Added `Secret<T>` / `SecretBytes` TS
wrappers, `EVENT_SCHEMAS` allow-list redactor, `request_id`-keyed bridge
dispatch (Map + `stale_completion`), `RuntimeReadinessTimeoutError`,
per-instance `SessionController` with monotonic `SessionEpoch`. PR16b
stripped `share_package_json` from persisted PWA state (red-team grep
confirms 0 occurrences).

### Bucket E — shell hardening (PRs 18–24) — ✅ Complete

| PR | Scope | Submodule | Status |
|---|---|---|---|
| PR18 — Tauri CSP + capabilities | `igloo-home` | ✅ merged |
| PR19 — PWA CSP + COOP/COEP | `igloo-pwa` | ✅ merged (`a1b0f95`) |
| PR19 (Chrome side) — manifest CSP | `igloo-chrome` | ✅ merged (`6dfe68d`) |
| PR20 — WASM SHA-384 integrity | `igloo-shared` + `igloo-pwa` + `igloo-chrome` | ✅ merged (shared `842cdcd`) |
| PR21 — test-mode server gating | various | ✅ merged |
| PR22 — path canon under allowed roots | `igloo-home` | ✅ merged (`33285e1`, `85ddd69`) |
| PR23 — typed Tauri IPC errors | `igloo-home` | ✅ merged + follow-up fix (`102c377`) |
| PR24 — Tauri passphrase newtype migration | `igloo-home` | ✅ merged (`bb758af`) |

**Bucket E delivered (2026-05-29):**
- **PR20:** SHA-384 self-verifying WASM loader. Implemented entirely in
  `igloo-shared` — `build-bridge-wasm.sh` embeds the hash in the generated
  `_loader.mjs`, which fetches `_bg.wasm`, recomputes SHA-384, and throws
  `wasm_integrity_check_failed` before `WebAssembly.instantiate`. No
  `bifrost-rs` build change was needed. **Plan deviation:** the PWA had to
  be repointed from the raw `.js` glue to `_loader.mjs` (`configure-igloo-shared.ts`)
  or the check was inert; `igloo-chrome` already imported `_loader.mjs` via
  `preloadedModule`, so it needed no config change. Regression test:
  `test/igloo-pwa/specs/wasm-integrity.spec.ts` (4 cases, green).
- **PR24:** `Passphrase` newtype wired through the Tauri IPC layer in
  `igloo-home` (serde `deserialize_with` shim at the boundary, no frontend
  change). Also carried a `DaemonToken::from_hex` fix + `Cargo.lock` regen
  that repaired a latent build break of `igloo-home` against post-A/B/C
  `bifrost-rs`.

### Bucket F — workspace hardening (PRs 25–28) — ✅ Complete

Four PRs merged to the parent `frostr-infra` master (commits `7daf56a`,
`25b53a8`, `8f0ba93`, `44c2308` plus follow-ups for harness CI / xvfb
/ test-server feature gating). Non-root containers, `:ro` mounts,
`.env.example` cleanup, `data/` removal from VCS, GitHub Actions SHA
pinning, least-privilege workflow permissions, concurrency guards,
`npm ci` for test deps, demo entrypoint refactor.

## End-of-R1 coordination (after PR12 merges)

R1 lands as a single coordinated operator-migration event. Once Bucket C
is closed and PR20 / PR24 land:

1. From the parent `frostr-infra` master, `git add` the submodule
   pointers for every R1-touched repo (currently dirty per `git status`:
   bifrost-rs, igloo-chrome, igloo-home, igloo-pwa, igloo-shared,
   igloo-shell).
2. One commit titled along the lines of
   `Bump submodule pointers for R1 coordinated release`.
3. **Local-only.** Do not push without explicit user say-so.

The submodule pointer update is one commit, not 28; everything inside
the submodules is already merged to their respective `master` branches.

## Conventions in force

These were chosen explicitly by the user during execution and apply to
all future work in this track unless overridden.

- **One agent per repo at a time.** Parallel agents touching the same
  submodule cause branch-state races. Two earlier incidents (PR25/PR27
  in parent, PR28 in submodule) recovered via rebase; the rule is firm
  now.
- **Hard-cut.** No shims, no feature flags, no transitional re-export
  layers. Alpha allows this; fewer moving parts during review.
- **Local merges only.** Subagents do NOT push; the user reviews each
  branch's diff before the assistant merges.
- **`security-hardening` is the integration branch in every repo.** All
  remediation PRs land on `security-hardening`, not `master`. `master` in
  each repo (and in the parent) stays equal to `origin/master` until the
  work is reviewed end-to-end and explicitly cut over. Created 2026-05-20
  as a single batched move once the user decided the local divergence
  should not sit on `master`.
- **Merge style (onto `security-hardening`):**
  - **Submodules:** fast-forward only (`git merge --ff-only`). Linear
    history per repo.
  - **Parent repo:** `--no-ff` so each release boundary leaves a merge
    commit summarising the bundle.
- **No `Co-Authored-By` trailers.** Per `~/.claude/CLAUDE.md`.
- **DTOs over feature flags.** Persistence/wire shapes get explicit DTO
  types when their in-memory counterpart loses serde
  (`SharePackageWire`, `DeviceStatePersisted`, `ControlRequestWire`).
- **Secrets via newtypes.** `ZeroizeOnDrop`, redacted `Debug`, no serde,
  no `Clone` derive (explicit `clone_secret()`), constant-time
  `PartialEq` for 32-byte tokens via `subtle::ConstantTimeEq`.
- **NIP-44 byte-compat is non-negotiable.** Every cipher refactor pins
  KATs before changing code, then re-runs them after.

## Repo HEAD snapshot (2026-05-20)

Every repo now has two branches: `master` (pristine, equal to
`origin/master`) and `security-hardening` (the integration branch
holding all remediation track + pre-remediation onboarding-status work).
Active branch in each repo is `security-hardening`.

All branches **pushed to `origin/security-hardening`** on GitHub
(`FROSTR-ORG/*`) as of 2026-05-20.

| Repo | `security-hardening` HEAD | `master` (== origin/master) | Notes |
|---|---|---|---|
| `frostr-infra` (parent) | R1 release commit (this tip) | `4c43ef3` | R1 closeout: `--no-ff` merge `6a23cbc` (WS4/WS5b/PR20 test) + the submodule-pointer bump that is this tip |
| `repos/bifrost-rs` | `2c3037b` | `4a9d4f8` | + fast-KDF knob (`for_new_envelope`, both Argon2Params types) + devtools env rename |
| `repos/igloo-shell` | `15d2543` | `24248c0` | + WS5: managed_integration sets `BIFROST_TEST_FAST_KDF` (1381s→416s) |
| `repos/igloo-shared` | `842cdcd` | `7f9c8ab` | + PR20: self-verifying `_loader.mjs` (embedded SHA-384) + console.warn removal + regenerated artifacts |
| `repos/igloo-pwa` | `e825163` | `e12f2e5` | + PR20: loader repointed to `_loader.mjs` + synced artifacts |
| `repos/igloo-home` | `bb758af` | `eed7b7a` | + PR24: Passphrase newtype IPC migration + DaemonToken/Cargo.lock build-break fix |
| `repos/igloo-chrome` | `3111b1c` | `1d92ce0` | + PR20: synced self-verifying artifacts (already used `_loader.mjs`) |
| `repos/igloo-ui` | `87f2ac5` | `32b6188` | unchanged; will gain Bucket H work in R2 |
| `repos/igloo-paper` | (detached) | `8f29f71` | Reference-only; not touched |

**Not pushed.** R1 is integrated locally on `security-hardening` in every
repo; `master` everywhere is still pristine at `origin/master`. The L2
cutover (`security-hardening` → `master`) is deferred until R2 + R3 land
and is gated on explicit operator approval.

Note: igloo-shell's `security-hardening` is the renamed
`remediation/pr12-igloo-shell-bucket-c-migration` branch — same commits,
new name. Next R1 PRs (PR20, PR24) land on top of `cb29a14`.

## R2 / R3 dispatch entry points

When R1 closes and the user is ready:

- **R2 (Buckets G + H, ~10 PRs)** — TS structural refactor + UI hardening.
  Plans at `dev/plans/remediation-2026-04-22/bucket-g-runtime-types.md` and
  `bucket-h-ui-hardening.md`. Bucket G touches `igloo-shared` and the
  three browser hosts; Bucket H touches `igloo-ui` + `igloo-pwa`. Largest
  single PR: G PR30 (split `browser-runtime-core.ts` monolith).
- **R3 (Buckets I + J, 8+ PRs)** — residual test coverage + docs +
  `igloo-chrome` re-audit. Plans at `bucket-i-test-coverage.md` and
  `bucket-j-docs-chrome.md`.
- **Bucket K (backlog)** — 18 deferred items. Not an execution track;
  scheduled when triggers fire. Register at `bucket-k-deferred-register.md`.

Operator-impact summary for R1's coordinated release lives at the bottom
of `dev/plans/remediation-2026-04-22/README.md`.

## Live caveats / known follow-ups

- **frostr-infra harness env-var references — ✅ CLOSED (2026-05-29).**
  Investigation showed this was *not* the retired implicit fallback (that
  has zero code references): the `test/` fixtures use the still-supported
  explicit `--passphrase-env <NAME>` flag, they just reused the retired
  var's *name*. Renamed the test-chosen var
  `IGLOO_SHELL_PROFILE_PASSPHRASE` → `IGLOO_SHELL_TEST_PASSPHRASE` across
  `test/scripts/test-demo-harness-onboard.sh`,
  `test/igloo-chrome/fixtures/live-signer.ts`,
  `services/igloo-demo/entrypoint.sh`, and `bifrost-devtools/src/e2e.rs`.
  (`IGLOO_SHELL_ONBOARDING_PASSWORD` was already fully retired — comment
  only.) Note: the two sites in `test-demo-harness-onboard.sh` look
  vestigial (set/exported while `onboard` uses `--passphrase-file`);
  candidate for outright removal in a later pass.
- **bifrost-rs WASM bridge doesn't echo `request_id`** — PR14 in
  `igloo-shared` worked around this with a client-UUID map + per-kind
  FIFO tombstone. Future bifrost-rs simplification candidate.
- **Pre-existing clippy errors on `bifrost-profile` and
  `bifrost-app::runtime::health.rs`** are unrelated to this track; flagged
  so future agents don't waste time on them.
- **Argon2id double-KDF cost** in the parent + spawned daemon path made
  several `igloo-shell` integration tests flaky under the original
  timeouts. PR12 bumped them; if more flakes appear elsewhere, that's the
  first thing to check.
- **`data/` scratch dir leak — ✅ CLOSED (2026-05-29).** The leaked
  `data/test-harness/` tree (28 stale files: daemon tokens, onboarding
  passwords, sockets, encrypted vaults) was confirmed to be a *stale
  leftover* — no current script writes `data/` (the audit said as much,
  and `FROSTR_TEST_HARNESS_DIR` was unset). Fix: (1) scrubbed the stale
  tree from disk; (2) `resolve_workspace_scratch_dir()` in
  `scripts/lib-scratch.sh` now rejects any override that resolves inside
  the repo working tree but outside `<ROOT_DIR>/.tmp/` (uses `realpath -m`
  + trailing-slash prefix match; 5 cases tested incl. prefix-sibling).
  `.gitignore data/` kept as defense-in-depth.
- **`igloo-shell` integration tests are very slow — ✅ CLOSED (2026-05-29).**
  Implemented mitigation #1: `bifrost-profile` and `frostr-utils` (they
  have separate `Argon2Params` types) gained
  `Argon2Params::for_new_envelope()`, a `cfg(debug_assertions)`-gated
  resolver that returns `minimum_secure()` (64 MiB/t=3) when
  `BIFROST_TEST_FAST_KDF` is set, else `default()` (256 MiB/t=4). Release
  builds compile the branch out — production can never derive with weaker
  params. The three encrypt-side `default()` call sites now route through
  it. The `managed_integration` harness sets `BIFROST_TEST_FAST_KDF=1` on
  every spawned CLI (the daemon inherits it). Result: **1381s → 416s** (24
  passed, 0 failed). Residual is genuine non-KDF work (real daemon
  round-trips, FROST signing, sleep-polling), not Argon2.

## Where to read next

- `dev/plans/remediation-2026-04-22/README.md` — the master plan index.
- `dev/audit/workspace-audit-synthesis-2026-04-22.md` — the audit that
  drives this work.
- `dev/audit/` — per-repo audit reports.
- `dev/docs/RELEASE.md` — coordinated-release process.
- `dev/plans/remediation-2026-04-22/bucket-c-secret-hygiene.md` — the
  in-flight bucket's plan.

## Setup on the new machine

The branches are already on GitHub. To pick up where this left off:

```bash
# Clone the parent and check out the integration branch.
git clone --recurse-submodules git@github.com:FROSTR-ORG/frostr-infra.git
cd frostr-infra
git checkout security-hardening

# Point every submodule at its security-hardening branch (the parent's
# pointer is fine, but you want a real branch checked out, not a
# detached HEAD, for the next round of PR work).
git submodule foreach --recursive \
  'git fetch origin && git checkout security-hardening || true'
```

Verify state:
```bash
# Each row should show branch=security-hardening and HEAD matching the
# table above.
for path in . repos/bifrost-rs repos/igloo-shell repos/igloo-shared \
            repos/igloo-pwa repos/igloo-home repos/igloo-chrome repos/igloo-ui; do
  (cd "$path" && printf "%-20s %-22s %s\n" \
    "$(basename "$(pwd)")" "$(git branch --show-current)" \
    "$(git rev-parse --short HEAD)")
done
```

## Resume prompt

> Continuing the FROSTR remediation track from `dev/HANDOFF.md`. **R1
> (Buckets A–F) is COMPLETE and integrated locally on `security-hardening`
> in every repo** (see the HEAD snapshot table); `master` everywhere is
> still pristine at `origin/master` and nothing is pushed. All three R1
> live caveats are closed (fast-KDF knob, `data/` scrub+guard, env-var
> rename). **Next: R2 (Buckets G + H, ~10 PRs)** — TS structural refactor
> + UI hardening. Plans at `dev/plans/remediation-2026-04-22/bucket-g-runtime-types.md`
> and `bucket-h-ui-hardening.md`. Keep landing work on `security-hardening`
> (L1 merges as we go); the `master` cutover (L2) waits until R2 + R3 are
> done and the operator explicitly approves. Conventions unchanged: one
> agent per repo, hard-cut, ff-only submodules / `--no-ff` parent, local
> merges only, no `Co-Authored-By`.

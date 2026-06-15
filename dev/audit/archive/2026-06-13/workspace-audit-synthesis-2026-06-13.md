# Workspace audit synthesis

Date: 2026-06-13

Scope: All eight in-scope targets covered this pass — the parent workspace
(`frostr-infra`), the Rust signing core (`bifrost-rs`), the shared TypeScript
runtime (`igloo-shared`), the shared UI package (`igloo-ui`), and the four hosts
(`igloo-pwa`, `igloo-chrome`, `igloo-home`, `igloo-shell`). `igloo-paper` is
reference-only and excluded. WASM build artifacts and `node_modules/` were not
audited in any target.

The headline is that the deep security remediation from the prior pass largely
held: secret newtypes are zeroizing in bifrost-rs, NIP-44 was consolidated, MAC
comparisons are constant-time, file-store encryption and 0o600 perms landed in
the profile/shell layers, and daemon tokens are now random. What this pass finds
is not a regression but a **uniformity gap** — the hardened patterns exist but
were not applied everywhere they should be. The single genuinely-broken
primitive is in `igloo-shared`: the host-facing ECDH→NIP-44 conversation-key
derivation uses HMAC where NIP-44 specifies HKDF-Extract, with swapped key/IKM
roles, and it has no test that would have caught it. Around that, the debt
clusters into three recurring shapes that repeat across nearly every target:
**god files** (one per host/crate, each 1.5k–4.5k LOC), **secret-lifecycle
hardening that exists in the reference implementation but is bypassed at the
consuming sites**, and **tooling seams that drifted from the code they gate** (a
CI push trigger on a nonexistent branch, CI jobs naming retired crates, and a
total absence of any TypeScript formatter across all five TS targets). None of
these is novel to one repo; the value of acting on them is that a single
decision retires the same finding in six places at once.

## Highest-signal items

The cross-cutting issues worth acting on first, in priority order. Each
references the per-target findings it aggregates.

1. **C1 — Broken NIP-44 key derivation on the ECDH path, untested.** `igloo-shared`
   finding 1 (`SEC-03`) is the only correctness bug in the pass: `nip44Encrypt`/
   `nip44Decrypt` derive the conversation key via `HMAC-SHA-256` with the
   `'nip44-v2'` label as the HMAC *key* and the hex-string-as-bytes as the
   message, where NIP-44 requires `HKDF-Extract(ikm=raw_shared_secret,
   salt='nip44-v2')`. `igloo-shared` finding 6 (`TST-01`) is its enabler — this
   path has zero unit tests, so a wrong-but-self-consistent round-trip passes.
   bifrost-rs finding 8 (`TST-03`) names the parallel gap on the Rust side
   (FROST roundtrip-only, no pinned KAT vectors). Fix the derivation, then pin
   KAT vectors at both the `igloo-shared` NIP-44 seam and the bifrost-rs FROST
   seam so this class of bug becomes catchable.

2. **C2 — Passphrases on argv / inheritable env at trust boundaries.** The
   production code already knows the right pattern (stdin pipe, `--passphrase-env`,
   `--passphrase-file`), but several callers still leak. `frostr-infra` finding 2
   (`SEC-05`) has `--passphrase <value>` on two `entrypoint.sh` exec calls plus a
   literal in the Playwright fixture; bifrost-rs finding 7 (`SEC-05`) has
   `command.env("IGLOO_SHELL_TEST_PASSPHRASE", ...)` in devtools — the exact path
   production removed. These appear in `/proc/<pid>/cmdline` and `/environ`. Route
   all of them through the out-of-band channel the production path already uses.

3. **C3 — Secret newtypes/zeroize exist but are bypassed at the consuming sites.**
   The wrappers are built and correct; the consumers pass plain strings.
   `igloo-shared` finding 3 (`SEC-01`): `Secret<T>`/`SecretBytes` are exported but
   unused in production — every `shareSecret`/`seckey` is a bare `string`.
   `igloo-home` findings 2 and 8 (`SEC-01`): `GeneratedKeyset.nsec` is a plain
   `String` with no `ZeroizeOnDrop` while the sibling `RecoveredGroupKey` models
   the correct pattern, and the same `nsec` lingers in React state with no
   scrub-on-leave. bifrost-rs finding 5 (`SEC-01`): the KDF output
   `derive_profile_encryption_key_v2` returns a bare `[u8; 32]` with a
   "caller-must-zeroize" comment instead of a `ZeroizeOnDrop` newtype.
   `igloo-ui` finding 6 (`SEC-01`): the optional-nsec input renders unmasked
   plaintext while every other secret field uses `type="password"`. One decision
   — "thread the existing wrapper to its consumers" — closes all four.

4. **C4 — One god file per host/crate.** Every target has a single oversized
   module that bundles unrelated concerns and is the named coordination
   bottleneck: bifrost-rs finding 1 (`bifrost-signer/src/lib.rs`, 4554 LOC),
   `igloo-pwa` finding 1 (`store.tsx` 2067 + `App.tsx` 1724), `igloo-home`
   finding 1 (`App.tsx` ~1945), `igloo-ui` finding 1 (`CreateFlow.tsx` 1723),
   `igloo-shared` finding 2 (`BrowserBridgeNode` 1559, post-extraction), and
   `frostr-infra` finding 7 (`live-signer.ts` 799, just under threshold). All
   `ARC-01`. The extraction pass is the same shape in each: split along the flow
   seams that already exist in the routing/index surface.

5. **C5 — No enforced formatter anywhere in TypeScript.** `AES-06` fires on every
   TS target: `frostr-infra` finding 9 (`test/`), `igloo-shared` finding 8,
   `igloo-ui` finding 7, `igloo-pwa` finding 6, `igloo-chrome` finding 5,
   `igloo-home` finding 7. `igloo-shell` finding 5 is the Rust analogue (no
   `rustfmt.toml`/CI gate, only a manual `cargo fmt` note). This is a single
   workspace-level decision (adopt Prettier + a `format:check` gate, plus an
   `eslint react-hooks` rule that would also catch the stale-deps suppression in
   `igloo-ui` finding 11) that closes seven findings.

6. **C6 — CI tooling drifted from the code it gates.** Two high-severity blind
   spots: `frostr-infra` finding 1 (`SEC-05`/`TST-01`) — `release-validation.yml`
   triggers `push` on `main` in a repo whose default branch is `master`, so the
   full release matrix never fires post-merge; and bifrost-rs finding 2
   (`DOC-02`) — CI jobs `cargo test -p` three crates (`bifrost-node`,
   `bifrost-transport-ws`, `bifrost-dev`) that do not exist in the workspace.
   Both are cheap to fix and both silently void coverage that operators believe
   they have. `frostr-infra` finding 4 (`AES-06`/`SEC-07`) is the related
   supply-chain asymmetry: the highest-frequency workflow uses floating
   `@v5`/`@stable` action pins while the lower-frequency ones are SHA-pinned.

7. **C7 — World-broad permissions on secret-bearing artifacts.** `frostr-infra`
   finding 3 (`SEC-06`): `chmod 0777` on the daemon socket and its dir, and
   `chmod -R a+rwX` on the artifact dir holding `onboard-*.password.txt`.
   bifrost-rs finding 6 (`SEC-06`): the encrypted device-state file is written
   with `File::create` (umask-dependent, world-readable under 0o022) while
   `bifrost-profile` already has `write_restricted_bytes_atomic(..., 0o600)`.
   Same theme as C3 — the hardened helper exists and is not used.

8. **C8 — Duplicated helpers with divergent or silently-wrong semantics.** The
   most dangerous is `igloo-shared` finding 4: two `normalizeRelays` where the
   rotation copy silently accepts `http://`/bare-domain URLs the canonical one
   rejects. Also `igloo-chrome` finding 3 (two `toErrorMessage`, two `profileKey`
   that mean different things under the same name), `igloo-shell` findings 2 and 4
   (`profile_domain` triplicated; `resolve_profile_runtime` body duplicated),
   `igloo-home` finding 5 (`ShellPaths` literal copied across four test modules),
   `frostr-infra` findings 5 and 6 (clang detection and `port_in_use` duplicated,
   the latter Linux-only and silently false-negative on macOS), bifrost-rs
   finding 3 (`Argon2Params` duplicated by deliberate lockstep across a dep
   cycle), and `igloo-ui` findings 2/8/9 (parallel peer-data models, duplicated
   clipboard helper, copied `setup-dom.ts`).

9. **C9 — Compatibility shims and dead surfaces with no retirement trigger.**
   `igloo-chrome` finding 1 (`LEG-03`): NIP-04 is fully wired through the
   provider and permission surface, then unconditionally throws at the crypto
   layer — a permission prompt that always fails. `igloo-ui` findings 3/4/5
   (`LEG-04`/`LEG-01`): dead distribution-banner props, the `Modal`→`Dialog` shim
   and `KeyField` "legacy" fallback with no removal milestone. `igloo-pwa`
   findings 2 and 12 (`LEG-04`): `PwaView` union members with no render branch
   and a never-read `onboarding_package` field. `igloo-shell` finding 1
   (`LEG-04`): an exported `resolve_profile_runtime` with no live callers.

10. **C10 — Changelog/version hygiene stalled across shared packages.** `DOC-06`
    everywhere: bifrost-rs finding 10 (empty `[Unreleased]`), `igloo-shared`
    finding 10 (stuck at `0.1.0`), `igloo-ui` finding 10 (`0.0.0`, single
    `[Unreleased]`), `igloo-home` finding 10 (`0.2.0` work sitting under
    `[Unreleased]`). Consumers bumping submodule pointers cannot tell what
    changed — directly at odds with the coordinated-release workflow.

## Theme map

| Theme | Domains | Where it shows up |
|---|---|---|
| Secret lifecycle: wrappers exist, bypassed at consumers | `SEC-01` | `igloo-shared` 3 · `igloo-home` 2, 8 · `bifrost-rs` 5 · `igloo-ui` 6 |
| Passphrase delivery via argv / inheritable env | `SEC-05` | `frostr-infra` 2 · `bifrost-rs` 7 |
| World-broad perms on secret artifacts | `SEC-06` | `frostr-infra` 3 · `bifrost-rs` 6 |
| Crypto correctness + missing KAT/adversarial coverage | `SEC-03` `TST-01` `TST-03` `TST-02` | `igloo-shared` 1, 6 · `bifrost-rs` 8 · `igloo-pwa` 7 · `igloo-home` 3 · `igloo-chrome` 7 · `igloo-shell` 6 |
| Page-boundary message trust (wildcard origin, log-in-error leak) | `SEC-04` `SEC-02` `SEC-07` | `igloo-chrome` 2 · `igloo-pwa` 3, 11 |
| God file per host/crate | `ARC-01` | `bifrost-rs` 1 · `igloo-pwa` 1, 4 · `igloo-home` 1 · `igloo-ui` 1 · `igloo-shared` 2 · `frostr-infra` 7 |
| Duplicated helpers, sometimes divergent | `CQ-04` `ARC-05` | `igloo-shared` 4, 5 · `igloo-chrome` 3 · `igloo-shell` 2, 4 · `igloo-home` 5 · `frostr-infra` 5, 6 · `bifrost-rs` 3 · `igloo-ui` 2, 8, 9 |
| Compat shims / dead surface, no retirement trigger | `LEG-01` `LEG-03` `LEG-04` | `igloo-chrome` 1 · `igloo-ui` 3, 4, 5 · `igloo-pwa` 2, 12 · `igloo-shell` 1 · `frostr-infra` 8 |
| No enforced formatter | `AES-06` | all TS targets (`frostr-infra` 9 · `igloo-shared` 8 · `igloo-ui` 7 · `igloo-pwa` 6 · `igloo-chrome` 5 · `igloo-home` 7) + `igloo-shell` 5 (Rust) |
| CI / supply-chain drift | `SEC-05` `DOC-02` `AES-06`/`SEC-07` | `frostr-infra` 1, 4 · `bifrost-rs` 2 |
| Undocumented public surface | `DOC-01` | `bifrost-rs` 4 · `igloo-shell` 7 |
| Changelog/version hygiene | `DOC-06` | `bifrost-rs` 10 · `igloo-shared` 10 · `igloo-ui` 10 · `igloo-home` 10 |
| Magic values unnamed | `CQ-06` | `igloo-shared` 9 · `igloo-pwa` 8 · `igloo-chrome` 8 · `igloo-home` 9 · `frostr-infra` 10 |
| Panic/unwrap discipline | `CQ-02` | `igloo-home` 4 · `igloo-chrome` 4 |
| Vocabulary inconsistency (peer/member/node) | `RS-01` `RS-06` | `bifrost-rs` 11 · `igloo-chrome` 9 |

## Severity rollup

| Target | H | M | L | Total |
|---|---|---|---|---|
| `frostr-infra` | 3 | 5 | 2 | 10 |
| `bifrost-rs` | 2 | 6 | 3 | 11 |
| `igloo-shared` | 4 | 4 | 3 | 11 |
| `igloo-ui` | 1 | 6 | 4 | 11 |
| `igloo-pwa` | 3 | 5 | 4 | 12 |
| `igloo-chrome` | 2 | 4 | 3 | 9 |
| `igloo-home` | 3 | 4 | 3 | 10 |
| `igloo-shell` | 0 | 4 | 3 | 7 |
| **Totals** | **18** | **38** | **25** | **81** |

## Prioritized buckets

Findings grouped by *where the change lives*, so remediation can be sequenced.

- **Bucket A — Crypto core (`igloo-shared` + `bifrost-rs`)**: the NIP-44 KDF fix
  (`igloo-shared` 1) and the KAT-vector seams (`igloo-shared` 6, `bifrost-rs` 8).
  The bifrost-rs KDF newtype (`bifrost-rs` 5) and `Argon2Params` cycle
  (`bifrost-rs` 3) also live here. Highest correctness stakes.
- **Bucket B — Shell/harness trust boundaries (`frostr-infra` + `bifrost-rs`
  devtools + `igloo-shell`)**: passphrase delivery (`frostr-infra` 2,
  `bifrost-rs` 7), socket/artifact perms (`frostr-infra` 3, `bifrost-rs` 6),
  the dead control token (`frostr-infra` 8), and the `unsafe env::set_var`
  SAFETY note (`igloo-shell` 3).
- **Bucket C — CI / workspace config (`frostr-infra` + `bifrost-rs`)**: the
  `main`→`master` push trigger (`frostr-infra` 1), retired-crate CI jobs
  (`bifrost-rs` 2), action-pin asymmetry (`frostr-infra` 4). Plus the
  workspace-wide formatter decision (`AES-06` across all TS targets +
  `igloo-shell` 5).
- **Bucket D — Secret-wrapper threading (`igloo-shared`, `igloo-home`,
  `igloo-ui`)**: apply the existing wrappers/zeroize/masking to their consumers
  (`igloo-shared` 3, `igloo-home` 2/8, `igloo-ui` 6). One contract decision in
  `igloo-shared`, then propagated.
- **Bucket E — God-file extraction (per target)**: `bifrost-rs` 1, `igloo-pwa`
  1/4, `igloo-home` 1, `igloo-ui` 1, `igloo-shared` 2, `frostr-infra` 7. Same
  mechanical shape each; large but parallelizable.
- **Bucket F — Browser host message-trust (`igloo-chrome` + `igloo-pwa`)**:
  wildcard postMessage / spoofing (`igloo-chrome` 2), NIP-04 dead surface
  (`igloo-chrome` 1), log-lines-in-error leak (`igloo-pwa` 3), dev-server
  `0.0.0.0` bind (`igloo-pwa` 11).
- **Bucket G — Dedup & dead-surface cleanup (all targets)**: the `CQ-04`/
  `ARC-05`/`LEG-04` cluster (C8, C9). Low-risk, high-count; good filler work.
- **Bucket H — Docs hygiene (shared packages)**: changelogs/versions (C10),
  rustdoc on bridge/router and `igloo-shell-core` surfaces (`bifrost-rs` 4,
  `igloo-shell` 7), README drift (`igloo-shared` 7).

## Suggested sequence

Single-threaded order by marginal signal:

1. **NIP-44 KDF fix + KAT (Bucket A, `igloo-shared` 1 + 6).** Small, isolatable,
   and the only active correctness defect. Adding the KAT first makes the fix
   verifiable and guards against regression. Unblocks trust in every host's
   ECDH/encrypt path.
2. **CI drift fixes (Bucket C, `frostr-infra` 1 + `bifrost-rs` 2).** One-line
   each, and they restore coverage you currently think you have. Do before any
   large refactor so the safety net is real when the god-file work starts.
3. **Passphrase + perms hardening (Bucket B + C7).** Mechanical, well-understood,
   matches patterns already in the codebase; closes the remaining `SEC-05`/
   `SEC-06` gaps cheaply.
4. **Workspace formatter decision (Bucket C, `AES-06`).** Adopt once at the
   workspace level; lands an `eslint react-hooks` rule that pre-empts stale-deps
   bugs in the upcoming extraction work. Do *before* the god-file splits so the
   new files are born formatted.
5. **Secret-wrapper threading (Bucket D).** Decide the `igloo-shared` contract,
   then propagate to `igloo-home`/`igloo-ui`. Depends on nothing above but reads
   cleaner after the formatter lands.
6. **Browser message-trust (Bucket F).** Independent; schedule alongside D.
7. **God-file extraction (Bucket E).** Largest effort, lowest urgency, highest
   parallelism — one host per contributor. Best done after steps 2 and 4 so the
   net and the formatter are in place.
8. **Dedup, dead-surface, docs (Buckets G + H).** Continuous low-risk filler;
   harvest into backlog and burn down opportunistically.

## Graduating to backlog

Move to `../BACKLOG.md` as discrete, actionable items (fixes are not written
here):

- The four highest-signal cross-cutting decisions, each as a single backlog
  epic: **NIP-44 KDF + KAT** (C1), **passphrase/perms hardening** (C2 + C7),
  **workspace TS formatter + eslint react-hooks** (C5), **secret-wrapper
  threading** (C3). Each epic links the per-target findings it subsumes.
- The two CI blind spots (C6) as standalone P1 tickets — they are one-line fixes
  with outsized blast radius and should not wait behind an epic.
- The god-file extractions (C4) as one ticket per target, tagged so they can be
  picked up independently; reference the natural seams each report names.
- The dedup/dead-surface/docs items (C8/C9/C10) as a single "audit cleanup"
  rollup with a checklist, rather than one ticket each, to keep the backlog
  readable.

Leave the magic-value, vocabulary, and unwrap-discipline findings (`CQ-06`,
`RS-01`/`RS-06`, `CQ-02`) noted in the per-target reports but not promoted —
they are real but low-urgency and best fixed in passing when their files are
already open for the work above.

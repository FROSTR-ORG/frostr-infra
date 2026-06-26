# History

Completed-work log for the `frostr-infra` workspace, newest first. Open work
lives in [`BACKLOG.md`](./BACKLOG.md); full plan docs live in [`done/`](./done)
and [`plans/`](./plans).

Each curated entry is `## YYYY-MM-DD — <title>` with a one-paragraph summary and
links to commits/plans. Below the curated entries is the verbatim archive of the
former root `FOLLOWUPS.md` (migrated 2026-06-10), kept for history; its open
items were triaged into [`BACKLOG.md`](./BACKLOG.md).

## 2026-06-23 — Icon button pressed-feedback contract

Tightened the shared `igloo-ui` IconButton primitive so icon-only actions keep
the same background, border, shadow, color, opacity, and transform transition
surface as normal buttons instead of collapsing back to color-only feedback.
Validation: red/green `IconButton` primitive coverage, full
`misc-primitives` coverage, and `igloo-ui` build.

## 2026-06-23 — Paper Permissions source cleanup

Aligned the live Paper source and exported `igloo-paper` references with the
runtime Permissions naming contract. Dashboard authenticated headers now use
Permissions in the remaining modal/loading/export variants, blocked-state
operator action copy points to permissions instead of policies, and reusable
peer-permission review/profile cards now say Peer Permissions while preserving
signer-policy domain language. Validation: Paper MCP screenshot review,
`make igloo-paper-sync`, and `make igloo-paper-verify STRICT=1`.

## 2026-06-23 — Stable shared Button loading labels

Polished the shared `igloo-ui` Button loading state so actions with
`loadingLabel` reserve space for both idle and loading labels. Busy buttons now
keep their accessible name focused on the visible loading label while the hidden
idle label still prevents width jumps during async actions across PWA flows.
Validation: red/green `DesignPrimitives` coverage, focused loading/busy
coverage in `CreateFlow` and `OperatorPanels`, and `igloo-ui` build.

## 2026-06-23 — Dashboard Permissions naming contract

Removed the last stale **Policies** naming from the dashboard navigation
contract and affected PWA smoke helpers. `DashboardHeaderActions` now accepts a
`permissions` action in `igloo-ui`, the PWA dashboard caller uses that shared
contract, browser helpers query the tabpanel by the accessible name
`Permissions`, and the onboarding completion summary now says Peer Permissions
instead of Peer Policies. Validation: red/green focused `DesignNavigation`
coverage, focused `CreateFlow` summary coverage, focused PWA dashboard unit
coverage, `igloo-ui` build, PWA typecheck, and the app-shell Permissions peer
override smoke path through reload/unlock.

## 2026-06-23 — Settings Browser Settings sidebar group

Restored the Paper **Browser Settings** group as a top-level Settings sidebar
section in the shared `igloo-ui` sidebar while keeping runtime-only numeric
settings hidden when the PWA opts out of Advanced settings. The PWA page object
now asserts the Remember browser state, Open signer after import, and Prefer
install prompt controls are visible in the Settings sidebar, and the visual
manifest note now records Browser Settings as part of the aligned Paper section
order. Validation: red/green focused `OperatorSettingsSidebar` coverage,
focused Settings visual capture, focused app-shell Settings browser coverage,
and the PWA visual manifest guard.

## 2026-06-23 — Dashboard route coverage and permissions manifest cleanup

Closed a stale dashboard-permissions tracker note and expanded browser route
coverage for the routed dashboard shell. The app-shell spec now verifies
`/dashboard/settings` opens the Settings sidebar after profile unlock alongside
the existing Permissions and Recover deep-link checks. The PWA visual manifest
guard now rejects unresolved-question language on screens marked `aligned`, and
the dashboard Permissions note records the decided peer-only PWA scope instead
of carrying an old open-product-question marker. Validation: red/green visual
manifest guard and focused app-shell dashboard deep-link browser coverage.

## 2026-06-23 — Dashboard recover deep-link intent

Polished dashboard route handling so a locked visit to `/dashboard/recover`
keeps the recover intent through profile unlock and opens the dashboard-return
Collect Shares flow at the same route. The guard still normalizes stale
dashboard URLs for public/non-dashboard flows back to `/`, so Safari refresh
recovery remains defensive. Validation: red/green focused app-shell browser
coverage for `/dashboard/recover`, nearby dashboard route/deep-link browser
checks, focused PWA route unit coverage, and PWA typecheck.

## 2026-06-23 — Recover source failure review state

Polished the shared Recover **Collect Shares** failure state so completed remote
source packages stop presenting as `Ready` after reconstruction fails. Completed
sources now flip to a `Review required` badge with share-specific package and
password guidance, while incomplete sources keep their missing-field status.
Validation: red/green focused `RecoverCollectSharesPanel` coverage, full
`CreateFlow.test.tsx`, focused PWA recover unit coverage, `igloo-ui` build, and
the Recover visual capture suite.

## 2026-06-23 — Primary dashboard Paper header cleanup

Aligned the primary **Signer Dashboard** Paper source with the current dashboard
header pattern already used by the degraded and modal dashboard states. The live
Paper artboard and exported `igloo-paper` reference now use the
Dashboard / Permissions / Settings header instead of the older
Recover / Policies header, while preserving the existing signer body and footer.
Validation: Paper screenshot review, `make igloo-paper-sync`,
`make igloo-paper-verify STRICT=1`, focused signer-dashboard PWA visual capture,
visual manifest guard, and regenerated PWA visual comparison report.

## 2026-06-22 — Dashboard signing-failed visual parity

Added visual-manifest coverage for the dashboard **Signing Failed** state and
closed the exported Paper reference against the current modal flow. The PWA
visual harness now injects a runtime-only signing failure through the existing
DEV dashboard runtime seam, renders the Paper failure copy/detail/actions over
the live dashboard shell, and captures the state as `dashboard-signing-failed`.
The live Paper artboard and `igloo-paper` export now use the current dashboard
header treatment and the matching outlined dismiss affordance while preserving
the failure modal layout. Validation: red/green aligned-output capture guard,
focused signing-failed PWA visual capture, and `make igloo-paper-sync` with
strict Paper reconciliation.

## 2026-06-22 — Dashboard signing-blocked parity

Closed the dashboard **Signing Blocked** state against the current Paper source.
The PWA now projects runtime readiness blocks into the shared detailed-attention
layout with a policy/readiness relay summary, Paper-style Common Causes and
Operator Action cards, warning cause pills, and no live Peers / Pending
Approvals / Event Log sections while signing is blocked. The live Paper artboard
and `igloo-paper` export now use the current Dashboard / Permissions / Settings
header, merged degraded runtime identity card, matching cards, and the same
1440x569 visual state; the PWA visual manifest row is promoted to `aligned`.
Validation: focused PWA signing-blocked unit coverage, focused signing-blocked
PWA visual capture, `make igloo-paper-sync`, and strict Paper reconciliation.

## 2026-06-22 — Dashboard all-relays-offline parity

Closed the dashboard **All Relays Offline** state against the current Paper
source. The shared signer panel renders detailed attention states as Paper-style
Readiness and Recovery cards, suppresses the live Peers / Pending Approvals /
Event Log sections for the degraded all-relays state, and keeps Retry
Connections on the shared loading contract. The live Paper artboard and
`igloo-paper` export now use the current Dashboard / Permissions / Settings
header, merged runtime identity card, degraded signer status, and matching
state-card layout; the PWA visual manifest row is promoted to `aligned`.
Validation: focused red/green `OperatorSignerPanel` detailed-attention coverage,
focused PWA all-relays unit coverage, focused all-relays PWA visual capture,
full dashboard visual spec, PWA typecheck, strict visual-spec typecheck, visual
manifest guards, `igloo-ui` build, docs guard, `test:visual:report`, and
`make igloo-paper-sync` / `make igloo-paper-verify STRICT=1` with strict Paper
reconciliation.

## 2026-06-22 — Dashboard stopped visual parity

Added the exported Paper **Signer Stopped** dashboard state to the PWA visual
manifest and dashboard visual harness. The shared `igloo-ui` signer panel now
renders Paper's stopped-state Readiness and Next Step cards instead of live
Peers / Pending Approvals / Event Log sections, and `igloo-pwa` projects the
Paper offline relay summary copy for inactive runtime snapshots. Validation:
red/green focused `OperatorSignerPanel` coverage, red/green focused PWA
stopped-dashboard visual capture, full dashboard visual spec, strict visual
manifest capture guard, PWA typecheck, strict visual-spec typecheck, and
`igloo-ui` build.

## 2026-06-22 — Dashboard header Recover removal

Aligned the runtime dashboard header with the current Paper dashboard source by
removing the visible **Recover** action from the dashboard chrome. Recover
remains available from the locked Welcome profile menu, while stale
`/dashboard/recover` route guards stay in place for defensive normalization.
Validation: red/green `npm --prefix repos/igloo-ui test -- --run
test/DesignNavigation.test.tsx -t "Paper AuthActions dashboard header"`,
focused `igloo-pwa` dashboard/recover unit coverage, focused app-shell fast
browser coverage, and focused dashboard visual capture.

## 2026-06-22 — Settings Onboard handoff key formats

Polished the Settings **Onboard Device** package handoff summary so the remote
share identity shows both the display `npub` and raw hex public key when both
formats are available. The PWA Settings Onboard flow now verifies the same
handoff result through the consuming app path. Validation: red/green `npm
--prefix repos/igloo-ui test -- --run test/OperatorPanels.test.tsx -t "package
handoff state"`, focused Settings Onboard coverage in `igloo-ui` and
`igloo-pwa`, and full `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx`.

## 2026-06-22 — Event Log filtered count

Polished the signer dashboard Event Log filter state so the header count reflects
the visible filtered result set. Unfiltered logs still show `N events`, while an
active domain filter now reports `visible of total events` alongside the filtered
rows. Validation: red/green `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx -t "filters the diagnostics log"`, focused
Pending/Event coverage, and full `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx`.

## 2026-06-22 — Pending operation timing context

Polished the signer dashboard Pending Approvals queue for runtime operation
rows by surfacing both the operation start time and expiry in the visible row
detail and accessible row label. Pending operation rows now read as a timeline
instead of only showing response count plus timeout. Validation: red/green `npm
--prefix repos/igloo-ui test -- --run test/OperatorPanels.test.tsx -t "pending
operation start and expiry"`, focused Pending/Event coverage, and full `npm
--prefix repos/igloo-ui test -- --run test/OperatorPanels.test.tsx`.

## 2026-06-22 — Signer peer method telemetry

Polished the signer dashboard peer rows so each peer's permission-method badge
cluster is exposed as named telemetry, e.g. `Peer #2 methods: SIGN, ECDH,
PING`, while preserving the existing Paper-style colored method tokens.
Validation: red/green `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx -t "labels per-peer permission method badges"`,
focused peer telemetry coverage, and full `npm --prefix repos/igloo-ui test --
--run test/OperatorPanels.test.tsx`.

## 2026-06-22 — Recover failure live status

Polished the shared Recover **Collect Shares** failure state so the named
collection status no longer advertises readiness after a failed recovery
attempt. Failure now wins the live-status copy and directs the user back to the
highlighted source package or password fields. Validation: red/green `npm
--prefix repos/igloo-ui test -- --run test/CreateFlow.test.tsx -t "announces
recover failures"`, focused Recover/Create coverage, and full `npm --prefix
repos/igloo-ui test -- --run test/CreateFlow.test.tsx`.

## 2026-06-22 — Settings Onboard signer status

Promoted the stopped-signer blocker in the shared Settings **Onboard Device**
sponsor dialog to a named live status, so the disabled **Create Package** reason
is announced and testable like the rest of the inline sponsor-package states.
Validation: red/green `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx -t "blocks Settings Onboard Device package
creation"`, focused Settings Onboard coverage, and full `npm --prefix
repos/igloo-ui test -- --run test/OperatorPanels.test.tsx`.

## 2026-06-22 — Recover remote-source empty state

Polished the shared Recover **Collect Shares** panel for the case where no
remote source packages have been added yet. The source stack now renders a
named empty status card with Paper-style badge/detail treatment and keeps the
Add Source action available, instead of jumping from the local device share
directly to an unexplained empty source area. Validation: red/green `npm
--prefix repos/igloo-ui test -- --run test/CreateFlow.test.tsx -t "empty
remote-source"`, focused Recover/Create coverage, full `npm --prefix
repos/igloo-ui test -- --run test/CreateFlow.test.tsx`, and `npm --prefix
repos/igloo-ui run build`.

## 2026-06-22 — Event Log filter loading feedback

Polished the shared signer dashboard Event Log clear transition so the sibling
Filter control uses the shared `Button` loading contract while logs are being
cleared. The disabled filter now keeps the Paper filter content visible while
also exposing the shared spinner, `aria-busy`, and `data-loading`, and expanded
filter chips stay locked until clearing finishes. Validation: red/green `npm
--prefix repos/igloo-ui test -- --run test/OperatorPanels.test.tsx -t "locks
Event Log filter controls"`, full `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx`, `npm --prefix repos/igloo-ui test`, and `npm
--prefix repos/igloo-ui run build`.

## 2026-06-22 — Shared icon ping loading feedback

Extended the shared `igloo-ui` `IconButton` with icon-only loading semantics
and moved the older `PeerList` and `RelayList` ping actions onto that contract.
In-flight icon pings now expose stable `Pinging...` / `Pinging <relay>`
accessible labels, shared spinners, `aria-busy`, and `data-loading` while
preserving the compact icon-button treatments and latency result rows.
Validation: red/green `npm --prefix repos/igloo-ui test -- --run
test/ui/peer-list.test.tsx -t "marks a peer ping action busy"` and `npm
--prefix repos/igloo-ui test -- --run test/ui/misc-primitives.test.tsx -t
"marks manual relay pings busy"`, focused `npm --prefix repos/igloo-ui test --
--run test/ui/peer-list.test.tsx test/ui/misc-primitives.test.tsx
test/axe/primitives.test.tsx`, `npm --prefix repos/igloo-ui test`, `npm
--prefix repos/igloo-ui run build`, and `npm --prefix test run
test:typecheck:pwa`.

## 2026-06-22 — Signer peer ping loading feedback

Moved the signer dashboard per-peer ping control onto the shared `igloo-ui`
`Button` loading contract. In-flight peer pings now render the shared spinner
with `aria-busy` and `data-loading` while preserving the peer-row telemetry
labels and unavailable/local states. Validation: red/green `npm --prefix
repos/igloo-ui test -- --run test/OperatorPanels.test.tsx -t "per-peer ping
actions busy"`, full `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx`, `npm --prefix repos/igloo-ui test`, `npm
--prefix repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`,
and scoped diff whitespace checks.

## 2026-06-22 — Signer dashboard refresh loading feedback

Moved the signer dashboard peer refresh and retry-connection actions onto the
shared `igloo-ui` `Button` loading contract while preserving the Paper dashboard
classes and labels. Busy refresh/retry states now render the shared spinner with
`aria-busy` and `data-loading` instead of hand-written loading attributes only.
Validation: red/green `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx -t "dashboard peer refresh actions busy"`, full
`npm --prefix repos/igloo-ui test -- --run test/OperatorPanels.test.tsx`, `npm
--prefix repos/igloo-ui test`, `npm --prefix repos/igloo-ui run build`, `npm
--prefix test run test:typecheck:pwa`, and scoped diff whitespace checks.

## 2026-06-22 — Legacy settings save loading feedback

Polished the legacy shared `OperatorSettingsPanel` save action so it uses the
same `Button` loading contract as the newer Settings sidebar. `Save Settings`
now exposes `Saving...` with spinner, `aria-busy`, and `data-loading` instead
of a disabled text swap. Validation: red/green `npm --prefix repos/igloo-ui test
-- --run test/OperatorPanels.test.tsx -t "legacy operator settings save busy"`,
full `npm --prefix repos/igloo-ui test -- --run test/OperatorPanels.test.tsx`,
`npm --prefix repos/igloo-ui test`, `npm --prefix repos/igloo-ui run build`,
`npm --prefix test run test:typecheck:pwa`, and scoped diff whitespace checks.

## 2026-06-22 — Shared export/password loading feedback

Moved two remaining manual text-swap busy states onto the shared `igloo-ui`
`Button` loading contract. `ExportPackageModal` now disables its password
fields and exposes `Exporting...` with spinner, `aria-busy`, and `data-loading`
while backup export is running. `ProfilePasswordChangeDialog` now exposes the
same loading affordance for `Saving...` during profile password changes.
Validation: red/green `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx -t "profile password changes busy|gates export"`,
full `npm --prefix repos/igloo-ui test -- --run test/OperatorPanels.test.tsx`,
`npm --prefix repos/igloo-ui test`, `npm --prefix repos/igloo-ui run build`,
`npm --prefix test run test:typecheck:pwa`, and scoped diff whitespace checks.

## 2026-06-22 — Public task route deep links

Moved the PWA entry flows one step away from app-state-only navigation.
`igloo-pwa` now hydrates `/create`, `/import`, and `/onboard` into their first
public task screens, pushes those URLs from the Welcome actions, preserves the
route while each flow advances internally, and clears stale public-task routes
when returning to Welcome. Validation: red/green `npm --prefix repos/igloo-pwa
run test:unit:raw -- test/frontend/App.test.tsx -t "public task|routes .*
Welcome|clears the public task route"`, full `npm --prefix repos/igloo-pwa run
test:unit:raw -- test/frontend/App.test.tsx`, `npm --prefix test run
test:typecheck:pwa`, and scoped diff whitespace checks for
`repos/igloo-pwa/src/App.tsx` and `repos/igloo-pwa/test/frontend/App.test.tsx`.
Follow-up routing pass: browser navigation back to `/` from a public task now
returns to Welcome, while saved-profile load failures no longer get pulled into
the `/import` route. Validation: red/green `npm --prefix repos/igloo-pwa run
test:unit:raw -- test/frontend/App.test.tsx -t "returns from a public task route
to Welcome on browser navigation"`, focused profile-load guard, full
`npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx`,
`npm --prefix test run test:typecheck:pwa`, and scoped diff whitespace checks.

## 2026-06-22 — Recover locked-local share state

Polished the outside-runtime Recover **Collect Shares** path for locked Welcome
and Safari-refresh scenarios. `igloo-ui` now exposes a passphrase-locked local
share state and renders recovery failures as the Paper-style **Recovery Failed**
card with a share-count code pill. `igloo-pwa` now only counts the local device
share when the selected profile is actually unlocked, creates enough fixed
remote source rows when it is not, and sends only real unlocked/pasted sources
to recovery. Validation: `npm --prefix repos/igloo-ui test`, `npm --prefix
repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx`, `npm --prefix
test run test:typecheck:pwa`, `npm --prefix repos/igloo-ui run build`, `npm
--prefix test run test:guards:docs`, and scoped diff whitespace checks for the
touched `igloo-ui`/`igloo-pwa` files.

## 2026-06-22 — Stopped signer returns to locked Welcome

Fixed the passphrase-required dashboard trap seen after stopping or losing the
browser signer session. `igloo-pwa` now treats `stopSigner` as a lock transition:
the runtime snapshot and unlock passphrase are cleared, `activeView` returns to
`landing`, and the dashboard route normalizer takes the URL back to `/`. The App
regression covers unlocking a stored profile, stopping the signer, and landing
back on the locked Welcome profile list instead of showing a `Start Signer`
dashboard without a passphrase. Validation: `npm --prefix repos/igloo-pwa run
test:unit:raw -- test/frontend/App.test.tsx -t "returns to the locked welcome"`
and `npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx
-t "reloaded dashboard route|returns to the locked welcome|keeps dashboard
navigation"`.

## 2026-06-22 — Runtime sign-miss failure classification

Fixed the stale runtime failure classification that reported inbound sign nonce
misses as `op_type="ping"`. `bifrost-signer` now converts failed inbound request
handling into typed operation failures using the decrypted request payload, so a
stale/missing sign nonce drains as a `sign` failure before the router/host
fallback path can mislabel it. `bifrost-bridge-wasm` now has wrapper coverage
for the JSON shape consumed by browser hosts. Validation: `cargo test -p
bifrost-signer inbound_sign_request_failure_reports_sign_op_type --offline`,
`cargo test -p bifrost-bridge-wasm inbound_sign_nonce_miss_surfaces_sign_failure
--offline`, `cargo test -p bifrost-signer --offline`, and `cargo test -p
bifrost-bridge-wasm --offline`.

## 2026-06-22 — Export backup password-modal decision

Closed the Settings **Export Profile / Export Share** quick-copy product call.
The current Paper source and runtime implementation both use the password-modal
model: Settings opens Export Profile / Export Share, the user enters a fresh
export password, and only the resulting password-protected `bfprofile` or
`bfshare` package offers Copy / Download / Done. The shared `igloo-ui`
`ExportPackageModal` regression now asserts Copy and Download are absent in the
entry state, preserving the no quick unencrypted copy-to-clipboard decision.
Validation: `npm test -- --run test/OperatorPanels.test.tsx -t "gates export on
a matching password"` from `repos/igloo-ui`.

## 2026-06-22 — Settings Onboard handoff visual closure

Closed the remaining Settings **Onboard Device** sponsor outcome-state tracker
for the current package-handoff product model. `igloo-pwa` now has a DEV-only
visual seam for the in-memory Package Handoff result, the visual manifest tracks
`dashboard-settings-onboard-handoff` against
`repos/igloo-paper/screens/dashboard/3e-onboard-package-handoff-modal/screenshot.png`,
and `igloo-ui` now uses the Paper success check icon in the handoff banner.
The plan and audit now state the source-of-truth decision: Settings creates a
`bfonboard` package handoff; Device Onboarded / Onboarding Failed are
recipient-side onboarding states unless product later adds live recipient
tracking to Settings. Validation: `npm --prefix test run
test:e2e:igloo-pwa:visual -- --grep "Settings Onboard Device package
handoff"`.

## 2026-06-22 — Peer telemetry parity tracker cleanup

Retired the stale peer telemetry visual-parity backlog item after verifying the
current runtime-to-dashboard path. `bifrost-rs` exposes latest peer response
latency and policy-derived method capabilities, the WASM/shared runtime status
shape carries the fields, `igloo-ui` projects method badges, per-row readiness,
per-row latency, average latency, and nonce inventory history, and `igloo-pwa`
renders those live fields through the dashboard. The visual manifest already
promotes `dashboard-signer` to `aligned`; rolling latency history remains out of
scope unless product asks for more than latest response latency. Validation:
`cargo test -p bifrost-signer peer_status_reports_latest_response_latency`,
`cargo test -p bifrost-signer peer_status_reports_method_capabilities_from_policy`,
`cargo test -p bifrost-bridge-wasm runtime_metadata_peer_status_and_empty_drains_are_queryable`,
`npm --prefix repos/igloo-shared run test:unit -- src/runtime-api.test.ts`,
`npm --prefix repos/igloo-shared run test:typecheck`, `npm test -- --run
test/DesignAdapters.test.tsx -t "peer method capabilities|runtime peer method
capabilities|runtime status"`, `npm test -- --run test/OperatorPanels.test.tsx
-t "peer readiness|renders per-peer readiness|labels per-peer nonce|peer
refresh|per-peer ping|unavailable peer ping|summarizes peer readiness counts"`,
and `npm --prefix repos/igloo-pwa run test:unit:raw --
test/frontend/App.test.tsx -t "projects runtime peer method capabilities"`.

## 2026-06-22 — Pending and Event Log parity tracker cleanup

Retired the stale Pending Operations / Event Log backlog item after verifying
the current Paper, shared UI, adapter, and PWA surfaces. The exported Paper
dashboard and visual manifest already name populated Pending Approvals rows and
compact domain-tagged Event Log rows; `OperatorSignerPanel` renders the combined
pending approval/operation queue with Paper collapse controls, keeps ordinary
runtime operations out of approval prompts, and exposes Event Log filter, clear,
collapse, row, and empty states. Validation: `npm test -- --run
test/OperatorPanels.test.tsx -t "Event Log|Pending|pending approval|operation"`
and `npm test -- --run test/DesignAdapters.test.tsx -t "pending runtime
operations|observability events|runtime status"` from `repos/igloo-ui`, plus
`npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx
-t "ordinary runtime pending operations|fallback log filtering|dashboard
projects runtime"`.

## 2026-06-22 — Permissions runtime reflection live spec

Closed the PWA Permissions runtime-reflection coverage gap with a real `@live`
spec against a cooperating `igloo-shell` signer. The flow starts a 2-of-2 shell
peer and stored PWA profile over a local relay, verifies a baseline
shell-initiated sign succeeds, toggles the PWA peer policy to deny inbound
`respond SIGN`, and verifies the next shell-initiated sign fails through the
live runtime path. The shell signer fixture now accepts test-only runtime
options so denial checks can use short sign/ping timeouts without changing
product defaults. Validation: red/green `npm --prefix test run
test:e2e:igloo-pwa:live -- ./igloo-pwa/specs/permissions-runtime-live.spec.ts`.

## 2026-06-22 — Welcome unlock live readiness spec

Closed the PWA Welcome unlock behavioral coverage gap with a real `@live`
stored-profile test. The new Playwright flow starts a headless `igloo-shell`
co-signer, seeds the PWA with the matching stored profile, unlocks from the
Welcome screen, and verifies the dashboard reaches the Paper-facing **Ready**
peer state while the shell runtime also reports sign readiness. The shared
shell-signer fixture now keeps its runtime root under `/tmp` so macOS
Unix-domain socket limits do not block daemon startup, and the PWA readiness
helper now matches the current UI label for internal `sign-ready` peers.
Validation: red/green `npm --prefix test run test:e2e:igloo-pwa:live --
./igloo-pwa/specs/welcome-unlock-live.spec.ts`.

## 2026-06-22 — Recover execution live spec

Closed the PWA Recover execution coverage gap with a real `@live` browser spec.
The new Playwright flow generates a deterministic 2-of-3 keyset, publishes the
matching encrypted profile backups, seeds one saved local profile, unlocks the
dashboard, launches Recover, pastes a real remote `bfshare`, and verifies that
the app reveals the recovered normalized NSEC without using the visual harness
fake-key seam. The shared browser-artifact helper now supports fixed private-key
generation so live specs can assert deterministic recovery output. Validation:
red/green `npm --prefix test run test:e2e:igloo-pwa:live --
./igloo-pwa/specs/recover-execution.spec.ts`, `npm --prefix test run
test:typecheck:pwa`, `npm --prefix test run test:guards:docs`, and `npm
--prefix test run test:guards:selectors`.

## 2026-06-22 — Peers collapse control

Aligned the shared signer dashboard **Peers** header with the Paper chevron
affordance by wiring it into the same dashboard section collapse control used
by Pending Approvals and Event Log. The peer section starts expanded, keeps its
online/total/ready/latency summary visible in the header, hides the peer rows
while collapsed, and restores live peer telemetry when expanded again.
Validation: red/green `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx -t "collapses and expands Peers"`, then `npm
--prefix repos/igloo-ui test -- --run test/OperatorPanels.test.tsx -t
"Peers|Event Log|Pending|pending approval|operation|peer"`.

## 2026-06-22 — Pending Approvals collapse control

Aligned the shared signer dashboard **Pending Approvals** header with the Paper
chevron affordance by reusing the dashboard section collapse control. The queue
starts expanded, keeps its pending count and nearest-expiry summary visible in
the header, hides the approval/operation row list while collapsed, and restores
the named list when expanded again. Validation: red/green `npm --prefix
repos/igloo-ui test -- --run test/OperatorPanels.test.tsx -t "collapses and
expands Pending Approvals"`, then `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx -t "Event Log|Pending|pending
approval|operation"`.

## 2026-06-22 — Event Log collapse control

Aligned the shared signer dashboard **Event Log** header with the Paper
chevron affordance by turning the visual marker into an accessible collapse /
expand control. The Event Log starts expanded, keeps its count, Clear, and
Filter controls in the header, hides only the row body while collapsed, and
restores the live log region when expanded again. Validation: red/green `npm
--prefix repos/igloo-ui test -- --run test/OperatorPanels.test.tsx -t
"collapses and expands the Event Log"`, then `npm --prefix repos/igloo-ui test
-- --run test/OperatorPanels.test.tsx -t "Event Log|Pending|pending
approval|operation"`.

## 2026-06-22 — Pending operations projection split

Fixed the shared dashboard projection so ordinary runtime pending operations no
longer masquerade as signer approval prompts. `igloo-ui` now only projects
pending operations into **Pending Approvals** when the runtime context carries
explicit approval/prompt labels, while `igloo-pwa` also passes ordinary pending
operations into the shared **Pending Operations** rows; ordinary operations also
use the same relative expiry labels as Paper approval rows. Validation:
red/green `npm --prefix repos/igloo-ui test -- --run
test/DesignAdapters.test.tsx -t "ordinary pending runtime operations"`,
red/green `npm --prefix repos/igloo-pwa run test:unit:raw --
test/frontend/App.test.tsx -t "ordinary runtime pending operations"`, full
`npm --prefix repos/igloo-ui test -- --run test/DesignAdapters.test.tsx`,
`npm --prefix repos/igloo-ui test -- --run test/OperatorPanels.test.tsx -t
"Pending|pending approval|operation"`, focused PWA App coverage for ordinary
operations, runtime peer capabilities, and fallback log filtering, `npm
--prefix test run test:typecheck:pwa`, and `npm --prefix repos/igloo-ui run
build`.

## 2026-06-22 — Recover local share source

Fixed the PWA Recover **Collect Shares** execution path so dashboard-launched
recovery includes the unlocked local profile share that the UI shows as
**Share #1 (this device)**. `recoverKeyFromShares` now mirrors the rotation
source builder: when the selected source profile is unlocked and has an
encrypted local `bfshare`, it prepends that source before pasted remote shares,
deduping by package text. This prevents the Recover flow from claiming the
threshold is met visually while sending only pasted remote sources to the
adapter. Validation: red/green `npm --prefix repos/igloo-pwa run
test:unit:raw -- test/frontend/App.test.tsx -t "auto-includes the unlocked
local share when recovering"`, `npm --prefix repos/igloo-pwa run
test:unit:raw -- test/frontend/App.test.tsx -t "recover|Recover"`, `npm
--prefix repos/igloo-ui test -- --run test/CreateFlow.test.tsx -t
"recover|Recover"`, and `npm --prefix test run test:typecheck:pwa`.

## 2026-06-22 — Live nonce inventory history

Threaded bounded peer-held nonce inventory history from `bifrost-rs` runtime
status through `igloo-shared`, `igloo-ui`, and the PWA dashboard projection.
Ping responses now record normalized held-count samples in a runtime-only
per-peer ring buffer; shared/PWA view models carry the samples as
`nonceInventoryHistory`; and `OperatorSignerPanel` renders the series as mini
history bars in the peer nonce meter with an accessible telemetry label.
Validation: `cargo test -p bifrost-signer peer_status_reports_`, `cargo test -p
bifrost-bridge-tokio`, `cargo test -p bifrost-bridge-wasm
runtime_metadata_peer_status_and_empty_drains_are_queryable`, `npm --prefix
repos/igloo-shared run test:unit -- src/runtime-api.test.ts`, `npm --prefix
repos/igloo-shared run test:typecheck`, `npm --prefix repos/igloo-ui test --
--run test/DesignAdapters.test.tsx`, `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx -t "labels per-peer nonce availability"`, `npm
--prefix repos/igloo-ui run build`, `npm --prefix repos/igloo-pwa run
test:unit:raw -- test/frontend/App.test.tsx -t "projects runtime peer method
capabilities"`, and `npm --prefix test run test:typecheck:pwa`.

## 2026-06-22 — Live peer response latency

Threaded latest peer response latency from `bifrost-rs` runtime status through
`igloo-shared` and the PWA dashboard. Runtime-created pending operations now
remember millisecond start times in memory; accepted peer responses record
`PeerStatus.latency_ms`, restored/manual pending operations fall back to the
existing second-resolution `started_at`, and the PWA dashboard smoke path now
renders the row latency plus the shared Avg pill from live runtime data.
Validation: `cargo test -p bifrost-signer
peer_status_reports_latest_response_latency`, `cargo test -p bifrost-signer
peer_status_reports_method_capabilities_from_policy`, `cargo test -p
bifrost-bridge-tokio`, `cargo test -p bifrost-bridge-wasm
runtime_metadata_peer_status_and_empty_drains_are_queryable`, `npm --prefix
repos/igloo-ui test -- --run test/DesignAdapters.test.tsx`, `npm --prefix
repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx -t "projects
runtime peer method capabilities"`, and `npm --prefix repos/igloo-shared run
test:typecheck`.

## 2026-06-22 — Live peer method capability badges

Threaded live peer method capabilities from `bifrost-rs` runtime status through
`igloo-shared`, `igloo-ui`, and the PWA dashboard projection. `PeerStatus` now
reports policy-gated `can_sign` plus request-side `can_ping`, `can_onboard`, and
`can_ecdh`; shared/PWA peer rows derive SIGN/ECDH/PING/ONBOARD badges from those
fields when no richer policy state is available, and ECDH readiness uses the
explicit runtime capability when present. Validation: `cargo test -p
bifrost-signer peer_status_reports_method_capabilities_from_policy`, `cargo test
-p bifrost-bridge-tokio`, `cargo test -p bifrost-bridge-wasm
runtime_metadata_peer_status_and_empty_drains_are_queryable`, `npm --prefix
repos/igloo-shared run test:unit -- src/runtime-api.test.ts`, `npm --prefix
repos/igloo-ui test -- --run test/DesignAdapters.test.tsx`, `npm --prefix
repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx -t "projects
runtime peer method capabilities"`, `npm --prefix repos/igloo-shared run
test:typecheck`, `npm --prefix repos/igloo-ui run build`, and `npm --prefix test
run test:typecheck:pwa`.

## 2026-06-22 — Paper dashboard-only runtime card cleanup

Removed the repeated merged identity/runtime status card from the Paper
Permissions and Settings artboards so the card is dashboard-only, matching the
runtime navigation model. `igloo-paper` now exports `dashboard/1c-permissions`
starting at Signer Permissions, and `dashboard/3-settings-lock-profile` no
longer repeats Signer Running behind the Settings drawer. Validation: Paper
screenshots for Permissions and Settings, `make igloo-paper-sync`,
`make igloo-paper-verify STRICT=1`, and generated export search confirming the
target screens no longer contain Signer Running / Group Public Key / Share
Public Key copy.

## 2026-06-22 — Paper Browser Settings source cleanup

Added the PWA-only **Browser Settings** group to the Paper Settings sidebar and
refreshed the `igloo-paper` export. The `502-0` Settings artboard now shows
Remember Browser State, Open Signer After Import, and Prefer Install Prompt with
the same compact sidebar row treatment as the rest of Settings; the artboard was
expanded to the drawer's measured height so Browser Settings and Profile
Security are not clipped in the checked-in reference. Validation: Paper
screenshots for the full artboard and sidebar, `make igloo-paper-sync`, and
`make igloo-paper-verify STRICT=1`.

## 2026-06-22 — Settings sponsor Paper source cleanup

Reconciled the Settings **Onboard a Device** sponsor source-of-truth docs with
the current Paper file and export. The live Paper canvas and `igloo-paper`
export now show the canonical sponsor screens as dashboard modal states
`3d-onboard-device-modal` and `3e-onboard-package-handoff-modal`; older
`onboard-sponsor/*` references were retired in the app-header component doc,
implementation plan, and Settings sidebar audit. Remaining product/design
work is only to decide whether separate Device Onboarded / Onboarding Failed /
Cancel Confirm sponsor artboards should be restored. Validation: live Paper MCP
`get_basic_info`, `rg` against `repos/igloo-paper`, `npm --prefix test run
test:guards:docs`, and diff checks.

## 2026-06-22 — Permissions override persistence

Closed the PWA Permissions persisted round-trip gap that was previously only
covered by visual screenshots. The app-shell browser test now toggles a peer
request policy from allow to deny, reloads to the locked Welcome screen,
unlocks again, and verifies the override is still shown in the dashboard
Permissions tab. The store now persists manual peer policy overrides
immediately, preserves them when runtime snapshots come back with unset/default
policy projections, and passes explicit `allow`/`deny` values through the local
adapter instead of collapsing them to booleans. Validation: red/green `npm
--prefix test run test:e2e:igloo-pwa:fast --
./igloo-pwa/specs/app-shell.spec.ts -g "saves Permissions peer overrides"`,
full `npm --prefix test run test:e2e:igloo-pwa:fast --
./igloo-pwa/specs/app-shell.spec.ts` (9 tests), `npm --prefix repos/igloo-pwa
run test:unit:raw -- test/frontend/App.test.tsx
test/frontend/session-controller.test.ts test/frontend/operator-settings.test.ts`
(67 tests), `npm --prefix test run test:typecheck:pwa`, and `npm --prefix test
run test:guards:docs`.

## 2026-06-22 — Settings save round-trip

Closed the PWA Settings save behavioral gap that was previously only covered by
visual screenshots. The app-shell browser test now edits the signer profile
name and relay list through the Settings sidebar, saves through the runtime
settings path, reloads to the locked Welcome screen, unlocks again, and verifies
the saved profile name and relay are still present. The store now writes an
explicit Settings save through the existing persistence allow-list immediately,
instead of relying only on the debounced background writer. Validation:
red/green `npm --prefix test run test:e2e:igloo-pwa:fast --
./igloo-pwa/specs/app-shell.spec.ts -g "saves Settings profile changes"`, full
`npm --prefix test run test:e2e:igloo-pwa:fast --
./igloo-pwa/specs/app-shell.spec.ts` (8 tests), `npm --prefix repos/igloo-pwa
run test:unit:raw -- test/frontend/App.test.tsx
test/frontend/operator-settings.test.ts` (57 tests), and `npm --prefix test run
test:typecheck:pwa`.

## 2026-06-22 — Dashboard deep-link route intent

Polished the PWA dashboard route handoff so locked dashboard tab deep links keep
their intended destination through profile unlock while still normalizing the
visible locked URL back to the public landing route. The app-shell browser
coverage now also seeds dashboard reload states without fighting the app's
persist-on-unload behavior, and the dashboard Recover route reload test exercises
the real `/dashboard/recover` route. Validation: red/green `npm --prefix test
run test:e2e:igloo-pwa:fast -- ./igloo-pwa/specs/app-shell.spec.ts -g "opens
dashboard deep links after unlock"`, `npm --prefix test run
test:e2e:igloo-pwa:fast -- ./igloo-pwa/specs/app-shell.spec.ts -g "keeps
dashboard navigation through Recover"`, full `npm --prefix test run
test:e2e:igloo-pwa:fast -- ./igloo-pwa/specs/app-shell.spec.ts` (7 tests),
`npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx`
(55 tests), and `npm --prefix test run test:typecheck:pwa`.

## 2026-06-22 — Import and Onboard Save Profile visual seams

Closed the remaining PWA visual-manifest save-profile holes for passphrase
bearing Import and Onboard states. The Import **Save Profile** and Onboard
**Save Profile** screenshots now render through DEV-only, non-persisted visual
seams instead of trying to seed `pendingLoadConfirmation` or
`pendingOnboardConnection` into localStorage. Both manifest rows are promoted
to `aligned`, and `igloo-ui` now exports the shared
`OnboardDeviceSponsorErrorField` type required by the PWA build. Validation:
red/green focused visual specs for `captures the imported profile save step
through the visual seam` and `captures the onboarded profile save step through
the visual seam`; `npm --prefix test run test:e2e:igloo-pwa:visual --
./igloo-pwa/specs/import-visual.spec.ts ./igloo-pwa/specs/onboard-visual.spec.ts`
(5 tests); `npm --prefix test run test:guards:visual`, `npm --prefix test run
test:typecheck:pwa`, `npm --prefix test run test:typecheck:strict-visual-specs`,
`npm --prefix repos/igloo-ui run build`, `git -C repos/igloo-ui diff --check`,
`git -C repos/igloo-pwa diff --check`, and `git diff --check`.

## 2026-06-22 — Dashboard recover stale-route normalization

Polished the PWA dashboard/recover route guard so a stale `/dashboard/recover`
URL only survives when recovery was launched from the signer dashboard. A
Welcome-launched recovery collection with resumable package text now keeps the
Collect Shares screen but normalizes the browser URL back to `/`, preventing
Safari refreshes from showing a public recover flow under a dashboard route.
Validation: `npm test -- --run test/frontend/App.test.tsx -t "normalizes a
stale dashboard recover URL for welcome-launched recovery collection"` from
`repos/igloo-pwa` (repo script ran all 54 App tests), `npm --prefix test run
test:typecheck:pwa`, `npm --prefix test run test:guards:docs`, `git -C
repos/igloo-pwa diff --check`, and `git diff --check`.

## 2026-06-22 — Settings Onboard source failure field state

Polished the shared Settings **Onboard Device** sponsor-package creation
failure path so adapter-side source material errors point back to the source
fields that need correction. The shared dialog now accepts field-level error
ownership, and `igloo-pwa` marks **Source bfshare** and **Source Password**
invalid after a failed `bfshare` sponsor-package attempt while clearing the
state on the next edit. Validation: `npm test -- --run
test/OperatorPanels.test.tsx -t "marks Settings Onboard source material invalid
after package creation fails"` and `npm test -- --run
test/OperatorPanels.test.tsx -t "Settings Onboard Device|Onboard Device"` from
`repos/igloo-ui`; `npm test -- --run test/frontend/App.test.tsx -t "marks
Settings onboarding source material invalid after package creation fails"` and
`npm test -- --run test/frontend/App.test.tsx -t "Settings onboarding|settings
onboarding|Onboard Device|onboarding package"` from `repos/igloo-pwa` (repo
script ran all 53 App tests); `npm --prefix repos/igloo-ui run build`, `npm
--prefix test run test:typecheck:pwa`, `npm --prefix test run
test:guards:docs`, `git -C repos/igloo-ui diff --check`, `git -C
repos/igloo-pwa diff --check`, and `git diff --check`.

## 2026-06-22 — Settings Onboard password mismatch semantics

Polished the shared Settings **Onboard Device** sponsor-package form so a
package password mismatch is exposed as a named **Package password mismatch**
alert and the **Confirm Package Password** control is marked invalid and
described by that error. The visible Paper-aligned copy stays the same while the
form now points operators to the exact field that needs correction. Validation:
`npm test -- --run test/OperatorPanels.test.tsx -t "renders the Settings
Onboard Device source-package form"` and `npm test -- --run
test/OperatorPanels.test.tsx -t "Settings Onboard Device|Onboard Device"` from
`repos/igloo-ui`; `npm test -- --run test/frontend/App.test.tsx -t "creates a
Settings onboarding package from an explicit bfshare while signer is
running|locks the Settings onboarding form while package creation is running"`
from `repos/igloo-pwa` (repo script ran all 52 App tests); `npm --prefix
repos/igloo-ui run build` and `npm --prefix test run test:typecheck:pwa`.

## 2026-06-22 — Settings Onboard error status semantics

Polished the shared Settings **Onboard Device** sponsor-package dialog so its
creation failures and package handoff failures announce as named error states.
The Paper-aligned configure/handoff layout and copy remain unchanged, while
handoff warnings now use **Onboard package handoff status** as an assertive
alert and source-package creation errors use **Onboard package creation failed**.
Validation: `npm test -- --run test/OperatorPanels.test.tsx -t "renders the
Settings Onboard Device source-package form"`, `npm test -- --run
test/OperatorPanels.test.tsx -t "renders Settings Onboard Device handoff
failures with a warning status tone"`, and `npm test -- --run
test/OperatorPanels.test.tsx -t "Settings Onboard Device|Onboard Device"` from
`repos/igloo-ui`; `npm test -- --run test/frontend/App.test.tsx -t "creates a
Settings onboarding package from an explicit bfshare while signer is
running|locks the Settings onboarding form while package creation is running"`
from `repos/igloo-pwa` (repo script ran all 52 App tests); `npm --prefix
repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`, `npm
--prefix test run test:guards:docs`, `git -C repos/igloo-ui diff --check`, `git
-C repos/igloo-pwa diff --check`, and `git diff --check`.

## 2026-06-22 — Recover failure alert semantics

Polished the outside-runtime Recover **Collect Shares** failure state so the
inline error announces as a named **Recovery failed** alert instead of a generic
alert. The shared `igloo-ui` panel keeps the existing Paper-style warning copy
and invalid field state while making the failure region directly navigable.
Validation: `npm test -- --run test/CreateFlow.test.tsx -t "marks recover
source fields invalid after a recovery failure"` and `npm test -- --run
test/CreateFlow.test.tsx -t "recover collection|labels the recover
collection|exposes recover threshold progress|labels each recover source
card|locks recover source material|which recovery source|fixed
recovery|threshold-worthy|marks recover source fields invalid"` from
`repos/igloo-ui`; `npm test -- --run test/frontend/App.test.tsx -t "keeps
recover collection blocked|locks recover collection inputs|shows a local
recovery error|opens recover with the fixed Paper source count"` from
`repos/igloo-pwa` (repo script ran all 52 App tests); `npm --prefix
repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`, `npm
--prefix test run test:guards:docs`, `git -C repos/igloo-ui diff --check`,
`git -C repos/igloo-pwa diff --check`, and `git diff --check`.

## 2026-06-22 — Recover collection status semantics

Polished the outside-runtime Recover **Collect Shares** panel so its live
blocked/ready/recovering message has a stable accessible name. The shared
`igloo-ui` panel now exposes **Recovery collection status** while preserving the
same Paper copy for blocked, threshold-met, and recovering states. Validation:
`npm test -- --run test/CreateFlow.test.tsx -t "labels the recover collection
live status"` and `npm test -- --run test/CreateFlow.test.tsx -t "recover
collection|labels the recover collection|exposes recover threshold
progress|labels each recover source card|locks recover source material|which
recovery source|fixed recovery|threshold-worthy|marks recover source fields
invalid"` from `repos/igloo-ui`; `npm test -- --run test/frontend/App.test.tsx
-t "keeps recover collection blocked|locks recover collection inputs|shows a
local recovery error|opens recover with the fixed Paper source count"` from
`repos/igloo-pwa` (repo script ran all 52 App tests); `npm --prefix
repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`, `npm
--prefix test run test:guards:docs`, `git -C repos/igloo-ui diff --check`,
`git -C repos/igloo-pwa diff --check`, and `git diff --check`.

## 2026-06-22 — Event Log filter group semantics

Polished the shared signer dashboard **Event Log** filter drawer so the
expanded All/domain chips are exposed as one named control group instead of a
loose row of buttons. Opening the Paper-style Filter control now reveals
**Event Log filters**, with the existing pressed-state chips preserved inside
the group. Validation: `npm test -- --run test/OperatorPanels.test.tsx -t
"labels expanded Event Log filters as one control group"` and `npm test --
--run test/OperatorPanels.test.tsx -t "Event Log|filters the diagnostics
log|labels expanded Event Log filters|pending approval|Pending
Approvals|orders pending|labels pending|dispatches pending|peer refresh|per-peer
ping|unavailable peer ping|renders per-peer readiness|labels per-peer nonce"`
from `repos/igloo-ui`; `npm test -- --run test/frontend/App.test.tsx -t
"dashboard navigation|dashboard tab|filters fallback runtime log lines"` from
`repos/igloo-pwa` (repo script ran all 52 App tests); `npm --prefix
repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`, `npm
--prefix test run test:guards:docs`, `git -C repos/igloo-ui diff --check`,
`git -C repos/igloo-pwa diff --check`, and `git diff --check`.

## 2026-06-22 — Pending queue row semantics

Polished the shared signer dashboard **Pending Approvals** queue so approval
and operation rows are exposed as one named list instead of anonymous layout
divs. The queue now announces as **Pending approval and operation rows**, with
each visible row named by method, peer/threshold, detail/response, and expiry,
for example **SIGN approval from Peer #2: kind:1 Short Text Note, expires
42s**. Validation: `npm test -- --run test/OperatorPanels.test.tsx -t "labels
pending approval and operation rows as a combined queue"` and `npm test --
--run test/OperatorPanels.test.tsx -t "pending approval|Pending
Approvals|orders pending|labels pending|dispatches pending|Event Log|filters
the diagnostics log|peer refresh|per-peer ping|unavailable peer ping|renders
per-peer readiness|labels per-peer nonce"` from `repos/igloo-ui`; `npm test --
--run test/frontend/App.test.tsx -t "dashboard navigation|dashboard
tab|filters fallback runtime log lines"` from `repos/igloo-pwa` (repo script
ran all 52 App tests); `npm --prefix repos/igloo-ui run build`, `npm --prefix
test run test:typecheck:pwa`, `npm --prefix test run test:guards:docs`, `git
-C repos/igloo-ui diff --check`, `git -C repos/igloo-pwa diff --check`, and
`git diff --check`.

## 2026-06-22 — Event Log row semantics

Polished the shared signer dashboard **Event Log** so visible diagnostics rows
are exposed as a named log instead of an anonymous div list. The event list now
announces as **Event Log entries**, and each visible row is an article named by
its normalized domain plus message, for example **sign event: sign request
received**, preserving the Paper row layout while making filtered runtime
diagnostics easier to navigate. Validation: `npm test -- --run
test/OperatorPanels.test.tsx -t "summarizes peer readiness counts"` and `npm
test -- --run test/OperatorPanels.test.tsx -t "Event Log|filters the
diagnostics log|pending approval|Pending Approvals|peer refresh|per-peer
ping|unavailable peer ping|renders per-peer readiness|labels per-peer nonce"`
from `repos/igloo-ui`; `npm test -- --run test/frontend/App.test.tsx -t
"filters fallback runtime log lines"` from `repos/igloo-pwa` (repo script ran
all 52 App tests); `npm --prefix repos/igloo-ui run build`, `npm --prefix
test run test:typecheck:pwa`, `npm --prefix test run test:guards:docs`, `git
-C repos/igloo-ui diff --check`, `git -C repos/igloo-pwa diff --check`, and
`git diff --check`.

## 2026-06-22 — Recover source-card group labels

Polished the outside-runtime Recover **Collect Shares** source rows so each
remote share card exposes a share-specific group label tied to its current
status, such as **Share #2 recovery source: Password required**. This preserves
the existing Paper card layout while making multi-source recovery easier to
navigate and distinguish. Validation: `npm test -- --run
test/CreateFlow.test.tsx -t "labels each recover source card"` and `npm test
-- --run test/CreateFlow.test.tsx -t "recover collection|exposes recover
threshold progress|labels each recover source card|locks recover source
material|which recovery source|fixed recovery|threshold-worthy|marks recover
source fields invalid"` from `repos/igloo-ui`; `npm test -- --run
test/frontend/App.test.tsx -t "opens recover with the fixed Paper source
count"` from `repos/igloo-pwa` (repo script ran all 52 App tests); `npm
--prefix repos/igloo-ui run build`, `npm --prefix test run
test:typecheck:pwa`, `npm --prefix test run test:guards:docs`, `git -C
repos/igloo-ui diff --check`, `git -C repos/igloo-pwa diff --check`, and `git
diff --check`.

## 2026-06-22 — Recover threshold progress semantics

Polished the outside-runtime Recover **Collect Shares** progress meter so the
visual threshold bar is also exposed as a proper progressbar. The shared
`igloo-ui` meter now reports the recovery threshold progress name, min/max,
current collected count, and text such as **1 of 3 required**, giving the
existing Paper-style meter a concrete semantic state without changing the
layout. Validation: `npm test -- --run test/CreateFlow.test.tsx -t "exposes
recover threshold progress"` and `npm test -- --run test/CreateFlow.test.tsx -t
"recover collection|exposes recover threshold progress|locks recover source
material|which recovery source|fixed recovery|threshold-worthy|marks recover
source fields invalid"` from `repos/igloo-ui`; `npm test -- --run
test/frontend/App.test.tsx -t "keeps recover collection blocked"` from
`repos/igloo-pwa` (repo script ran all 52 App tests); `npm --prefix
repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`,
`npm --prefix test run test:guards:docs`, `git -C repos/igloo-ui diff
--check`, `git -C repos/igloo-pwa diff --check`, and `git diff --check`.

## 2026-06-22 — Dashboard peer nonce telemetry labels

Polished the shared signer dashboard peer nonce meter so the visible
incoming/outgoing bars expose concrete per-peer telemetry instead of a generic
label. Each meter now names the peer and the incoming, outgoing, and spent
nonce counts when runtime data is present, while unavailable rows still report
that nonce availability is unavailable. Validation: `npm test -- --run
test/OperatorPanels.test.tsx -t "labels per-peer nonce availability"` and `npm
test -- --run test/OperatorPanels.test.tsx -t "peer readiness|renders per-peer
readiness|labels per-peer nonce|peer refresh|per-peer ping|unavailable peer
ping|Event Log|Pending Approvals"` from `repos/igloo-ui`; `npm --prefix
repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`,
`npm --prefix test run test:guards:docs`, `git -C repos/igloo-ui diff
--check`, and `git diff --check`.

## 2026-06-22 — Dashboard peer row telemetry split

Polished the shared signer dashboard peer rows so readiness and measured
latency render as separate telemetry instead of one replacing the other. Rows
now keep the readiness word (**Ready**, **Known**, **Offline**, etc.) visible
alongside a latency chip when runtime data includes `latencyMs`, and expose a
single accessible summary that includes readiness, latency, and last-seen
context. Validation: `npm test -- --run test/OperatorPanels.test.tsx -t
"renders per-peer readiness and latency"` and `npm test -- --run
test/OperatorPanels.test.tsx -t "peer readiness|renders per-peer
readiness|peer refresh|per-peer ping|unavailable peer ping|Event Log|Pending
Approvals"` from `repos/igloo-ui`; `npm --prefix repos/igloo-ui run build`,
`npm --prefix test run test:typecheck:pwa`, `git -C repos/igloo-ui diff
--check`, and `git diff --check`.

## 2026-06-22 — Recover source failure field state

Polished the outside-runtime Recover **Collect Shares** failure state so a
failed recovery attempt marks the source package and package password controls
invalid in addition to showing the inline alert. This keeps the visible error
connected to the exact source material the operator needs to fix, and the PWA
recover flow consumes the shared invalid state after the adapter rejects a
recovery attempt. Validation: `npm test -- --run test/CreateFlow.test.tsx -t
"marks recover source fields invalid"` and `npm test -- --run
test/CreateFlow.test.tsx -t "recover collection|locks recover source
material|which recovery source|fixed recovery|threshold-worthy|marks recover
source fields invalid"` from `repos/igloo-ui`; `npm test -- --run
test/frontend/App.test.tsx -t "shows a local recovery error"` from
`repos/igloo-pwa`; `npm --prefix repos/igloo-ui run build`, `npm --prefix test
run test:typecheck:pwa`, `npm --prefix test run test:guards:docs`, `git -C
repos/igloo-ui diff --check`, `git -C repos/igloo-pwa diff --check`, and `git
diff --check`.

## 2026-06-22 — Settings Onboard cancel confirmation

Added the Paper-listed cancel-confirm state to the Settings **Onboard a
Device** sponsor package flow. The shared `igloo-ui` sponsor dialog now accepts
a host-supplied dirty-draft signal and asks operators to keep editing or discard
the onboarding package draft before closing; `igloo-pwa` drives that signal only
after real sponsor source/password/label edits so a freshly opened dialog still
closes normally. Validation: `npm test -- --run test/OperatorPanels.test.tsx -t
"confirms before closing dirty Settings Onboard"` and `npm test -- --run
test/OperatorPanels.test.tsx -t "Settings Onboard Device|confirms before
closing dirty Settings Onboard"` from `repos/igloo-ui`; `npm test -- --run
test/frontend/App.test.tsx -t "unified settings actions"` from
`repos/igloo-pwa`; `npm --prefix repos/igloo-ui run build`, `npm --prefix test
run test:typecheck:pwa`, `npm --prefix test run test:guards:docs`, `git -C
repos/igloo-ui diff --check`, `git -C repos/igloo-pwa diff --check`, and `git
diff --check`.

## 2026-06-22 — Permissions busy-state token lock

Polished the shared Permissions panel transition behavior so peer policy tokens
and sibling toolbar actions lock while a permissions refresh or clear operation
is running. This prevents manual request/respond overrides from racing with
**Refreshing...** or **Clearing...** dashboard operations, and the PWA
Permissions tab already consumes the same busy props. Validation: `npm test --
--run test/OperatorPanels.test.tsx -t "locks peer permission tokens"`, `npm
test -- --run test/OperatorPanels.test.tsx -t "permissions|Peer
Permissions|locks peer permission tokens|pending approval|Pending Approvals|Event
Log|filters the diagnostics log|peer refresh|per-peer ping|unavailable peer
ping|attention states|empty pending queue"` from `repos/igloo-ui`; `npm test --
--run test/frontend/App.test.tsx -t "dashboard navigation|dashboard tab|Peer
Permissions"` from `repos/igloo-pwa`; `npm --prefix repos/igloo-ui run build`,
`npm --prefix test run test:typecheck:pwa`, `npm --prefix test run
test:guards:docs`, `git -C repos/igloo-ui diff --check`, and `git diff
--check`.

## 2026-06-22 — Rotate Keyset transition input lock

Polished the shared Rotate Existing keyset transition so the source profile
selector, bfshare source textareas, package password fields, and add/remove
source controls lock while rotation is running. The primary action keeps its
**Rotating...** loading state, and the PWA create-rotate path already consumes
the shared `actionBusy` prop. Validation: `npm test -- --run
test/CreateFlow.test.tsx -t "locks rotate-keyset source inputs"` and `npm test
-- --run test/CreateFlow.test.tsx -t "rotate-keyset|locks
rotate-keyset|replace-share package entry|locks replace-share package
entry|onboarding package entry|import profile entry|locks onboarding package
entry|locks import profile entry|locks save-profile inputs|locks create-flow
keyset inputs|locks select-share choices|recover collection"` from
`repos/igloo-ui`; `npm test -- --run test/frontend/App.test.tsx -t
"auto-includes the unlocked local share"` from `repos/igloo-pwa`; `npm --prefix
repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`, `npm
--prefix test run test:guards:docs`, `git -C repos/igloo-ui diff --check`, and
`git diff --check`.

## 2026-06-22 — Replace Share package-entry transition lock

Polished the shared Settings-launched Replace Share package entry transition so
the onboarding package textarea, package password field, and Scan QR action lock
while the replacement package is connecting. The primary action keeps its
**Connecting...** loading state, and the PWA replacement flow consumes the same
shared component from Settings. Validation: `npm test -- --run
test/CreateFlow.test.tsx -t "locks replace-share package entry"` and `npm test
-- --run test/CreateFlow.test.tsx -t "replace-share package entry|locks
replace-share package entry|replace-share applying|onboarding package
entry|import profile entry|locks onboarding package entry|locks import profile
entry|locks save-profile inputs|locks select-share choices|recover collection"`
from `repos/igloo-ui`; `npm test -- --run test/frontend/App.test.tsx -t "shows
the Paper applying replacement state after a replacement package connects"` from
`repos/igloo-pwa`; `npm --prefix repos/igloo-ui run build`, `npm --prefix test
run test:typecheck:pwa`, `npm --prefix test run test:guards:docs`, `git -C
repos/igloo-ui diff --check`, and `git diff --check`.

## 2026-06-22 — Import and Onboard entry transition locks

Polished the shared outside-runtime Import Profile and Onboard Package entry
transitions so package/profile textareas, password fields, and the Onboard QR
scan action lock while the profile/package submit action is running. The primary
actions keep their existing **Importing...** and **Connecting...** loading
states, and the PWA import/onboard entry paths consume the same shared
components. Validation: `npm test -- --run test/CreateFlow.test.tsx -t "locks
onboarding package entry"`, `npm test -- --run test/CreateFlow.test.tsx -t
"locks import profile entry"`, and `npm test -- --run test/CreateFlow.test.tsx
-t "onboarding package entry|import profile entry|locks onboarding package
entry|locks import profile entry|locks save-profile inputs|locks create-flow
keyset inputs|locks select-share choices|recover collection"` from
`repos/igloo-ui`; `npm test -- --run test/frontend/App.test.tsx -t "routes
Import Existing Device|accepts a real-looking bfonboard"` from `repos/igloo-pwa`;
`npm --prefix repos/igloo-ui run build`, `npm --prefix test run
test:typecheck:pwa`, `npm --prefix test run test:guards:docs`, `git -C
repos/igloo-ui diff --check`, and `git diff --check`.

## 2026-06-22 — Save Profile transition input lock

Polished the shared Create **Save Profile** transition so profile name,
password fields, relay add/remove controls, and the Back action lock while the
local profile is being saved. The primary action keeps its **Saving...** loading
state, and the relay list uses the existing read-only treatment during the
in-flight transition. Validation: `npm test -- --run test/CreateFlow.test.tsx
-t "locks save-profile inputs"` and `npm test -- --run
test/CreateFlow.test.tsx -t "save-profile setup|locks save-profile
inputs|onboard save surface|select-share group public key|locks select-share
choices|locks create-flow keyset inputs"` from `repos/igloo-ui`, `npm --prefix
repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`, `npm
--prefix test run test:guards:docs`, `git -C repos/igloo-ui diff --check`, and
`git diff --check`.

## 2026-06-22 — Select Share save transition lock

Polished the shared Create **Select Share** transition so share-card choices and
the Back action lock while the local share selection is being saved. The primary
action keeps its **Continuing...** loading state, and users can no longer switch
which share stays local during the in-flight transition. Validation: `npm test
-- --run test/CreateFlow.test.tsx -t "locks select-share choices"` and `npm
test -- --run test/CreateFlow.test.tsx -t "select-share group public key|locks
select-share choices|create-flow keyset|Paper four-step|locks create-flow
keyset inputs"` from `repos/igloo-ui`, `npm --prefix repos/igloo-ui run
build`, `npm --prefix test run test:typecheck:pwa`, `npm --prefix test run
test:guards:docs`, `git -C repos/igloo-ui diff --check`, and `git diff
--check`.

## 2026-06-22 — Create Keyset generation input lock

Polished the shared Create Keyset first-step transition so the form locks while
keyset generation is running. The shared `igloo-ui` card now keeps the primary
action in its **Generating...** loading state and disables the keyset name,
threshold/total-share counters, optional private-key field, and back action
until generation resolves. Validation: `npm test -- --run
test/CreateFlow.test.tsx -t "locks create-flow keyset inputs"` and `npm test --
--run test/CreateFlow.test.tsx -t "create-flow keyset|Paper four-step|locks
create-flow keyset inputs|tooltip affordances"` from `repos/igloo-ui`, `npm
--prefix repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`,
`npm --prefix test run test:guards:docs`, `git -C repos/igloo-ui diff --check`,
and `git diff --check`.

## 2026-06-22 — Recover source remove action labels

Polished the shared Recover **Collect Shares** panel so editable source-row
remove actions keep the compact visible **Remove** text while exposing the
specific share being removed, for example **Remove Share #2 source**. This makes
multi-source recovery controls distinguishable without changing the Paper row
layout. Validation: `npm test -- --run test/CreateFlow.test.tsx -t "locks
recover source material"` and `npm test -- --run test/CreateFlow.test.tsx -t
"recover collection|locks recover source material|which recovery source|fixed
recovery|threshold-worthy"` from `repos/igloo-ui`, `npm --prefix
repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`, `npm
--prefix test run test:guards:docs`, `git -C repos/igloo-ui diff --check`, and
`git diff --check`.

## 2026-06-22 — Dashboard peer refresh loading labels

Polished the shared signer dashboard peer refresh transition so both the
attention retry action and the Peers section refresh action announce and display
explicit in-flight copy while refresh is running: **Retrying...** /
**Retrying connections** and **Refreshing...** / **Refreshing peers**. This
keeps dashboard refresh controls consistent with the broader loading-feedback
pass. Validation: `npm test -- --run test/OperatorPanels.test.tsx -t "marks
dashboard peer refresh actions busy"` and `npm test -- --run
test/OperatorPanels.test.tsx -t "peer refresh|per-peer ping|unavailable peer
ping|All Relays Offline|Retry Connections|attention states"` from
`repos/igloo-ui`, `npm --prefix repos/igloo-ui run build`, `npm --prefix test
run test:typecheck:pwa`, `npm --prefix test run test:guards:docs`, `git -C
repos/igloo-ui diff --check`, and `git diff --check`.

## 2026-06-22 — Pending queue contextual open labels

Polished the shared signer dashboard pending queue so approval and operation
rows keep the compact visible **Open** action while exposing row-specific
accessible labels such as **Open SIGN approval from Peer #2** and **Open ecdh
operation for threshold 2**. This keeps repeated pending actions distinguishable
for assistive navigation and future host wiring. Validation: `npm test --
--run test/OperatorPanels.test.tsx -t "pending approval|Pending
Approvals|empty pending queue|labels pending open actions|orders
pending|dispatches pending"` from `repos/igloo-ui`, `npm --prefix
repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`, `npm
--prefix test run test:guards:docs`, `git -C repos/igloo-ui diff --check`, and
`git diff --check`.

## 2026-06-22 — Pending queue empty-state copy

Aligned the shared signer dashboard pending queue empty state with the combined
approvals/operations surface. When no approval prompts or pending operations
exist, the section now says **No pending approvals or operations.** instead of
only naming approvals. Validation: `npm test -- --run test/OperatorPanels.test.tsx
-t "empty pending queue"` and `npm test -- --run test/OperatorPanels.test.tsx -t
"empty pending queue|pending approval|Pending Approvals|Event Log|filters the
diagnostics log"` from `repos/igloo-ui`, `npm --prefix repos/igloo-ui run build`,
`npm --prefix test run test:typecheck:pwa`, `npm --prefix test run
test:guards:docs`, `git -C repos/igloo-ui diff --check`, and `git diff --check`.

## 2026-06-22 — Recover key copy transition lock

Polished the recovered private-key export screen so Copy waits for the clipboard
write before showing success. While copying is in flight, Save, QR, Reveal,
Clear, Encrypt Key, and password edits are disabled to keep the exported value
stable through the transition. The pass also refreshed stale PWA persistence
test fixtures with the current `pendingLoadErrorKind` field so the PWA build
can type-check the test surface. Validation: `npm test -- --run
test/frontend/App.test.tsx -t "locks recovered key export controls"` from
`repos/igloo-pwa` (repo script ran the full App test file), `npm --prefix
repos/igloo-pwa run build`, `npm --prefix test run test:typecheck:pwa`, `npm
--prefix test run test:guards:docs`, `git -C repos/igloo-pwa diff --check`, and
`git diff --check`.

## 2026-06-22 — Event Log clearing filter lock

Polished the shared signer dashboard Event Log clearing transition. When the
log is clearing, the Clear action keeps its busy state and any open Filter
controls now lock until the clear operation resolves, preventing filter changes
against an in-flight log mutation. Validation: `npm test -- --run
test/OperatorPanels.test.tsx -t "locks Event Log filter"` and `npm test -- --run
test/OperatorPanels.test.tsx -t "Event Log|filters the diagnostics log|pending
approval|Pending Approvals|peer refresh|per-peer ping|unavailable peer ping"`
from `repos/igloo-ui`, `npm --prefix repos/igloo-ui run build`, `npm --prefix
test run test:typecheck:pwa`, and `npm --prefix test run test:guards:docs`.

## 2026-06-22 — Peer ping unavailable-state labels

Polished the shared signer dashboard peer rows so auto-filled local and missing
member rows no longer expose a generic disabled **Ping** action. Unavailable
peer actions now explain whether the row is local, missing, or lacks a valid
public key while preserving real Ping behavior for reachable remote peers.
Validation: `npm test -- --run test/OperatorPanels.test.tsx -t "unavailable
peer ping"` and `npm test -- --run test/OperatorPanels.test.tsx -t "peer
readiness|peer refresh|per-peer ping|unavailable peer ping|Peer #2"` from
`repos/igloo-ui`, `npm --prefix repos/igloo-ui run build`, `npm --prefix test
run test:typecheck:pwa`, and `npm --prefix test run test:guards:docs`.

## 2026-06-22 — Settings Onboard handoff action lock

Polished the Settings **Onboard a Device** package handoff state so Copy, Save,
QR, Done, and Create Another behave as an exclusive transition. While one
handoff action is running, sibling actions and modal dismiss are disabled until
the current action resolves, preventing status races between package copy/save/QR
operations. Validation: `npm test -- --run test/OperatorPanels.test.tsx -t
"Settings Onboard Device|package handoff|locks Settings Onboard"` from
`repos/igloo-ui`, `npm test -- --run test/frontend/App.test.tsx -t "Settings
onboarding package from an explicit bfshare"` from `repos/igloo-pwa` (repo
script ran the full App test file), `npm --prefix repos/igloo-ui run build`,
`npm --prefix test run test:typecheck:pwa`, and `npm --prefix test run
test:guards:docs`.

## 2026-06-22 — Settings Onboard package creation lock

Polished the Settings **Onboard a Device** sponsor package creation state. The
shared dialog now announces package creation, disables sponsor inputs and
password reveal toggles, blocks Cancel/backdrop/Escape dismiss while creation is
in flight, and keeps the PWA modal frozen until the package helper resolves.
Validation: `npm test -- --run test/OperatorPanels.test.tsx -t "Settings
Onboard Device|package handoff|locks Settings Onboard"` from `repos/igloo-ui`,
`npm test -- --run test/frontend/App.test.tsx -t "locks the Settings onboarding
form"` from `repos/igloo-pwa` (repo script ran the full App test file), `npm
--prefix repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`,
and `npm --prefix test run test:guards:docs`.

## 2026-06-22 — Recover collection in-flight lock

Polished the outside-runtime Recover **Collect Shares** transition state. The
shared panel now announces that recovery is running, disables source package
and password edits, and locks add/remove controls while the recovery action is
in flight; the PWA path passes through the same `recover.collect` busy state.
Validation: `npm test -- --run test/CreateFlow.test.tsx -t "recover
collection|locks recover source|which recovery source|fixed recovery"` from
`repos/igloo-ui`, `npm test -- --run test/frontend/App.test.tsx -t "locks
recover collection inputs"` from `repos/igloo-pwa` (repo script ran the full
App test file), `npm --prefix repos/igloo-ui run build`, `npm --prefix test run
test:typecheck:pwa`, and `npm --prefix test run test:guards:docs`.

## 2026-06-22 — Dashboard action busy-state signals

Added accessible busy-state feedback to the custom signer dashboard refresh
and ping actions. Peer refresh, attention retry, and per-peer ping buttons now
pair their visible loading/disabled state with `aria-busy`, keeping the
hand-rolled dashboard actions aligned with the shared `Button` loading
contract. Validation: `npm test -- --run test/OperatorPanels.test.tsx -t
"pending approval|Pending Approvals|orders pending|Event Log controls|filters
the diagnostics log|peer refresh actions busy|per-peer ping actions busy|peer
refresh and per-peer ping"` from `repos/igloo-ui`, `npm --prefix
repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`, and
`npm --prefix test run test:guards:docs`.

## 2026-06-22 — Pending Approvals open-action guard

Polished the shared signer dashboard Pending Approvals section so `Open`
actions are disabled until a host wires an opener callback, while preserving
callback hooks for approval and pending-operation rows. This removes another
dead dashboard action without blocking the future interactive approval queue.
Validation: `npm test -- --run test/OperatorPanels.test.tsx -t "pending
approval|Pending Approvals|orders pending|Event Log controls|filters the
diagnostics log"` from `repos/igloo-ui`, `npm --prefix repos/igloo-ui run
build`, `npm --prefix test run test:typecheck:pwa`, and `npm --prefix test run
test:guards:docs`.

## 2026-06-22 — Event Log empty-state clear guard

Polished the shared signer dashboard Event Log empty state so an empty log
keeps the **Clear** action disabled while still showing the Paper-style `0
events` summary and no filter control. This prevents a dead action on fresh or
cleared signer sessions and aligns the empty state with the broader button
feedback pass. Validation: `npm test -- --run test/OperatorPanels.test.tsx -t
"Event Log controls|filters the diagnostics log"` from `repos/igloo-ui`, `npm
--prefix repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`,
`npm --prefix test run test:guards:docs`, and `git diff --check`.

## 2026-06-22 — Select Share key identity info

Replaced the Select Share group-key copy action with an info-only identity
section that shows both the keyset `npub` and raw hex group public key. The
shared `igloo-ui` panel now accepts explicit npub/hex labels, wraps both values
responsively, and the PWA derives the npub from the generated group hex before
rendering the create flow. Validation: `npm test -- --run
test/CreateFlow.test.tsx -t "select-share group public key"` from
`repos/igloo-ui`, `npm test -- --run test/frontend/App.test.tsx -t "hard-cut
create flow"` from `repos/igloo-pwa`, `npm --prefix repos/igloo-ui run build`,
`npm --prefix test run test:typecheck:pwa`, `npm --prefix test run
test:guards:docs`, and `git diff --check`.

## 2026-06-21 — Settings Onboard handoff status tones

Added explicit info/success/warning tones to the shared Settings **Onboard a
Device** handoff status. PWA copy/save/QR handoff feedback now renders
in-progress states as info, successful handoffs as success, and failed or
canceled handoffs as warnings instead of showing every status in green.
Validation: `npm test -- --run test/OperatorPanels.test.tsx -t "handoff
failures with a warning|package handoff state"` from `repos/igloo-ui`, `npm
test -- --run test/frontend/App.test.tsx -t "Settings onboarding package"`
from `repos/igloo-pwa`, `npm --prefix repos/igloo-ui run build`, `npm --prefix
test run test:typecheck:pwa`, `npm --prefix test run test:guards:docs`, and
`git diff --check`.

## 2026-06-21 — Settings Onboard sponsor missing-input status

Added a form-local missing-input status to the shared Settings **Onboard a
Device** sponsor dialog. When `Create Package` is disabled because required
sponsor fields are incomplete, the modal now names the missing device/source
or password fields instead of leaving the disabled state unexplained.
Validation: `npm test -- --run test/OperatorPanels.test.tsx -t "explains
missing Settings Onboard"`, `npm test -- --run test/OperatorPanels.test.tsx -t
"Settings Onboard Device|missing Settings Onboard"` from `repos/igloo-ui`,
`npm --prefix repos/igloo-ui run build`, `npm --prefix test run
test:typecheck:pwa`, and `npm test -- --run test/frontend/App.test.tsx -t
"Settings onboarding package"` from `repos/igloo-pwa`.

## 2026-06-21 — Recover Collect Shares source-row guidance

Added row-level readiness guidance to the shared outside-runtime **Collect
Shares** panel. Each remote share now shows whether it is waiting, missing the
source package, missing the package password, or ready to count toward the
threshold. Validation: `npm test -- --run test/CreateFlow.test.tsx -t "which
recovery source field is missing"`, `npm test -- --run test/CreateFlow.test.tsx
-t "recover collection|fixed recovery|which recovery source"` from
`repos/igloo-ui`, `npm --prefix repos/igloo-ui run build`, `npm --prefix test
run test:typecheck:pwa`, and `npm test -- --run test/frontend/App.test.tsx -t
"recover collection"` from `repos/igloo-pwa`.

## 2026-06-21 — Recover Collect Shares inline failure state

Added a form-local failure state to the outside-runtime **Collect Shares**
recovery panel. Failed recovery attempts now show an inline error next to the
source-package form, keep the user on the Collect Shares step, and clear the
message as soon as source material changes. Validation: `npm test -- --run
test/frontend/App.test.tsx -t "shows a local recovery error"` from
`repos/igloo-pwa`, `npm test -- --run test/CreateFlow.test.tsx -t "recover
collection|fixed recovery"` from `repos/igloo-ui`, `npm --prefix
repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`, and
`git diff --check`.

## 2026-06-21 — Settings Onboard handoff display identity split

Split the Settings **Onboard a Device** package handoff result so the modal can
show a compact Paper-style `npub...` share label while Save still derives the
`bfonboard` filename from the actual remote share public key. Validation:
`npm test -- --run test/frontend/App.test.tsx -t "Settings onboarding package"`
from `repos/igloo-pwa` and `npm test -- --run test/OperatorPanels.test.tsx -t
"package handoff state|Create Another action"` from `repos/igloo-ui`.

## 2026-06-21 — Settings Onboard handoff action guard

Hardened the shared Settings **Onboard a Device** package handoff dialog so
`Create Another` only renders when a host provides an action handler. This keeps
non-PWA hosts from exposing a dead command while preserving the PWA sponsor
flow. Validation: `npm test -- --run test/OperatorPanels.test.tsx -t "Create
Another action"` from `repos/igloo-ui`.

## 2026-06-21 — Settings Onboard handoff npub summary

Aligned the Settings **Onboard a Device** package handoff summary with the
Paper modal by showing the remote share public key as a compact `npub...`
display label instead of raw hex. Validation: `npm test -- --run
test/frontend/App.test.tsx -t "Settings onboarding package"` from
`repos/igloo-pwa`.

## 2026-06-21 — PWA dashboard route coherence

Made the PWA dashboard URL agree with the rendered runtime state: locked
reloads from `/dashboard/...` now replace back to `/`, and the dashboard
Recover action owns `/dashboard/recover` instead of leaving the previous tab's
URL behind. Browser back/forward between dashboard-launched Recover and
dashboard tab URLs now swaps the rendered view with the URL instead of leaving
Collect Shares or a dashboard tab under a stale path. Validation: `npm test --
--run test/frontend/App.test.tsx -t "dashboard navigation|reloaded dashboard
route"` from `repos/igloo-pwa`.

## 2026-06-21 — Dashboard peer method badges from policy state

Projected live runtime peer policy state into signer dashboard peer rows so the
Paper SIGN/ECDH/PING/ONBOARD method badges appear from `effective_policy`
instead of only when callers manually provide `permissionMethods`. Validation:
`npm --prefix repos/igloo-ui test -- --run test/DesignAdapters.test.tsx` and
`npm --prefix repos/igloo-ui test -- --run test/OperatorPanels.test.tsx -t
"peer"`.

## 2026-06-21 — Recover success save feedback

Added visible Save feedback to the outside-runtime Recover private-key success
screen: saving the recovered `nsec` or encrypted `ncryptsec` export now changes
the action label to **Saved!**, matching the existing Copy acknowledgment and
the broader button-feedback pass. Validation: `npm --prefix repos/igloo-pwa run
test:unit:raw -- test/frontend/App.test.tsx -t "recovered private key"`.

## 2026-06-21 — Settings Onboard handoff loading states

Added loading-button feedback to the Settings **Onboard a Device** package
handoff actions. The shared sponsor dialog now accepts the active handoff
action and renders Copy/Save/QR with the standard `igloo-ui` loading labels,
while PWA keeps Copy and Save in loading state until the clipboard/file writes
actually settle. Validation: `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx -t "package handoff state"` and `npm --prefix
repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx -t "Settings
onboarding package"`.

## 2026-06-21 — Recover Collect Shares guidance status

Aligned Recover **Collect Shares** copy with the Paper reference by keeping the
"Old devices do not need to be online..." guidance visible in all collection
states and moving the threshold-blocked/ready message into a separate
aria-live status line. The remote source password field also now uses the Paper
"Enter password to decrypt" placeholder. Validation: `npm --prefix
repos/igloo-ui test -- --run test/CreateFlow.test.tsx -t "recover collection"`
and `npm --prefix repos/igloo-pwa run test:unit:raw --
test/frontend/App.test.tsx -t "recover collection blocked"`.

## 2026-06-21 — Settings Onboard handoff feedback

Finished the Settings **Onboard a Device** package handoff action feedback:
the shared `igloo-ui` sponsor dialog now accepts an aria-live handoff status,
and `igloo-pwa` announces copy, save, and QR-code outcomes for the generated
`bfonboard` package while clearing stale messages on new package work.
Validation: `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx -t "package handoff state"` and `npm --prefix
repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx -t "Settings
onboarding package"`.

## 2026-06-21 — Recover fixed source-count collection

Aligned the outside-runtime Recover **Collect Shares** screen with the Paper
reference: shared `igloo-ui` recovery collection can render a fixed source set
without add/remove controls, and PWA recovery now initializes exactly
`threshold - 1` remote source slots from the selected profile. A 3-of-5 keyset
therefore opens with two remote source cards and `1 of 3 required` progress
instead of a single editable source list. Validation: `npm --prefix
repos/igloo-ui test -- --run test/CreateFlow.test.tsx` and `npm --prefix
repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx`.

## 2026-06-21 — Pending Operations Paper row projection

Aligned pending runtime operations with the shared Paper dashboard row model:
`runtimeStatusToSignerDashboardView` now projects operations into
`pendingApprovalRows` with method, peer, detail, and expiry labels while keeping
the legacy operation rows available for compatibility. The dashboard de-dupes
matching operation ids so the PWA and direct adapter consumers render one
Paper-style pending row instead of a duplicate legacy row. Validation: `npm
--prefix repos/igloo-ui test -- --run test/OperatorPanels.test.tsx
test/DesignAdapters.test.tsx`.

## 2026-06-21 — Event Log filter summary parity

Aligned the shared dashboard Event Log filter summary with the Paper dashboard
reference: the closed filter control now reports the four primary active
runtime lanes while preserving sync/echo diagnostic rows and the expanded
filter affordance. Validation: `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx`.

## 2026-06-21 — Pending Approvals nearest ordering

Aligned the shared dashboard Pending Approvals section with the live Paper
dashboard reference: approvals and pending runtime operations now render in
nearest-expiry order, and the section header's **Nearest** label is derived
from the same sorted list rather than trusting caller order. This keeps the
urgent approval row first when runtime data arrives out of order. Validation:
`npm --prefix repos/igloo-ui test -- --run test/OperatorPanels.test.tsx` and
`npm --prefix repos/igloo-ui run build`.

## 2026-06-21 — Settings Onboard signer-active gate

Tightened the Settings **Onboard a Device** sponsor dialog now that the
explicit `bfshare` producer path exists. The shared dialog honors its
`signerActive` prop, shows inline guidance when the signer is stopped, keeps
**Create Package** disabled until the signer is active and the package form is
complete, and uses the shared loading button state while packaging. PWA Settings
tests now cover both stopped-signer gating and the running-signer package
creation path. Validation: `npm --prefix repos/igloo-ui test -- --run
test/OperatorPanels.test.tsx -t "package creation while the signer is stopped"`,
`npm --prefix repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx
-t "unified settings actions"`, and `npm --prefix repos/igloo-pwa run
test:unit:raw -- test/frontend/App.test.tsx -t "creates a Settings onboarding
package"`.

## 2026-06-21 — Recover collection readiness gate

Aligned the Recover **Collect Shares** action with the Paper share-collection
state: the shared `igloo-ui` panel now keeps **Next Step** disabled until the
threshold is met, shows explicit blocked-state guidance, and the PWA counts
only remote source entries that include both package text and password. This
prevents empty or half-filled recovery submissions from falling through to the
generic adapter error. Validation: `npm --prefix repos/igloo-ui test -- --run
test/CreateFlow.test.tsx`, `npm --prefix repos/igloo-pwa run test:unit:raw --
test/frontend/App.test.tsx`, `npm --prefix repos/igloo-ui run build`, and `npm
--prefix test run test:typecheck:pwa`.

## 2026-06-21 — RelayList inline validation

Added inline validation to the shared `igloo-ui` `RelayList` primitive so
invalid relay text is rejected at entry time instead of surfacing later during
profile creation. PWA now passes `igloo-shared`'s `normalizeRelays` through the
create/import/onboard save-profile relay editors, and the create flow shows the
specific invalid relay message while leaving the saved relay list unchanged.
Validation: `npm --prefix repos/igloo-ui test -- --run
test/ui/misc-primitives.test.tsx -t "RelayList"` and `npm --prefix
repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx -t "validates
relays"`.

## 2026-06-21 — Shared RelayList primitive

Resolved the redundant relay-control follow-up by extracting the richer
create-flow relay editor into a public `igloo-ui` `RelayList` primitive while
leaving the older `RelayInput` export intact for compatibility. Create/save
profile flows now consume the shared primitive directly, and primitive tests
cover add, remove, read-only, and ping states. Validation: `npm --prefix
repos/igloo-ui test -- --run test/ui/misc-primitives.test.tsx -t "Relay"` and
`npm --prefix repos/igloo-ui test -- --run test/CreateFlow.test.tsx`.

## 2026-06-21 — Structural Settings dirty check

Replaced the PWA Settings dirty check's `JSON.stringify` comparison with an
explicit structural comparator for signer name, relay order, and signer setting
fields. This keeps transient relay input out of dirty state and avoids false
dirty states from harmless object key-order differences in persisted or
migrated signer settings. Validation: `npm --prefix repos/igloo-pwa run
test:unit:raw -- test/frontend/operator-settings.test.ts` and `npm --prefix
repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx -t "settings"`.

## 2026-06-21 — Stale load-recover reload cleanup

Closed the orphaned `load-recover` follow-up. The view is no longer part of the
PWA surface, and old persisted blobs with `activeView: "load-recover"` now
normalize to the resumable import entry screen instead of rendering an
Import-labeled shell with no body. Validation: `npm --prefix repos/igloo-pwa run
test:unit:raw -- test/frontend/App.test.tsx -t "stale load-recover"`.

## 2026-06-21 — Event Log fallback domain filtering

Resolved the Event Log fallback-filter open question. PWA fallback runtime log
lines now strip leading level/domain bracket tokens from their rendered message
while still inferring canonical domains such as `sync`, `sign`, `ecdh`, `ping`,
`echo`, and `signer policy` for badges and filters. Level-only fallback lines
remain visible without creating level filter chips. Validation: `npm --prefix
repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx -t "fallback
runtime log"`.

## 2026-06-21 — Runtime failure metadata pass-through

Preserved safe scalar failure metadata from WASM bridge failures through
`igloo-shared` observability: `parseOperationFailure` now retains the bridge
failure `code` as `reasonCode` plus `failed_peer`, the runtime failure schema
allows `failed_peer`, and the browser bridge emits `reason_code`/`failed_peer`
with runtime failure events. This supports richer Dashboard **Signing Failed**
details without loosening the observability redactor. Validation: `npm --prefix
repos/igloo-shared run test:unit -- src/runtime-pump.test.ts` and `npm
--prefix repos/igloo-shared run test:unit -- src/observability-schema.test.ts`.

## 2026-06-21 — Dashboard signing-failed state

Added the Paper **Signing Failed** dashboard modal for structured runtime sign
failures. `igloo-ui` now exports a shared `DashboardSigningFailedDialog`, and
`igloo-pwa` derives it from `runtime.failure` events with `op_type="sign"`,
showing the round id/error detail and routing **Retry** through the existing
signer refresh path. The PWA adapter also accepts richer future event metadata
for exact Paper copy when the runtime emits event kind, retry count, and peer
response counts. Validation: `npm --prefix repos/igloo-pwa run test:unit:raw --
test/frontend/App.test.tsx -t "signing-failed"`, `npm --prefix repos/igloo-ui
test -- --run test/OperatorPanels.test.tsx`, `npm --prefix repos/igloo-pwa run
test:unit:raw -- test/frontend/App.test.tsx`, `npm --prefix repos/igloo-ui run
build`, and `npm --prefix test run test:typecheck:pwa`.

## 2026-06-21 — Dashboard loading-profile state

Added the Paper **Loading profile...** transition for saved-profile unlocks
while the browser signer session is starting. `igloo-ui` now exports a shared
`DashboardLoadingState` with the dashboard profile strip and centered spinner,
and `igloo-pwa` renders it in-memory during the pending `startSession` call
while keeping incorrect-passphrase errors able to reopen the unlock modal.
Validation: `npm --prefix repos/igloo-pwa run test:unit:raw --
test/frontend/App.test.tsx -t "loading-profile"`, `npm --prefix repos/igloo-ui
test -- --run test/OperatorPanels.test.tsx`, `npm --prefix repos/igloo-pwa run
test:unit:raw -- test/frontend/App.test.tsx`, `npm --prefix repos/igloo-ui run
build`, `npm --prefix test run test:typecheck:pwa`, and `npm --prefix test run
test:guards`.

## 2026-06-21 — Dashboard all-relays-offline state

Mapped relay-specific runtime degradation onto the Paper **All Relays Offline**
state instead of collapsing it into generic signing-blocked copy. The shared
`igloo-ui` dashboard attention model now supports compact detail cards and a
contextual retry action, while `igloo-pwa` derives the relay outage from
runtime readiness `degraded_reasons`, shows `All relays unreachable · signing
degraded.`, and routes **Retry Connections** through the existing signer refresh
path. Validation: `npm --prefix repos/igloo-pwa run test:unit:raw --
test/frontend/App.test.tsx -t "all-relays-offline"`, `npm --prefix
repos/igloo-ui test -- --run test/OperatorPanels.test.tsx`, `npm --prefix
repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx`, `npm
--prefix repos/igloo-ui run build`, `npm --prefix test run test:typecheck:pwa`,
and `npm --prefix test run test:guards`.

## 2026-06-21 — Dashboard profile-load-failed state

Mapped saved-profile unlock/runtime startup failures onto the Paper
**Couldn't load profile** state instead of leaving every `startSession` failure
inside the password modal. Incorrect passphrases still remain inline in the
unlock modal, while non-passphrase profile load failures close the modal, show
Paper copy/actions (`Try Again`, `Back to Profiles`), and keep the error
in-memory only. Validation: `npm --prefix repos/igloo-pwa run test:unit:raw --
test/frontend/App.test.tsx -t "profile-load-failed"` and `npm --prefix
repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx`.

## 2026-06-21 — Dashboard signing-blocked attention state

Extended the PWA dashboard attention derivation to surface runtime readiness
blocks: when a running signer has relays configured but `sign_ready=false`, the
shared dashboard banner now shows **Signing is blocked** with the current
signing-peer count versus threshold and guidance to bring another signing peer
online. Validation: `npm --prefix repos/igloo-pwa run test:unit:raw --
test/frontend/App.test.tsx -t "no relays|signing-blocked"`.

## 2026-06-21 — Dashboard no-relays attention state

Added a shared `igloo-ui` dashboard attention model and warning banner for
actionable signer-level states, then wired `igloo-pwa` to surface it when an
unlocked profile has no configured relays. The runtime card no longer labels an
active zero-relay signer as `Connected`; it shows `No relays configured` plus
guidance to add a relay in Settings. Validation: `npm --prefix repos/igloo-ui
test -- --run test/OperatorPanels.test.tsx -t "attention states"` and `npm
--prefix repos/igloo-pwa run test:unit:raw -- test/frontend/App.test.tsx -t "no
relays"`.

## 2026-06-21 — Rotate collect-share local validation

Aligned the older Rotate Existing collect-shares path with the Recover flow:
when the selected source profile is the currently unlocked local device,
`igloo-ui` renders a **Share #N (this device)** validated row and `igloo-pwa`
auto-includes that encrypted local `bfshare` with the in-memory passphrase
before any pasted remote sources. Locked profiles still require pasted
`bfshare` packages. Validation: `npm --prefix repos/igloo-ui test -- --run
test/CreateFlow.test.tsx`, `npm --prefix repos/igloo-pwa test -- --run
test/frontend/App.test.tsx -t "auto-includes the unlocked local share"`,
`npm --prefix repos/igloo-ui run build`, and `npm --prefix test run
test:typecheck:pwa`.

## 2026-06-21 — Dashboard routes and deep links

Added URL-backed dashboard tab routing in `igloo-pwa` without persisting
runtime secrets: `/dashboard`, `/dashboard/permissions`, and
`/dashboard/settings` now deep-link into the unlocked dashboard, while locked
loads still render the Welcome/profile unlock surface until the user enters the
device passphrase. Dashboard tab clicks push browser history, Back restores the
previous dashboard tab, and dirty Settings browser navigation now opens the
unsaved-changes guard and restores `/dashboard/settings` when the user keeps
editing. Validation: `npx playwright test -c ./igloo-pwa/playwright.config.ts
./igloo-pwa/specs/app-shell.spec.ts`, `npm --prefix repos/igloo-pwa test --
--run test/frontend/App.test.tsx`, `npm --prefix test run test:typecheck:pwa`,
and `npm --prefix test run test:guards:selectors`.

## 2026-06-21 — Smoke UI polish backlog reconciliation

Reconciled the Igloo UI/PWA smoke-feedback backlog against the current branch.
Settings **Onboard a Device** now uses the shared explicit `bfshare` sponsor
dialog to produce post-setup `bfonboard` packages, Recover **Collect Shares**
uses its tailored panel with the local share validated, and Recover private-key
export now has a focused test asserting the encrypted `ncryptsec1` path. The
remaining Peer Telemetry item was narrowed to live bifrost-rs/igloo-shared
instrumentation because the shared dashboard UI and visual projection are
already aligned, while router and Paper source-of-truth cleanup remain open.
Validation: `npm --prefix repos/igloo-pwa test -- --run test/frontend/App.test.tsx`.

## 2026-06-20 — Settings sponsor producer clarified

Searched `igloo-pwa`, `igloo-home`, `igloo-ui`, `igloo-shared`, and
`bifrost-rs` for the Settings `Onboard a Device` producer path. The
`bfonboard` producer is already defined in code: PWA creates packages during
create/distribute, Home exposes the same operation through Tauri, `igloo-shared`
owns the shared sponsorship builder, and `bifrost-rs` owns the encoder. Updated
the Settings audit, unblock plan, and backlog to clarify that the remaining
blocker is Settings-time access to explicit target-member source material, not
an undefined package format or encoder.

## 2026-06-20 — Settings sponsor live Paper check

Inspected the live `igloo-ui-shared` Paper file through Paper MCP while
revisiting the Settings `Onboard a Device` blocker. The file currently has 70
artboards and no Onboard Sponsor artboards; the old sponsor IDs remain only in
the AppHeader usage documentation as stale references. Updated the Settings
audit, unblock plan, and backlog so the next pass starts by restoring,
recreating, or explicitly retiring those sponsor screens before implementation.

## 2026-06-19 — Settings sidebar audit and visual guard

Recorded the Settings sidebar alignment audit and the follow-up unblock plan for
the remaining `Onboard a Device` sponsor gap. The audit confirms the shared
Settings sidebar, profile security actions, Replace Share states, and responsive
PWA coverage are implemented, while the sponsor action still intentionally shows
a safe package-producer boundary until Paper sponsor screens and a real
source-material contract exist. Also tightened the PWA visual manifest/report
guarding so aligned rows cannot silently point at missing capture artifacts, and
confirmed strict Paper reconciliation passes with only recipient Onboard screens
exported.

## 2026-06-19 — Settings sidebar responsive guard

Added a narrow-viewport PWA visual capture for the shared Settings sidebar and
an explicit Playwright guard that fails when the document, sidebar panel, or
sidebar scroll body introduces horizontal overflow. The guard surfaced a real
mobile-width overflow in the dashboard header action slot, fixed by letting the
shared `igloo-ui` app header action area and the PWA dashboard nav wrap
compactly on phone-sized screens. The shared sidebar panel surface is now
opaque as well, matching Paper's solid Settings panel and preventing underlying
dashboard copy from bleeding through the mobile capture. The Settings Onboard
Device action row now uses the same compact outline action treatment as the
other Paper sidebar rows instead of a full-width primary button.

## 2026-06-19 — Settings sidebar Paper-only API

Relaxed the shared `igloo-ui` `OperatorSettingsSidebar` API so the Paper
sidebar can render without runtime/Advanced settings props. Runtime settings now
render only when explicitly supplied, while the PWA path keeps
`showAdvancedSettings={false}` for the Paper `502-0` sidebar. The component also
accepts the Paper-named `lockProfileAction` prop while preserving `logoutAction`
as a compatibility alias for older consumers, and exports
`OperatorSettingsSidebarProps` for downstream apps that need to type the shared
sidebar surface directly.

## 2026-06-19 — Settings sponsorship package contract

Added a host-neutral `igloo-shared` sponsorship package builder for the future
Settings `Onboard a Device` producer path. The helper creates a valid
`bfonboard` package only when a caller supplies explicit remote member source
material, validates that the source share matches the target group member, and
returns the canonical shared preview shape. The readiness model and shared
`igloo-ui` producer-ready panel now distinguish a real outside-runtime package
producer from explicit source-share package producers. PWA's existing
create/distribute package path now consumes the shared builder and strips the
secret-bearing shared preview field before returning its public app preview,
while Settings continues to show the safe producer-required boundary until a
real app-side package producer exists.

## 2026-06-19 — Settings Onboard Device readiness boundary

Moved the Settings `Onboard a Device` unavailable decision into a host-neutral
`igloo-shared` readiness helper and wired PWA to render the shared `igloo-ui`
sponsorship dialog with that status. The readiness model now names the missing
remote-share package producer, the required NSEC-or-threshold source material,
the saved-profile local-share-only boundary, and the safe fallback actions. This
preserves the current security boundary while leaving the real post-setup
package-producer contract in [`BACKLOG.md`](./BACKLOG.md). The shared
`igloo-ui` dialog also has a producer-ready branch for the eventual package
producer contract, covered by package-local tests. The UI props now use a
discriminated readiness union that is structurally compatible with the
`igloo-shared` helper, so future producer-state drift fails at compile time
instead of falling through loose string fields.

## 2026-06-19 — Settings Replace Share visual coverage

Added deterministic PWA visual captures for the Settings-launched Replace Share
runtime states: Applying Replacement, Replacement Failed, and Share Replaced.
The captures use a DEV-only in-memory visual seam so the pending onboarding
connection and passphrase remain non-persistable, and the shared `igloo-ui`
success summary now matches Paper by avoiding a duplicate Group Profile
`Unchanged` tag. The active PWA Replace Share path now also moves directly
from validated package entry into Applying Replacement, matching Paper without
an extra post-validation confirmation step.

## 2026-06-19 — Settings Clear Credentials alignment

Aligned the PWA Settings `Clear Credentials` action with Paper screen `3b` by
moving the destructive confirmation into a shared `igloo-ui` dialog, wiring the
PWA confirm path to stop the signer, delete the selected saved profile, clear
the unlock passphrase, and return to the profile list, and adding a visual
manifest capture for the modal.

## 2026-06-09 — Paper↔runtime design-sync reconciliation

Re-ran the PWA visual loop after the dashboard/settings/export work landed and
reconciled the tracking: promoted `dashboard-permissions`, `dashboard-settings`,
and `dashboard-export-profile` from `needs-work` → `aligned` in
`test/igloo-pwa/visual-manifest.json` (with notes recording the intentional,
plan-decided deviations), and expanded the `dashboard-signer` note to cover its
structural divergence (it stays `needs-work`, gated on bifrost-rs telemetry —
see [`BACKLOG.md`](./BACKLOG.md)). Repaired the strict design-sync gate by
repointing the `Modal` design-contract entry from the deleted `confirm-modal.tsx`
to `dialog.tsx`. Commits: `igloo-paper 31e343c`, parent `9e0f7a9`. Plan:
[`plans/dashboard-settings-export-paper-redesign-2026-06-01.md`](./plans/dashboard-settings-export-paper-redesign-2026-06-01.md).

---

# Archived follow-up log (migrated from root `FOLLOWUPS.md`, 2026-06-10)

The entries below are the verbatim historical follow-up log. Still-open items
have been triaged into [`BACKLOG.md`](./BACKLOG.md); this section is retained for
provenance and is not actively maintained.

## 2026-06-03 — RESOLVED: Docker follow-up batch (+ igloo-home skew found)

Cleared the loose-ends/issues/adjacent/open-question/future-scope items from the
section below. igloo-shell first (pushed `paper-create-flow-update`: `16d1a99` +
`a6eece3`), then parent.

### Resolved
- [x] ~~Push igloo-shell `16d1a99`~~ — pushed branch `paper-create-flow-update` to
  origin (`16d1a99` + `a6eece3`); parent pointer now resolves.
- [x] ~~`signing_key32: None` stopgap / confirm intent~~ — confirmed `None` is
  correct (the field drives bifrost-rs recovery re-split; igloo-shell has no
  import-from-key CLI). Hardened: call sites use `CreateKeysetConfig::new(...)`
  (`a6eece3`) so future optional-field additions don't churn igloo-shell.
- [x] ~~bifrost-rs↔igloo-shell drift gate~~ — added `make demo-pair-check`
  (`cargo check` both bins) + a CI step before `make test-demo`.
- [x] ~~Trim libssl from the Dockerfile~~ — dropped `pkg-config`/`libssl-dev`
  (builder) + explicit `libssl3` (runtime); both trees confirmed pure rustls.
  (Note: `libssl3` still ships in the `ubuntu:24.04` base — no longer our explicit
  dep, binaries don't link it.)
- [x] ~~Pin `RUST_IMAGE`~~ — `rust:1.95-bookworm` (matches host/CI stable 1.95).
- [x] ~~`make demo-stop` sweep default-project containers~~ — `stop_projects` now
  uses `docker ps -a` and always tears down the default (`frostr-infra`) project.
- [x] ~~Drop redundant host build on `make demo-start`~~ — removed `build_binaries`
  from `start_stack`; demo-start is now Docker-only (images self-build).
- [x] ~~BuildKit cache for CI~~ — `compose.ci.yml` (`type=gha` cache) + CI
  `docker/setup-buildx-action` + `COMPOSE_BAKE=true` + `FROSTR_DEMO_COMPOSE_OVERRIDE`;
  `test-prebuild.sh` threads the override into the demo image build. (Cross-run
  cache efficacy is observable only on a GHA runner.)

### Issues discovered, not fixed
- [ ] **igloo-home is skewed against this branch's igloo-ui** (effort: L) — surfaced
  while running `make test-demo` (chrome lane prebuilds the `home` target).
  igloo-home `eed7b7a` still imports removed igloo-ui exports
  (`OperatorPeerPermissionState`, `OperatorPendingOperation`) and uses the old
  `AppHeaderProps` (`centered`/`subtitle`), `StoredProfileCardModel`, and
  `SharedDistributionResult`/`SharedDistributionAction` shapes from before the Phase B
  igloo-ui changes. **This fails `make test-demo` — a required release-validation
  gate — on the `paper-create-flow-update` branch, independent of the Docker work.**
  Needs igloo-home ported to the current igloo-ui operator/create APIs (Tauri app:
  `src/App.tsx`, `src/pages/CreatePage.tsx`). The chrome `@demo` artifact-dir fix
  itself is verified by proxy (`make test-smoke` uses the identical repo-relative
  bind-mount mechanism and passes).

## 2026-06-03 — after cross-platform Docker demo stack (in-Docker builds)

### Loose ends
- [ ] Push the igloo-shell submodule commit `16d1a99` (branch `paper-create-flow-update`) before/with pushing the parent (effort: S) — parent `bf4679e` bumps the igloo-shell pointer to a local-only commit; until it's pushed, the parent pointer dangles for anyone else (and CI cloning the submodule).
- [ ] Verify the chrome `@demo` lane (`make test-demo`) end-to-end on colima (effort: S) — only `make test-smoke` was run to completion; `demo-harness.ts` got the same repo-relative artifact-dir fix but wasn't executed this session.

### Issues discovered, not fixed
- [ ] igloo-shell `signing_key32: None` is a compat stopgap, not a feature (effort: M, unsure) — `crates/igloo-shell-core/src/shell/rotation.rs:134,538` now hardcode `None`. If bifrost-rs added `signing_key32` to support importing a keyset from a known signing key, igloo-shell's keygen/rotation paths may need to actually thread a real value through rather than always `None`. Confirm with the bifrost-rs change intent.
- [ ] bifrost-rs ↔ igloo-shell submodule pointers drift silently (effort: M) — igloo-shell uses path deps into `../bifrost-rs/crates/*`, so a bifrost-rs API change (like `signing_key32`) breaks igloo-shell with no version gate. Worth a CI check that the pinned submodule pair compiles together, or a documented bump protocol in `dev/docs/RELEASE.md`.

### Adjacent improvements
- [ ] Trim defensive `libssl-dev`/`libssl3` from `services/demo/Dockerfile` (effort: S, unsure) — both bifrost-devtools and igloo-shell-core use rustls (`tokio-tungstenite` `rustls-tls-webpki-roots`); the OpenSSL libs were kept defensively while igloo-shell was uninspected. Now confirmed rustls, so they're likely removable (verify the full igloo-shell dep tree first).
- [ ] Pin `RUST_IMAGE` to an exact stable (e.g. `rust:1.89-bookworm`) instead of floating `rust:1-bookworm` (effort: S) — floating mirrors the repo's `stable` toolchain but makes image builds non-reproducible across time; pin if reproducibility matters, override via the existing ARG.
- [ ] The stale `frostr-infra-dev-relay-1` crash-loop container from the original bug had to be removed by hand this session (effort: S) — consider having `make demo-stop` also sweep the default-project `dev-relay`/`igloo-demo` containers, not just the named demo projects.

### Open questions
- [ ] Should `make demo-start` stop doing the redundant host `build_binaries` now that containers self-build? (effort: M) — carried/sharpened: host binaries are still needed by host `@live` lanes and the smoke's host `igloo-shell`, but a pure `make demo-start` no longer needs them for the containers. Splitting webapp-asset prep from demo-binary prep would make demo-start Docker-only. Needs care around the smoke/`@live` consumers.

### Future scope
- [ ] Add a BuildKit/registry cache for the in-Docker Rust build in CI (effort: M) — CI is ephemeral, so each `release-validation` run now pays a cold compile of bifrost-devtools + igloo-shell inside Docker. A `cache-from`/`cache-to` (GHA cache or registry) or `docker buildx` layer cache would cut that. Local dev already benefits from the cache mounts.

## 2026-06-02 — after the follow-up batch (Event-Log tags/filter, Peers counts, export)

### Loose ends
- [x] ~~No unit test for the `store.clearLogs` → `clearSessionLogs` adapter path~~ — RESOLVED: added `test/frontend/clear-session-logs.test.tsx` covering the active-session clearLogs call + the inactive/no-profile guards.

### Issues discovered, not fixed
- [x] ~~`App.tsx` `lastSeenLabel` skipped the seconds-vs-ms guard~~ — RESOLVED: now formatted via the existing `formatRuntimeTimestamp` helper (same ms-guard + `toLocaleString` as the igloo-ui adapter), fixing both the wrong-time bug and the format inconsistency below.
- [x] ~~`observabilityEventsToEventRows` row id had no index~~ — RESOLVED: id is now prefixed with the array index so same-tick events can't collide on the React key.
- [x] ~~`attachLogBuffer` kept two unbounded buffers~~ — RESOLVED: both `lines` and `events` are capped to the last 500 via `pushCapped`.

### Adjacent improvements
- [x] ~~`refreshSession` diverged from `toRuntimeSnapshot`~~ — RESOLVED: `refreshSession` now builds through `toRuntimeSnapshot` (so `peer_permission_states`/`events` stay in sync) and only annotates the log tail with the refresh marker.
- [x] ~~Peer last-seen formatted two different ways~~ — RESOLVED together with the ms-guard fix (both paths now use `toLocaleString`-style formatting).
- [x] ~~Clear-Log button could render on a stopped session~~ — RESOLVED: `App.tsx` only passes `onClearLogs` while the runtime is active, so the button is hidden when inactive.

### Open questions
- [ ] Filter chips key off `badgeLabel` = domain for structured events but = level (info/warn/error) for the string fallback (effort: S) — the Filter still works for the fallback but filters by level, not domain. Decide whether the fallback should be filterable at all or the chips should hide when events are unstructured.

### Future scope
- [ ] (Carried, unchanged) Per-peer latency / "Avg" latency / nonce sparkline / per-method SIGN·ECDH·PING capability badges — runtime instrumentation in bifrost-rs/igloo-shared; the trigger to promote the `dashboard-signer` manifest entry to `aligned` (documented in its `notes`).

## 2026-06-02 — RESOLVED: Phase B follow-up batch (Event Log structure, Peers counts, export + cleanups)

Cleared the loose-end / issue / adjacent / one open-question items below in a
single pass. igloo-ui first (then dist rebuild), igloo-pwa next, parent pointer.

### Resolved
- [x] ~~Export Download uses an anchor blob with no save confirmation~~ — extracted
  `downloadText`/`saveTextToFile` into `repos/igloo-pwa/src/lib/file-save.ts`;
  `App.tsx` ExportPackageModal `onDownload` now routes through `saveTextToFile`
  (File System Access API confirmed-write + anchor fallback), matching the
  distribution flow. Verified by the export `@live` spec.
- [x] ~~Inline `group_package_json`/`share_package_json` parsing duplicated in
  `App.tsx`~~ — folded into `deriveGroupSummary` + `deriveExportSummary` in
  `src/lib/dashboard-view.ts` (alongside the existing `deriveMemberLabel`/
  `toDashboardKey`), with unit coverage in `test/frontend/dashboard-view.test.tsx`.
- [x] ~~Reconcile Permissions summary pills vs Paper~~ — gated behind a new
  `showPeerSummary` prop on `OperatorPermissionsPanel` (default true for other
  consumers); the PWA passes `showPeerSummary={false}` so the page matches Paper.
- [x] ~~Event Log Clear button was inert in the PWA~~ — wired `onClearLogs` →
  `store.clearLogs()` → `clearSessionLogs` adapter → host-side `session.clearLogs()`.
- [x] **Event Log structured tags + filter** — the host-side log buffer
  (`page-runtime-host.ts`) now retains the raw `ObservabilityEvent` objects it
  already received (no igloo-shared change); threaded `events` through the snapshot/
  types/adapter and rendered via igloo-ui's `observabilityEventsToEventRows`, with a
  domain-tag Filter control in `OperatorSignerPanel`.
- [x] **Peers header counts (UI-only)** — online/total + ready counts and per-row
  last-seen from data the runtime already exposes. Also fixed a latent state-mapping
  bug in `derivePwaPeers` (sign-ready peers were flagged `'warning'`, contradicting
  their `sign-ready` status label and the shared igloo-ui adapter).
- [x] `dashboard-signer` manifest stays `needs-work` with a `notes:` promotion
  trigger documenting the remaining runtime-gated gaps.

### Still future scope (runtime-gated; unchanged)
- [ ] Per-peer latency, "Avg" latency, the nonce sparkline, and per-method
  SIGN/ECDH/PING capability badges (effort: L) — require bifrost-rs/igloo-shared
  runtime instrumentation; the promotion trigger for the dashboard manifest entries.
- [ ] Persisting structured events end-to-end was NOT needed for the log tags — the
  PWA host already receives them; a deeper structured-event *store* (history,
  cross-session) remains future scope if richer Event-Log queries are wanted.

## 2026-06-02 — after Phase B complete (Settings, Export modals, Unsaved-changes guard)

### Loose ends
- [ ] Promote the dashboard family's `needs-work` visual-manifest entries → `aligned` (effort: M) — `dashboard-signer`, `dashboard-permissions`, `dashboard-settings`, `dashboard-export-profile` in `test/igloo-pwa/visual-manifest.json` are all still `needs-work`. They're structurally faithful but gated on the deferred Peers/Event-Log parity (and a deliberate side-by-side review) before honestly flipping to `aligned`.

### Issues discovered, not fixed
- [ ] The export Download uses an anchor-click blob download with no save confirmation (effort: S) — `repos/igloo-pwa/src/App.tsx` ExportPackageModal `onDownload` mirrors the recover flow's optimistic anchor download; unlike `saveTextToFile` in `store.tsx` it doesn't use `showSaveFilePicker`. Consider routing both through the same save helper so "Download" reflects an actual write.
- [ ] Export modal has no busy/disabled treatment on Copy/Download while re-encrypting (effort: S, unsure) — `exportBusy` gates the Export submit but the complete-state actions assume `result` is ready; fine in practice since they only render post-result, but worth confirming no flicker between busy→complete.

### Adjacent improvements
- [ ] Reconcile the Permissions summary pills (Peers / Effective responders) with Paper (effort: S) — carried from step 2; Paper doesn't draw them. Confirm they stay or drop.
- [ ] `deriveExportSummary` + `deriveMemberLabel` + `toDashboardKey` now all parse `group_package_json`/`share_package_json` inline in `App.tsx` (effort: S) — the export summary parse duplicates member/group parsing; could fold into the extracted `src/lib/dashboard-view.ts` for one parsing path + unit coverage.
- [ ] Settings dirty-check compares via `JSON.stringify` of relays/signerSettings (effort: S, unsure) — `settingsDirty` in `App.tsx` relies on key-order-stable stringify; true for these fixed-shape objects, but a structural compare would be more robust if the shapes grow.

### Open questions
- [ ] Should the merged identity/runtime card also top the Permissions + Settings sub-pages? (effort: M) — carried from step 2; Paper shows it on all three, the PWA shows it only on Dashboard. Header nav already gives context; decide the cross-page pattern (and whether to lift the card into a shared page-shell) rather than leave it Dashboard-only.
- [ ] Confirm whether `Export Profile`/`Export Share` should also keep a quick unencrypted copy-to-clipboard alongside the password modal (effort: S) — step 3→4 replaced copy with the modal entirely; some users may want a fast copy. Product call.

### Future scope
- [ ] Dashboard Peers + Event Log full Paper parity (effort: M) — Peers rows (online/ready counts, latency sparkline, per-method badges) + Event Log (type-tagged rows + filter); the trigger to promote the dashboard visual entries to `aligned`.
- [ ] Interactive signing-approval runtime feature behind the Pending Approvals shell (effort: L) — the empty-state card is shipped; real Deny/Allow-once/Always-allow needs runtime hooks in `igloo-shared`/`bifrost-rs`.
- [ ] Deferred dashboard screens: error/empty states (loading, load-failed, all-relays-offline, signing-blocked, signing-failed) + Clear Credentials modal (`3b`) (effort: L) — Clear Credentials needs a new destructive "clear this device's saved profile/share/password/relays" store action.
- [ ] Evaluate a real router for the dashboard pages (effort: L) — header nav still drives `store.activeDashboardTab`; URL deep-linking/back-button is a separate refactor with route-guard considerations.
- [ ] Adopt the new igloo-ui Settings `sections` API + ExportPackageModal in igloo-chrome (effort: M) — chrome still uses the flat `maintenanceActions` row and its own export; aligning it would unify the operator surface, but is out of the PWA-focused Paper pass.

## 2026-06-02 — after Phase B step 2 (Permissions page)

### Open questions
- [ ] Should the merged identity/runtime card also appear at the top of the
  Permissions (and Settings) sub-pages? (effort: M) — Paper's `1c-permissions`
  artboard shows the identity card above the permissions sections, but the PWA
  Permissions page currently renders only the permissions panel (the identity card
  is dashboard-only). The header nav already provides context, so omitting it is
  defensible; decide the cross-page pattern before/with the Settings page so it's
  consistent. If "yes," the merged card likely wants to move into a shared
  page-shell above the tab content rather than be duplicated per panel.

### Adjacent improvements
- [ ] Reconcile the Permissions summary pills (Peers / Effective responders) with
  Paper (effort: S) — the PWA `OperatorPermissionsPanel` shows summary pills Paper
  doesn't draw. Harmless and arguably useful, but confirm whether they stay when
  the page is finalized.

## 2026-06-01 — after Phase B dashboard slice (merged identity card + header nav)

### Loose ends
- [x] ~~Trim the redundant dashboard outer `ContentCard` title~~ — RESOLVED
  (cleanup pass): removed the outer `ContentCard` wrapper entirely (bare surfaces;
  see resolved open question). `dashboardRoot` test-id now sits on a plain `div`;
  the profile label persists via the merged card's `profileName` badge so the
  `expectDashboard`/`expectPwaDashboard` label assertions still hold (verified via
  app-shell + dashboard-visual specs).
- [~] `dashboard-signer` visual manifest stays `needs-work` — REVIEWED 2026-06-02
  (ran `test:visual:report` + a direct side-by-side of the PWA capture vs
  `repos/igloo-paper/screens/dashboard/1-signer-dashboard/screenshot.png`).
  **Structurally faithful** (Dashboard·Permissions·Settings nav + active pill,
  merged identity/runtime card with split npub copy, Peers → Pending Approvals →
  Event Log order). **Remaining fidelity gaps = exactly the deferred work**, so
  `aligned` would be premature:
  1. **Peers rows** — Paper shows online/ready counts, a latency sparkline, avg
     latency, and per-method SIGN/ECDH/PING badges; the PWA shows bare metric tiles.
     (Deferred "Peers full-parity" enhancement.)
  2. **Event Log** — Paper is populated with type-tagged rows + a filter control;
     the PWA seeds an empty log. (Deferred "Event Log parity" enhancement.)
  3. **Pending Approvals** — Paper shows populated approval rows; the PWA shows the
     intentional empty-state shell (interactive approval is the deferred runtime
     feature — working as designed).
  Promote to `aligned` only after the Peers/Event-Log parity pass; until then
  `needs-work` is the accurate status.

### Issues discovered, not fixed
- [x] ~~The split-copy hex/npub caret menu has no outside-click dismiss~~ — RESOLVED
  (cleanup pass): `KeyRow` now registers a `document` `mousedown` listener while the
  menu is open and closes it on an outside click (cleaned up on unmount); covered by
  a new assertion in `OperatorPanels.test.tsx`.
- [x] ~~The npub/hex copy menu can overflow/clip near a card edge~~ — CHECKED, no
  change needed: the menu's container is `overflow-visible` and the merged card has
  ample right-side room; not observed clipping in the 1440px capture. Re-evaluate if
  a narrow-viewport dashboard is ever added.

### Adjacent improvements
- [x] ~~Add an igloo-pwa unit test for `toDashboardKey` / `deriveMemberLabel`~~ —
  RESOLVED (cleanup pass): new `repos/igloo-pwa/test/frontend/dashboard-view.test.tsx`
  covers valid/normalized/malformed inputs for both.
- [x] ~~Extract `toDashboardKey`/`deriveMemberLabel` out of `App.tsx`~~ — RESOLVED
  (cleanup pass): moved to `repos/igloo-pwa/src/lib/dashboard-view.ts` (pure, no
  React/store); `deriveMemberLabel` now takes the share-package-json string directly.
- [x] ~~Reconcile leftover `pulse-animation`/`User` imports in `OperatorSignerPanel`~~
  — CHECKED: `pulse-animation` and `User` are already gone; `Input`/`KeyField` remain
  in deliberate use as the single-copy fallback for consumers without structured keys
  (igloo-chrome). No dead code.

### Open questions
- [x] ~~Remove the dashboard `ContentCard` wrapper in favor of bare surfaces?~~ —
  DECIDED: yes. Wrapper removed this pass; establishes the surfaces-not-boxes pattern
  for the upcoming Permissions/Settings pages.

### Future scope
- [ ] Remaining Phase B steps (all shaped in `dev/plans/dashboard-settings-export-paper-redesign-2026-06-01.md`): Permissions page (step 2), Settings page incl. Advanced section + Replace Share + Logout + Unsaved-Changes guard modal (step 3), Export Profile/Share password modals (step 4) (effort: L).
- [ ] Two remaining Paper-source edits before the Settings pass: "Lock Profile" → "Logout" on artboard `502-0`, and reconcile "Replace Share" terminology (effort: S) — noted in the plan; needs a Paper MCP edit + re-sync.
- [ ] Standardize the rotate→"Replace Share" user-facing rename across igloo-ui/igloo-pwa (flow title "Rotate Key", button "Replace Active Device", Settings action) while keeping internal `rotate*` names (effort: M) — decided this session; lands with the Settings page.
- [ ] Deferred dashboard screens not yet aligned: error/empty states (`1b-loading-profile`, `1b-profile-load-failed`, `2b-all-relays-offline`, `2c-signing-blocked`, `6-signing-failed`), Clear Credentials modal, and the interactive signing-approval runtime feature behind the Pending Approvals shell (effort: L).
- [ ] Dashboard Peers + Event Log full Paper parity (effort: M) — Peers rows want online/ready counts, latency sparkline, avg latency, and per-method SIGN/ECDH/PING badges (vs current bare metric tiles); Event Log wants type-tagged rows + a filter control. This is the trigger to promote the `dashboard-signer` visual manifest entry from `needs-work` → `aligned` (see the 2026-06-01 reviewed loose end).
- [ ] Evaluate a real router for the dashboard pages (effort: L) — currently header nav drives `store.activeDashboardTab`; URL deep-linking/back-button is a separate future refactor with route-guard considerations for sensitive unlocked states.

## 2026-05-31 — after fixing the two-device onboard handshake test

### Resolved
- [x] The live two-device onboard handshake **does** complete locally (~14ms relay
  round-trip). The earlier "handshake never completes" was a false alarm: the test
  helper `onboardPwaDevice` waited for "Onboarding Complete" text and `onboardSave*`
  test-ids that the PWA never renders. The PWA's onboard-save screen is
  `CreateFlowProfileSetup` (title "Save Profile", `saveProfile*` ids), with a
  read-only, package-derived device name. Helper fixed; `onboarding.spec.ts` now
  drives a complete onboard and asserts the request/response crossed the relay;
  `rotation-create.spec.ts` (same helper) also green. The duplicate
  `onboarding-live.spec.ts` was removed.

### Discovered while verifying the `@live` lane (pre-existing, separate from the onboard fix)
- [x] ~~`profile-import.spec.ts` import helper is stale~~ — RESOLVED: `openPwaLoadProfile`
  was rebuilt as `openPwaImportProfile` on the welcome/import test-ids
  (`welcomeEntryImport`, `importProfileInput`, `importPasswordInput`, `importNext`, then
  `saveProfile*`). profile-import is green.
- [x] ~~`rotation-update.spec.ts` (`@live`) drives a stale dashboard rotate-key flow~~ —
  RESOLVED: the rotate-connect/confirm flow was actually current (the spec only failed on the
  now-fixed import helper). Hardened its remaining copy-coupled selectors anyway —
  `connectPwaRotationPackage` uses new `rotationPackageInput`/`rotationPasswordInput` ids and
  `openPwaRotateShare` opens Settings via `dashboardTabSettings`. The full igloo-pwa `@live`
  lane is green (5/5: onboarding, profile-import, profile-inventory, rotation-create,
  rotation-update).

### Resolved — recipients can name their device on onboard
- [x] ~~Onboarded devices are auto-named "Onboarded Device" with a read-only name field~~ —
  FIXED: `CreateFlowProfileSetup` now takes a `lockName` prop (defaulting to `lockIdentity`
  so create/import callers are unchanged), and the igloo-pwa onboard-save screen passes
  `lockName={false}`. The recipient names their own device during onboarding while the keyset
  relays stay locked; `onboarding.spec.ts`/`rotation-create.spec.ts` assert the chosen names.

## 2026-05-30 — after the test-system hard-cut refactor

### Loose ends
- [ ] Convert the igloo-chrome e2e specs to the page-object model (effort: M) — the
  tightened `check-e2e-selector-contracts.sh` scopes the role/label/placeholder/class bans
  to `test/igloo-pwa/specs` because chrome specs (`dashboard.spec.ts`, `provider.spec.ts`,
  `rotation-update.spec.ts`, …) still use raw interaction locators. Build
  `test/igloo-chrome/support/pages/*` reusing the shared registry keys, then broaden the
  guard to chrome. (igloo-chrome **unit** tests are already fixed and green.)
- [x] ~~Decide whether the `@live` two-device specs should run in CI and confirm the live
  onboard handshake there~~ — RESOLVED (see 2026-05-31 above): the handshake completes
  locally; both `@live` two-device specs are green and run in `make test-live` + CI's live lane.

### Issues discovered, not fixed
- [x] ~~The live two-device onboard handshake does not complete in the local sandbox~~ —
  RESOLVED (see 2026-05-31 above): it was a stale test-helper assertion, not a runtime/relay
  problem. The handshake completes in ~14ms; both specs now pass locally and assert the
  request/response crossed the relay.
- [ ] The jsdom-28 `--localstorage-file` Node warning is benign but noisy across unit runs
  (effort: S) — it fires before the setup shim installs; suppress via a vitest pool/Node-option
  tweak if the noise matters.
- [x] ~~chrome e2e lane can't resolve `igloo-shared` from `test/`~~ — FIXED (2026-05-31):
  added `"igloo-shared": "file:../repos/igloo-shared"` to `test/package.json` devDependencies
  (`npm install` materialises the `test/node_modules/igloo-shared` symlink; the `exports` map
  points `.` → `src/index.ts`, which Playwright transforms). The chrome lane now resolves it and
  runs. Root cause was: `test/shared/browser-runtime-host.ts` bare-imports `igloo-shared`
  (only `igloo-chrome/specs/rotation-update.spec.ts` pulls it in); the client repos have the
  symlink but `test/` didn't, and the tsconfig `paths` alias is typecheck-only.
- [x] ~~chrome fast lane drags in the home+demo prebuild it never runs~~ — FIXED (2026-05-31):
  added a `fastPrebuild` set to `test/shared/test-targets.json` (`chrome → ["chrome"]`),
  honoured by `targetsForClient` when `FROSTR_TEST_LANE=fast` (set by the `:fast` npm scripts),
  and added `@cross-client` to the chrome fast `--grep-invert` (matching the pwa fast lane).
  `make test-fast` no longer needs the uninitialized `igloo-home`/`igloo-shell` submodules or
  the Tauri toolchain. (The cross-client pairing specs still run in the full/CI lane.)
- [x] ~~**REAL BUG: chrome profile import fails in the MV3 service worker**~~ — FIXED (2026-06-01):
  `import() is disallowed on ServiceWorkerGlobalScope` when loading the profile/bridge WASM in the
  background service worker (`COMMAND_TYPE.PROFILES_IMPORT` → `router-profiles.ts` → igloo-shared
  `loadConfiguredWasmModule` → `dynamicImportModule`). Fixed in
  `repos/igloo-chrome/src/lib/configure-igloo-shared.ts` by statically importing the two wasm-pack
  glue modules (static import IS allowed in a module worker) and passing them via `preloadedModule`,
  which bypasses the loader's dynamic-import branch. The glue still `fetch`es its `_bg.wasm` from the
  explicit `wasmBinaryUrl` (allowed in a SW); no `.wasm` is inlined. igloo-shared + the PWA (page
  context, dynamic import allowed) are untouched. `profile-import.spec.ts` + `rotation-update.spec.ts`
  now pass; chrome fast lane 17/17 green.

### Adjacent improvements
- [ ] Give the QR-package modal and the onboard "Apply"/connect surfaces explicit copy that
  matches a test-id (effort: S) — the onboard-connect submit is labeled "Next Step" while the
  helper history assumed "Apply Onboarding Package"; the test-id (`onboard-connect-submit`)
  now decouples it, but the label drift is worth reconciling with Paper.
- [ ] Remove the now-stale pre-existing `test/scripts/test-run-sh.sh` WIP from the working tree
  or land it (effort: S) — it is the only remaining dirty parent file and predates this work.

## 2026-05-30 — after WS4 Paper sync, WS5 verify, and e2e spec alignment

### Loose ends
- [ ] Fix `rotation-create.spec.ts` secondary-device isolation so the live onboard handshake completes (effort: M) — after the Finish Setup + label alignment, the test reaches the secondary onboard but `openFreshPwaPage(browser)`'s context shows the seeded "Source Device 1" returning Welcome instead of a clean entry hero, so `onboardPwaDevice` never reaches the onboard screen (times out on "Apply Onboarding Package"). Likely `browser.newContext()` inheriting a global `storageState` from `test/igloo-pwa/playwright.config.ts`; pass an empty `storageState` (or clear localStorage) for the fresh page. The spec's label/structure alignment is staged but left uncommitted until the handshake passes. `app-shell.spec.ts` is fully aligned and green.

### Adjacent improvements
- [ ] Add an e2e assertion that the distributor's share card flips to **Onboarded** after a real peer onboarding (effort: M) — exercises the WS3d onboard-complete event end-to-end; depends on the rotation-create isolation fix above.
- [ ] Give distribution cards a stable test id (effort: S) — `app-shell.spec.ts` now locates the first card positionally because the packaged card no longer renders a password field; a `data-test-id` per share card would make the create/rotation specs less brittle and unblock consolidating the duplicated create→distribute setup already tracked in earlier sections.

## 2026-05-27 — after hard-cut Create flow implementation

### Loose ends
- [ ] Review and commit the multi-repo branch state across root, `repos/igloo-paper`, `repos/igloo-ui`, `repos/igloo-pwa`, `repos/bifrost-rs`, `repos/igloo-shared`, and `repos/igloo-chrome` (effort: M) — this implementation is validated but spans several submodules plus refreshed WASM artifacts, so commit ordering and submodule pointers need a deliberate pass.
- [ ] Decide what to do with the pre-existing untracked `dev/plans/igloo-ui-remaining-paper-sync-hard-cut-plan-2026-05-25.md` before final staging (effort: S) — it still appears in root status and should be either intentionally added, archived, or left out of this branch.

### Issues discovered, not fixed
- [ ] Investigate the PWA visual web-server `NO_COLOR` / `FORCE_COLOR` warning around `test/igloo-pwa/playwright.config.ts:14` (effort: S) — the visual lane still prints the warning even though the config deletes both env keys, and `repos/igloo-pwa/CHANGELOG.md:15` says it was fixed.
- [ ] Investigate the Vitest `--localstorage-file` warning in `repos/igloo-pwa` unit tests (effort: S) — every PWA unit run reports the warning before tests pass, which adds noise to otherwise clean validation output.

### Adjacent improvements
- [ ] Add focused tests for `optionalSigningKeyBytes` in `repos/igloo-pwa/src/lib/local-adapter/profile-generate.ts:38` (effort: S) — Rust covers splitting an existing key and the UI covers the field, but the PWA nsec/hex decoding bridge has no direct test.
- [ ] Decide whether `Launch Signer` should be disabled until every remote share is marked `Done` (effort: S) — the current implementation leaves it enabled so users can enter the signer immediately, but the distribution cards now expose completion state.
- [ ] Extract the repeated Create flow Playwright setup across `test/igloo-pwa/specs/app-shell.spec.ts`, `test/igloo-pwa/specs/rotation-create.spec.ts`, and `test/igloo-pwa/specs/welcome-visual.spec.ts` (effort: M) — the new Select Share / Save Profile path is repeated in several specs and will be easy to drift.
- [ ] Add a small regression test for `repos/igloo-paper/scripts/update_usage_coverage.py` (effort: M) — the command is now part of the Paper workflow, but only the manifest pruning and verifier-count helpers have direct script-level tests.

### Open questions
- [ ] Confirm whether the UI copy for `Existing Private Key (optional)` should explicitly mention 64-character hex as well as nsec (effort: S) — `repos/igloo-pwa/src/lib/local-adapter/profile-generate.ts:38` accepts both formats, while the Paper/user-facing label emphasizes nsec.
- [ ] Confirm default peer permissions for new remote shares (effort: S) — `repos/igloo-pwa/src/lib/store.tsx` initializes each remote share with `sign`, `ecdh`, `ping`, and `onboard` enabled, which is permissive and may need product confirmation.

### Future scope
- [ ] Run and archive a visual comparison report with `npm --prefix test run test:visual:report` after design review (effort: M) — the capture lane passed, but the Paper-to-PWA screenshot review artifact is still the next useful review deliverable.
- [ ] Consider a smaller routine WASM validation path for sandboxed agent runs (effort: L) — `wasm-opt` still requires escalation for full browser WASM refresh/build work, which is accurate but slows routine iteration.

## 2026-05-27 — after Create flow Paper redesign

### Loose ends
- [ ] Review and commit the `repos/igloo-paper` export changes, then commit the parent workspace pointer and `test/igloo-pwa/visual-manifest.json` update (effort: S) — this session left validated work on branch `paper-create-flow-update`, but no commits were made.

### Issues discovered, not fixed
- [x] Make `make igloo-paper-sync` run Python with bytecode disabled or clean `__pycache__` before verification (effort: S) — the first sync failed because generated Python caches under `repos/igloo-paper/scripts/` violated the verifier’s cache-artifact guard.
- [x] Teach the Paper export workflow to remove stale generated screen directories when artboards are deleted or renamed (effort: M) — deleting `Generation Progress`, `Distribution Completion`, and renamed shared screens required manual directory cleanup before manifest verification could pass.
- [x] Replace or wrap the hard-coded `artboard-map.json` count checks in `repos/igloo-paper/scripts/verify.py:190` with a less brittle update path (effort: M) — deleting two mapped screens and adding one new screen required manually changing the expected total and screen count.
- [x] Add a documented command for regenerating `design/tokens/usage-coverage.json` from current exports (effort: M) — strict drift coverage had to be regenerated manually after the new Paper nodes introduced and removed prototype-only colors and typography pairs.

### Adjacent improvements
- [x] Update `repos/igloo-paper/docs/mcp-edit-workflow.md:40` with a “renaming or deleting artboards” checklist (effort: S) — the current workflow lists files to update when adding artboards, but not stale export cleanup, visual-manifest updates, or manifest rebuild order.
- [x] Update `repos/igloo-paper/docs/mcp-edit-workflow.md:55` to recommend `PYTHONDONTWRITEBYTECODE=1 make igloo-paper-sync` until the command handles caches itself (effort: S) — this avoids a known verifier failure mode during Paper sync.
- [x] Add a note in `dev/docs/WORKFLOWS.md` that Paper screen renames may require `test/igloo-pwa/visual-manifest.json` updates (effort: S) — the guard caught stale Paper screenshot paths only after the old exports were removed.

### Open questions
- [x] Decide what the final `Next Step` on `Distribute Shares` should do now that Distribution Completion is removed (effort: S) — the final action is now `Launch Signer` and transitions directly to the signer dashboard.

### Future scope
- [x] Update `igloo-ui` / `igloo-pwa` implementation to match the new four-step Paper design (effort: L) — this pass wires the four-step flow through `igloo-ui` and `igloo-pwa`.

## 2026-05-25 — after Paper welcome label sync and UI workflow cleanup

### Loose ends
- [ ] Push the new root and submodule commits once review is complete (effort: S) — root is ahead of `origin/master` by six commits and `repos/igloo-paper`, `repos/igloo-ui`, and `repos/igloo-pwa` are each ahead by one commit.
- [ ] Document the three UI workflows in a repo-owned guide under `dev/docs/` or `dev/plans/` (effort: M) — `repos/igloo-paper/docs/mcp-edit-workflow.md:16` covers live Paper MCP edits, but does not yet cover choosing between Paper-to-export, export-to-UI screenshot alignment, and dual Paper+UI edits.
- [ ] Create a `frostr-paper-ui-workflows` skill that dispatches agents to the right Paper/UI workflow (effort: M) — the user wants agents to select the correct workflow instead of rediscovering the process each session.

### Issues discovered, not fixed
- [ ] Investigate why full `make igloo-paper-sync` refreshed unrelated dashboard screenshots and non-Welcome reference HTML during a Welcome label change (effort: M) — accepting generated drift is sometimes correct, but unrelated churn makes Paper review noisier.
- [ ] Add progress logging or per-artboard context to `repos/igloo-paper/scripts/paper_mcp.py:84` screenshot export (effort: S) — the retry/context patch helped, but a long timeout still should identify the current artboard before failing.
- [ ] Decide whether onboarding should expose a device-name field again or whether tests should stop passing a label to `onboardPwaDevice` (effort: M) — `test/igloo-pwa/support/ui.ts:66` still accepts `label`, but the current UI no longer uses it and the rotation test now expects `Onboarded Device`.

### Adjacent improvements
- [ ] Extract repeated distribution-card setup into a Playwright helper (effort: M) — `test/igloo-pwa/specs/app-shell.spec.ts:24` and `test/igloo-pwa/specs/rotation-create.spec.ts:52` now duplicate the create-package, QR, and mark-distributed sequence.
- [ ] Add a focused visual comparison report for Paper screenshot versus PWA capture pairs (effort: L) — the current loop relies on manual `view_image` inspection after `npm --prefix test run test:e2e:igloo-pwa:visual`, which works but is hard to audit later.
- [ ] Add a guard or doc note for the scratch WASM ESM `package.json` behavior in `scripts/prepare-browser-wasm.sh:120` (effort: S) — the fix is small and validated, but future refactors could remove it without realizing Node needs the wasm-pack `.js` files treated as ESM.
- [ ] Broaden `scripts/igloo-pwa-dev.sh:65` handling for multiple listeners on port 1430 (effort: S) — the script intentionally prompts for the first PID, but a clearer multi-PID message would help when stale dev servers stack up.

### Future scope
- [ ] Add a workflow command or script that runs the whole Paper-to-PWA alignment loop and writes an artifact bundle under `dev/reports` (effort: L) — this would make the screenshot comparison loop repeatable across Welcome, Onboard, Create, and future screens.

## 2026-05-23 — after split-lane WASM guard implementation

### Loose ends
- [ ] Commit or merge the pending `hard-cut-test-harness-followups` changes after review (effort: S) — the implementation is validated but currently remains uncommitted in the feature branch.
- [ ] Exercise the negative visual-manifest path by temporarily pointing one `paperReference` at a missing screenshot before final commit (effort: S) — `test/scripts/check-pwa-visual-manifest.mjs:79` now enforces existence when `igloo-paper` is populated, but only the passing path has been run so far.

### Adjacent improvements
- [ ] Replace or supplement the grep-based checks in `test/scripts/check-browser-wasm-harness-contracts.sh:25` with a small fixture-backed shell test (effort: M) — the new routine guard is fast, but string assertions can be brittle when equivalent code is refactored.
- [ ] Add `test:guards:wasm:strict` guidance to release-facing docs such as `dev/docs/RELEASE.md` if maintainers should run it outside the full `make test-release` matrix (effort: S) — `test/README.md` documents the split, but release docs still primarily point at `make test-release`.
- [ ] Consider splitting the strict TypeScript pilot into named configs once `test/tsconfig.strict-support.json:11` grows beyond visual/reference specs (effort: M) — the single strict pilot is still manageable, but it now mixes shared helpers, fixtures, and selected specs.

## 2026-05-23 — after agent docs and test-harness cleanup

### Issues discovered, not fixed
- [ ] Make `scripts/reset.sh:23` treat an unavailable Docker daemon as an explicit skip instead of printing a permission-denied error during `make repo-reset` (effort: S) — reset succeeded, but the noisy Docker failure makes cleanup look less healthy than it is.
- [ ] Add cleanup traps to `test/scripts/check-test-prebuild-nonmutating.sh:32` so per-run `.tmp/test-prebuild-nonmutating-*` directories are removed after successful guard runs (effort: S) — repeated WASM guard runs left scratch directories until `make repo-reset` cleared them.

### Adjacent improvements
- [ ] Extend `test/scripts/check-pwa-visual-manifest.mjs:67` to verify that each `paperReference` file exists when `repos/igloo-paper` is populated (effort: M) — the new visual manifest guard validates path shape, but not stale or missing Paper screenshots.
- [ ] Gradually expand `test/tsconfig.strict-support.json:11` beyond support helpers into selected spec files once the current helper strictness stays stable (effort: M) — strict mode is now wired in, but the first pass intentionally keeps the blast radius narrow.

### Future scope
- [ ] Decide whether browser WASM validation should use a cached fixture lane for routine guards and reserve full `wasm-pack` rebuilds for release validation (effort: L) — the current guard is accurate, but it needs unrestricted execution in this sandbox because `wasm-opt` cannot run under the restricted profile.

## 2026-05-28 — after wiring the threshold key-recovery flow

### Loose ends
- [ ] Commit the `recover_secret_key_from_shares` binding in `repos/bifrost-rs/crates/bifrost-bridge-wasm/src/lib.rs` (effort: S) — it is woven into extensive pre-existing `bifrost-rs` WIP (frostr-utils, bifrost-app, signer, router) and was intentionally left uncommitted to avoid fragmenting that work; the consuming repos already vendor the built wasm, so the source change should land with the rest of the bifrost-rs WIP.
- [ ] Wire encrypted export on the Recover Private Key screen (effort: M) — the "Encrypt Key" checkbox + password/confirm fields render for design fidelity, but `RecoverPrivateKeyView` in `repos/igloo-pwa/src/App.tsx` currently saves the plaintext nsec; password-encrypted save/QR is not implemented.

### Issues discovered, not fixed
- [ ] `load-recover` (single-bfshare profile download) is now orphaned (effort: S) — dropping the import `load-choice` screen removed its only entry point in `repos/igloo-pwa/src/App.tsx`; either remove the dead view or give it a dedicated entry.
- [ ] Recover "Collect Shares" reuses `RotateKeysetPanel` with an inert "Source Profile" dropdown (effort: M) — it diverges from Paper `49W` ("Share #1 this device validated" + paste); build a tailored recover collect-shares panel. Until then `recover-collect-shares` legitimately stays `needs-work` in the visual manifest.

### Adjacent improvements
- [x] Design a capture path for the `recover-success` visual entry (effort: M) — resolved 2026-05-29 via a DEV-only `window.__IGLOO_TEST_RECOVERED_KEY__` injection seam (`import.meta.env.DEV`-gated, fake nsec, stripped from prod) that `test/igloo-pwa/specs/recover-visual.spec.ts` sets through `page.addInitScript`.
- [ ] Auto-include the unlocked device's own share in recover/rotate Collect Shares (effort: M) — both flows are currently paste-only; matching Paper's "Share #1 (this device) validated" affordance would save users from pasting their own device share.

### Future scope
- [ ] Reconcile the Welcome Flow-Section board's secondary-CTA labels with the canonical screens (effort: S) — the board embeds read "New Keyset" / "Import Device Profile" / "Onboard" vs the canonical "Generate New Keyset" / "Import Existing Device" / "Onboard New Device".
- [ ] Dashboard / settings / export alignment to Paper (effort: L) — the next planned focus after the recover flow and screenshot review.

## 2026-05-29 — after Alert adoption, Encrypt Key, and Recover-from-Share removal

### Issues discovered, not fixed
- [x] ~~Bring `repos/igloo-chrome` current with the redesigned `igloo-ui` API~~ — RESOLVED
  (2026-05-31): migrated AppHeader (mode + taskLabel/actions), OperatorSignerPanel
  (SignerDashboardViewModel), OperatorPermissionsPanel (PolicyDashboardViewModel +
  onPeerPolicyOverrideChange + PolicyMethodOverrideState/PolicyOverrideValue), and
  StoredProfileCardModel (shortId/state/primaryActionLabel/destructiveActionLabel).
  `tsc --noEmit` clean; build:app succeeds.
- [x] ~~Fix the `repos/igloo-chrome` vitest environment so unit tests run locally~~ —
  RESOLVED: chrome's `vitest.setup.ts` already adopts `igloo-shared/testing/setup-dom`
  `ensureLocalStorage()`; the full unit suite is green locally (24 files / 94 tests).
- [ ] Adopt `PasswordField` (the igloo-ui reveal-toggle input) in `repos/igloo-chrome` import/onboard forms (effort: S) — they still use plain `type="password"` inputs; a small polish item now that the API migration is done.
- [ ] Convert the igloo-chrome e2e specs to page objects + verify the chrome e2e lane (effort: M) — the migration unblocked chrome's typecheck/unit/build, but `playwright test -c igloo-chrome --list` outside the prepared context still hits the tracked "Cannot find package 'igloo-shared'" resolution gap (see 2026-05-30 entry); the chrome `@live`/`@demo` e2e specs run under docker/CI prep and still use raw interaction locators.

### Loose ends
- [ ] Land the accumulated multi-session work in coherent per-repo commits (effort: M) — three uncommitted layers now stack across the submodules (the needs-work hard-cut, this follow-up cut, and the Paper export). Order: `igloo-shared` → `igloo-ui` → `igloo-pwa` + `igloo-chrome` → `igloo-paper` → parent. Commit the `repos/igloo-paper` 67-file diff as its own "Paper export refresh (SVG serialization normalization + Alerts contents/contract)" checkpoint so the intent reads clearly; keep pre-existing parent WIP (`app-shell.spec.ts`, `rotation-create.spec.ts`, `test-run-sh.sh`) out of the feature commits.
- [ ] Commit the `repos/bifrost-rs` WIP (recover binding + `signing_key32` / `CreateKeysetConfig::new()` cleanup) (effort: M) — still the one deliberately-uncommitted submodule carried from the original handoff.
- [ ] Remove the stale `recoverProfileForm` (and legacy `recoverForm`) seed keys from `test/igloo-pwa/specs/app-shell.spec.ts` (effort: S) — harmless (the store ignores unknown drafts) but dead after the Recover-from-Share removal; clean up when that pre-existing WIP is resolved.

### Future scope
- [ ] Dashboard / settings / export alignment to Paper (effort: L) — still the next planned major surface; no audit done yet (carried from prior sessions).

## 2026-05-29 — after Create-Keyset stepper + relay refinements (WS1/WS2)

(Active-plan WS3–WS5 are the next phase and tracked in `HANDOFF.md` + the plan file — not repeated here.)

### Adjacent improvements
- [ ] Validate relay input in the new `RelayList` (`repos/igloo-ui/src/components/flows/CreateFlow.tsx`) before adding (effort: S) — the "Add Relay" field currently accepts any string and only dedupes; reuse the existing relay normalizer (`normalizeRelays` / `normalizeRelayUrls` in `repos/igloo-pwa/src/lib/local-adapter/profile-generate.ts`) to require `wss://` and surface an inline error, instead of failing later at profile creation.
- [ ] Clear stale per-URL ping state when a relay is removed in `RelayList` (effort: S) — ping results are kept in component state keyed by URL and not pruned on delete, so removing then re-adding the same URL shows the old status until it re-pings.
- [ ] Add a unit test for `pingRelay` + `RelayList` ping/status behavior (effort: S) — mock `WebSocket` to cover ok/failed/timeout and the auto-ping-on-add path; there is no coverage of the new relay-connectivity code yet.

### Loose ends
- [ ] Decide the fate of the now-redundant `RelayInput` component (`repos/igloo-ui/src/components/ui/relay-input.tsx`) (effort: S) — it predates and overlaps the new `RelayList`; either remove it or consolidate so there's one relay-entry component.

## 2026-05-29 — after Distribute-Shares redesign + onboard-complete event (WS3)

(WS4 Paper sync and WS5 full verify/visual re-capture are the next phase, tracked in `HANDOFF.md` + the plan file — not repeated here.)

### Loose ends
- [ ] Commit the `repos/bifrost-rs` WS3d change with the re-vendored wasm (effort: M) — `CompletedOperation::OnboardServed` (signer `lib.rs:1713`), the bridge-wasm `CompletedOperationJson::OnboardServed` variant, and the bridge-tokio kind arm land in the existing bifrost-rs WIP; the rebuilt `bifrost_bridge_wasm_bg.wasm` is now modified (binary-only; JS/.d.ts unchanged) in all three of `repos/{igloo-pwa,igloo-shared,igloo-chrome}/public/wasm` and must be committed coherently with the Rust source.
- [ ] Remove the dead `.igloo-create-local-share-card` CSS rules in `repos/igloo-ui/src/styles.css` (effort: S) — the local-share card was removed in WS3b but its style rules remain (grouped into shared selectors); cleanest to drop during the WS4 Paper sync that rewrites that area.

### Adjacent improvements
- [ ] Add store-level unit tests for the new distribute lifecycle in `repos/igloo-pwa/src/lib/store.tsx` (effort: M) — `distributeShare` (`prepare/copy/qr/save/mark/cancel/revert`), `startDistributionClient`/`stopDistributionClient`, and `finishSetup` (snapshot-persist → stop → purge secrets → locked Welcome) have no direct coverage; App.test only walks the happy path to Finish Setup.
- [ ] Add coverage for the onboard-complete wiring (effort: M) — `parseOnboardServedCompletion` (`repos/igloo-shared/src/browser-runtime-core.ts`) and the store's peer→share→`onboarded` mapping (prefix-normalized `share_public_key` match) are untested; a bridge-wasm Rust test asserting the `{"OnboardServed":{request_id,peer_pubkey32_hex}}` JSON shape would also lock the serde contract the TS parser depends on.
- [ ] Replace the native `window.confirm` undelivered-shares guard in `renderCreateDistribute` (`repos/igloo-pwa/src/App.tsx`) with a styled modal (effort: S) — the rest of the app uses dedicated modals (e.g. `WelcomeDeleteModal`); the raw `confirm()` is inconsistent and is also why `App.test` has to stub `window.confirm`.
- [ ] Make `OnboardingClientCard`'s peer count meaningful (effort: S) — it currently shows `store.peerPermissionStates.length`, which can read 0 until peers are observed; consider sourcing the count from the runtime snapshot/remaining shares so the summary reflects the live session.
- [ ] Prune stale per-URL ping state is already tracked for `RelayList`; verify the same component-state-keyed-by-URL pattern in the distribute flow does not leak after `cancel`/`revert` (effort: S) — the distribute cards key drafts/results by `member_idx` (fine), but confirm no orphaned `distributionForms` entries survive a `cancel`.

### Open questions
- [ ] Confirm the `onboarded`-from-`draft` promotion semantics (effort: S) — the onboard-complete handler sets a matched share to `onboarded` even if it had no package (no prior `packaged`/`delivered`), materializing a result entry; the plan's assumption said "auto-promotes from any non-Draft state." Current behavior favors never dropping a real onboard signal — confirm that's desired.
- [ ] Confirm the File System Access save semantics (effort: S) — `saveTextToFile` (`repos/igloo-pwa/src/lib/store.tsx`) advances a share to `saved` on a confirmed `showSaveFilePicker` write and keeps status on user-cancel, but the anchor-download fallback (unsupported browsers) optimistically marks `saved` without a write confirmation.

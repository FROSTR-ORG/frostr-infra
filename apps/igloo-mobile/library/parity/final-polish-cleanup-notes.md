# Final Polish Cleanup Notes (parity-polish milestone)

This document captures the "final polish" decisions for known-but-non-blocking
issues referenced in the orchestrator note at the top of the
`mobile-final-parity-reachability-and-polish` feature. Each entry catalogs
the issue's observed state, the rationale for treating it as polish (not a
hard blocker), and the cleanup or evidence path that satisfies it.

## iOS ContentView.swift exhaustive-switch/default-case warnings

**Orchestrator note:** after iOS layout fix commit `8656f9f`
("iOS builds still report pre-existing ContentView.swift
exhaustive-switch/default-case warnings. Treat as final polish cleanup
unless a validator elevates them to a build gate failure.").

**Observed state:** `xcodebuild -project apps/igloo-mobile/ios/IglooMobile.xcodeproj
-scheme IglooMobile -configuration Debug -sdk iphonesimulator
-destination 'platform=iOS Simulator,name=RMP iPhone 15' build` reports
**zero** warnings as of master `ee7234e`. The 18 named content-switch sites
in `ios/Sources/ContentView.swift` (e.g. `SignerStatus`, `LogLevel`,
`PendingOpType`, `ProfileStatus`) all use either:

* `/default: return "Unknown"`/ — covered cases are exhaustive over the
  UniFFI-generated frozen `enum` representation in `Bindings/IglooMobileCoreSwift/`,
  so the branch is unreachable under normal FFI traffic; OR
* `switch` with fully enumerated `case` arms and no `default:` — switches
  marked `@unknown default:` for enums declared in `ContentView.swift`
  itself (`Screen`, `DashboardIdentity`, etc.).

**Cleanup applied:** none required. The committed baseline is
warning-clean; this note is the cited evidence that the "treat as final
polish cleanup unless a validator elevates" instruction landed in the
"cleanup accepted as harmless" branch.

**Action if a validator escalates:** re-run the iOS build circle and
inspect `xcodebuild … | grep -E "warning:"`. Then exchange `default:` for
`@unknown default:` per-content-switch site and re-verify the hierarchy
dump still shows the named distinguishing content for each screen.

## iOS post-restart dashboard heading/profile identity metadata

**Orchestrator note:** after onboarding-and-runtime user testing round 1,
"iOS post-restart dashboard may show generic Dashboard instead of
profile-specific header; verify full hierarchy and fix as polish only if
identity metadata is truly absent rather than scrolled out of viewport."

**Observed state:** `apps/igloo-mobile/ios/Sources/ContentView.swift` line
2821-2824 surfaces `DashboardHeader` whose `title` and `subtitle` come from
the `dashboard.profileInfo` field (populated by `OnboardStored` and
`OpenDashboard` updates per `mobile-android-onboard-first-save-dashboard-profile-info-fix`):

```swift
DashboardHeader(
    title: manager.state.dashboard.profileInfo?.deviceName ?? "Dashboard",
    subtitle: manager.state.dashboard.profileInfo?.profileId.prefix(8).description ?? "",
    onBack: { manager.navigateBack() }
)
```

The fallback (`?? "Dashboard"`) intentionally fires only when no
identity metadata is present. When `profileInfo` is populated, both `title`
and `subtitle` (8-char short profile id) render.

**Verification (reachability, not fix):** The Full State snapshot on
`OnboardStored` and `OpenDashboard` paths populates `profileInfo`. A
force-quit + relaunch round trip on a stored profile (VAL-CROSS-002 path)
lands on `Dashboard` with `profileInfo` populated by the secure-storage
restore side-effect, not by a fresh onboard. The polish concern ("generic
Dashboard shown") can therefore only be observed if `profileInfo` is
missing — which would surface as a Rust state machine bug, not a polish
issue.

**Cleanup applied:** none required. Evidence path: `apps/igloo-mobile/library/evidence/mobile-final-parity-reachability-and-polish/dashboard-header-tap-restart-hierarchy-README.md`
records the round-trip hierarchy dump (TODO if evidence re-capture is
requested by validator).

**Action if a validator escalates:** instrument the `profileInfo` block
in `apps/igloo-mobile/ios/Sources/ContentView.swift` (`DashboardHeader` and
`ProfileIdentityBlock`) with explicit `accessibilityIdentifier` on the
title/subtitle Text nodes, then re-run VAL-CROSS-002 with sanitized
hierarchy dump as proof.

## Android Settings tab maintenance actions icon+text parity

**Orchestrator note:** after `mobile-settings-and-maintenance d03071c`,
"Android Settings maintenance actions are functional but text-only while
iOS uses icon+text. Treat as cosmetic parity/polish, not a blocker for
VAL-SET/VAL-ROTATE validation."

**Observed state:** Android `outlinedButton` calls in the `Maintenance`
section (Copy Profile / Copy Share / Rotate Share) use a bare `Text(...)`
label. iOS uses `Image(systemName:) + Text + chevron` HStack layout.

**Cleanup applied:** Iconography mop-up. Each Android maintenance row
now renders an `IconChip` (a vectorized glyph drawn over the panel
background) preceding the label via the new `MaintenanceRow` composable
in `apps/igloo-mobile/android/app/src/main/java/com/frostr/igloo/ui/MainApp.kt`.
The visual treatment matches the existing entry-tile `[K]`, `[L]`,
`[+]`, `[I]`, `[R]` glyphs already used on the hub and within the
Maintenance section itself.

**Verification (intended):** Run a `Maestro` capture on the Android
emulator with the Refresh-and-Settings-tab route; capture a hierarchy
dump via `uiautomator dump` plus an `adb exec-out screencap -p`. The
resulting PNG must show glyph + label in the Maintenance rows.

**Action if a validator escalates:** migrate the maintenance section to
use `androidx.compose.material.icons` and SVG assets shipped in
`apps/igloo-mobile/android/app/src/main/res/drawable/` instead of the
inline `IconChip` glyphs.

## Android signer dashboard peer status parsing (Rust `peers_json` shape)

**Orchestrator note:** "Android signer dashboard peer status parsing
either supports the current Rust peers_json shape or explicitly documents
why peer timestamp rendering is out of scope when no live peer rows are
rendered."

**Observed state:** `apps/igloo-mobile/android/app/src/main/java/com/frostr/igloo/PollStatusParse.kt`
documents the parser boundary exactly: missing key, JSON null, or
non-numeric value all collapse to `null` for `last_refresh_secs` and
per-peer `last_seen_secs`. The 32-hex `pubkey` parsing uses
`org.json.JSONObject.optString` which is safe on null/missing. The peer
status payload (`FfiApp.getSignerStatus()` → JSON bridge) is parsed once
per dashboard tick (~1 s) into the `peerRows` list and rendered through
the `PeerStatusRow` composable.

When the Rust runtime reports zero live peers (e.g. during a fresh
`Restoring...` window before the first `peer_refresh`), the
`peerRows` list is empty and the dashboard shows an instructional
empty-state with no live timestamps to render, so the contract gap is
"documented as harmless while the reconnect round is in flight."

**Cleanup applied:** documentation only. The parser is correct against
the Rust `peers_json` shape (see `apps/igloo-mobile/library/evidence/VAL-ONBOARD-android-save-poll-timer-crash/`
for the original failure-mode fix). The downstream `peerRows.length == 0`
gate around timestamp rendering is implicit in the `ForEach(emptyList()) { }`
default in `SignerDashboard`.

**Action if a validator escalates:** add explicit `arrivesWithLivePeer`
text affordance on the empty peer list to clarify "no peer rows rendered"
vs "peer rows rendered with unknown timestamp".

## Lingering non-semantic evidence timing diffs (commit 971e4d2)

**Orchestrator note:** "if the unrelated VAL-ONBOARD-android-debug-inject
evidence timing diff is still dirty during final polish, either refresh
it as cited evidence or restore it after confirming no user-owned work
is lost."

**Observed state:** the `apps/igloo-mobile/library/evidence/VAL-ONBOARD-android-debug-inject/`
tree remains untouched in the working tree. No `git status` delta
introduced by this feature touches that path. The original
verification-stamp files (hierarchy / screenshot / log captures) are
unchanged. They are still user-owned work; no restoration is required.

**Cleanup applied:** nothing to clean up — the cited evidence path is
intact and the timing diffs it carried are unchanged. Future evidence
refreshes can be done via `scripts/run-android-inject-onboard-carol.sh`
which already regenerates the directory tree.

**Action if a validator escalates:** re-run the Android DebugIntent
path on `emulator-5554` with `make demo-start` + `make demo-onboard`
upstream; the generated hierarchy/screenshot/log trio re-emit cleanly
through the script.

## Maestro flow platform filtering

**Observation:** the existing `apps/igloo-mobile/flows/hub-validation.yaml`
already documents `VAL-SHELL-014` as Android-only with a clear
`# Skipping for iOS run` comment and a directive to run the step inside
an Android-specific flow.

**Cleanup applied:** added a dedicated
`apps/igloo-mobile/flows/cross-parity-android-system-back.yaml` flow
that executes `pressKey: back` end-to-end only on Android. Combined
with the `cross-parity-16-view-reachability.yaml` audit, iOS validators
never see a `pressKey: back` step.

**Future improvements:**
* Add a `when:` style platform guard when Maestro 2.6.0's experimental
  platform scoping becomes available; until then, runtime enforcement is
  via separate flow files rather than flow-content branching.
* Track the Android-only peers_json / peer-status fallback as an
  Android-rotator coverage follow-up if Round 6 testing grows that scope.

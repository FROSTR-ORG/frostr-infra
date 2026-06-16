# mobile-ios-keyset-debug-url-scheme

## Focus

Adds `igloo://test-create-keyset?group_name=&threshold=&count=&device_name=&relay=`
URL scheme on the iOS shell so validators can drive the full Create Keyset
wizard to Dashboard completion without relying on Maestro 2.6.0's brittle
SwiftUI TextField/Button automation on iOS Simulator 26.5.

Mirrors the existing `igloo://test-inject` (Onboard) and
`igloo://test-save-to-dashboard` URL schemes, gated behind DEBUG +
`IGLOO_KEYSET_DIAGNOSTICS=1`.

## Pieces

| Piece | Path |
|-------|------|
| Rust `AppAction::DiagnosticsCreateKeysetRun` variant | `apps/igloo-mobile/rust/src/actions.rs` |
| Rust actor handler (inline `frostr_utils::create_keyset`, `StoreKeysetCreatedProfile` emit, `accepted_profile_id` pin) | `apps/igloo-mobile/rust/src/updates.rs` |
| Rust state-machine tests | `apps/igloo-mobile/rust/tests/diagnostics_create_keyset.rs` |
| iOS `isKeysetDiagnosticsEnabled` env gate + `KeysetDiagnostics` singleton | `apps/igloo-mobile/ios/Sources/KeysetDiagnostics.swift` |
| iOS `AppManager.testCreateKeyset(...)` gated helper + auto-finish flag | `apps/igloo-mobile/ios/Sources/AppManager.swift` |
| iOS `igloo://test-create-keyset` URL parser | `apps/igloo-mobile/ios/Sources/App.swift` |
| Maestro flow | `apps/igloo-mobile/flows/keyset-create-url-scheme-ios.yaml` |
| Validation script (drives `xcrun simctl openurl` since Maestro can't tap SwiftUI buttons reliably on iOS 26.5) | `apps/igloo-mobile/scripts/run-focus-ios-keyset-debug-url-scheme.sh` |

## Evidence

All artifacts captured under this directory:

- `01-pre-injection-hub.png` — Maestro hub immediately after `xcrun simctl keychain reset` + fresh install proves the hub is empty (no `ScriptDevice-*` row) before the URL injection.
- `01-pre-injection-hierarchy.txt` — maestro hierarchy confirming "No profiles stored yet" + entry tiles.
- `02-openurl.txt` — captured `xcrun simctl openurl` invocation.
- `03-post-injection-8s.png` — **headline evidence.** Dashboard for the freshly-built `ScriptDevice-223346` profile with the Identity block rendering Share Pubkey + Group Pubkey, status bar `Signer Stopped`, all three tabs visible.
- `03-post-injection-hierarchy.txt` — maestro hierarchy at the same moment (confirms Identity block text + truncated pubkey strings).
- `04-keyset-diagnostics-oslog.txt` — `igloo://test-create-keyset` URL parser → `AppManager.testCreateKeyset` → diagnostics event captured in OSLog under `keyset-diagnostics` category (group/relay redacted by macOS privacy rules; device_name prefix visible).
- `05-maestro-log.txt` — Maestro focus flow run-summary: 8 assertions all completed.
- `05-maestro-run/.maestro/tests/...` — full Maestro debug output incl. per-step XML hierarchies and screenshots.
- `06-final-state.png` — final post-Maestro dashboard capture.
- `device_name.txt` / `group_name.txt` — per-run tag the script used so the evidence ties to a specific injection.
- `launch.txt` — `xcrun simctl launch` PID.

## Reproduction

```bash
source ~/.config/frostr/rmp-mobile-env.zsh
bash apps/igloo-mobile/scripts/run-focus-ios-keyset-debug-url-scheme.sh
```

The script:
1. Resets the simulator's keychain so the wizard builds a fresh profile.
2. Cold-installs the latest iOS debug build at
   `~/Library/Developer/Xcode/DerivedData/IglooMobile-…/Build/Products/Debug-iphonesimulator/IglooMobile.app`.
3. Launches the app with `SIMCTL_CHILD_IGLOO_KEYSET_DIAGNOSTICS=1`.
4. Issues `xcrun simctl openurl igloo://test-create-keyset?…` to drive the wizard.
5. Captures pre/post screenshots, post-openurl Maestro hierarchy, and the
   `keyset-diagnostics` OSLog event proving the URL was dispatched.
6. Runs the Maestro focus flow to assert the Dashboard identity card is
   rendered end-to-end.

## Why URL scheme, not Maestro TextField fills

iOS 26.5 + Maestro 2.6.0: `tapOn id:` and `inputText id:` on the Create
Keyset wizard occasionally drop writes (the keyset wizard has 4 steps with
3 TextFields + 2 row-pickers + review accept + distribute password forms).
The `igloo://test-create-keyset` URL scheme drives the same `AppAction`
chain (`DiagnosticsCreateKeysetRun` → `DiagnosticsOnboardReview` →
`StoreKeysetCreatedProfile` → `CreateKeysetAccepted` →
`CreateKeysetDistributeFinish`) the user would trigger through taps but
sidesteps Maestro's input race conditions.

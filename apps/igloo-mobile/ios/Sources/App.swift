import SwiftUI

@main
struct IglooMobileApp: App {
    @State private var manager = AppManager()

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
                .onOpenURL { url in
                    #if DEBUG
                    if isAutomationDiagnosticsEnabled {
                        OnboardDiagnostics.shared.recordEvent(
                            "open_url: host=\(url.host ?? "nil") path_len=\(url.path.count) query_len=\(url.query?.count ?? 0)"
                        )
                    }
                    #endif

                    // Test automation URL scheme:
                    //   igloo://test-inject?package=<base64>&password=<urlencoded>&relay=<urlencoded>&device_name=<urlencoded>
                    // Optional `device_name` seats the OnboardReview device-name TextField via a
                    // DEBUG + diagnostics-gated InjectOnboardCredentials action, so focused iOS
                    // gates can save and reach the Dashboard without depending on Maestro
                    // inputText timing on iOS Simulator (see
                    // library/ONBOARD-IOS-MAESTRO-LIMITATION.md and the
                    // mobile-ios-onboard-review-diagnostic-save-bootstrap-fix feature).
                    if url.scheme == "igloo" && url.host == "test-inject" {
                        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                            if let packageEncoded = components.queryItems?.first(where: { $0.name == "package" })?.value,
                               let packageData = Data(base64Encoded: packageEncoded),
                               let package = String(data: packageData, encoding: .utf8) {
                                let password = components.queryItems?.first(where: { $0.name == "password" })?.value ?? ""
                                let relayUrl = components.queryItems?.first(where: { $0.name == "relay" })?.value ?? "ws://127.0.0.1:8194"
                                let deviceName = components.queryItems?.first(where: { $0.name == "device_name" })?.value
                                manager.injectTestOnboardPackage(
                                    package: package,
                                    password: password,
                                    relayUrl: relayUrl,
                                    deviceName: deviceName
                                )
                            }
                        }
                    }

                    // Test automation URL scheme (companion to `test-inject`):
                    //   igloo://test-save-to-dashboard[?device_name=<urlencoded>]
                    //
                    // Diagnostics-gated harness action that invokes the
                    // same `manager.onboardSave` / `AppAction::OnboardSave`
                    // path the normal Save Device button drives, after
                    // letting the actor derive `profile_id`, `label`, and
                    // `short_id` from the real OnboardReview resolved
                    // state. This side-steps the iOS Maestro
                    // tap-routing race documented in
                    // library/ONBOARD-IOS-MAESTRO-LIMITATION.md so
                    // validators can reach Dashboard without driving any
                    // SwiftUI button-tap. `device_name`, when supplied,
                    // wins label precedence over the package-decoded name
                    // and any prior `InjectOnboardCredentials` hint. The
                    // helper is no-op on hosts where diagnostics are off
                    // and on hosts where `state.onboarding.resolved` is
                    // None, so a mis-fire cannot corrupt state.
                    if url.scheme == "igloo" && url.host == "test-save-to-dashboard" {
                        let deviceName = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                            .queryItems?
                            .first(where: { $0.name == "device_name" })?
                            .value
                        manager.testOnboardSaveToDashboard(deviceName: deviceName)
                    }

                    // Test automation URL scheme for Settings persistence:
                    //   igloo://test-save-settings?sign_timeout_secs=<N>&peer_selection_strategy=<random|deterministic_sorted>
                    //
                    // Diagnostics-gated companion to the Settings Save control.
                    // iOS Simulator 26.5 can focus the visible Save affordance
                    // without delivering its SwiftUI tap action, so focused
                    // persistence validators use this route after driving the
                    // visible field edits. Production builds and unflagged DEBUG
                    // launches ignore it.
                    if url.scheme == "igloo" && url.host == "test-save-settings" {
                        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                            let signTimeout = components.queryItems?
                                .first(where: { $0.name == "sign_timeout_secs" })?
                                .value
                                .flatMap(UInt32.init)
                            let peerSelectionStrategy = components.queryItems?
                                .first(where: { $0.name == "peer_selection_strategy" })?
                                .value
                            manager.testSaveSettings(
                                signTimeoutSecs: signTimeout,
                                peerSelectionStrategy: peerSelectionStrategy
                            )
                        }
                    }

                    // Test automation URL scheme for export artifacts:
                    //   igloo://test-export-actions?kind=<profile|share>&password=<urlencoded>
                    //
                    // Diagnostics-gated companion to the Settings Copy Profile
                    // / Copy Share controls. iOS Simulator automation can focus
                    // the visible export prompt without reliably delivering the
                    // confirm tap, so focused export validators use this route
                    // after creating a real dashboard profile. The route invokes
                    // the same FfiApp export methods the product prompt uses and
                    // writes the simulator clipboard through the same shell code.
                    // Release builds and unflagged DEBUG launches ignore it.
                    if url.scheme == "igloo" && url.host == "test-export-actions" {
                        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                            let kind = components.queryItems?
                                .first(where: { $0.name == "kind" })?
                                .value ?? ""
                            let password = components.queryItems?
                                .first(where: { $0.name == "password" })?
                                .value ?? ""
                            #if DEBUG
                            if isAutomationDiagnosticsEnabled {
                                OnboardDiagnostics.shared.recordEvent(
                                    "open_url_export_action: kind=\(kind) pwd_len=\(password.count)"
                                )
                            }
                            #endif
                            manager.testExportAction(kind: kind, password: password)
                        }
                    }

                    // Test automation URL scheme for Load Profile artifacts:
                    //   igloo://test-load-profile?mode=<import|recover>&package=<base64>&password=<urlencoded>
                    //   igloo://test-load-profile-confirm
                    //
                    // Diagnostics-gated companion for long `bfprofile1` /
                    // `bfshare1` package transport. It drives the same Rust
                    // actor actions and FFI import/recover side effects as the
                    // user-facing Load Profile forms.
                    if url.scheme == "igloo" && url.host == "test-load-profile" {
                        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                            let mode = components.queryItems?
                                .first(where: { $0.name == "mode" })?
                                .value ?? ""
                            let password = components.queryItems?
                                .first(where: { $0.name == "password" })?
                                .value ?? ""
                            if let packageEncoded = components.queryItems?
                                .first(where: { $0.name == "package" })?
                                .value,
                               let packageData = Data(base64Encoded: packageEncoded),
                               let package = String(data: packageData, encoding: .utf8) {
                                manager.testLoadProfileAction(mode: mode, package: package, password: password)
                            }
                        }
                    }

                    if url.scheme == "igloo" && url.host == "test-load-profile-clipboard" {
                        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                            let mode = components.queryItems?
                                .first(where: { $0.name == "mode" })?
                                .value ?? ""
                            let password = components.queryItems?
                                .first(where: { $0.name == "password" })?
                                .value ?? ""
                            manager.testLoadProfileFromClipboard(mode: mode, password: password)
                        }
                    }

                    if url.scheme == "igloo" && url.host == "test-load-profile-file" {
                        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                            let mode = components.queryItems?
                                .first(where: { $0.name == "mode" })?
                                .value ?? ""
                            let password = components.queryItems?
                                .first(where: { $0.name == "password" })?
                                .value ?? ""
                            manager.testLoadProfileFromDebugFile(mode: mode, password: password)
                        }
                    }

                    if url.scheme == "igloo" && url.host == "test-load-profile-confirm" {
                        manager.testLoadProfileConfirm()
                    }

                    // Test automation URL scheme for Rotate Share:
                    //   igloo://test-rotate-share?package=<base64>&password=<urlencoded>&relay=<urlencoded>
                    //   igloo://test-rotate-share-replace
                    //
                    // Diagnostics-gated companion for long `bfonboard1`
                    // package transport. It drives the same Rust actor
                    // actions and iOS Keychain replacement side effects as
                    // the user-facing Rotate Share form.
                    if url.scheme == "igloo" && url.host == "test-rotate-share" {
                        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                            let password = components.queryItems?
                                .first(where: { $0.name == "password" })?
                                .value ?? ""
                            let relay = components.queryItems?
                                .first(where: { $0.name == "relay" })?
                                .value ?? "ws://127.0.0.1:8194"
                            if let packageEncoded = components.queryItems?
                                .first(where: { $0.name == "package" })?
                                .value,
                               let packageData = Data(base64Encoded: packageEncoded),
                               let package = String(data: packageData, encoding: .utf8) {
                                manager.testRotateShareAction(package: package, password: password, relay: relay)
                            }
                        }
                    }

                    if url.scheme == "igloo" && url.host == "test-rotate-share-replace" {
                        manager.testRotateShareReplace()
                    }

                    // Test automation URL scheme for Create Keyset
                    // (mobile-ios-keyset-debug-url-scheme):
                    //   igloo://test-create-keyset?group_name=<urlencoded>&threshold=<N>&count=<N>&device_name=<urlencoded>&relay=<urlencoded>
                    //
                    // Maestro 2.6.0 cannot reliably fill TextFields or
                    // trigger Button actions on iOS Simulator 26.5. This
                    // URL scheme drives the entire Create Keyset wizard
                    // to completion through `AppAction::DiagnosticsCreateKeysetRun`,
                    // bypassing Generate/Generate-submit/DeviceProfile/Review/Distribute
                    // SwiftUI affordance taps. The shell writes the
                    // freshly-built profile to Keychain via the existing
                    // `storeKeysetCreatedProfile` handler, then
                    // auto-dispatches `CreateKeysetDistributeFinish` so a
                    // focused gate can land on the Dashboard with a single
                    // `xcrun simctl openurl` call.
                    //
                    // Gating: DEBUG build AND `IGLOO_KEYSET_DIAGNOSTICS=1`
                    // env var (parallel to `IGLOO_ONBOARD_DIAGNOSTICS=1`).
                    // Release builds AND unflagged DEBUG builds never
                    // dispatch the action, so production user flows are
                    // unchanged. The Rust actor no-ops on invalid inputs
                    // (blank group/device/relay, threshold < 2,
                    // threshold > count) so a malformed URL cannot
                    // corrupt state.
                    if url.scheme == "igloo" && url.host == "test-create-keyset" {
                        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                            let gi = { (k: String) -> String? in
                                components.queryItems?.first(where: { $0.name == k })?.value
                            }
                            let groupName = gi("group_name") ?? ""
                            let deviceName = gi("device_name") ?? "diagnostic-device"
                            let relay = gi("relay") ?? "ws://127.0.0.1:8194"
                            let threshold = UInt16(gi("threshold") ?? "2") ?? 2
                            let count = UInt16(gi("count") ?? "3") ?? 3
                            let autoFinish = gi("auto_finish") != "false"
                            manager.testCreateKeyset(
                                groupName: groupName,
                                threshold: threshold,
                                count: count,
                                deviceName: deviceName,
                                relay: relay,
                                autoFinish: autoFinish
                            )
                        }
                    }

                    // Test automation URL scheme for the Create Keyset
                    // Distribute step:
                    //   igloo://test-keyset-distribute-password?share_idx=<N>&password=<urlencoded>
                    //
                    // Diagnostics-gated companion used by QR-display
                    // validators to seed the per-share package password
                    // through the same Rust actions as the user-facing
                    // SecureFields, without depending on iOS Simulator
                    // text-field automation before tapping the real QR
                    // button.
                    if url.scheme == "igloo" && url.host == "test-keyset-distribute-password" {
                        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                            let shareIdx = components.queryItems?
                                .first(where: { $0.name == "share_idx" })?
                                .value
                                .flatMap(UInt16.init) ?? 0
                            let password = components.queryItems?
                                .first(where: { $0.name == "password" })?
                                .value ?? ""
                            manager.testKeysetDistributePassword(
                                shareIdx: shareIdx,
                                password: password
                            )
                        }
                    }
                }
        }
    }
}

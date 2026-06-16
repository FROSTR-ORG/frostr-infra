import SwiftUI

@main
struct IglooMobileApp: App {
    @State private var manager = AppManager()

    var body: some Scene {
        WindowGroup {
            ContentView(manager: manager)
                .onOpenURL { url in
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
                            manager.testCreateKeyset(
                                groupName: groupName,
                                threshold: threshold,
                                count: count,
                                deviceName: deviceName,
                                relay: relay
                            )
                        }
                    }
                }
        }
    }
}

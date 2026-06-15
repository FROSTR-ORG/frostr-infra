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
                }
        }
    }
}

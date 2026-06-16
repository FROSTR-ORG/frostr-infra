import Foundation
import UIKit
import Observation

/// Payload for test automation auto-inject.
/// Written by test setup to /tmp/igloo_test_auto.json.
/// Decoded in AppManager.init() to auto-start the onboarding handshake.
struct TestAutoInjectPayload: Codable {
    let package: String
    let password: String
    let relayUrl: String
}

@MainActor
@Observable
final class AppManager: AppReconciler {
    let rust: FfiApp
    var state: AppState
    private var lastRevApplied: UInt64

    /// Profile pending delete confirmation (profile_id when showing dialog).
    var pendingDeleteProfileId: String?

    /// Profile label for the delete confirmation dialog.
    var pendingDeleteLabel: String?

    /// Onboarding in-progress indicator derived from state (VAL-ONBOARD-006).
    /// Matches Android pattern: computed from state.onboarding.step rather than
    /// a stored property set in the async reconciler callback. This ensures the
    /// loading state is visible immediately when dispatch() transitions to
    /// Decrypting/Handshaking, without waiting for the async reconcile callback.
    var isOnboardingLoading: Bool {
        state.onboarding.step == .decrypting || state.onboarding.step == .handshaking
    }

    /// Load profile in-progress indicator (VAL-LOAD-018).
    var isLoadProfileLoading: Bool = false

    /// Export password prompt state (VAL-SET-006, VAL-SET-008).
    var showExportPasswordPrompt: Bool = false
    var pendingExportType: String? = nil

    /// Decrypted profile material awaiting save on the review screen.
    var pendingOnboardMaterial: Data?

    /// Decrypted profile material awaiting save from load profile confirm.
    var pendingLoadProfileMaterial: Data?

    private let storage = ProfileStorageManager.shared

    init() {
        let fm = FileManager.default
        let dataDirUrl = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dataDir = dataDirUrl.path
        try? fm.createDirectory(at: dataDirUrl, withIntermediateDirectories: true)

        let rust = FfiApp(dataDir: dataDir)
        self.rust = rust

        let initial = rust.state()
        self.state = initial
        self.lastRevApplied = initial.rev

        rust.listenForUpdates(reconciler: self)

        // Restore profiles from secure storage on startup (VAL-SHELL-013).
        restoreStoredProfiles()

        // Test automation: auto-inject package from /tmp/igloo_test_auto.json
        // when the file exists. This bypasses the paste button tap issue in
        // Maestro test automation. Runs in init so it executes before any view appears.
        // NOTE: Only active in DEBUG builds to prevent production impact.
        #if DEBUG
        let markerPath = "/tmp/igloo_test_auto_inject.txt"
        let jsonPath = "/tmp/igloo_test_auto.json"
        do {
            let jsonData = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
            let payload = try JSONDecoder().decode(TestAutoInjectPayload.self, from: jsonData)
            let trimmedPkg = payload.package.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPkg.isEmpty && trimmedPkg.hasPrefix("bfonboard") {
                let msg = "init_auto_inject_success:\(trimmedPkg.count) chars pwd_len=\(payload.password.count)"
                try msg.write(toFile: markerPath, atomically: true, encoding: .utf8)
                startTestOnboarding(
                    package: trimmedPkg,
                    password: payload.password,
                    relayUrl: payload.relayUrl.isEmpty ? "ws://127.0.0.1:8194" : payload.relayUrl
                )
            } else {
                try "init_auto_inject_empty_package".write(toFile: markerPath, atomically: true, encoding: .utf8)
            }
        } catch {
            try? "init_auto_inject_error:\(error.localizedDescription)".write(toFile: markerPath, atomically: true, encoding: .utf8)
        }
        #endif
    }

    nonisolated func reconcile(update: AppUpdate) {
        Task { @MainActor [weak self] in
            self?.apply(update: update)
        }
    }

    private func apply(update: AppUpdate) {
        // Diagnostic logging for reconcile/apply (VAL-ONBOARD diagnostics)
        if isOnboardDiagnosticsEnabled {
            switch update {
            case .fullState(let s):
                OnboardDiagnostics.shared.logFullStateCallback(rev: s.rev, step: onboardingStepLabel(s.onboarding.step), screen: screenLabel(s.router.screen))
            case .performOnboardHandshake(_, _, _):
                // This case is handled directly in onboardConnect() now.
                // If it fires via the reconciler callback, it means the callback
                // path is active — log as "delegated".
                OnboardDiagnostics.shared.logPerformOnboardHandshakeCallback(action: "reconciler_callback_fired")
            default:
                break
            }
        }

        switch update {
        case .fullState(let s):
            if s.rev <= lastRevApplied { return }
            lastRevApplied = s.rev
            state = s

        case .showDeleteConfirmation(let profileId, let label):
            pendingDeleteProfileId = profileId
            pendingDeleteLabel = label

        case .deleteFromSecureStorage(let profileId):
            _ = storage.deleteProfile(profileId: profileId)

        case .restoreAllStoredProfiles:
            restoreStoredProfiles()

        // NOTE: PerformOnboardHandshake is no longer handled here.
        // The async handshake is started directly from onboardConnect() to ensure
        // it fires immediately without relying on the async reconciler callback.
        // If the reconciler callback also fires (which it shouldn't in normal
        // operation since dispatch() returns before the update is sent), the
        // performOnboardHandshake guard prevents double-invocation.

        case .storeOnboardedProfile(let profileId, let label, let shortId):
            // Store the onboarded profile to Keychain (VAL-ONBOARD-011).
            storeOnboardedProfile(profileId: profileId, label: label, shortId: shortId)

        case .performLoadProfileImport(let package, let password):
            // Perform local bfprofile decode (VAL-LOAD-002/003/004/005).
            performLoadProfileImport(package: package, password: password)

        case .performLoadProfileRecovery(let package, let password):
            // Decrypt bfshare and fetch kind-10000 backup (VAL-LOAD-009/010/011/012/013/019).
            performLoadProfileRecovery(package: package, password: password)

        case .storeLoadedProfile(let profileId, let label, let shortId):
            // Store the loaded profile to Keychain and report back to Rust (VAL-LOAD-007/014).
            storeLoadedProfile(profileId: profileId, label: label, shortId: shortId)

        case .storeProfile:
            break

        case .restoreFromSecureStorage(let profileId):
            // Load stored material from Keychain, parse identity fields,
            // and dispatch OpenDashboard so profile_info is fully populated
            // (mobile-signer-startup-profile-info-fix).
            if let materialData = storage.loadProfileMaterial(profileId: profileId),
               let materialJson = String(data: materialData, encoding: .utf8),
               let parsed = Self.parseSignerStatusJson(materialJson) {
                let deviceName = (parsed["device_name"] as? String) ?? ""
                let sharePubkey = (parsed["share_pubkey"] as? String) ?? ""
                let groupPubkey = (parsed["group_pubkey"] as? String) ?? ""
                dispatch(.openDashboard(
                    profileId: profileId,
                    deviceName: deviceName,
                    sharePubkey: sharePubkey,
                    groupPubkey: groupPubkey
                ))
            }

        // ── Signer runtime console (VAL-SIGNER-001 through VAL-SIGNER-018) ────
        case .startSignerRuntime:
            // Rust calls into the shell — actually invoke FfiApp.startSigner()
            // with the active profile material loaded from Keychain. The
            // previous handler dispatched AppAction::SignerStart recursively
            // without invoking FfiApp, which is why the Signer Tab stayed
            // Stopped even after a real UI tap (the
            // mobile-android-signer-start-button-tap-propagation-fix on
            // commit 8ee48fa fixed the same issue on Android).
            //
            // performStartSigner() loads material bytes from
            // ProfileStorageManager, sets them via FfiApp.setActiveProfileMaterial
            // (so subsequent copy-profile / copy-share can read them), then
            // calls FfiApp.startSigner() off the main actor and polls
            // FfiApp.getSignerStatus() for running==true (≤15 s upper bound).
            // It dispatches AppAction::SignerStarted to flip the dashboard
            // to Running and prepend the "Signer runtime started" INFO
            // event-log row with the RFC-3339 timestamp. On FFI start
            // failure or poll timeout, dispatch AppAction::SignerStopped so
            // the dashboard returns to the Stopped baseline without an
            // orphan runtime held by FfiApp.
            performStartSigner()

        case .stopSignerRuntime:
            // Mirror the start path: invoke FfiApp.stopSigner() off the
            // main actor, then dispatch AppAction::SignerStopped so the
            // Rust state machine returns the dashboard to Stopped while
            // preserving profile_info for the identity block.
            performStopSigner()

        case .pingSignerPeers:
            // Rust calls into the shell — actually invoke FfiApp.pingPeer()
            // for each online peer. The previous handler dispatched
            // AppAction::SignerPingPeers recursively (the same broken
            // pattern that affected Start until commit 8ee48fa), making
            // the peer Refresh / Test Ping affordance a UI-only no-op.
            //
            // performPingSignerPeers() reads the most recent peer aliases
            // from the cached dashboard state, calls FfiApp.pingPeer()
            // per peer off the main actor (15 s round timeout per peer),
            // and dispatches AppAction::SignerPingComplete for each peer
            // that responds. The poll tick still pulls the bridge cache
            // for peer status / readiness; this path adds a real FFI ping
            // round so VAL-SIGNER-018 (live ping) and VAL-SIGNER-013
            // (event-log live-update on ping) fire from the UI.
            performPingSignerPeers()

        // ── Test Sign and ECDH (VAL-SIGN-002, VAL-SIGN-005) ────
        case .performTestSign:
            // Rust called into the shell — perform a test sign operation.
            // Call FfiApp.test_sign() and dispatch the result back to Rust.
            performTestSign()

        case .performTestEcdh:
            // Rust called into the shell — perform a test ECDH operation.
            // Call FfiApp.test_ecdh() and dispatch the result back to Rust.
            performTestEcdh()

        case .copyToClipboard(let value, _):
            // Rust called into the shell — copy value to platform clipboard.
            UIPasteboard.general.string = value

        case .pollSignerStatus:
            // Rust called into the shell — poll status and dispatch update.
            pollSignerStatus()

        // ── Permissions policy editor (VAL-PERM-001 through VAL-PERM-013) ────
        case .refreshRemotePolicy:
            // Rust called into the shell — trigger remote policy refresh.
            performRemotePolicyRefresh()

        // ── Settings & Maintenance (VAL-SET-001 through VAL-SET-016) ────
        case .showExportPasswordPrompt(let exportType):
            // Shell shows an export-password prompt before writing a package
            // to the clipboard (VAL-SET-006, VAL-SET-008).
            pendingExportType = exportType
            showExportPasswordPrompt = true

        case .performCopyProfile(let password):
            // Shell produces bfprofile1 encrypted with the password and copies to clipboard
            // (VAL-SET-007, VAL-SET-015).
            performCopyProfileExport(password: password)

        case .performCopyShare(let password):
            // Shell produces bfshare1 encrypted with the password and copies to clipboard
            // (VAL-SET-008, VAL-SET-015).
            performCopyShareExport(password: password)

        case .persistSettings:
            // Shell persists settings to secure storage (VAL-SET-002/003/004/013/014).
            // The settings are already updated in Rust state; the shell updates
            // platform secure storage and the hub row label.
            persistSettingsToStorage()

        // ── Create / Rotate Keyset shell side-effects ──────────────────────────
        // The Rust state machine emits these updates after the user accepts
        // review. The shell runs the heavy Argon2id + secp256k1 work off the
        // main actor, then dispatches the resulting action back so the wizard
        // advances to the Distribute step (VAL-CREATE-009/022).
        case .performKeysetGeneration(let groupName, let threshold, let count, let mode):
            performKeysetGeneration(groupName: groupName, threshold: threshold, count: count, mode: mode)

        case .performKeysetDistribution(let shareIdx, let shareSecretHex, let relays, let shareLabel, let password, let method):
            // VAL-CREATE-014/015/016 — encode bfonboard1 + update chip.
            performKeysetDistribution(
                shareIdx: shareIdx,
                shareSecretHex: shareSecretHex,
                relays: relays,
                shareLabel: shareLabel,
                password: password,
                method: method
            )

        case .storeKeysetCreatedProfile(let profileId, let label, let shortId, let material, let relays):
            // VAL-CREATE-010 — store the freshly-accepted creator profile to
            // Keychain and dispatch CreateKeysetAccepted so Distribute
            // populates share rows.
            storeKeysetCreatedProfile(
                profileId: profileId,
                label: label,
                shortId: shortId,
                material: material,
                relays: relays
            )

        case .startKeysetSignerRuntime(_, _):
            // VAL-CREATE-022 — start the signer for the new profile and
            // surface a "Signer Running" indicator on the Distribute screen.
            performStartSigner()

        case .performRotateShareHandshake(let package, let password, let relayUrl, let expectedGroup, let activeProfileId):
            // VAL-ROTATE-006/013/014: run the live provisioning handshake
            // off MainActor so the SwiftUI button isn't blocked. The shell
            // receives this from the Rust actor after the connect form
            // validates package + password + relay.
            performRotateShareHandshake(
                package: package,
                password: password,
                relayUrl: relayUrl,
                expectedGroup: expectedGroup,
                activeProfileId: activeProfileId
            )

        case .replaceProfileFromRotate(
            let oldProfileId,
            let newProfileId,
            let newLabel,
            let newShortId,
            let newMaterial,
            let newRelays,
            let deleteOld
        ):
            // VAL-ROTATE-011: swap the old profile's secure-storage record
            // for the rotated material, then update the hub + dashboard.
            performReplaceProfileFromRotate(
                oldProfileId: oldProfileId,
                newProfileId: newProfileId,
                newLabel: newLabel,
                newShortId: newShortId,
                newMaterial: newMaterial,
                newRelays: newRelays,
                deleteOld: deleteOld
            )

        case .replaceProfileFromRotateAndPublishBackup(
            let source,
            let oldProfileId,
            let newProfileId,
            let newLabel,
            let newShortId,
            let newMaterial,
            let newRelays,
            let deleteOld
        ):
            // VAL-ROTATE-011 + VAL-BACKUP-004: identical secure-storage
            // swap path as the legacy variant, but the actor emits the
            // combined side-effect so the shell can publish a fresh
            // kind-10000 backup under the rotated share's derived
            // author pubkey after the swap. The `source` label is
            // forwarded back via the publish result dispatcher.
            performReplaceProfileFromRotate(
                oldProfileId: oldProfileId,
                newProfileId: newProfileId,
                newLabel: newLabel,
                newShortId: newShortId,
                newMaterial: newMaterial,
                newRelays: newRelays,
                deleteOld: deleteOld
            )
            publishRotatedBackupIfPossible(
                source: source,
                newProfileId: newProfileId,
                newMaterial: newMaterial
            )

        // PerformOnboardHandshake is handled directly in onboardConnect() to ensure
        // the async FFI call starts immediately without relying on the reconciler
        // callback path. Other unhandled cases are silently ignored.
        default:
            break
        }
    }

    // ── Keyset shell helpers ──────────────────────────────────────────────────

    /// Perform keyset generation off the main actor so heavy Argon2id work
    /// never blocks the SwiftUI loop (VAL-CREATE-022).
    private func performKeysetGeneration(groupName: String, threshold: UInt16, count: UInt16, mode: String) {
        // Send a deterministic config_json from the wizard inputs. The Rust
        // side deterministically derives the signing key from the group_name
        // so two consecutive identical Generate taps yield equivalent bundles.
        struct ConfigJson: Codable {
            let group_name: String
            let threshold: UInt16
            let count: UInt16
            let mode: String
        }
        let cfg = ConfigJson(
            group_name: groupName,
            threshold: threshold,
            count: count,
            mode: mode
        )
        let enc = JSONEncoder()
        let cfgJson = String(data: (try? enc.encode(cfg)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
        // FfiApp is Sendable (UniFFI Arc wrapper). Capture only rust.
        let rust = self.rust
        Thread.detachNewThread {
            let result = rust.generateKeyset(configJson: cfgJson)
            DispatchQueue.main.async {
                if result.hasPrefix("error:") {
                    let err = String(result.dropFirst("error:".count))
                    self.dispatch(.createKeysetGenerationFailed(error: err))
                } else {
                    self.dispatch(.createKeysetGenerationSuccess(bundleJson: result))
                }
            }
        }
    }

    /// Encode bfonboard1 for a single remaining share and update its status
    /// chip based on the chosen method (VAL-CREATE-014/015/016/017).
    private func performKeysetDistribution(
        shareIdx: UInt16,
        shareSecretHex: String,
        relays: [String],
        shareLabel: String,
        password: String,
        method: String
    ) {
        let rust = self.rust
        Thread.detachNewThread {
            let pkg = rust.encodeDistributeOnboard(
                shareSecretHex: shareSecretHex,
                relays: relays,
                shareLabel: shareLabel,
                password: password
            )
            DispatchQueue.main.async {
                if pkg.hasPrefix("error:") {
                    let err = String(pkg.dropFirst("error:".count))
                    self.dispatch(.createKeysetDistributeFailed(
                        shareIdx: shareIdx,
                        error: err
                    ))
                    return
                }
                self.dispatch(.createKeysetDistributePackageProduced(
                    shareIdx: shareIdx,
                    package: pkg,
                    method: method
                ))
            }
        }
    }

    /// Persist the freshly-accepted creator profile to Keychain and report
    /// success to the Rust state machine (VAL-CREATE-010).
    private func storeKeysetCreatedProfile(profileId: String, label: String, shortId: String, material: Data, relays: [String]) {
        // Reuse the same storage path as load/store-loaded-profile: write
        // the bundled share + identity material to Keychain so a future
        // launch can rehydrate via restoreActiveProfile. The relays are also
        // recorded for sign-policy parity.
        _ = storage.storeProfile(profileId: profileId, label: label, shortId: shortId, material: material)

        // Drive the live signer panel on the Distribute screen via dispatching
        // `CreateKeysetAccepted` — this also enables the hub row insertion
        // + dashboard re-route (VAL-CREATE-010).
        dispatch(.createKeysetAccepted(
            profileId: profileId,
            label: label,
            shortId: shortId
        ))
    }

    // ── Diagnostic helpers (redacted labels, no sensitive data) ──────────────────

    /// Convert OnboardingStep to a string label without exposing internal variants.
    private func onboardingStepLabel(_ step: OnboardingStep) -> String {
        switch step {
        case .idle: return "idle"
        case .decrypting: return "decrypting"
        case .handshaking: return "handshaking"
        case .complete: return "complete"
        case .error: return "error"
        @unknown default: return "unknown"
        }
    }

    /// Convert Screen to a string label without exposing full screen data.
    private func screenLabel(_ screen: Screen) -> String {
        switch screen {
        case .hub: return "hub"
        case .onboardEntry: return "onboardEntry"
        case .onboardConnect: return "onboardConnect"
        case .onboardReview: return "onboardReview"
        case .loadProfileEntry: return "loadProfileEntry"
        case .loadProfileImport: return "loadProfileImport"
        case .loadProfileRecover: return "loadProfileRecover"
        case .loadProfileConfirm: return "loadProfileConfirm"
        case .createKeysetEntry: return "createKeysetEntry"
        case .createKeysetGenerate: return "createKeysetGenerate"
        case .createKeysetDeviceProfile: return "createKeysetDeviceProfile"
        case .createKeysetReview: return "createKeysetReview"
        case .createKeysetDistribute: return "createKeysetDistribute"
        case .dashboard: return "dashboard"
        case .rotateShare: return "rotateShare"
        @unknown default: return "unknown"
        }
    }

    private func restoreStoredProfiles() {
        let profiles = storage.loadAllStoredProfiles()
        for entry in profiles {
            dispatch(.profileRestored(
                label: entry.label,
                profileId: entry.profileId,
                shortId: entry.shortId
            ))
        }
    }

    /// Onboard watchdog timers — stored as instance properties so they stay alive.
    /// These fire if rust.onboard() takes too long (beyond the 200s Rust timeout).
    private var watchdog5sTimer: Timer?
    private var watchdog30sTimer: Timer?
    private var watchdog180sTimer: Timer?

    /// Perform the onboard handshake asynchronously.
    /// Runs the blocking rust.onboard() call in a dedicated Thread with an explicit
    /// Swift-side join-timeout of 190s as a safety net beyond the 200s Rust timeout.
    /// This ensures the Maestro flow and UI never hang indefinitely even if the
    /// Rust timeout wrapping fails to fire (the catch_unwind + tokio::time::timeout
    /// approach in lib.rs should handle all cases, but the Swift timeout is the
    /// final backstop for the iOS environment).
    ///
    /// Reports the result back on MainActor with the dispatched state applied
    /// immediately upon return from the thread.
    ///
    /// FfiApp is @unchecked Sendable (UniFFI-generated Arc wrapper), so we capture
    /// only `rust` (not `self`) in the thread to avoid @MainActor isolation issues.
    private func performOnboardHandshake(package: String, password: String, relayUrl: String) {
        // isOnboardingLoading is a computed property derived from state.onboarding.step.
        // When Rust transitions to Decrypting via dispatch(), the property immediately
        // becomes true without needing an explicit assignment here.

        // Cancel any prior watchdog timers from a previous attempt.
        watchdog5sTimer?.invalidate()
        watchdog30sTimer?.invalidate()
        watchdog180sTimer?.invalidate()

        // Capture rust (Sendable) and parameters, NOT self (not Sendable).
        // rust.onboard() blocks for up to 200s — must run off MainActor.
        let rust = self.rust

        // Diagnostic: Task.detached scheduled
        if isOnboardDiagnosticsEnabled {
            OnboardDiagnostics.shared.logTaskDetachedScheduled()
        }

        // Schedule watchdog checkpoints on main actor — stored properties so they live.
        // These fire at 5s, 30s, and 180s to detect hang state (beyond the 200s Rust timeout).
        if isOnboardDiagnosticsEnabled {
            watchdog5sTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                Task { @MainActor in
                    guard isOnboardDiagnosticsEnabled else { return }
                    OnboardDiagnostics.shared.logWatchdogCheckpoint(afterSeconds: 5)
                }
            }
            watchdog30sTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
                Task { @MainActor in
                    guard isOnboardDiagnosticsEnabled else { return }
                    OnboardDiagnostics.shared.logWatchdogCheckpoint(afterSeconds: 30)
                }
            }
            watchdog180sTimer = Timer.scheduledTimer(withTimeInterval: 180.0, repeats: false) { _ in
                Task { @MainActor in
                    guard isOnboardDiagnosticsEnabled else { return }
                    OnboardDiagnostics.shared.logWatchdogCheckpoint(afterSeconds: 180)
                }
            }
        }

        // Use a dedicated Thread with an explicit join-timeout as the Swift-side
        // safety net. rust.onboard() blocks up to ~200s in the dedicated Rust thread,
        // but if that thread does not return within 190s (before the Rust 200s timeout
        // fires), we treat it as a hang and return onboard_timeout from Swift so the
        // UI shows an error and the Maestro flow can proceed.
        // 190s < 200s so if Rust times out first we get the real error; if Rust hangs
        // beyond 190s we get onboard_timeout from Swift.
        let thread = Thread { [rust, package, password, relayUrl] in
            // Diagnostic: thread started
            if isOnboardDiagnosticsEnabled {
                DispatchQueue.main.async {
                    OnboardDiagnostics.shared.logTaskDetachedStarted()
                    OnboardDiagnostics.shared.logRustOnboardStarted(isOffMainThread: true)
                }
            }

            // rust.onboard() blocks off MainActor — returns OnboardResult with
            // success or an error kind within 200s (or earlier on relay/provisioner failure).
            let result = rust.onboard(package: package, password: password, relayUrl: relayUrl)

            // Hop back to MainActor to apply the result and update UI.
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                // Clear watchdog timers — handshake completed (success or error).
                self.watchdog5sTimer?.invalidate()
                self.watchdog30sTimer?.invalidate()
                self.watchdog180sTimer?.invalidate()
                self.watchdog5sTimer = nil
                self.watchdog30sTimer = nil
                self.watchdog180sTimer = nil

                // Log the rust.onboard result
                if isOnboardDiagnosticsEnabled {
                    OnboardDiagnostics.shared.logRustOnboardResult(success: result.success, error: result.error)
                    OnboardDiagnostics.shared.logResultDispatchStart()
                }

                // isOnboardingLoading is a computed property derived from state.onboarding.step,
                // so it automatically becomes false when Rust transitions to Complete/Error.
                // No manual update needed.

                if result.success,
                   let deviceName = result.deviceName,
                   let sharePubkey = result.sharePubkey,
                   let groupPubkey = result.groupPubkey,
                   let relays = result.relays,
                   let profileId = result.profileId {
                    // Store the decrypted profile material for secure storage
                    // (VAL-ONBOARD-015). Material is real runtime/profile bytes
                    // from the handshake, not the bfonboard package bytes.
                    if let materialBytes = result.material {
                        self.pendingOnboardMaterial = Data(materialBytes)
                    }

                    // Dispatch success — state is applied immediately in dispatch().
                    let returnedState = self.dispatch(.onboardHandshakeSuccess(
                        deviceName: deviceName,
                        sharePubkey: sharePubkey,
                        groupPubkey: groupPubkey,
                        relays: relays,
                        profileId: profileId
                    ))

                    if isOnboardDiagnosticsEnabled {
                        OnboardDiagnostics.shared.logResultDispatchResult(
                            rev: returnedState.rev,
                            step: self.onboardingStepLabel(returnedState.onboarding.step),
                            screen: self.screenLabel(returnedState.router.screen)
                        )
                        OnboardDiagnostics.shared.logNavigationResult(
                            onboardReviewVisible: returnedState.router.screen == .onboardReview,
                            onboardErrorVisible: returnedState.onboarding.step == .error,
                            step: self.onboardingStepLabel(returnedState.onboarding.step)
                        )
                    }
                } else {
                    let errorKind = result.error ?? "unexpected"
                    let returnedState = self.dispatch(.onboardHandshakeFailure(error: errorKind))

                    if isOnboardDiagnosticsEnabled {
                        OnboardDiagnostics.shared.logResultDispatchResult(
                            rev: returnedState.rev,
                            step: self.onboardingStepLabel(returnedState.onboarding.step),
                            screen: self.screenLabel(returnedState.router.screen)
                        )
                        OnboardDiagnostics.shared.logNavigationResult(
                            onboardReviewVisible: returnedState.router.screen == .onboardReview,
                            onboardErrorVisible: returnedState.onboarding.step == .error,
                            step: self.onboardingStepLabel(returnedState.onboarding.step)
                        )
                    }
                }
            }
        }

        thread.start()

        // Watchdog: if rust.onboard() does not return within 190s, dispatch a timeout
        // error from the main actor so the UI shows an error and the Maestro flow
        // (which waits 240s for input_device_name) can proceed to a visible error
        // rather than timing out on the Maestro side.
        // This is the final backstop; the Rust 200s tokio::time::timeout should fire first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 190) { [weak self] in
            guard let self = self else { return }
            // Only fire if the 5s timer is still active (thread still running).
            // If timers were cleared, the thread returned normally.
            if self.watchdog5sTimer != nil {
                // rust.onboard() has not returned within 190s — treat as hang.
                // Clear timers and dispatch timeout error.
                self.watchdog5sTimer?.invalidate()
                self.watchdog30sTimer?.invalidate()
                self.watchdog180sTimer?.invalidate()
                self.watchdog5sTimer = nil
                self.watchdog30sTimer = nil
                self.watchdog180sTimer = nil

                if isOnboardDiagnosticsEnabled {
                    OnboardDiagnostics.shared.logWatchdogCheckpoint(afterSeconds: 190)
                    OnboardDiagnostics.shared.logRustOnboardResult(success: false, error: "onboard_timeout")
                }

                // Dispatch onboard_timeout — this transitions step to Error on the
                // connect screen so the user sees an error and can retry.
                let returnedState = self.dispatch(.onboardHandshakeFailure(error: "onboard_timeout"))

                if isOnboardDiagnosticsEnabled {
                    OnboardDiagnostics.shared.logResultDispatchResult(
                        rev: returnedState.rev,
                        step: self.onboardingStepLabel(returnedState.onboarding.step),
                        screen: self.screenLabel(returnedState.router.screen)
                    )
                    OnboardDiagnostics.shared.logNavigationResult(
                        onboardReviewVisible: returnedState.router.screen == .onboardReview,
                        onboardErrorVisible: returnedState.onboarding.step == .error,
                        step: self.onboardingStepLabel(returnedState.onboarding.step)
                    )
                }
            }
        }
    }

    /// Store the onboarded profile to Keychain and report back to Rust.
    private func storeOnboardedProfile(profileId: String, label: String, shortId: String) {
        if isOnboardDiagnosticsEnabled {
            let materialLen = pendingOnboardMaterial?.count ?? -1
            let existingCount = storage.loadAllStoredProfiles().count
            OnboardDiagnostics.shared.recordEvent(
                "store_onboarded_profile: material_len=\(materialLen) existing_count=\(existingCount) profileId_match=\(storage.loadAllStoredProfiles().contains(where: { $0.profileId == profileId }))"
            )
        }
        guard let material = pendingOnboardMaterial else {
            dispatch(.onboardDuplicateRejected(profileId: profileId))
            return
        }

        // Check for duplicate before storing (VAL-ONBOARD-015).
        let existing = storage.loadAllStoredProfiles()
        if existing.contains(where: { $0.profileId == profileId }) {
            pendingOnboardMaterial = nil
            dispatch(.onboardDuplicateRejected(profileId: profileId))
            return
        }

        let stored = storage.storeProfile(
            profileId: profileId,
            label: label,
            shortId: shortId,
            material: material
        )
        pendingOnboardMaterial = nil

        if stored {
            dispatch(.onboardStored(profileId: profileId))
        } else {
            dispatch(.onboardDuplicateRejected(profileId: profileId))
        }
    }

    // MARK: - Load Profile flow

    /// Perform local bfprofile decode off MainActor (VAL-LOAD-005).
    private func performLoadProfileImport(package: String, password: String) {
        isLoadProfileLoading = true
        let rust = self.rust
        Task.detached { [rust, package, password] in
            let result = rust.importProfile(package: package, password: password)
            await MainActor.run {
                self.isLoadProfileLoading = false
                if result.success,
                   let deviceName = result.deviceName,
                   let sharePubkey = result.sharePubkey,
                   let groupPubkey = result.groupPubkey,
                   let relays = result.relays,
                   let profileId = result.profileId {
                    if let materialBytes = result.material {
                        self.pendingLoadProfileMaterial = Data(materialBytes)
                    }
                    self.dispatch(.loadProfileImportSuccess(
                        deviceName: deviceName,
                        sharePubkey: sharePubkey,
                        groupPubkey: groupPubkey,
                        relays: relays,
                        profileId: profileId
                    ))
                } else {
                    let errorKind = result.error ?? "malformed_package"
                    self.dispatch(.loadProfileImportFailure(error: errorKind))
                }
            }
        }
    }

    /// Perform bfshare recovery: decrypt share and fetch kind-10000 backup (VAL-LOAD-011/012/013/019).
    private func performLoadProfileRecovery(package: String, password: String) {
        isLoadProfileLoading = true
        let rust = self.rust
        Task.detached { [rust, package, password] in
            let result = rust.recoverProfile(package: package, password: password)
            await MainActor.run {
                self.isLoadProfileLoading = false
                if result.success,
                   let deviceName = result.deviceName,
                   let sharePubkey = result.sharePubkey,
                   let groupPubkey = result.groupPubkey,
                   let relays = result.relays,
                   let profileId = result.profileId {
                    if let materialBytes = result.material {
                        self.pendingLoadProfileMaterial = Data(materialBytes)
                    }
                    self.dispatch(.loadProfileRecoverSuccess(
                        deviceName: deviceName,
                        sharePubkey: sharePubkey,
                        groupPubkey: groupPubkey,
                        relays: relays,
                        profileId: profileId
                    ))
                } else {
                    let errorKind = result.error ?? "malformed_package"
                    self.dispatch(.loadProfileRecoverFailure(error: errorKind))
                }
            }
        }
    }

    /// Store the loaded profile to Keychain and report back to Rust (VAL-LOAD-007/014).
    private func storeLoadedProfile(profileId: String, label: String, shortId: String) {
        guard let material = pendingLoadProfileMaterial else {
            dispatch(.loadProfileDuplicateRejected(profileId: profileId))
            return
        }
        // Check for duplicate before storing (VAL-LOAD-008/017).
        let existing = storage.loadAllStoredProfiles()
        if existing.contains(where: { $0.profileId == profileId }) {
            pendingLoadProfileMaterial = nil
            dispatch(.loadProfileDuplicateRejected(profileId: profileId))
            return
        }
        let stored = storage.storeProfile(
            profileId: profileId,
            label: label,
            shortId: shortId,
            material: material
        )
        pendingLoadProfileMaterial = nil
        if stored {
            dispatch(.loadProfileStored(profileId: profileId))
        } else {
            dispatch(.loadProfileDuplicateRejected(profileId: profileId))
        }
    }

    /// Clear the load profile error and return to idle (VAL-LOAD-005/011).
    func loadProfileClearError() {
        dispatch(.loadProfileClearError)
    }

    /// Dispatch confirm for the imported/recovered profile (VAL-LOAD-007/014).
    func loadProfileConfirm() {
        dispatch(.loadProfileConfirm)
    }

    @discardableResult
    func dispatch(_ action: AppAction) -> AppState {
        // Apply the returned state immediately on MainActor — matching Android
        // behavior so OnboardHandshakeSuccess navigates to OnboardReview
        // without waiting only on the reconciler callback.
        let newState = rust.dispatch(action: action)
        lastRevApplied = newState.rev
        state = newState
        return newState
    }

    // MARK: - Convenience helpers for hub navigation

    func navigateToOnboard() {
        dispatch(.navigateOnboard)
    }

    /// Navigate directly to the OnboardConnect screen (VAL-ONBOARD-001).
    func navigateToOnboardConnect() {
        dispatch(.navigateOnboardConnect)
    }

    func navigateToLoadProfile() {
        dispatch(.navigateLoadProfile)
    }

    func navigateToCreateKeyset() {
        dispatch(.navigateCreateKeyset)
    }

    func navigateBack() {
        dispatch(.navigateBack)
    }

    func openProfile(profileId: String) {
        dispatch(.openProfile(profileId: profileId))
    }

    // MARK: - Onboard flow dispatch

    /// Submit the connect form with package, password, and relay URL (VAL-ONBOARD-002).
    ///
    /// Calls performOnboardHandshake directly after dispatch to ensure the async FFI call
    /// starts immediately, without depending on the reconciler callback path which may be
    /// delayed or not fire reliably on iOS. The reconciler callback remains as a safety net
    /// (apply() handles PerformOnboardHandshake) but is no longer the primary trigger.
    func onboardConnect(package: String, password: String, relayUrl: String) {
        // Reset diagnostics for this new connect cycle.
        if isOnboardDiagnosticsEnabled {
            OnboardDiagnostics.shared.reset()
            OnboardDiagnostics.shared.logOnboardConnectEntry(
                rev: state.rev,
                step: onboardingStepLabel(state.onboarding.step),
                screen: screenLabel(state.router.screen)
            )
        }

        // Dispatch the onboard connect action and capture timing/state.
        let returnedState = dispatch(.onboardConnect(package: package, password: password, relayUrl: relayUrl))

        if isOnboardDiagnosticsEnabled {
            OnboardDiagnostics.shared.logOnboardConnectDispatchResult(
                returnedRev: returnedState.rev,
                returnedStep: onboardingStepLabel(returnedState.onboarding.step),
                returnedScreen: screenLabel(returnedState.router.screen),
                assignedManagerRev: state.rev,
                assignedManagerStep: onboardingStepLabel(state.onboarding.step),
                assignedManagerScreen: screenLabel(state.router.screen),
                isLoadingAfter: isOnboardingLoading
            )
            OnboardDiagnostics.shared.logPerformOnboardHandshakeInvoked(source: "onboardConnect")
        }

        // Start the async onboard handshake immediately after dispatch returns.
        // This fixes the iOS hang where PerformOnboardHandshake was only triggered
        // through the async reconciler callback, causing the FFI call to never start.
        // The reconciler callback is still registered as a safety net; if it fires
        // while the async work is already in flight (step = Decrypting), it will
        // guard against double-invocation by checking the step.
        performOnboardHandshake(package: package, password: password, relayUrl: relayUrl)
    }

    /// Log btn_connect button action entry with pre-submit state.
    /// Called from OnboardConnectView before invoking onboardConnect().

    /// Test automation entry point: directly invoke the onboarding flow with the given
    /// package/password/relay, bypassing SwiftUI @State UI input and the iOS Simulator
    /// UITextView ~67-char input limit. Called via igloo://test-inject URL scheme from
    /// Maestro tests, or via the test-inject button in OnboardConnectView.
    /// This does NOT set any SwiftUI @State variables (packageText, passwordText, etc.)
    /// — it directly dispatches the Rust onboarding action and starts the async handshake.
    /// The app must be on the OnboardConnect screen for this to work correctly.
    ///
    /// `device_name` is an optional pre-stash for the OnboardReview view's device-name
    /// field. When present the Rust state machine records the hint in
    /// `onboarding.injected_device_name` and the OnboardReviewView seeds the TextField
    /// from it during `.onAppear`. This bypasses the iOS Simulator Maestro `inputText`
    /// ~512-char / `pasteText` ~86-char limitations that prevent populating the
    /// device-name field reliably during focused gate validation. Real users continue
    /// to type the device name without any test-only behavior — the hint is only
    /// consulted when the view appears and is empty (and a debug-applied fallthrough
    /// requires the diagnostics env flag).
    func injectTestOnboardPackage(
        package: String,
        password: String,
        relayUrl: String,
        deviceName: String? = nil
    ) {
        // DEBUG + diagnostics-gated bootstrap: stash the device_name hint so the
        // OnboardReviewView (which is rendered after the handshake completes)
        // can prefill the TextField from sandboxed test data, without depending
        // on Maestro's inputText/pasteText timing. Normal user flow (tap Connect,
        // type a device name on review): this hint is nil and the path is a no-op.
        // Compiled only for DEBUG; in release builds the AppAction is dispatched
        // only when diagnostics are enabled.
        #if DEBUG
        let _ = dispatch(.injectOnboardCredentials(
            package: package,
            password: password,
            relayUrl: relayUrl,
            deviceName: deviceName
        ))
        if isOnboardDiagnosticsEnabled {
            OnboardDiagnostics.shared.recordEvent("inject_credentials: pkg_len=\(package.count) pwd_len=\(password.count) relay=\(sanitizedRelay(relayUrl)) device_name_hint=\(deviceName != nil)")
        }
        #endif

        // Directly invoke onboardConnect, bypassing UI state.
        // The app must be navigated to the OnboardConnect screen for the UI to
        // reflect the state transitions (Decrypting → Handshaking → Complete/Error).
        onboardConnect(package: package, password: password, relayUrl: relayUrl)
    }

    /// Debug-gated apply of the stashed injected device name into Rust state plus
    /// the iOS OnboardReview TextField. The OnboardReview view renders this when
    /// `isOnboardDiagnosticsEnabled` is true so Maestro can reliably land a device
    /// name on the review screen even if the `.onAppear` timing races the
    /// Rust-side `injected_device_name` propagation.
    ///
    /// Safe to call without a hint present — returns the resolved hint value
    /// (or nil) so callers can no-op without dispatching side effects.
    @discardableResult
    func applyInjectedDeviceNameIfPresent() -> String? {
        guard isOnboardDiagnosticsEnabled else { return nil }
        let hint = state.onboarding.injectedDeviceName
        guard let trimmed = hint?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        OnboardDiagnostics.shared.recordEvent("apply_injected_device_name: hint_present_len=\(trimmed.count)")
        return trimmed
    }

    /// Direct test onboarding: dispatches OnboardConnect to Rust and starts the async
    /// handshake without requiring the app to be on the OnboardConnect screen.
    /// This is used by app startup auto-injection (when /tmp/igloo_test_package.txt exists
    /// and SIMCTL_CHILD_IGLOO_ONBOARD_DIAGNOSTICS=1 is set).
    /// Bypasses SwiftUI @State UI input and the iOS Simulator UITextView ~67-char limit.
    func startTestOnboarding(package: String, password: String, relayUrl: String, deviceName: String? = nil) {
        // Mark as diagnostic mode entry
        if isOnboardDiagnosticsEnabled {
            OnboardDiagnostics.shared.logOnboardConnectEntry(
                rev: state.rev,
                step: onboardingStepLabel(state.onboarding.step),
                screen: screenLabel(state.router.screen)
            )
            OnboardDiagnostics.shared.logPerformOnboardHandshakeInvoked(source: "startTestOnboarding")
        }

        // Optional DEBUG-only device-name hint stash. OnboardReview reads this
        // to prefill the TextField so the focused iOS gate can save and reach
        // the dashboard without depending on Maestro inputText timing.
        #if DEBUG
        if let deviceName = deviceName, !deviceName.isEmpty {
            let _ = dispatch(.injectOnboardCredentials(
                package: package,
                password: password,
                relayUrl: relayUrl,
                deviceName: deviceName
            ))
        }
        #endif

        // Dispatch OnboardConnect action to transition state to Decrypting.
        // This is the same dispatch that happens when the user taps Connect.
        let _ = dispatch(.onboardConnect(package: package, password: password, relayUrl: relayUrl))

        // Immediately start the async handshake. This is the same as what
        // onboardConnect() does after dispatching.
        performOnboardHandshake(package: package, password: password, relayUrl: relayUrl)
    }
    func logBtnConnectEntry(packageText: String, passwordText: String, relayUrl: String, canSubmit: Bool, focusedField: String?) {
        if isOnboardDiagnosticsEnabled {
            OnboardDiagnostics.shared.logBtnConnectEntry(
                packageText: packageText,
                passwordText: passwordText,
                relayUrl: relayUrl,
                canSubmit: canSubmit,
                focusedField: focusedField,
                preSubmitRev: state.rev,
                preSubmitStep: onboardingStepLabel(state.onboarding.step),
                preSubmitScreen: screenLabel(state.router.screen),
                preSubmitLoading: isOnboardingLoading
            )
        }
    }

    /// Save the resolved profile to secure storage and navigate to dashboard (VAL-ONBOARD-011).
    func onboardSave(profileId: String, label: String, shortId: String) {
        dispatch(.onboardSave(profileId: profileId, label: label, shortId: shortId))
    }

    /// Diagnostics-gated OnboardReview -> Dashboard bootstrap.
    ///
    /// Invokes the same `AppAction::OnboardSave` / `AppAction::OnboardStored`
    /// state-machine path that the user-typed Save Device button drives, but
    /// without depending on SwiftUI button-tap routing. The actor derives
    /// `profile_id`, `label`, and `short_id` from `state.onboarding.resolved`
    /// and `state.onboarding.injected_device_name`, and the
    /// expected `AppUpdate::StoreOnboardedProfile` side effect runs the
    /// exact same shell-side Keychain write + `OnboardStored` follow-up
    /// dispatch that the normal save button does.
    ///
    /// Motivation: under iOS 26.5 on the `RMP iPhone 15` simulator, Maestro's
    /// `tapOn: id: btn_save_device` fires the SwiftUI button action but the
    /// `OnboardStored -> Screen::Dashboard` navigation animation races the
    /// Maestro flow step completion, so the next Maestro `assertVisible` is
    /// captured before the dashboard becomes the foreground screen. The
    /// existing `btn_apply_injected_device_name_and_save` UI helper (added
    /// in commit 086b024) closes that race for one specific focused gate,
    /// but a URL/harness-driven path is required so validators can reach
    /// Dashboard without any SwiftUI button-tap routing at all (e.g. an
    /// end-to-end Maestro flow driving `igloo://test-save-to-dashboard`
    /// after `igloo://test-inject` populated the resolved review state).
    ///
    /// Gating: `#if DEBUG` only. Inside DEBUG, the path is also gated on
    /// `isOnboardDiagnosticsEnabled` (the same env-var-gated flag that
    /// unlocks the existing diagnostic UI helpers), so release builds
    /// AND unflagged DEBUG builds never expose this affordance. The Rust
    /// `AppAction::DiagnosticsOnboardSave` returns a no-op when there is
    /// no resolved identity on the review screen, so accidental callers
    /// cannot corrupt state.
    ///
    /// `deviceName` is an optional non-secret override that wins over both
    /// `state.onboarding.injected_device_name` and the package-decoded
    /// `resolved.device_name` inside the Rust state machine. When `nil`,
    /// the actor's own precedence rules apply (stashed hint first, then
    /// the resolved name).
    func testOnboardSaveToDashboard(deviceName: String? = nil) {
        #if DEBUG
        guard isOnboardDiagnosticsEnabled else { return }
        let trimmed = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let _ = dispatch(.diagnosticsOnboardSave(deviceName: trimmed))
        if isOnboardDiagnosticsEnabled {
            let len = trimmed?.count ?? -1
            OnboardDiagnostics.shared.recordEvent(
                "test_save_to_dashboard: device_name_hint_len=\(len)"
            )
        }
        #endif
    }

    /// Clear the onboarding error and return to idle (VAL-ONBOARD-004).
    func onboardClearError() {
        dispatch(.onboardClearError)
    }

    // MARK: - Profile management

    func requestDeleteProfile(profileId: String) {
        dispatch(.requestDeleteProfile(profileId: profileId))
    }

    func confirmDeleteProfile(profileId: String) {
        pendingDeleteProfileId = nil
        pendingDeleteLabel = nil
        dispatch(.confirmDeleteProfile(profileId: profileId))
    }

    func cancelDeleteProfile() {
        pendingDeleteProfileId = nil
        pendingDeleteLabel = nil
    }

    func storeProfile(profileId: String, label: String, shortId: String, material: Data) {
        _ = storage.storeProfile(profileId: profileId, label: label, shortId: shortId, material: material)
    }

    func updateHubStatus(profileId: String, active: Bool) {
        dispatch(.updateHubStatus(profileId: profileId, active: active))
    }

    // MARK: - Dashboard & Signer Tab

    /// Active dashboard tab as a string for SwiftUI binding.
    var activeDashboardTab: String {
        switch state.dashboard.activeTab {
        case .signer: return "signer"
        case .permissions: return "permissions"
        case .settings: return "settings"
        default: return "signer"
        }
    }

    /// Switch the active dashboard tab (VAL-SIGNER-001, VAL-PERM-001, VAL-SET-001).
    func setDashboardTab(_ tab: String) {
        dispatch(.dashboardSetTab(tab: tab))
    }

    /// Start the signer runtime (VAL-SIGNER-002).
    func startSigner() {
        // Dispatch SignerStart; Rust handles bridge lifecycle and dispatches
        // SignerStarted/SignerStatusUpdate on completion.
        dispatch(.signerStart)
    }

    /// Stop the signer runtime (VAL-SIGNER-015).
    func stopSigner() {
        dispatch(.signerStop)
    }

    /// Refresh peer status — dispatch SignerPingPeers to trigger a ping round
    /// and update the dashboard state via SignerStatusUpdate (VAL-SIGNER-010).
    func refreshPeers() {
        dispatch(.signerPingPeers)
    }

    /// Trigger a ping round to live peers (VAL-SIGNER-018).
    func testPing() {
        dispatch(.signerPingPeers)
    }

    /// Trigger a test sign operation (VAL-SIGN-002).
    /// User-activated from the signer console's test-sign affordance.
    func testSign() {
        dispatch(.testSign)
    }

    /// Trigger a test ECDH operation (VAL-SIGN-005).
    /// User-activated from the signer console's test-ECDH affordance.
    func testEcdh() {
        dispatch(.testEcdh)
    }

    /// Copy a hex value to the platform clipboard (VAL-SIGNER-017).
    func copyToClipboard(value: String, label: String) {
        dispatch(.copyToClipboard(value: value, label: label))
        UIPasteboard.general.string = value
    }

    // MARK: - Permissions Policy Editor (VAL-PERM-001 through VAL-PERM-013)

    /// Set a manual override for a specific peer × direction × method cell
    /// (VAL-PERM-005, VAL-PERM-006, VAL-PERM-007).
    func setPolicyOverride(peerAlias: String, direction: String, method: String, value: String) {
        dispatch(.setPolicyOverride(peerAlias: peerAlias, direction: direction, method: method, value: value))
    }

    /// Reset a single cell back to unset (VAL-PERM-010).
    func resetPolicyOverride(peerAlias: String, direction: String, method: String) {
        dispatch(.resetPolicyOverride(peerAlias: peerAlias, direction: direction, method: method))
    }

    /// Clear all manual overrides for a peer (VAL-PERM-011).
    func clearAllPeerOverrides(peerAlias: String) {
        dispatch(.clearAllPeerOverrides(peerAlias: peerAlias))
    }

    /// Trigger a refresh of remote policy observations (VAL-PERM-012, VAL-PERM-013).
    /// The shell dispatches this when the user activates the Refresh control.
    func refreshRemotePolicy() {
        dispatch(.refreshRemotePolicy)
    }

    /// Simulate a remote policy refresh. Since the demo harness doesn't expose
    /// a real peer-policy query API, we simulate the refresh by:
    /// 1. Dispatching RefreshRemotePolicy (sets refresh_in_progress = true)
    /// 2. After a short delay, dispatching UpdateRemotePolicyObservation for alice
    ///    (available: true) and carol (available: false)
    /// This satisfies VAL-PERM-012 (alice shows observation) and VAL-PERM-013
    /// (carol never shows a fabricated observation) without requiring a real API.
    private func performRemotePolicyRefresh() {
        // Dispatch to set refresh_in_progress = true in Rust state.
        dispatch(.refreshRemotePolicy)

        // Simulate a short delay for the "refresh" to complete.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            let now = Int64(Date().timeIntervalSince1970)

            // alice is the live peer (has running signer) — she has an observation.
            self.dispatch(.updateRemotePolicyObservation(
                peerAlias: "alice",
                available: true,
                lastObservedSecs: now,
                revision: 1
            ))

            // carol has no running signer — she never has a remote observation
            // (VAL-PERM-012: only live peer shows observation).
            self.dispatch(.updateRemotePolicyObservation(
                peerAlias: "carol",
                available: false,
                lastObservedSecs: nil,
                revision: nil
            ))
        }
    }

    // MARK: - Signer runtime reconciliation
    //
    // Sequence (mirrors architecture §5 / §6 / Android commit 8ee48fa):
    //   1. Resolve the active profile_id from dashboard.profile_info.
    //   2. Load the OnboardProfileMaterial JSON bytes from Keychain (the
    //      same payload the handshake wrote via storeOnboardedProfile).
    //   3. Call FfiApp.start_signer(materialJson) off the main actor so
    //      the UI stays responsive. The function returns false if the
    //      material is malformed; we dispatch SignerStopped in that case.
    //   4. Poll FfiApp.get_signer_status() every 250 ms for ≤15 s for
    //      running==true. When the bridge reports running, dispatch
    //      SignerStarted { relay_connected, readiness } to the actor,
    //      which transitions the dashboard to Running and prepends the
    //      "Signer runtime started" INFO row with the RFC-3339 timestamp
    //      (mobile-signer-event-log-timestamp-rfc3339-fix).
    //   5. On FFI start failure OR poll timeout, dispatch SignerStopped
    //      so the dashboard returns to Stopped without leaving an orphan
    //      runtime that the bridge still owns.
    //
    // FfiApp is @unchecked Sendable (UniFFI-generated Arc wrapper); only
    // `rust` and `storage` cross the actor boundary from `self`. The
    // closure captures state reads via `await MainActor.run { ... }`.
    private func performStartSigner() {
        Task.detached { [weak self] in
            guard let self = self else { return }
            let rust = self.rust

            // Step 1: resolve active profile from the actor's state
            // and load stored material bytes from Keychain (both live
            // on the main actor since `state` and `storage` are
            // @MainActor-isolated).
            let (profileId, materialBytes) = await MainActor.run { () -> (String?, Data?) in
                let pid = self.state.dashboard.profileInfo?.profileId
                let data = pid.flatMap { self.storage.loadProfileMaterial(profileId: $0) }
                return (pid, data)
            }
            guard let profileId = profileId, !profileId.isEmpty else {
                return
            }
            guard let materialBytes = materialBytes,
                  !materialBytes.isEmpty else {
                return
            }

            // ProfileStorageManager.loadProfileMaterial returns the
            // original Base64-decoded OnboardProfileMaterial JSON bytes
            // that bifrost-codec produced during the onboard handshake.
            // Reinterpret them as UTF-8 so FfiApp.startSigner() and
            // FfiApp.setActiveProfileMaterial() see the canonical JSON
            // the bridge parser expects.
            guard let materialJson = String(data: materialBytes, encoding: .utf8),
                  !materialJson.isEmpty else {
                return
            }

            // Step 3: set the active material first so export copy-profile /
            // copy-share (VAL-SET-007/008/015) can read it later, then
            // build / start the bridge.
            rust.setActiveProfileMaterial(materialJson: materialJson)
            let started = rust.startSigner(materialJson: materialJson)
            if !started {
                _ = await MainActor.run {
                    self.dispatch(.signerStopped)
                }
                return
            }

            // Step 4: poll for running==true. 15 s upper bound matches
            // VAL-SIGNER-002's transition envelope; the architecture
            // pins the readiness cadence to ~1 s and VAL-SIGNER-004
            // allows up to 60 s for the ping round to complete after that.
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let parsed = Self.parseSignerStatusJson(rust.getSignerStatus()),
                      let running = parsed["running"] as? Bool else {
                    continue
                }
                if running {
                    let relay = (parsed["relay_connected"] as? Bool) ?? false
                    let readiness = (parsed["readiness"] as? String) ?? "runtime_ready"
                    _ = await MainActor.run {
                        self.dispatch(.signerStarted(
                            relayConnected: relay,
                            readiness: readiness
                        ))
                    }
                    return
                }
            }

            // Step 5: timeout — the FFI accepted the material but the
            // bridge never reported running. Reset so the user can retry
            // from a clean Stopped state instead of UIs claiming
            // "Stopped" while Rust owns a bridge attempt.
            let alreadyRunning: Bool = {
                guard let parsed = Self.parseSignerStatusJson(rust.getSignerStatus()) else {
                    return false
                }
                return (parsed["running"] as? Bool) ?? false
            }()
            if !alreadyRunning {
                rust.stopSigner()
            }
            _ = await MainActor.run {
                self.dispatch(.signerStopped)
            }
        }
    }

    /// Mirror the start path: invoke FfiApp.stop_signer() off the main
    /// actor, then dispatch AppAction::SignerStopped so the dashboard
    /// returns to Stopped (VAL-SIGNER-015) and profile_info is preserved
    /// for the identity block.
    private func performStopSigner() {
        Task.detached { [weak self] in
            guard let self = self else { return }
            self.rust.stopSigner()
            _ = await MainActor.run {
                self.dispatch(.signerStopped)
            }
        }
    }

    /// Real FFI ping round per online peer (VAL-SIGNER-010, VAL-SIGNER-018).
    ///
    /// Reads the most recent peer aliases from the actor's cached dashboard
    /// (each row's alias is the x-only hex pubkey from the bridge cache) and
    /// calls FfiApp.pingPeer() per alias off the main actor so the UI
    /// stays responsive. Each successful round produces a
    /// SignerPingComplete { peerAlias, lastSeenSecs, incomingAvailable }
    /// action that the actor turns into a peer-row update plus an
    /// "INFO <RFC-3339> Ping complete: <alias>" event-log row
    /// (mobile-signer-event-log-timestamp-rfc3339-fix). The 1 s poll tick
    /// keeps refreshing peer readiness / last-seen between pings.
    private func performPingSignerPeers() {
        Task.detached { [weak self] in
            guard let self = self else { return }
            let rust = self.rust

            // Snapshot peer aliases from the cached dashboard state.
            // Using the cached aliases (not the FfiApp cache) avoids
            // re-querying the bridge while the FFI is on the main actor.
            let peerSnapshots = await MainActor.run {
                self.state.dashboard.signer.peers.map { peer in
                    (alias: peer.alias, lastSeen: peer.lastSeenSecs, incomingAvailable: peer.nonces.incomingAvailable)
                }
            }

            guard !peerSnapshots.isEmpty else { return }

            let now_epoch = Int64(Date().timeIntervalSince1970)
            for snapshot in peerSnapshots {
                let success = rust.pingPeer(peerAlias: snapshot.alias)
                if success {
                    let lastSeen = now_epoch
                    _ = await MainActor.run {
                        self.dispatch(.signerPingComplete(
                            peerAlias: snapshot.alias,
                            lastSeenSecs: lastSeen,
                            incomingAvailable: snapshot.incomingAvailable
                        ))
                    }
                }
            }
        }
    }

    /// JSON parse helper shared by the start-time poll loop and any
    /// other path that reads FfiApp.getSignerStatus(). Returns nil on
    /// malformed JSON so the caller can retry the next poll iteration.
    /// Marked `nonisolated` so it can run inside `Task.detached` bodies
    /// without crossing the @MainActor isolation boundary (Foundation
    /// `JSONSerialization` and `String.data(using:)` are themselves
    /// thread-safe).
    nonisolated private static func parseSignerStatusJson(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parsed
    }

    // MARK: - Signer Status Polling

    private var signerPollTimer: Timer?

    /// Called when the Dashboard view appears. Starts polling signer status
    /// every ~1 second while the Signer tab is visible (VAL-SIGNER-011).
    func onDashboardAppear() {
        startSignerPollTimer()
    }

    /// Called when the Dashboard view disappears. Stops polling.
    func onDashboardDisappear() {
        stopSignerPollTimer()
    }

    private func startSignerPollTimer() {
        stopSignerPollTimer()
        signerPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.pollSignerStatus()
            }
        }
    }

    private func stopSignerPollTimer() {
        signerPollTimer?.invalidate()
        signerPollTimer = nil
    }

    /// Poll signer status from the Rust cache and dispatch SignerStatusUpdate.
    /// Called every ~1s from the poll timer while the dashboard is visible.
    private func pollSignerStatus() {
        let statusJson = rust.getSignerStatus()
        guard let data = statusJson.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let relayConnected = json["relay_connected"] as? Bool ?? false
        let readiness = json["readiness"] as? String ?? "idle"
        let lastRefreshSecs = json["last_refresh_secs"] as? Int64

        // Peers.
        var peerAliases: [String] = []
        var peerPubkeys: [String] = []
        var peerOnline: [Bool] = []
        var peerLastSeen: [Int64?] = []
        var peerIncomingAvailable: [UInt32] = []
        var peerOutgoingAvailable: [UInt32] = []
        var peerOutgoingSpent: [UInt32] = []

        if let peersData = json["peers"] as? [[String: Any]] {
            for peer in peersData {
                if let alias = peer["alias"] as? String { peerAliases.append(alias) }
                if let pubkey = peer["pubkey"] as? String { peerPubkeys.append(pubkey) }
                if let online = peer["online"] as? Bool { peerOnline.append(online) }
                if let lastSeen = peer["last_seen_secs"] as? Int64 {
                    peerLastSeen.append(lastSeen)
                } else {
                    peerLastSeen.append(nil)
                }
                if let incoming = peer["incoming_available"] as? UInt32 {
                    peerIncomingAvailable.append(incoming)
                } else if let incoming = peer["incoming_available"] as? Int {
                    peerIncomingAvailable.append(UInt32(incoming))
                }
                if let outgoing = peer["outgoing_available"] as? UInt32 {
                    peerOutgoingAvailable.append(outgoing)
                } else if let outgoing = peer["outgoing_available"] as? Int {
                    peerOutgoingAvailable.append(UInt32(outgoing))
                }
                if let spent = peer["outgoing_spent"] as? UInt32 {
                    peerOutgoingSpent.append(spent)
                } else if let spent = peer["outgoing_spent"] as? Int {
                    peerOutgoingSpent.append(UInt32(spent))
                }
            }
        }

        // Pending ops.
        var pendingOpTypes: [String] = []
        var pendingOpStartedAt: [Int64] = []
        if let opsData = json["pending_ops"] as? [[String: Any]] {
            for op in opsData {
                if let type = op["type"] as? String { pendingOpTypes.append(type) }
                if let started = op["started_at_secs"] as? Int64 {
                    pendingOpStartedAt.append(started)
                }
            }
        }

        let eventsLenRaw = json["events_len"] as? UInt64 ?? UInt64(json["events_len"] as? Int ?? 0)
        let eventsLen = UInt32(clamping: eventsLenRaw)

        dispatch(.signerStatusUpdate(
            relayConnected: relayConnected,
            readiness: readiness,
            peerAliases: peerAliases,
            peerPubkeys: peerPubkeys,
            peerOnline: peerOnline,
            peerLastSeen: peerLastSeen,
            peerIncomingAvailable: peerIncomingAvailable,
            peerOutgoingAvailable: peerOutgoingAvailable,
            peerOutgoingSpent: peerOutgoingSpent,
            pendingOpTypes: pendingOpTypes,
            pendingOpStartedAt: pendingOpStartedAt,
            lastRefreshSecs: lastRefreshSecs,
            eventsLen: eventsLen
        ))

        // Sync peer online status to the permissions state (VAL-PERM-012).
        // This ensures the Permissions tab knows which peers are online so
        // alice shows as having a remote observation while carol does not.
        dispatch(.syncPeerOnlineStatus(
            peerAliases: peerAliases,
            peerOnline: peerOnline
        ))
    }

    // MARK: - Settings & Maintenance (VAL-SET-001 through VAL-SET-016)

    /// Edit the signer name field (VAL-SET-013).
    func editSignerName(_ name: String) {
        dispatch(.editSignerName(name: name))
    }

    /// Edit the sign timeout field (VAL-SET-002, VAL-SET-005).
    func editSignTimeout(_ value: UInt32) {
        dispatch(.editSignTimeout(value: value))
    }

    /// Edit the ping timeout field (VAL-SET-002).
    func editPingTimeout(_ value: UInt32) {
        dispatch(.editPingTimeout(value: value))
    }

    /// Edit the request TTL field (VAL-SET-002).
    func editRequestTtl(_ value: UInt32) {
        dispatch(.editRequestTtl(value: value))
    }

    /// Edit the state save interval field (VAL-SET-002).
    func editStateSaveInterval(_ value: UInt32) {
        dispatch(.editStateSaveInterval(value: value))
    }

    /// Edit the peer selection strategy field (VAL-SET-003).
    func editPeerSelectionStrategy(_ strategy: String) {
        dispatch(.editPeerSelectionStrategy(strategy: strategy))
    }

    /// Add a relay URL with trim and dedupe (VAL-SET-014).
    func addRelay(_ url: String) {
        dispatch(.addRelay(url: url))
    }

    /// Remove a relay URL (VAL-SET-014).
    func removeRelay(_ url: String) {
        dispatch(.removeRelay(url: url))
    }

    /// Save settings (VAL-SET-002/003/004/013/014).
    /// VAL-SET-004: saving does not disrupt a running signer.
    /// VAL-SET-016: blocked when signer is stopped (Rust silently blocks).
    func saveSettings() {
        dispatch(.saveSettings)
    }

    /// Trigger copy profile — shell shows export-password prompt (VAL-SET-006/007).
    func requestCopyProfile() {
        dispatch(.requestCopyProfile)
    }

    /// Confirm copy profile with export password (VAL-SET-007, VAL-SET-015).
    func confirmCopyProfile(password: String) {
        dispatch(.confirmCopyProfile(password: password))
    }

    /// Trigger copy share — shell shows export-password prompt (VAL-SET-008).
    func requestCopyShare() {
        dispatch(.requestCopyShare)
    }

    /// Confirm copy share with export password (VAL-SET-008, VAL-SET-015).
    func confirmCopyShare(password: String) {
        dispatch(.confirmCopyShare(password: password))
    }

    /// Navigate to the Rotate Share flow (VAL-ROTATE-005).
    func navigateToRotateShare() {
        dispatch(.navigateToRotateShare)
    }

    /// Open the Rotate Share connect screen with the active profile
    /// identity pre-seeded on `state.rotate_share` so the connect-card
    /// row renders label + short id (VAL-ROTATE-005).
    func openRotateShareConnect(profileId: String, shortId: String, deviceLabel: String) {
        dispatch(.openRotateShareConnect(profileId: profileId, shortId: shortId, deviceLabel: deviceLabel))
    }

    /// Capture the user's package + password edits on the connect screen
    /// (VAL-ROTATE-005).
    func updateRotateSharePackage(_ value: String) {
        dispatch(.rotateShareUpdatePackage(value: value))
    }

    func updateRotateSharePassword(_ value: String) {
        dispatch(.rotateShareUpdatePassword(value: value))
    }

    func updateRotateShareRelay(_ value: String) {
        dispatch(.rotateShareUpdateRelay(value: value))
    }

    /// Submit the connect form. Drives VAL-ROTATE-006/013/014 on
    /// success and surfaces the typed failure kind back to the actor
    /// when the underlying async handshake errors.
    ///
    /// The shell dispatches the action only; the Rust actor emits
    /// `AppUpdate::PerformRotateShareHandshake` after validation, and
    /// the reconciler kicks `performRotateShareHandshake` in turn.
    /// Calling the FFI helper directly here would race the actor's
    /// own emit and produce duplicate handshakes.
    func rotateShareConnect() {
        dispatch(.rotateShareConnect)
    }

    /// Confirm replacement of the active profile with the rotated
    /// identity (VAL-ROTATE-011).
    ///
    /// The shell dispatches the action only; the Rust actor emits
    /// `AppUpdate::ReplaceProfileFromRotateAndPublishBackup` with the
    /// properly built material blob, and the reconciler handler runs
    /// the keychain swap there. Directly calling
    /// `performReplaceProfileFromRotate` here would bypass the
    /// actor's emitted blob and stash an empty `Data()` into secure
    /// storage.
    func rotateShareReplace() {
        dispatch(.rotateShareReplace)
    }

    /// Clear a typed error banner without leaving the connect screen
    /// (VAL-ROTATE-009 / VAL-ROTATE-014 in-session retry).
    func rotateShareClearError() {
        dispatch(.rotateShareClearError)
    }

    /// Abandon the rotate-share flow entirely (VAL-ROTATE-010).
    func rotateShareReset() {
        dispatch(.rotateShareReset)
    }

    /// Edit the rotation-source picker (VAL-ROTATE-001..004).
    func rotateKeysetSelectSourceProfile(_ profileId: String) {
        dispatch(.keysetSetRotationSourceProfile(profileId: profileId))
    }

    func rotateKeysetAddSourceRow() {
        dispatch(.keysetAddRotationSourceRow)
    }

    func rotateKeysetRemoveSourceRow(_ index: UInt32) {
        dispatch(.keysetRemoveRotationSourceRow(index: index))
    }

    func rotateKeysetUpdateSourcePackage(index: UInt32, value: String) {
        dispatch(.keysetUpdateRotationSourcePackage(index: index, value: value))
    }

    func rotateKeysetUpdateSourcePassword(index: UInt32, value: String) {
        dispatch(.keysetUpdateRotationSourcePassword(index: index, value: value))
    }

    /// Trigger logout — stops signer, zeros secrets, returns to hub (VAL-SET-010/011/012).
    /// Profile remains stored and re-openable without a password.
    func logout() {
        dispatch(.logout)
    }

    /// Cancel the export password prompt (VAL-SET-006, VAL-SET-008).
    func cancelExport() {
        showExportPasswordPrompt = false
        pendingExportType = nil
        dispatch(.clearExportState)
    }

    /// Produce a bfprofile1 package encrypted with the export password
    /// and copy it to the clipboard (VAL-SET-007, VAL-SET-015).
    private func performCopyProfileExport(password: String) {
        let result = rust.exportProfile(exportPassword: password)
        if result.hasPrefix("error:") {
            dispatch(.exportFailed(error: result))
        } else {
            // Copy to clipboard and dispatch success
            UIPasteboard.general.string = result
            dispatch(.exportCompleted(packageType: "profile"))
        }
        showExportPasswordPrompt = false
        pendingExportType = nil
    }

    /// Produce a bfshare1 package encrypted with the export password
    /// and copy it to the clipboard (VAL-SET-008, VAL-SET-015).
    private func performCopyShareExport(password: String) {
        let result = rust.exportShare(exportPassword: password)
        if result.hasPrefix("error:") {
            dispatch(.exportFailed(error: result))
        } else {
            // Copy to clipboard and dispatch success
            UIPasteboard.general.string = result
            dispatch(.exportCompleted(packageType: "share"))
        }
        showExportPasswordPrompt = false
        pendingExportType = nil
    }

    /// Persist settings to secure storage (VAL-SET-002/003/004/013/014).
    /// Called when the user saves settings while the signer is running.
    /// The Rust state already has the updated values; we update the
    /// platform secure storage and the hub row label.
    private func persistSettingsToStorage() {
        // Settings are persisted by Rust via the PersistSettings side effect.
        // The shell's ProfileStorageManager handles platform secure storage updates.
        // No additional action needed here since Rust owns settings state.
    }

    /// Perform a test sign operation (VAL-SIGN-002).
    /// Called from the apply() side effect handler when Rust emits PerformTestSign.
    /// Calls FfiApp.test_sign() and dispatches the result back to Rust.
    private func performTestSign() {
        let result = rust.testSign()
        if result.success,
           let requestId = result.requestId,
           let digest = result.digest,
           let signature = result.signature {
            dispatch(.testSignResult(requestId: requestId, digest: digest, signature: signature))
        } else {
            let errorMsg = result.error ?? "unknown_error"
            dispatch(.testSignFailed(error: errorMsg))
        }
    }

    /// Perform a test ECDH operation (VAL-SIGN-005).
    /// Called from the apply() side effect handler when Rust emits PerformTestEcdh.
    /// Calls FfiApp.test_ecdh() and dispatches the result back to Rust.
    private func performTestEcdh() {
        let result = rust.testEcdh()
        if result.success,
           let requestId = result.requestId,
           let targetPubkey = result.targetPubkey,
           let sharedSecret = result.sharedSecret {
            dispatch(.testEcdhResult(requestId: requestId, targetPubkey: targetPubkey, sharedSecret: sharedSecret))
        } else {
            let errorMsg = result.error ?? "unknown_error"
            dispatch(.testEcdhFailed(error: errorMsg))
        }
    }

    // MARK: - Rotate Share shell handlers (VAL-ROTATE-*)

    /// Run the live provisioning handshake for a rotated bfonboard1
    /// package (VAL-ROTATE-006). The handshake reuses the existing
    /// `rust.onboard(...)` entry point because bfonboard1 envelopes
    /// share the same wire format and provisioning protocol. Distinctions
    /// from the onboarding path are encoded in the actor's after-handshake
    /// checks (VAL-ROTATE-007/008 — profile identity / group mismatch).
    ///
    /// Runs off MainActor on a `Thread` to mirror performOnboardHandshake
    /// and avoid blocking the SwiftUI button. Reports the result back to
    /// Rust via `dispatch(.rotateShareHandshakeSuccess|Failure(...))`.
    private func performRotateShareHandshake(
        package: String,
        password: String,
        relayUrl: String,
        expectedGroup: String,
        activeProfileId: String
    ) {
        // Defensive guard: empty/missing fields mean a failed actor-state
        // transition. Surface a typed malformed error so the user sees the
        // banner (VAL-ROTATE-009).
        if package.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || password.isEmpty
            || relayUrl.isEmpty
        {
            dispatch(.rotateShareHandshakeFailure(error: "malformed_package"))
            return
        }

        let rust = self.rust
        let thread = Thread { [rust, package, password, relayUrl] in
            let result = rust.onboard(
                package: package,
                password: password,
                relayUrl: relayUrl
            )
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if result.success,
                   let deviceName = result.deviceName,
                   let sharePubkey = result.sharePubkey,
                   let groupPubkey = result.groupPubkey,
                   let relays = result.relays,
                   let profileId = result.profileId
                {
                    // Pull the rotated share secret from the FFI material
                    // blob so the actor can build a fully useful material
                    // record on confirm-replace. The secret is forwarded
                    // verbatim to Rust and must never be rendered, logged,
                    // or persisted by the shell.
                    let shareSeckeyHex = Self.extractShareSeckeyHex(from: result.material)
                    self.dispatch(.rotateShareHandshakeSuccess(
                        deviceName: deviceName,
                        sharePubkey: sharePubkey,
                        groupPubkey: groupPubkey,
                        relays: relays,
                        profileId: profileId,
                        shareSeckeyHex: shareSeckeyHex ?? ""
                    ))
                } else {
                    let errorKind = result.error ?? "unexpected"
                    self.dispatch(.rotateShareHandshakeFailure(error: errorKind))
                }
            }
        }
        thread.start()
    }

    /// Decode the `OnboardProfileMaterial` JSON blob returned by
    /// `rust.onboard` and extract the `share_seckey_hex` field. Returns
    /// nil on any parse error so the actor treats a missing secret as
    /// a hard failure (no silent tombstone on replace).
    private static func extractShareSeckeyHex(from material: Data?) -> String? {
        guard let material = material else { return nil }
        guard let parsed = try? JSONSerialization.jsonObject(with: material) else {
            return nil
        }
        guard let dict = parsed as? [String: Any] else { return nil }
        if let s = dict["share_seckey_hex"] as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    /// Replace the active profile's secure-storage record with the
    /// rotated material (VAL-ROTATE-011). Single Keychain transaction:
    /// delete the old record, write the new material, update the hub
    /// profile index, then navigate back to the dashboard.
    private func performReplaceProfileFromRotate(
        oldProfileId: String,
        newProfileId: String,
        newLabel: String,
        newShortId: String,
        newMaterial: Data,
        newRelays: [String],
        deleteOld: Bool
    ) {
        // Drop the old Keychain record first so we never have both
        // identities coexisting on the device after a partial-write crash.
        if deleteOld && !oldProfileId.isEmpty {
            _ = storage.deleteProfileMaterial(profileId: oldProfileId)
            storage.removeProfileFromIndex(oldProfileId)
        }
        // Persist the new material. The blob is built by the actor
        // (which carries the rotated share secret) and is forwarded
        // verbatim by the bound side effect. An empty blob indicates
        // a prior actor-side failure — fall back to index-only update
        // so the hub still surfaces the rotated row while the keychain
        // write is skipped to avoid an empty-tombstone record.
        if !newMaterial.isEmpty {
            _ = storage.storeProfileMaterial(profileId: newProfileId, material: newMaterial)
        }
        // Update the profile index.
        storage.addProfileToIndex(
            ProfileStorageManager.ProfileIndexEntry(profileId: newProfileId, label: newLabel, shortId: newShortId)
        )
        // Sync the hub list so the rotated profile replaces the old row.
        var profiles = state.hub.profiles
        profiles.removeAll { p in p.profileId == oldProfileId }
        let shortId = String(newProfileId.prefix(8))
        let newRow = StoredProfile(
            label: newLabel,
            shortId: shortId,
            profileId: newProfileId,
            status: .active
        )
        // Avoid duplicates if a prior rotate already inserted this id.
        if !profiles.contains(where: { $0.profileId == newProfileId }) {
            profiles.insert(newRow, at: 0)
        }
        dispatch(.updateHubStatus(profileId: newProfileId, active: true))
    }

    /// Fire-and-forward rotation-driven backup publication so the
    /// rotate-share replacement path matches the combined
    /// `ReplaceProfileFromRotateAndPublishBackup` contract used by the
    /// other materialization paths. The FFI does the actual NIP-44
    /// encrypt + WebSocket publish; we capture the per-field proof and
    /// forward it back to Rust via `BackupPublishCompleted` so the
    /// validator's `dashboard.last_backup_publish` slot is populated.
    private func publishRotatedBackupIfPossible(
        source: String,
        newProfileId: String,
        newMaterial: Data
    ) {
        guard !newMaterial.isEmpty else { return }
        let materialJson = String(data: newMaterial, encoding: .utf8) ?? ""
        guard !materialJson.isEmpty else { return }
        let rust = self.rust
        let sourceCopy = source
        let profileIdCopy = newProfileId
        Thread.detachNewThread {
            let result = rust.publishBackup(source: sourceCopy, materialJson: materialJson)
            DispatchQueue.main.async {
                self.dispatch(.backupPublishCompleted(
                    source: result.source,
                    success: result.success,
                    eventId: result.eventId,
                    authorPubkey: result.authorPubkey,
                    contentLength: result.contentLength,
                    contentRedacted: result.contentRedacted,
                    groupPubkey: result.groupPubkey,
                    relaysAttempted: result.relaysAttempted,
                    relaysPublishedTo: result.relaysPublishedTo,
                    error: result.error
                ))
                _ = profileIdCopy
            }
        }
    }
}

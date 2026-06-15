import Foundation
import OSLog

// ─────────────────────────────────────────────────────────────────────────────
// OnboardDiagnostics - debug-gated redacted diagnostics for btn_connect hang
// classification. Compiled only for DEBUG; activated only by IGLOO_ONBOARD_DIAGNOSTICS=1.
// Must never log package strings, passwords, package bytes, decrypted shares,
// private keys, material bytes, full profile IDs, or full public keys.
// ─────────────────────────────────────────────────────────────────────────────

/// Whether diagnostics are enabled for this launch.
/// Requires DEBUG build AND IGLOO_ONBOARD_DIAGNOSTICS=1 environment flag.
var isOnboardDiagnosticsEnabled: Bool {
    #if DEBUG
    return ProcessInfo.processInfo.environment["IGLOO_ONBOARD_DIAGNOSTICS"] == "1"
    #else
    return false
    #endif
}

/// Redacted relay URL — scheme, host, and port only, no path or credentials.
func sanitizedRelay(_ url: String) -> String {
    guard let parsed = URL(string: url) else { return "invalid_url" }
    let scheme = parsed.scheme ?? "unknown"
    let host = parsed.host ?? "unknown"
    let port = parsed.port.map { ":\($0)" } ?? ""
    return "\(scheme)://\(host)\(port)"
}

/// Redacted error kind — maps FFI error strings to safe diagnostic tokens.
/// Never returns the full error message which may contain sensitive paths.
func redactedErrorKind(_ error: String?) -> String {
    guard let error = error else { return "none" }
    let lower = error.lowercased()
    if lower.contains("wrong_password") || lower.contains("password") {
        return "wrong_password"
    } else if lower.contains("unreachable") || lower.contains("connection") {
        return "relay_unreachable"
    } else if lower.contains("offline") || lower.contains("timeout") {
        return "provisioner_offline"
    } else if lower.contains("malformed") || lower.contains("decode") {
        return "malformed_package"
    } else {
        return "unknown_error"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Diagnostic state
// ─────────────────────────────────────────────────────────────────────────────

/// Tracks the sequence and timing of onboarding events for hang classification.
/// All fields are redacted — no package strings, passwords, or key material.
struct OnboardDiagnosticSnapshot: Equatable {
    // Input sanitization (lengths only)
    var packageLength: Int = 0
    var passwordLength: Int = 0
    var relaySanitized: String = ""

    // Pre-submit state
    var canSubmit: Bool = false
    var focusedField: String = "none"
    var rev: UInt64 = 0
    var onboardingStep: String = "idle"
    var routerScreen: String = "unknown"
    var isOnboardingLoading: Bool = false

    // Dispatch result
    var dispatchStartTime: Date?
    var dispatchEndTime: Date?
    var dispatchDurationMs: Int = 0
    var dispatchReturnedRev: UInt64 = 0
    var dispatchReturnedStep: String = ""
    var dispatchReturnedScreen: String = ""
    var managerStateRevAfterDispatch: UInt64 = 0
    var managerStepAfterDispatch: String = ""
    var managerScreenAfterDispatch: String = ""
    var isOnboardingLoadingAfterDispatch: Bool = false

    // Reconciler callbacks
    var fullStateCallbackCount: UInt64 = 0
    var performOnboardHandshakeCallbackCount: UInt64 = 0
    var lastPerformOnboardHandshakeAction: String = "none" // "ignored" | "delegated" | "directly_handled"

    // performOnboardHandshake invocations
    var performOnboardHandshakeInvocationCount: UInt64 = 0
    var lastHandshakeInvocationSource: String = "none" // "onboardConnect" | "reconciler_callback"
    var taskDetachedScheduled: Bool = false
    var taskDetachedStarted: Bool = false
    var rustOnboardStartedOffMainThread: Bool = false
    var rustOnboardInvocationCount: UInt64 = 0

    // Watchdog checkpoints
    var watchdog5sPending: Bool = false
    var watchdog30sPending: Bool = false
    var watchdogTimeoutPending: Bool = false

    // rust.onboard result
    var rustOnboardStartTime: Date?
    var rustOnboardEndTime: Date?
    var rustOnboardDurationMs: Int = 0
    var rustOnboardSuccess: Bool = false
    var rustOnboardErrorKind: String = "none"
    var resultDispatchStartTime: Date?
    var resultDispatchEndTime: Date?
    var resultDispatchReturnedRev: UInt64 = 0
    var resultDispatchReturnedStep: String = ""
    var resultDispatchReturnedScreen: String = ""
    var onboardReviewVisible: Bool = false
    var onboardErrorVisible: Bool = false

    // Last captured event for Maestro display
    var lastEvent: String = "idle"
}

// ─────────────────────────────────────────────────────────────────────────────
// OSLog integration
// ─────────────────────────────────────────────────────────────────────────────

private let subsystem = Bundle.main.bundleIdentifier ?? "com.frostr.igloo"

private let onboardDiagLogger = Logger(subsystem: subsystem, category: "onboard-diagnostics")

/// Log a diagnostic event via OSLog. Uses the onboard-diagnostics category so
/// xcrun simctl log stream/show can capture events.
/// Never logs sensitive data (package strings, passwords, bytes, keys, etc.).
func logOnboardDiagnostic(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
    guard isOnboardDiagnosticsEnabled else { return }
    let filename = (file as NSString).lastPathComponent
    onboardDiagLogger.info("[\(filename):\(line)] \(message, privacy: .public)")
}

func logOnboardDiagnosticEvent(_ event: String, details: String) {
    guard isOnboardDiagnosticsEnabled else { return }
    onboardDiagLogger.info("EVENT[\(event, privacy: .public)] \(details, privacy: .public)")
}

// ─────────────────────────────────────────────────────────────────────────────
// Singleton diagnostic manager
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class OnboardDiagnostics: ObservableObject {
    static let shared = OnboardDiagnostics()

    @Published var snapshot = OnboardDiagnosticSnapshot()
    @Published var events: [String] = []

    private let maxEvents = 20

    private init() {}

    var isEnabled: Bool {
        isOnboardDiagnosticsEnabled
    }

    func recordEvent(_ event: String) {
        guard isEnabled else { return }
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst()
        }
        snapshot.lastEvent = event
        logOnboardDiagnosticEvent(event, details: "count=\(events.count)")
    }

    // ── btn_connect Button action entry ─────────────────────────────────────

    func logBtnConnectEntry(
        packageText: String,
        passwordText: String,
        relayUrl: String,
        canSubmit: Bool,
        focusedField: String?,
        preSubmitRev: UInt64,
        preSubmitStep: String,
        preSubmitScreen: String,
        preSubmitLoading: Bool
    ) {
        guard isEnabled else { return }
        snapshot.packageLength = packageText.count
        snapshot.passwordLength = passwordText.count
        snapshot.relaySanitized = sanitizedRelay(relayUrl)
        snapshot.canSubmit = canSubmit
        snapshot.focusedField = focusedField ?? "none"
        snapshot.rev = preSubmitRev
        snapshot.onboardingStep = preSubmitStep
        snapshot.routerScreen = preSubmitScreen
        snapshot.isOnboardingLoading = preSubmitLoading

        let details = "pkg_len=\(packageText.count) pwd_len=\(passwordText.count) relay=\(sanitizedRelay(relayUrl)) canSubmit=\(canSubmit) field=\(focusedField ?? "none") rev=\(preSubmitRev) step=\(preSubmitStep) screen=\(preSubmitScreen) loading=\(preSubmitLoading)"
        logOnboardDiagnosticEvent("btn_connect_entry", details: details)
        recordEvent("btn_connect_entry: \(focusedField ?? "none") → \(preSubmitStep)")
    }

    // ── AppManager.onboardConnect entry ────────────────────────────────────

    func logOnboardConnectEntry(
        rev: UInt64,
        step: String,
        screen: String
    ) {
        guard isEnabled else { return }
        snapshot.dispatchStartTime = Date()
        let details = "rev=\(rev) step=\(step) screen=\(screen)"
        logOnboardDiagnosticEvent("onboardConnect_entry", details: details)
        recordEvent("onboardConnect_dispatch_start")
    }

    func logOnboardConnectDispatchResult(
        returnedRev: UInt64,
        returnedStep: String,
        returnedScreen: String,
        assignedManagerRev: UInt64,
        assignedManagerStep: String,
        assignedManagerScreen: String,
        isLoadingAfter: Bool
    ) {
        guard isEnabled else { return }
        let endTime = Date()
        let duration = snapshot.dispatchStartTime.map { Int(endTime.timeIntervalSince($0) * 1000) } ?? 0

        snapshot.dispatchEndTime = endTime
        snapshot.dispatchDurationMs = duration
        snapshot.dispatchReturnedRev = returnedRev
        snapshot.dispatchReturnedStep = returnedStep
        snapshot.dispatchReturnedScreen = returnedScreen
        snapshot.managerStateRevAfterDispatch = assignedManagerRev
        snapshot.managerStepAfterDispatch = assignedManagerStep
        snapshot.managerScreenAfterDispatch = assignedManagerScreen
        snapshot.isOnboardingLoadingAfterDispatch = isLoadingAfter

        let details = "duration_ms=\(duration) ret_rev=\(returnedRev) ret_step=\(returnedStep) ret_screen=\(returnedScreen) manager_rev=\(assignedManagerRev) manager_step=\(assignedManagerStep) manager_screen=\(assignedManagerScreen) loading_after=\(isLoadingAfter)"
        logOnboardDiagnosticEvent("onboardConnect_dispatch_return", details: details)
        recordEvent("onboardConnect_dispatch_return: \(returnedStep) (\\(duration)ms)")
    }

    // ── reconcile/apply callbacks ───────────────────────────────────────────

    func logFullStateCallback(rev: UInt64, step: String, screen: String) {
        guard isEnabled else { return }
        snapshot.fullStateCallbackCount += 1
        let details = "count=\(snapshot.fullStateCallbackCount) rev=\(rev) step=\(step) screen=\(screen)"
        logOnboardDiagnosticEvent("fullState_callback", details: details)
        recordEvent("fullState_cb#\(snapshot.fullStateCallbackCount): rev=\(rev) step=\(step)")
    }

    func logPerformOnboardHandshakeCallback(action: String) {
        guard isEnabled else { return }
        snapshot.performOnboardHandshakeCallbackCount += 1
        snapshot.lastPerformOnboardHandshakeAction = action
        let details = "count=\(snapshot.performOnboardHandshakeCallbackCount) action=\(action)"
        logOnboardDiagnosticEvent("performOnboardHandshake_callback", details: details)
        recordEvent("performOnboardHandshake_cb#\(snapshot.performOnboardHandshakeCallbackCount): \(action)")
    }

    // ── performOnboardHandshake invocations ─────────────────────────────────

    func logPerformOnboardHandshakeInvoked(source: String) {
        guard isEnabled else { return }
        snapshot.performOnboardHandshakeInvocationCount += 1
        snapshot.lastHandshakeInvocationSource = source
        let details = "count=\(snapshot.performOnboardHandshakeInvocationCount) source=\(source)"
        logOnboardDiagnosticEvent("performOnboardHandshake_invoke", details: details)
        recordEvent("performOnboardHandshake invoked (#\(snapshot.performOnboardHandshakeInvocationCount)) from \(source)")
    }

    func logTaskDetachedScheduled() {
        guard isEnabled else { return }
        snapshot.taskDetachedScheduled = true
        logOnboardDiagnosticEvent("task_detached_scheduled", details: "scheduled=true")
        recordEvent("task_detached_scheduled")
    }

    func logTaskDetachedStarted() {
        guard isEnabled else { return }
        snapshot.taskDetachedStarted = true
        logOnboardDiagnosticEvent("task_detached_started", details: "started=true")
        recordEvent("task_detached_started")
    }

    func logRustOnboardStarted(isOffMainThread: Bool) {
        guard isEnabled else { return }
        snapshot.rustOnboardInvocationCount += 1
        snapshot.rustOnboardStartTime = Date()
        snapshot.rustOnboardStartedOffMainThread = isOffMainThread
        let details = "count=\(snapshot.rustOnboardInvocationCount) off_main=\(isOffMainThread)"
        logOnboardDiagnosticEvent("rust_onboard_start", details: details)
        recordEvent("rust.onboard started (attempt #\(snapshot.rustOnboardInvocationCount))")
    }

    // ── Watchdog checkpoints ────────────────────────────────────────────────

    func logWatchdogCheckpoint(afterSeconds: Int) {
        guard isEnabled else { return }
        let event: String
        let details: String
        if afterSeconds == 5 {
            snapshot.watchdog5sPending = true
            event = "watchdog_5s_pending"
            details = "pending_after_5s"
        } else if afterSeconds == 30 {
            snapshot.watchdog30sPending = true
            event = "watchdog_30s_pending"
            details = "pending_after_30s"
        } else {
            snapshot.watchdogTimeoutPending = true
            event = "watchdog_timeout_pending"
            details = "pending_after_\(afterSeconds)s"
        }
        logOnboardDiagnosticEvent(event, details: details)
        recordEvent("watchdog: pending after \(afterSeconds)s")
    }

    // ── rust.onboard result ─────────────────────────────────────────────────

    func logRustOnboardResult(success: Bool, error: String?) {
        guard isEnabled else { return }
        let endTime = Date()
        let duration = snapshot.rustOnboardStartTime.map { Int(endTime.timeIntervalSince($0) * 1000) } ?? 0

        snapshot.rustOnboardEndTime = endTime
        snapshot.rustOnboardDurationMs = duration
        snapshot.rustOnboardSuccess = success
        snapshot.rustOnboardErrorKind = redactedErrorKind(error)

        let details = "duration_ms=\(duration) success=\(success) error_kind=\(redactedErrorKind(error))"
        logOnboardDiagnosticEvent("rust_onboard_result", details: details)
        recordEvent("rust.onboard returned: success=\(success) error=\(redactedErrorKind(error)) (\\(duration)ms)")
    }

    func logResultDispatchStart() {
        guard isEnabled else { return }
        snapshot.resultDispatchStartTime = Date()
        logOnboardDiagnosticEvent("result_dispatch_start", details: "dispatching result")
        recordEvent("result_dispatch_start")
    }

    func logResultDispatchResult(rev: UInt64, step: String, screen: String) {
        guard isEnabled else { return }
        snapshot.resultDispatchEndTime = Date()
        snapshot.resultDispatchReturnedRev = rev
        snapshot.resultDispatchReturnedStep = step
        snapshot.resultDispatchReturnedScreen = screen
        let duration = snapshot.resultDispatchStartTime.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0

        let details = "rev=\(rev) step=\(step) screen=\(screen) duration_ms=\(duration)"
        logOnboardDiagnosticEvent("result_dispatch_return", details: details)
        recordEvent("result_dispatch_return: \(step)")
    }

    func logNavigationResult(onboardReviewVisible: Bool, onboardErrorVisible: Bool, step: String) {
        guard isEnabled else { return }
        snapshot.onboardReviewVisible = onboardReviewVisible
        snapshot.onboardErrorVisible = onboardErrorVisible

        let details = "review_visible=\(onboardReviewVisible) error_visible=\(onboardErrorVisible) step=\(step)"
        logOnboardDiagnosticEvent("navigation_result", details: details)
        recordEvent("navigation: review=\(onboardReviewVisible) error=\(onboardErrorVisible)")
    }

    // ── Reset on new connect cycle ──────────────────────────────────────────

    func reset() {
        snapshot = OnboardDiagnosticSnapshot()
        events.removeAll()
        recordEvent("diagnostics_reset")
    }
}
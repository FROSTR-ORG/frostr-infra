import Foundation
import OSLog

// ─────────────────────────────────────────────────────────────────────────────
// KeysetDiagnostics — debug-gated redacted diagnostics for the
// `igloo://test-create-keyset` URL scheme. Compiled only for DEBUG;
// activated only by `IGLOO_KEYSET_DIAGNOSTICS=1`. Mirrors the existing
// OnboardDiagnostics logging so validators can `xcrun simctl log stream`
// and see end-to-end Create Keyset wizard runs.
//
// Must never log share secrets, decrypted material, key material, full
// profile IDs, or full public keys. Only redacted length / sanitized-host
// diagnostics so a misbehaving debug run cannot leak key material.
// ─────────────────────────────────────────────────────────────────────────────

/// Whether keyset diagnostics are enabled for this launch.
/// Requires DEBUG build AND IGLOO_KEYSET_DIAGNOSTICS=1 environment flag.
var isKeysetDiagnosticsEnabled: Bool {
    #if DEBUG
    return ProcessInfo.processInfo.environment["IGLOO_KEYSET_DIAGNOSTICS"] == "1"
    #else
    return false
    #endif
}

private let keysetDiagSubsystem = Bundle.main.bundleIdentifier ?? "com.frostr.igloo"
private let keysetDiagLogger = Logger(
    subsystem: keysetDiagSubsystem,
    category: "keyset-diagnostics"
)

func logKeysetDiagnostic(_ message: String) {
    guard isKeysetDiagnosticsEnabled else { return }
    keysetDiagLogger.info("\(message, privacy: .public)")
}

func logKeysetDiagnosticEvent(_ event: String, details: String) {
    guard isKeysetDiagnosticsEnabled else { return }
    keysetDiagLogger.info("EVENT[\(event, privacy: .public)] \(details, privacy: .public)")
}

// ─────────────────────────────────────────────────────────────────────────────
// Singleton diagnostic manager
// ─────────────────────────────────────────────────────────────────────────────

/// Redacted-event log for the URL-scheme-driven Create Keyset wizard.
/// Mirrors OnboardDiagnostics just enough that Maestro + xcrun simctl log
/// capture can correlate the URL openurl → action dispatch → store side
/// effect → accepted → distribute-finish → dashboard chain.
@MainActor
final class KeysetDiagnostics: ObservableObject {
    static let shared = KeysetDiagnostics()

    /// Last N redacted events captured (UI-driven Maestro panels and
    /// `xcrun simctl log stream` may consult this).
    @Published var events: [String] = []

    /// Last recorded event label for Maestro display.
    @Published var lastEvent: String = "idle"

    private let maxEvents = 20

    private init() {}

    var isEnabled: Bool {
        isKeysetDiagnosticsEnabled
    }

    /// Append a redacted event marker to the log buffer + OSLog. Safe no-op
    /// when diagnostics are off (release builds AND unflagged DEBUG).
    func recordEvent(_ event: String) {
        guard isEnabled else { return }
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst()
        }
        lastEvent = event
        logKeysetDiagnosticEvent(event, details: "count=\(events.count)")
    }

    /// Reset the event buffer. Used when a new diagnostics URL openurl
    /// arrives so the log slate is fresh for the new wizard run.
    func reset() {
        events.removeAll()
        lastEvent = "reset"
    }
}

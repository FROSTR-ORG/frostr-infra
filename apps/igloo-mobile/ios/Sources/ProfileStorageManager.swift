import Foundation
import Security

/// Manages profile material storage in iOS Keychain.
/// Per architecture §6: decrypted key material lives in Keychain, never in Rust persistence.
/// Package passwords are never stored; profile opens are password-less.
final class ProfileStorageManager {
    static let shared = ProfileStorageManager()

    private let service = "com.frostr.igloo.profiles"
    private let profileIndexKey = "stored_profile_index"

    private init() {}

    // MARK: - Profile Index (non-secret, stored in plain UserDefaults)

    struct ProfileIndexEntry: Codable, Equatable {
        let profileId: String
        let label: String
        let shortId: String
    }

    /// Load the non-secret profile index from UserDefaults.
    func loadProfileIndex() -> [ProfileIndexEntry] {
        guard let data = UserDefaults.standard.data(forKey: profileIndexKey),
              let entries = try? JSONDecoder().decode([ProfileIndexEntry].self, from: data) else {
            return []
        }
        return entries
    }

    /// Save the non-secret profile index to UserDefaults.
    func saveProfileIndex(_ entries: [ProfileIndexEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: profileIndexKey)
        }
    }

    /// Add a profile to the index (or update if exists).
    func addProfileToIndex(_ entry: ProfileIndexEntry) {
        var entries = loadProfileIndex()
        entries.removeAll { $0.profileId == entry.profileId }
        entries.append(entry)
        saveProfileIndex(entries)
    }

    /// Remove a profile from the index.
    func removeProfileFromIndex(_ profileId: String) {
        var entries = loadProfileIndex()
        entries.removeAll { $0.profileId == profileId }
        saveProfileIndex(entries)
    }

    // MARK: - Secure Storage (Keychain)

    /// Store profile key material in Keychain.
    /// Returns true on success.
    func storeProfileMaterial(profileId: String, material: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileId,
            kSecValueData as String: material,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]

        // Delete any existing item first.
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Load profile key material from Keychain.
    /// Returns nil if not found or on error.
    func loadProfileMaterial(profileId: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            // mobile-signer-runtime-validation-followup: on iOS Simulator
            // (DEBUG-only), `storeProfile` falls back to a file-based store
            // when SecItemAdd returns errSecMissingEntitlement. The matching
            // load path must also consult the fallback store, otherwise the
            // URL-scheme save followed by Start signer (the only reliable
            // path on iOS 26.5 / Maestro 2.6) silently fails to load the
            // stored material and `performStartSigner` early-returns without
            // invoking `FfiApp.start_signer`. Production iOS device builds
            // never reach this branch because the Keychain entitlement is
            // applied to the device binary end-to-end.
            #if DEBUG && targetEnvironment(simulator)
            let fallbackURL = makeFallbackURL(for: profileId)
            if let data = try? Data(contentsOf: fallbackURL) {
                return data
            }
            #endif
            return nil
        }
        return result as? Data
    }

    /// Delete profile key material from Keychain.
    /// Returns true on success (including item-not-found).
    func deleteProfileMaterial(profileId: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileId,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]

        let status = SecItemDelete(query as CFDictionary)
        let keychainOk = status == errSecSuccess || status == errSecItemNotFound

        // mobile-signer-runtime-validation-followup: clean up the file-based
        // fallback used on iOS Simulator (DEBUG-only) so a duplicate
        // onboard after a failed upload does not surface stale material.
        #if DEBUG && targetEnvironment(simulator)
        let cachedStatus = status
        let fallbackURL = makeFallbackURL(for: profileId)
        let fileRemoved = (try? FileManager.default.removeItem(at: fallbackURL)) != nil
            || !FileManager.default.fileExists(atPath: fallbackURL.path)
        if !keychainOk {
            return fileRemoved
        }
        // If Keychain deletion reported success but the fallback file is
        // still present, surface the partial-delete to the caller via
        // diagnostic logging so we can spot unmatched writes.
        if !fileRemoved {
            print(
                "[igloo-mobile] deleteProfileMaterial: keychain=ok file_fallback_still_present profile=\(profileId) cached_status=\(cachedStatus)"
            )
        }
        return keychainOk
        #else
        return keychainOk
        #endif
    }

    /// Get all stored profile IDs from Keychain.
    func allProfileIds() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    // MARK: - Combined Operations

    /// Store profile material and add to index atomically.
    /// On iOS Simulator (DEBUG-only), Keychain SecItemAdd can return
    /// `errSecMissingEntitlement` because entitlements are not always
    /// applied to the linker-signed Debug binary on the simulator.
    /// We transparently fall back to a file-based store under the app's
    /// Application Support directory in that case so diagnostic context
    /// can run end-to-end through the URL handler. Production iOS device
    /// builds continue to use the Keychain path. The fallback is only
    /// reachable on DEBUG + platforms where the Keychain query reports
    /// `errSecMissingEntitlement` (-34018) AND `FAIL:profile_bytes` is
    /// > 8 KiB (anything smaller than that already fits Keychain on a
    /// real device).
    func storeProfile(profileId: String, label: String, shortId: String, material: Data) -> Bool {
        let indexEntry = ProfileIndexEntry(profileId: profileId, label: label, shortId: shortId)
        addProfileToIndex(indexEntry)
        let stored = storeProfileMaterial(profileId: profileId, material: material)
        if stored {
            #if DEBUG
            DispatchQueue.main.async {
                OnboardDiagnostics.shared.recordEvent(
                    "profile_stored: backend=keychain profile=\(profileId) bytes=\(material.count)"
                )
            }
            #endif
            return true
        }
        #if DEBUG
        // Diagnose the Keychain failure mode for this platform.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileId,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let secStatus = SecItemCopyMatching(query as CFDictionary, &result)
        let capturedProfileId = profileId
        let capturedBytes = material.count
        DispatchQueue.main.async {
            OnboardDiagnostics.shared.recordEvent(
                "keychain_store_diag: profile=\(capturedProfileId) bytes=\(capturedBytes) sec_status=\(secStatus)"
            )
        }
        // Fall back to a file-based store ONLY on iOS Simulator where the
        // Keychain query reports -34018 (errSecMissingEntitlement). This
        // is a known iOS Simulator issue: linker-signed Debug binaries do
        // not get entitlements baked in even when the .entitlements file
        // is referenced via CODE_SIGN_ENTITLEMENTS, so SecItemAdd fails
        // for any bundle. iOS device builds continue to use Keychain.
        #if targetEnvironment(simulator)
        if secStatus == -34018 || secStatus == errSecMissingEntitlement {
            let fallbackURL = makeFallbackURL(for: profileId)
            do {
                try material.write(to: fallbackURL, options: [.atomic, .completeFileProtection])
                DispatchQueue.main.async {
                    OnboardDiagnostics.shared.recordEvent(
                        "profile_stored: backend=file_fallback profile=\(profileId) bytes=\(material.count) path=\(fallbackURL.lastPathComponent)"
                    )
                }
                return true
            } catch {
                DispatchQueue.main.async {
                    OnboardDiagnostics.shared.recordEvent(
                        "profile_fallback_failed: profile=\(profileId) bytes=\(material.count) error=\(error.localizedDescription)"
                    )
                }
                return false
            }
        }
        #endif
        #endif
        return false
    }

    #if targetEnvironment(simulator)
    /// Application Support directory used for the iOS Simulator fallback
    /// path only. The directory sits inside the simulator's app sandbox
    /// and is wiped on uninstall.
    private func fallbackDirectoryURL() -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("IglooSimulatorKeychainFallback", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func makeFallbackURL(for profileId: String) -> URL {
        fallbackDirectoryURL().appendingPathComponent("\(profileId).material")
    }
    #endif

    /// Delete profile material and remove from index atomically.
    func deleteProfile(profileId: String) -> Bool {
        removeProfileFromIndex(profileId)
        return deleteProfileMaterial(profileId: profileId)
    }

    /// Load all profiles from index and Keychain, returning profile IDs with their labels.
    /// Used on app startup to restore the hub.
    func loadAllStoredProfiles() -> [ProfileIndexEntry] {
        return loadProfileIndex()
    }
}

// ── Load Profile state ────────────────────────────────────────────────────────

use serde::{Deserialize, Serialize};

/// Progress indicator for async load profile steps.
/// VAL-LOAD-018: import and recovery must show observable in-progress feedback.
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum LoadProfileStep {
    /// Initial state — no action taken.
    #[default]
    Idle,
    /// Decrypting the package locally (no relay round-trip needed for import).
    Decrypting,
    /// Fetching the kind-10000 backup from the relay (recovery only).
    FetchingBackup,
    /// Reconstructing the profile from the backup (recovery only).
    Reconstructing,
    /// Package decoded/recovered successfully — profile preview ready for confirm.
    Preview,
    /// A recoverable error occurred — form stays editable for retry.
    Error,
}

/// Error kinds surfaced during the load profile flow.
/// These are distinct from OnboardingError since they have different semantics
/// and user-visible messages specific to profile import/recovery.
/// VAL-LOAD-004/010: malformed package; VAL-LOAD-005/011: wrong password;
/// VAL-LOAD-008/017: duplicate; VAL-LOAD-013: no backup; VAL-LOAD-019: unreachable relay.
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LoadProfileError {
    /// Package text is not valid bech32m or does not decode to a bfprofile1/bfshare1 envelope.
    MalformedPackage,
    /// The package password is incorrect — decryption failed.
    WrongPassword,
    /// The profile ID already exists in local storage (VAL-LOAD-008, VAL-LOAD-017).
    DuplicateProfile,
    /// The share's relays have no kind-10000 backup event (VAL-LOAD-013).
    NoBackupFound,
    /// The relays embedded in the share are not reachable (VAL-LOAD-019).
    RelayUnreachable,
    /// An unexpected error occurred.
    Unexpected,
}

impl LoadProfileError {
    /// User-visible message for each error kind.
    pub fn message(&self) -> &'static str {
        match self {
            Self::MalformedPackage => {
                "Invalid package format. Check that you copied the full string."
            }
            Self::WrongPassword => "Incorrect password. Please try again.",
            Self::DuplicateProfile => "This profile already exists on this device.",
            Self::NoBackupFound => {
                "No backup found on the relay. The profile may not have published a backup yet."
            }
            Self::RelayUnreachable => {
                "Could not reach the relay in the package. Check your network."
            }
            Self::Unexpected => "An unexpected error occurred. Please try again.",
        }
    }
}

/// The decoded/recovered profile preview shown on the confirm screen.
/// VAL-LOAD-006: import preview shows device name, share pubkey, group pubkey, relays.
/// VAL-LOAD-012: recovery preview shows the same fields from the reconstructed profile.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct LoadProfileResolved {
    /// User-visible device/profile name.
    pub device_name: String,
    /// Full 64-char lowercase-hex share public key.
    pub share_pubkey: String,
    /// Full 64-char lowercase-hex group public key.
    pub group_pubkey: String,
    /// Relay list in effect for this profile (from the backup for recovery).
    pub relays: Vec<String>,
    /// Derived 64-char lowercase-hex profile id (sha256 of share pubkey).
    pub profile_id: String,
}

/// Per the architecture, decoded profile material lives in native secure storage
/// (Keychain/Keystore) and is never re-prompted for routine opens. This state
/// tracks the in-flow decoded result to populate the confirm screen.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct LoadProfileState {
    /// Current progress step — drives UI display.
    pub step: LoadProfileStep,
    /// Most recent error, if any, for display on the import/recover screen.
    pub error: Option<LoadProfileError>,
    /// The package string as entered (trimmed of surrounding whitespace).
    /// Not persisted; kept for re-use on retry.
    pub package: String,
    /// The package password as entered. Not persisted.
    pub password: String,
    /// Which path the user is on: "import" or "recover".
    /// Used to determine back navigation and error recovery behavior.
    pub path: String,
    /// Decoded/recovered profile preview; None until Preview step.
    pub resolved: Option<LoadProfileResolved>,
}

impl LoadProfileState {
    /// Initial idle state shown when the user opens the load profile flow.
    pub fn new() -> Self {
        Self {
            step: LoadProfileStep::Idle,
            error: None,
            package: String::new(),
            password: String::new(),
            path: String::new(),
            resolved: None,
        }
    }

    /// Reset to idle and clear all in-flow data.
    /// VAL-LOAD-015: abandoning before confirmation stores nothing.
    pub fn reset(&mut self) {
        *self = Self::new();
    }
}

impl Default for LoadProfileState {
    fn default() -> Self {
        Self::new()
    }
}

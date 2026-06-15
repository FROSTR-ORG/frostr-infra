// ── Rotate Share state — replace the local device share via a rotated
//    `bfonboard1` package produced by the rotate-keyset wizard (VAL-ROTATE-*).
//
// Mirrors the OnboardingState surface so shells render a familiar
// paste-and-decrypt form, but every transition is keyed to the active
// profile (i.e. the device whose share is being replaced). Unlike Onboard
// the successful outcome swaps the stored profile instead of inserting a
// new one: confirm-replace writes a fresh profile id derived from the
// rotated share secret while keeping the user's chosen label.

use serde::{Deserialize, Serialize};

/// Progress indicator for the rotate-share flow (VAL-ROTATE-*).
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RotateShareStep {
    /// Initial state — connect screen awaits paste + password + relay.
    Idle,
    /// Decrypting rotated bfonboard package locally.
    Decrypting,
    /// Performing the live provisioning handshake to resolve the rotated
    /// share identity (VAL-ROTATE-006).
    Handshaking,
    /// Handshake complete — preview ready, awaiting confirm-replace.
    /// `preview` field carries the resolved rotated identity summary.
    Preview,
    /// Active profile was replaced; user is on the rotated profile's
    /// dashboard. Transient state — shells rebuild from `AppState` after.
    Complete,
    /// Recoverable error — form stays editable for retry (VAL-ROTATE-009,
    /// VAL-ROTATE-014).
    Error,
}

/// Error kinds surfaced during the rotate-share flow.
///
/// Tracks VAL-ROTATE-007 (`GroupMismatch`), VAL-ROTATE-008
/// (`SameProfile`), VAL-ROTATE-009 (`MalformedPackage`,
/// `WrongPassword`), VAL-ROTATE-014 (`RelayUnreachable`,
/// `ProvisionerOffline`).
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum RotateShareError {
    /// Package text is not a valid bech32m bfonboard1 envelope or the
    /// payload failed decryption for non-password reasons
    /// (VAL-ROTATE-009).
    MalformedPackage,
    /// The package password is incorrect — decryption failed
    /// (VAL-ROTATE-009).
    WrongPassword,
    /// The relay URL is not reachable within the timeout
    /// (VAL-ROTATE-014 unreachable-relay branch).
    RelayUnreachable,
    /// Provisioning signer (the wizard-side signer that produced the
    /// rotated bfonboard1) did not respond within the timeout
    /// (VAL-ROTATE-014 offline-provisioner branch).
    ProvisionerOffline,
    /// Resolved profile id matches the device's current profile id —
    /// the rotated package did not yield a fresh share
    /// (VAL-ROTATE-008).
    SameProfile,
    /// Resolved group public key does not match the active profile's
    /// group public key — the rotated package belongs to a different
    /// keyset (VAL-ROTATE-007).
    GroupMismatch,
    /// Catch-all error type.
    Unexpected,
}

impl RotateShareError {
    pub fn message(&self) -> &'static str {
        match self {
            Self::MalformedPackage => "Invalid rotated bfonboard1 package.",
            Self::WrongPassword => "Incorrect package password.",
            Self::RelayUnreachable => "Cannot reach the relay. Check the URL.",
            Self::ProvisionerOffline => {
                "Provisioning signer is offline. Please retry once it restarts."
            }
            Self::SameProfile => "This package would not change your share.",
            Self::GroupMismatch => "This package is from a different group.",
            Self::Unexpected => "Rotate share failed unexpectedly.",
        }
    }
}

/// Resolved rotated identity shown in the Replacement Preview
/// (VAL-ROTATE-006).
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RotatePreviewIdentity {
    /// Pre-filled label candidate for the rotated profile (keeps the
    /// existing device name by default so the user does not see the
    /// rename side effect on the hub — VAL-ROTATE-011 parity keeps the
    /// previous label).
    pub device_name: String,
    /// 64-char lowercase-hex share public key of the rotated share.
    pub share_pubkey: String,
    /// 64-char lowercase-hex group public key (matches the active
    /// profile's group key — VAL-ROTATE-004 invariant).
    pub group_pubkey: String,
    /// Derived 64-char lowercase-hex profile id of the rotated share.
    pub profile_id: String,
    /// Relay list in effect for the rotated profile (carried verbatim
    /// from the rotated package so round-tripping is lossless).
    pub relays: Vec<String>,
}

/// The full Rotate Share flow state, owned by `AppState.rotate_share`.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct RotateShareState {
    /// Current progress step (UI drives off this field).
    pub step: RotateShareStep,
    /// Most recent error, if any, for display on the connect screen.
    pub error: Option<RotateShareError>,
    /// Raw error text the shell returned alongside the typed error —
    /// rendered next to the typed message for diagnostics.
    #[serde(default)]
    pub last_error_message: Option<String>,
    /// bfonboard package text as entered (trimmed).
    pub package: String,
    /// bfonboard package password as entered (not persisted).
    pub password: String,
    /// Relay URL in effect — package-embedded or user-edited to platform
    /// correct value (`127.0.0.1:8194` on iOS sim, `10.0.2.2:8194` on
    /// Android emulator).
    pub relay_url: String,
    /// Resolved rotated identity (set once handshake completes).
    pub preview: Option<RotatePreviewIdentity>,
    /// Active profile id at the time the user opened the rotate-share
    /// flow. Used by VAL-ROTATE-010 (back leaves original untouched),
    /// VAL-ROTATE-011 (confirm replacement swaps to the rotated profile),
    /// and VAL-ROTATE-008 (resolve SameProfile when the rotated
    /// profile_id matches this).
    pub active_profile_id: String,
    /// Active profile short id (first 8 hex chars) for the connect-card
    /// row (VAL-ROTATE-005).
    pub active_short_id: String,
    /// Active profile device label for the connect-card row
    /// (VAL-ROTATE-005).
    pub active_device_label: String,
}

impl RotateShareState {
    /// Initial state shown when the user opens the Rotate Share flow.
    pub fn new() -> Self {
        Self {
            step: RotateShareStep::Idle,
            error: None,
            last_error_message: None,
            package: String::new(),
            password: String::new(),
            relay_url: String::new(),
            preview: None,
            active_profile_id: String::new(),
            active_short_id: String::new(),
            active_device_label: String::new(),
        }
    }

    /// Reset to idle and clear all in-flow data, keeping the active
    /// profile identity fields intact (those are restored from the
    /// dashboard's `AppAction::OpenRotateShareConnect`).
    pub fn reset(&mut self) {
        self.step = RotateShareStep::Idle;
        self.error = None;
        self.last_error_message = None;
        self.package.clear();
        self.password.clear();
        // relay_url is intentionally preserved across reset so a
        // navigated-away-then-back session keeps the user's relay
        // override — fall through to the open action's reseed on
        // re-entry.
        self.preview = None;
    }
}

impl Default for RotateShareState {
    fn default() -> Self {
        Self::new()
    }
}

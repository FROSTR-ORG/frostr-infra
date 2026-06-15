// ── Onboarding state ─────────────────────────────────────────────────────────

use serde::{Deserialize, Serialize};

/// Progress indicator for async onboarding steps.
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum OnboardingStep {
    /// Initial state — no action taken.
    Idle,
    /// Decrypting bfonboard package locally.
    Decrypting,
    /// Connecting to relay and performing onboard handshake.
    Handshaking,
    /// Handshake complete — profile resolved and ready for review.
    Complete,
    /// A recoverable error occurred — form stays editable for retry.
    Error,
}

/// Error kinds surfaced during the onboard flow.
/// VAL-ONBOARD-007: unreachable relay; VAL-ONBOARD-004: wrong password;
/// VAL-ONBOARD-003: malformed package; VAL-ONBOARD-014: offline provisioner;
/// VAL-ONBOARD-015: duplicate profile id already stored.
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum OnboardingError {
    /// Package text is not valid bech32m or does not decode to a bfonboard1 envelope.
    MalformedPackage,
    /// The package password is incorrect — decryption failed.
    WrongPassword,
    /// The relay URL is not reachable within the timeout.
    RelayUnreachable,
    /// The provisioning signer (alice) is offline and did not respond.
    ProvisionerOffline,
    /// The resolved profile_id already exists in local secure storage.
    /// VAL-ONBOARD-015 — the user's already-stored identity must NOT be
    /// silently overwritten by re-onboarding. Parity with `LoadProfileError::DuplicateProfile`.
    DuplicateProfile,
    /// An unexpected error occurred (for display; details not logged).
    Unexpected,
}

impl OnboardingError {
    /// User-visible message for each error kind.
    pub fn message(&self) -> &'static str {
        match self {
            Self::MalformedPackage => "Invalid bfonboard1 package.",
            Self::WrongPassword => "Incorrect password. Please try again.",
            Self::RelayUnreachable => "Could not reach the relay. Check the URL.",
            Self::ProvisionerOffline => "The provisioning signer is offline. Please try again.",
            Self::DuplicateProfile => "This profile already exists on this device.",
            Self::Unexpected => "An unexpected error occurred. Please try again.",
        }
    }
}

/// The resolved identity from a successful onboard handshake.
/// Shown on the review/save screen (VAL-ONBOARD-008).
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct ResolvedIdentity {
    /// User-editable device name (pre-filled from the onboard package's device name).
    pub device_name: String,
    /// Full 64-char lowercase-hex share public key.
    pub share_pubkey: String,
    /// Full 64-char lowercase-hex group public key.
    pub group_pubkey: String,
    /// Relay list in effect for this profile.
    pub relays: Vec<String>,
    /// Derived 64-char lowercase-hex profile id (sha256 of share pubkey).
    pub profile_id: String,
}

/// Per the architecture, decoded profile material lives in native secure storage
/// (Keychain/Keystore) and is never re-prompted for routine opens. This state
/// tracks the in-flow decoded result to populate the review screen.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct OnboardingState {
    /// Current progress step — drives UI display.
    pub step: OnboardingStep,
    /// Most recent error, if any, for display on the connect screen.
    pub error: Option<OnboardingError>,
    /// The bfonboard package string as entered (trimmed of surrounding whitespace).
    /// Not persisted; kept for re-use on retry after a partial step.
    pub package: String,
    /// The package password as entered. Not persisted.
    pub password: String,
    /// The relay URL to use — either from the package or user-edited.
    pub relay_url: String,
    /// Resolved identity from a successful handshake; None until Complete.
    pub resolved: Option<ResolvedIdentity>,
    /// Optional device name pre-injected from a debug intent (Android
    /// `com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD`) before the handshake
    /// completes. The review screen uses this as the initial value when
    /// present so the user does not have to re-type a long name. Cleared
    /// on `reset()` so it cannot leak across flows.
    pub injected_device_name: Option<String>,
}

impl OnboardingState {
    /// Initial idle state shown when the user opens the onboard flow.
    pub fn new() -> Self {
        Self {
            step: OnboardingStep::Idle,
            error: None,
            package: String::new(),
            password: String::new(),
            relay_url: String::new(),
            resolved: None,
            injected_device_name: None,
        }
    }

    /// Reset to idle and clear all in-flow data.
    /// VAL-ONBOARD-013: backing out before save stores nothing.
    pub fn reset(&mut self) {
        *self = Self::new();
    }
}

impl Default for OnboardingState {
    fn default() -> Self {
        Self::new()
    }
}

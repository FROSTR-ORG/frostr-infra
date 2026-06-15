// ── State modules ────────────────────────────────────────────────────────────

mod dashboard;
mod hub;
mod keyset;
mod load_profile;
mod onboarding;
mod rotate_share;
mod router;

pub use dashboard::{
    DashboardState, DashboardTab, LogEntry, LogLevel, NonceInventory, PeerPermissions,
    PeerSelectionStrategy, PeerStatus, PendingOp, PendingOpType, PermissionsState, PolicyCell,
    PolicyDirection, PolicyMethod, PolicyOverrideValue, ProfileInfo, RemotePolicyObservation,
    SettingsState, SignerReadiness, SignerRuntimeState, SignerSettings, SignerStatus,
    TestEcdhResultData, TestSignResultData,
};
pub use hub::{HubState, ProfileStatus, StoredProfile};
pub use keyset::{
    DistributeShareRecord, DistributeStatus, GeneratedShare, KeysetBundleRecord, KeysetFlowMode,
    KeysetFlowState, KeysetFlowStep, KeysetValidationError, RotationSourceRow,
};
pub use load_profile::{LoadProfileError, LoadProfileResolved, LoadProfileState, LoadProfileStep};
pub use onboarding::{OnboardingError, OnboardingState, OnboardingStep, ResolvedIdentity};
pub use rotate_share::{
    RotatePreviewIdentity, RotateShareError, RotateShareState, RotateShareStep,
};
pub use router::{Router, Screen};

use serde::{Deserialize, Serialize};

/// Top-level application state — single source of truth behind the UniFFI
/// boundary. Shells receive full snapshots only; they never hold partial
/// or derived state.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct AppState {
    /// Navigation router — Rust owns the screen stack.
    pub router: Router,
    /// Landing hub: stored profile list + entry tiles.
    pub hub: HubState,
    /// Onboard Device flow state (VAL-ONBOARD-*).
    pub onboarding: OnboardingState,
    /// Load Profile flow state (VAL-LOAD-*).
    pub load_profile: LoadProfileState,
    /// Create / Rotate Keyset wizard state (VAL-CREATE-* / VAL-ROTATE-*).
    pub keyset: KeysetFlowState,
    /// Rotate Share flow state (VAL-ROTATE-*).
    pub rotate_share: RotateShareState,
    /// Dashboard state for signer runtime, permissions, and settings tabs.
    pub dashboard: DashboardState,
    /// Monotonically increasing revision counter used by shells to detect
    /// stale snapshots (rev guard).
    pub rev: u64,
}

impl AppState {
    /// Build the initial empty hub state shown on first launch.
    pub fn initial() -> Self {
        Self {
            rev: 0,
            router: Router::HUB,
            hub: HubState::empty(),
            onboarding: OnboardingState::new(),
            load_profile: LoadProfileState::new(),
            keyset: KeysetFlowState::new(),
            rotate_share: RotateShareState::new(),
            dashboard: DashboardState::empty(),
        }
    }
}

// ── AppAction — all user intents that drive state transitions ───────────────

use serde::{Deserialize, Serialize};

/// Navigation actions — mirrors the screen stack.
#[derive(uniffi::Enum, Clone, Debug, Serialize, Deserialize)]
#[allow(clippy::large_enum_variant)]
pub enum AppAction {
    // ── Hub navigation ────────────────────────────────────────────────────
    NavigateOnboard,
    NavigateOnboardConnect,
    NavigateLoadProfile,
    NavigateCreateKeyset,
    OpenProfile {
        profile_id: String,
    },

    // ── Back / cancel ─────────────────────────────────────────────────────
    NavigateBack,

    // ── Onboard flow ──────────────────────────────────────────────────────
    InjectOnboardCredentials {
        package: String,
        password: String,
        relay_url: String,
        device_name: Option<String>,
    },
    OnboardConnect {
        package: String,
        password: String,
        relay_url: String,
    },
    OnboardHandshakeSuccess {
        device_name: String,
        share_pubkey: String,
        group_pubkey: String,
        relays: Vec<String>,
        profile_id: String,
    },
    OnboardHandshakeFailure {
        error: String,
    },
    OnboardSave {
        profile_id: String,
        label: String,
        short_id: String,
    },
    DiagnosticsOnboardSave {
        device_name: Option<String>,
    },
    OnboardStored {
        profile_id: String,
    },
    OnboardDuplicateRejected {
        profile_id: String,
    },
    OnboardClearError,

    // ── Load Profile flow ─────────────────────────────────────────────────
    LoadProfileSelectImport,
    LoadProfileSelectRecover,
    LoadProfileImportSubmit {
        package: String,
        password: String,
    },
    LoadProfileRecoverSubmit {
        package: String,
        password: String,
    },
    LoadProfileImportSuccess {
        device_name: String,
        share_pubkey: String,
        group_pubkey: String,
        relays: Vec<String>,
        profile_id: String,
    },
    LoadProfileImportFailure {
        error: String,
    },
    LoadProfileRecoverSuccess {
        device_name: String,
        share_pubkey: String,
        group_pubkey: String,
        relays: Vec<String>,
        profile_id: String,
    },
    LoadProfileRecoverFailure {
        error: String,
    },
    LoadProfileConfirm,
    LoadProfileStored {
        profile_id: String,
    },
    LoadProfileDuplicateRejected {
        profile_id: String,
    },
    LoadProfileClearError,

    // ── Create Keyset flow (VAL-CREATE-*) ─────────────────────────────────
    /// Open the wizard — reset state and land on the entry screen.
    CreateKeysetEnter,
    /// Pick the create (new signing key) mode on the entry screen.
    CreateKeysetSelectCreate,
    /// Pick the rotate (preserve group key) mode on the entry screen. The
    /// rotation path is owned by the rotate-share feature; this action
    /// exists so the entry selector shape matches parity but the wizard
    /// stays in the Generate step until the rotate feature completes it.
    CreateKeysetSelectRotate,
    /// User-side field changes on the Generate step (VAL-CREATE-002,
    /// VAL-CREATE-003). Each field change recomputes validation.
    CreateKeysetUpdateGroupName {
        value: String,
    },
    CreateKeysetUpdateThreshold {
        value: u16,
    },
    CreateKeysetUpdateCount {
        value: u16,
    },
    CreateKeysetUpdateMode {
        mode: String,
    },
    /// User tapped Generate with valid inputs (VAL-CREATE-002..007).
    /// Shells dispatch an FfiApp.generate_keyset() call and then resolve
    /// with `CreateKeysetGenerationSuccess`/`CreateKeysetGenerationFailed`.
    CreateKeysetGenerateSubmit {
        group_name: String,
        threshold: u16,
        count: u16,
        mode: String,
    },
    /// FfiApp.generate_keyset() succeeded with a JSON bundle wire form.
    /// The actor parses the bundle, builds the share picker and the
    /// Distribute rows, and advances to `DeviceProfile`.
    CreateKeysetGenerationSuccess {
        bundle_json: String,
    },
    /// FfiApp.generate_keyset() failed — return to `GenerationFailed`.
    CreateKeysetGenerationFailed {
        error: String,
    },
    /// Pick which share becomes the local device (VAL-CREATE-004,
    /// VAL-CREATE-006).
    CreateKeysetSelectLocalShare {
        share_idx: u16,
    },
    /// User-side field changes on the Device Profile step.
    CreateKeysetUpdateDeviceName {
        value: String,
    },
    CreateKeysetUpdateRelays {
        value: Vec<String>,
    },
    /// User tapped "Continue to Review" with valid inputs
    /// (VAL-CREATE-005/007/008).
    CreateKeysetAdvanceToReview,
    /// User tapped "Accept and Continue" (VAL-CREATE-010). Triggers
    /// AppUpdate::StoreKeysetCreatedProfile so the shell writes the
    /// decrypted material to native secure storage.
    CreateKeysetAccept,
    /// Shell stored the profile and reported the new profile id back.
    CreateKeysetAccepted {
        profile_id: String,
        label: String,
        short_id: String,
    },
    /// User-side field changes on the Distribute step (VAL-CREATE-013).
    CreateKeysetDistributeSetPassword {
        share_idx: u16,
        password: String,
    },
    CreateKeysetDistributeSetConfirm {
        share_idx: u16,
        confirm: String,
    },
    CreateKeysetDistributeSetLabel {
        share_idx: u16,
        label: String,
    },
    CreateKeysetDistributeSubmit {
        share_idx: u16,
        method: String,
    },
    /// Shell produced the bfonboard1 package for the requested share;
    /// the actor stores it on the row and updates the status chip.
    CreateKeysetDistributePackageProduced {
        share_idx: u16,
        package: String,
        method: String,
    },
    /// Shell failed to produce the bfonboard1 package for the requested
    /// share (KDF error, missing share, etc.). The chip stays Pending.
    CreateKeysetDistributeFailed {
        share_idx: u16,
        error: String,
    },
    /// User tapped "Finish" (VAL-CREATE-018/019).
    CreateKeysetDistributeFinish,
    /// User abandoned the wizard before Review accept (VAL-CREATE-020).
    /// Actor resets `KeysetFlowState` and returns control to the caller.
    CreateKeysetAbandon,

    // ── Profile management ───────────────────────────────────────────────
    RequestDeleteProfile {
        profile_id: String,
    },
    ConfirmDeleteProfile {
        profile_id: String,
    },
    RestoreAllProfiles,
    ProfileRestored {
        label: String,
        profile_id: String,
        short_id: String,
    },
    UpdateHubStatus {
        profile_id: String,
        active: bool,
    },

    // ── Dashboard / signer runtime ───────────────────────────────────────
    DashboardSetTab {
        tab: String,
    },
    OpenDashboard {
        profile_id: String,
        device_name: String,
        share_pubkey: String,
        group_pubkey: String,
    },
    SignerStart,
    SignerStarted {
        relay_connected: bool,
        readiness: String,
    },
    SignerStop,
    SignerStopped,
    SignerStatusUpdate {
        relay_connected: bool,
        readiness: String,
        peer_aliases: Vec<String>,
        peer_pubkeys: Vec<String>,
        peer_online: Vec<bool>,
        peer_last_seen: Vec<Option<i64>>,
        peer_incoming_available: Vec<u32>,
        peer_outgoing_available: Vec<u32>,
        peer_outgoing_spent: Vec<u32>,
        pending_op_types: Vec<String>,
        pending_op_started_at: Vec<i64>,
        last_refresh_secs: Option<i64>,
        events_len: u32,
    },
    SignerPoll,
    SignerPingPeers,
    SignerPingComplete {
        peer_alias: String,
        last_seen_secs: i64,
        incoming_available: u32,
    },
    CopyToClipboard {
        value: String,
        label: String,
    },
    TestSign,
    TestSignResult {
        request_id: String,
        digest: String,
        signature: String,
    },
    TestSignFailed {
        error: String,
    },
    TestEcdh,
    TestEcdhResult {
        request_id: String,
        target_pubkey: String,
        shared_secret: String,
    },
    TestEcdhFailed {
        error: String,
    },
    ClearTestSignResult,
    ClearTestEcdhResult,

    // ── Permissions ──────────────────────────────────────────────────────
    SetPolicyOverride {
        peer_alias: String,
        direction: String,
        method: String,
        value: String,
    },
    ResetPolicyOverride {
        peer_alias: String,
        direction: String,
        method: String,
    },
    ClearAllPeerOverrides {
        peer_alias: String,
    },
    RefreshRemotePolicy,
    SyncPeerOnlineStatus {
        peer_aliases: Vec<String>,
        peer_online: Vec<bool>,
    },
    UpdateRemotePolicyObservation {
        peer_alias: String,
        available: bool,
        last_observed_secs: Option<i64>,
        revision: Option<u64>,
    },

    // ── Settings / maintenance ───────────────────────────────────────────
    OpenDashboardSettings {
        device_name: String,
        relays: Vec<String>,
    },
    EditSignerName {
        name: String,
    },
    EditSignTimeout {
        value: u32,
    },
    EditPingTimeout {
        value: u32,
    },
    EditRequestTtl {
        value: u32,
    },
    EditStateSaveInterval {
        value: u32,
    },
    EditPeerSelectionStrategy {
        strategy: String,
    },
    AddRelay {
        url: String,
    },
    RemoveRelay {
        url: String,
    },
    SaveSettings,
    RequestCopyProfile,
    ConfirmCopyProfile {
        password: String,
    },
    RequestCopyShare,
    ConfirmCopyShare {
        password: String,
    },
    NavigateToRotateShare,
    Logout,
    ExportCompleted {
        package_type: String,
    },
    ExportFailed {
        error: String,
    },
    ClearExportState,
}

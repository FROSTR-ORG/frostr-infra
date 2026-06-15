// ── Dashboard state — signer runtime console, permissions, settings tabs ─────

use serde::{Deserialize, Serialize};

// ════════════════════════════════════════════════════════════════════════════
// Policy model — per-peer request/respond × ping/onboard/sign/ecdh
// Default policy is ALLOW for all combinations; manual overrides (unset/allow/deny)
// live in the permissions state and propagate to the signer runtime flags.
// Remote policy observation comes from the running signer via peer status updates.
// ════════════════════════════════════════════════════════════════════════════

/// Policy direction: request (outbound to peer) or respond (inbound from peer).
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize, Hash)]
pub enum PolicyDirection {
    Request,
    Respond,
}

/// Policy method: which FROSTR operation the policy governs.
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize, Hash)]
pub enum PolicyMethod {
    Ping,
    Onboard,
    Sign,
    Ecdh,
}

/// Manual override value for a single request/respond × method cell.
/// Unset means no manual override is active (use default policy).
/// Allow/Deny means the manual override is active.
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum PolicyOverrideValue {
    #[default]
    Unset,
    Allow,
    Deny,
}

/// A single manual override cell in the policy matrix.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct PolicyCell {
    pub direction: PolicyDirection,
    pub method: PolicyMethod,
    pub override_value: PolicyOverrideValue,
}

impl PolicyCell {
    /// Build a cell with unset override (default).
    pub fn new(direction: PolicyDirection, method: PolicyMethod) -> Self {
        Self {
            direction,
            method,
            override_value: PolicyOverrideValue::Unset,
        }
    }

    /// Compute the effective policy for this cell.
    /// Default is Allow when override is Unset; otherwise the override wins.
    pub fn effective_allow(&self) -> bool {
        match self.override_value {
            PolicyOverrideValue::Unset => true, // default: allow
            PolicyOverrideValue::Allow => true,
            PolicyOverrideValue::Deny => false,
        }
    }
}

/// Remote policy observation from a live peer (VAL-PERM-012, VAL-PERM-013).
/// Only populated for peers that have a running signer and have responded
/// to a policy advertisement round. Carol has no running signer so her
/// observation stays empty.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize, Default)]
pub struct RemotePolicyObservation {
    /// Whether the peer has advertised its policy to us.
    pub available: bool,
    /// Unix timestamp of the last policy advertisement from this peer.
    pub last_observed_secs: Option<i64>,
    /// Revision marker from the peer's policy advertisement.
    pub revision: Option<u64>,
}

/// Per-peer permission state (VAL-PERM-002 through VAL-PERM-013).
/// Contains both the manually-edited override matrix and the remote
/// policy observation from a live peer signer.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct PeerPermissions {
    /// Peer alias (e.g. "alice", "carol").
    pub alias: String,
    /// Backward-compatible field name used by older UI/tests.
    pub peer_alias: String,
    /// Whether this peer is currently online (from signer runtime).
    pub online: bool,
    /// Manual override cells: 2 directions × 4 methods = 8 cells.
    /// Organized as a flat list; access by (direction, method) key.
    pub overrides: Vec<PolicyCell>,
    /// Remote policy observation from the running signer (VAL-PERM-012, VAL-PERM-013).
    pub remote_observation: RemotePolicyObservation,
}

impl PeerPermissions {
    /// Build a new PeerPermissions for the given alias with all cells unset.
    pub fn new(alias: String) -> Self {
        let mut overrides = Vec::with_capacity(8);
        for direction in [PolicyDirection::Request, PolicyDirection::Respond] {
            for method in [
                PolicyMethod::Ping,
                PolicyMethod::Onboard,
                PolicyMethod::Sign,
                PolicyMethod::Ecdh,
            ] {
                overrides.push(PolicyCell::new(direction, method));
            }
        }
        Self {
            peer_alias: alias.clone(),
            alias,
            online: false,
            overrides,
            remote_observation: RemotePolicyObservation::default(),
        }
    }

    /// Find the override cell for a specific direction and method.
    pub fn find_cell(
        &self,
        direction: PolicyDirection,
        method: PolicyMethod,
    ) -> Option<&PolicyCell> {
        self.overrides
            .iter()
            .find(|c| c.direction == direction && c.method == method)
    }

    /// Find and mutate the override cell for a specific direction and method.
    pub fn find_cell_mut(
        &mut self,
        direction: PolicyDirection,
        method: PolicyMethod,
    ) -> Option<&mut PolicyCell> {
        self.overrides
            .iter_mut()
            .find(|c| c.direction == direction && c.method == method)
    }

    /// Set an override for a specific direction and method.
    pub fn set_override(
        &mut self,
        direction: PolicyDirection,
        method: PolicyMethod,
        value: PolicyOverrideValue,
    ) {
        if let Some(cell) = self.find_cell_mut(direction, method) {
            cell.override_value = value;
        }
    }

    /// Reset the override for a specific direction and method to Unset.
    pub fn reset_override(&mut self, direction: PolicyDirection, method: PolicyMethod) {
        self.set_override(direction, method, PolicyOverrideValue::Unset);
    }

    /// Return the manual override value for a specific policy cell.
    ///
    /// `Unset` means the runtime default still applies.
    pub fn effective_policy(
        &self,
        direction: PolicyDirection,
        method: PolicyMethod,
    ) -> PolicyOverrideValue {
        self.find_cell(direction, method)
            .map(|cell| cell.override_value)
            .unwrap_or(PolicyOverrideValue::Unset)
    }

    /// Clear all overrides for this peer (VAL-PERM-011).
    pub fn clear_all_overrides(&mut self) {
        for cell in self.overrides.iter_mut() {
            cell.override_value = PolicyOverrideValue::Unset;
        }
    }

    /// Check if this peer has any manual overrides set.
    pub fn has_any_override(&self) -> bool {
        self.overrides
            .iter()
            .any(|c| c.override_value != PolicyOverrideValue::Unset)
    }
}

/// The full permissions state for the dashboard Permissions tab.
/// VAL-PERM-002: renders for each peer; VAL-PERM-012/013: refresh updates remote obs.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize, Default)]
pub struct PermissionsState {
    /// Per-peer permission states, one entry per known peer.
    pub peers: Vec<PeerPermissions>,
    /// Whether a remote policy refresh is currently in progress.
    pub refresh_in_progress: bool,
}

impl PermissionsState {
    /// Build a PermissionsState with entries for alice and carol (the 2-of-3 demo keyset).
    pub fn with_demo_peers() -> Self {
        Self {
            peers: vec![
                PeerPermissions::new("alice".to_string()),
                PeerPermissions::new("carol".to_string()),
            ],
            refresh_in_progress: false,
        }
    }

    /// Find a peer by alias.
    pub fn find_peer(&self, alias: &str) -> Option<&PeerPermissions> {
        self.peers
            .iter()
            .find(|p| p.alias == alias || p.peer_alias == alias)
    }

    /// Find a peer by alias (mutable).
    pub fn find_peer_mut(&mut self, alias: &str) -> Option<&mut PeerPermissions> {
        self.peers
            .iter_mut()
            .find(|p| p.alias == alias || p.peer_alias == alias)
    }

    /// Update the online status of a peer based on signer runtime peer list.
    pub fn update_peer_online_status(&mut self, alias: &str, online: bool) {
        if let Some(peer) = self.find_peer_mut(alias) {
            peer.online = online;
        }
    }

    /// Refresh remote policy observations for online peers.
    /// Called when the user activates the Refresh control (VAL-PERM-013).
    /// Also called automatically after a ping round completes (VAL-PERM-012).
    pub fn start_refresh(&mut self) {
        self.refresh_in_progress = true;
    }

    /// Complete a refresh cycle, updating remote observations.
    pub fn finish_refresh(&mut self, observations: Vec<(String, RemotePolicyObservation)>) {
        self.refresh_in_progress = false;
        for (alias, obs) in observations {
            if let Some(peer) = self.find_peer_mut(&alias) {
                peer.remote_observation = obs;
            }
        }
    }
}

/// Dashboard tab selection (VAL-SIGNER-*, VAL-PERM-*, VAL-SET-*).
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum DashboardTab {
    #[default]
    Signer,
    Permissions,
    Settings,
}

/// Peer selection strategy for the signer runtime.
/// VAL-SET-001: deterministic_sorted is the default.
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum PeerSelectionStrategy {
    #[default]
    DeterministicSorted,
    Random,
}

/// The signer settings state for the dashboard Settings tab.
/// VAL-SET-001 through VAL-SET-005, VAL-SET-010 through VAL-SET-016.
/// These fields are persisted through app restart via secure storage.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct SignerSettings {
    /// Sign operation timeout in seconds. Default: 30.
    pub sign_timeout_secs: u32,
    /// Ping timeout in seconds. Default: 15.
    pub ping_timeout_secs: u32,
    /// Request TTL in seconds. Default: 300.
    pub request_ttl_secs: u32,
    /// State save interval in seconds. Default: 30.
    pub state_save_interval_secs: u32,
    /// Peer selection strategy. Default: deterministic_sorted.
    pub peer_selection_strategy: PeerSelectionStrategy,
}

impl Default for SignerSettings {
    fn default() -> Self {
        Self {
            sign_timeout_secs: 30,
            ping_timeout_secs: 15,
            request_ttl_secs: 300,
            state_save_interval_secs: 30,
            peer_selection_strategy: PeerSelectionStrategy::DeterministicSorted,
        }
    }
}

impl SignerSettings {
    /// Check if a numeric value is positive (required for timeout fields).
    pub fn is_positive(v: u32) -> bool {
        v > 0
    }

    /// Normalize a potentially invalid value to the default.
    pub fn normalize_timeout(v: u32) -> u32 {
        if Self::is_positive(v) {
            v
        } else {
            Self::default().sign_timeout_secs
        }
    }
}

/// Settings state shown on the Settings tab.
/// VAL-SET-001: all five fields display with defaults.
/// VAL-SET-002/003: edits persist within the session.
/// VAL-SET-004: saving does not disrupt running signer.
/// VAL-SET-005: non-positive values are never persisted.
/// VAL-SET-014: relay list with add/remove/trim/dedupe.
/// VAL-SET-016: save is gated while signer is stopped.
#[derive(uniffi::Record, Clone, Debug, Default, Serialize, Deserialize)]
pub struct SettingsState {
    /// The signer name (device label) shown in the dashboard header and hub row.
    /// VAL-SET-013: editing renames everywhere live.
    pub signer_name: String,
    /// Signer runtime settings.
    pub settings: SignerSettings,
    /// Relay list with add/remove/trim/dedupe. VAL-SET-014.
    pub relays: Vec<String>,
    /// Whether there are unsaved edits (for UI state display).
    pub has_unsaved_edits: bool,
    /// Whether the settings save is currently blocked because the signer is stopped.
    /// VAL-SET-016: save is visibly gated while the signer is stopped.
    pub save_blocked_signer_stopped: bool,
    /// Pending export password for copy profile (set when user triggers copy profile).
    /// The shell shows a password prompt; the password is used once to encrypt the output.
    pub pending_export_password: Option<String>,
    /// Pending export type: "profile" or "share". Determines which package is exported.
    pub pending_export_type: Option<String>,
}

impl SettingsState {
    /// Build a SettingsState initialized from the profile info (on dashboard open).
    /// The signer_name comes from profile_info.device_name and relays from the profile.
    pub fn from_profile(device_name: String, relays: Vec<String>) -> Self {
        Self {
            signer_name: device_name,
            settings: SignerSettings::default(),
            relays,
            has_unsaved_edits: false,
            save_blocked_signer_stopped: false,
            pending_export_password: None,
            pending_export_type: None,
        }
    }

    /// Add a relay URL with trim and dedupe. VAL-SET-014.
    /// Whitespace is trimmed from both ends before adding.
    /// If the (trimmed) URL is already present, it is not added again.
    pub fn add_relay(&mut self, url: impl AsRef<str>) {
        let trimmed = url.as_ref().trim().to_string();
        if trimmed.is_empty() {
            return;
        }
        if !self.relays.contains(&trimmed) {
            self.relays.push(trimmed);
            self.has_unsaved_edits = true;
        }
    }

    /// Remove a relay URL. VAL-SET-014.
    pub fn remove_relay(&mut self, url: impl AsRef<str>) {
        let trimmed = url.as_ref().trim().to_string();
        self.relays.retain(|r| r != &trimmed);
        self.has_unsaved_edits = true;
    }

    /// Update the signer name. VAL-SET-013.
    pub fn set_signer_name(&mut self, name: String) {
        self.signer_name = name;
        self.has_unsaved_edits = true;
    }

    /// Update sign timeout with validation (non-positive → default). VAL-SET-005.
    pub fn set_sign_timeout(&mut self, value: u32) {
        self.settings.sign_timeout_secs = SignerSettings::normalize_timeout(value);
        self.has_unsaved_edits = true;
    }

    /// Update ping timeout with validation (non-positive → default). VAL-SET-005.
    pub fn set_ping_timeout(&mut self, value: u32) {
        self.settings.ping_timeout_secs = SignerSettings::normalize_timeout(value);
        self.has_unsaved_edits = true;
    }

    /// Update request TTL with validation (non-positive → default). VAL-SET-005.
    pub fn set_request_ttl(&mut self, value: u32) {
        self.settings.request_ttl_secs = SignerSettings::normalize_timeout(value);
        self.has_unsaved_edits = true;
    }

    /// Update state save interval with validation (non-positive → default). VAL-SET-005.
    pub fn set_state_save_interval(&mut self, value: u32) {
        self.settings.state_save_interval_secs = SignerSettings::normalize_timeout(value);
        self.has_unsaved_edits = true;
    }

    /// Update peer selection strategy. VAL-SET-003.
    pub fn set_peer_selection_strategy(&mut self, strategy: impl AsRef<str>) {
        self.settings.peer_selection_strategy = match strategy.as_ref() {
            "random" => PeerSelectionStrategy::Random,
            _ => PeerSelectionStrategy::DeterministicSorted,
        };
        self.has_unsaved_edits = true;
    }

    /// Mark that unsaved edits have been saved.
    pub fn mark_saved(&mut self) {
        self.has_unsaved_edits = false;
    }

    /// Check if the signer is running (used to gate save). VAL-SET-016.
    pub fn set_save_blocked(&mut self, blocked: bool) {
        self.save_blocked_signer_stopped = blocked;
    }

    /// Start the export password prompt flow for copy profile. VAL-SET-006.
    pub fn start_copy_profile(&mut self) {
        self.pending_export_type = Some("profile".to_string());
        self.pending_export_password = None;
    }

    /// Start the export password prompt flow for copy share. VAL-SET-008.
    pub fn start_copy_share(&mut self) {
        self.pending_export_type = Some("share".to_string());
        self.pending_export_password = None;
    }

    /// Clear the pending export state (after cancel or completion).
    pub fn clear_pending_export(&mut self) {
        self.pending_export_type = None;
        self.pending_export_password = None;
    }
}

/// Signer runtime operational readiness state.
/// VAL-SIGNER-004: readiness must reach SignReady after ping round.
/// VAL-SIGNER-003: Running + no degraded reasons = relay connected.
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum SignerReadiness {
    /// Runtime is not running or has not yet attempted to connect.
    #[default]
    Idle,
    /// Runtime is attempting to restore session or connect to relay.
    Restoring,
    /// Runtime is connected to relay but ping round not yet complete.
    RuntimeReady,
    /// Ping round complete; signer is ready to co-sign.
    SignReady,
    /// Runtime is connected but degraded (e.g. not enough live peers for signing).
    Degraded,
}

/// Summary of the signer runtime's running state.
/// VAL-SIGNER-001: stopped baseline when not running.
/// VAL-SIGNER-002: running summary when started.
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum SignerStatus {
    #[default]
    Stopped,
    Running,
}

/// Per-peer nonce inventory counters (VAL-SIGNER-009).
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize, Default)]
pub struct NonceInventory {
    pub incoming_available: u32,
    pub outgoing_available: u32,
    pub outgoing_spent: u32,
}

/// Individual peer status in the signer runtime (VAL-SIGNER-006/007/008/009).
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct PeerStatus {
    /// Human-readable peer alias (e.g. "alice", "carol").
    pub alias: String,
    /// 64-char lowercase-hex x-only public key of this peer.
    pub pubkey: String,
    /// Whether this peer is currently reachable and has completed the ping round.
    pub online: bool,
    /// Unix timestamp of the last received message from this peer.
    pub last_seen_secs: Option<i64>,
    /// Nonce inventory counters for this peer.
    pub nonces: NonceInventory,
}

/// A single log entry from the signer runtime event log (VAL-SIGNER-012/013).
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum LogLevel {
    Info,
    Warn,
    Error,
}

#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct LogEntry {
    pub level: LogLevel,
    /// ISO-8601 / RFC-3339 formatted timestamp string.
    pub timestamp: String,
    /// Human-readable log message.
    pub message: String,
}

/// A pending in-flight signer operation (VAL-SIGNER-014 idle/empty state).
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PendingOpType {
    Ping,
    Sign,
    Ecdh,
    Onboard,
}

/// A pending in-flight signer operation with its start time.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct PendingOp {
    pub op_type: PendingOpType,
    /// Unix timestamp when the operation started.
    pub started_at_secs: i64,
}

/// Result data for a completed test sign operation (VAL-SIGN-002).
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct TestSignResultData {
    /// Request id for correlating with demo-harness logs.
    pub request_id: String,
    /// The 32-byte digest that was signed (64-char lowercase-hex).
    pub digest: String,
    /// The 64-byte BIP340 signature (128-char lowercase-hex).
    pub signature: String,
    /// Unix timestamp when the operation completed.
    pub completed_at_secs: i64,
}

/// Result data for a completed test ECDH operation (VAL-SIGN-005).
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct TestEcdhResultData {
    /// Request id for correlating with demo-harness logs.
    pub request_id: String,
    /// The target public key used for ECDH (64-char lowercase-hex).
    pub target_pubkey: String,
    /// The derived 32-byte shared secret (64-char lowercase-hex).
    pub shared_secret: String,
    /// Unix timestamp when the operation completed.
    pub completed_at_secs: i64,
}

/// The signer runtime state shown on the Signer tab.
/// VAL-SIGNER-001 through VAL-SIGNER-018 all surface through this state.
/// VAL-SIGN-002/005: test sign and test ECDH result data.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize, Default)]
pub struct SignerRuntimeState {
    /// Whether the signer runtime is currently running.
    pub status: SignerStatus,
    /// Whether the relay connection is healthy (non-degraded).
    pub relay_connected: bool,
    /// Operational readiness of the signer.
    pub readiness: SignerReadiness,
    /// List of peer statuses (alice and carol for the 2-of-3 demo keyset).
    pub peers: Vec<PeerStatus>,
    /// Runtime event log entries, newest first.
    pub events: Vec<LogEntry>,
    /// Currently in-flight operations, empty when idle (VAL-SIGNER-014).
    pub pending_ops: Vec<PendingOp>,
    /// Unix timestamp of the last successful poll (for VAL-SIGNER-011 auto-update proof).
    pub last_refresh_secs: Option<i64>,
    /// Whether the signer is currently processing a ping round.
    pub ping_in_progress: bool,
    /// Whether a test sign operation is currently in flight (VAL-SIGN-002).
    pub test_sign_in_progress: bool,
    /// Result of the last completed test sign operation (VAL-SIGN-002).
    pub last_test_sign: Option<TestSignResultData>,
    /// Whether a test ECDH operation is currently in flight (VAL-SIGN-005).
    pub test_ecdh_in_progress: bool,
    /// Result of the last completed test ECDH operation (VAL-SIGN-005).
    pub last_test_ecdh: Option<TestEcdhResultData>,
    /// Highest `events_len` value the actor has ingested from shell polls.
    /// Used to dedupe the per-poll cadence so a single runtime
    /// transition only produces one safe INFO row. The runtime counter
    /// follows the bridge count down on restarts/recovery so a
    /// post-recovery advancement appends exactly one fresh row.
    /// `mobile-create-keyset-flow` events_len contract.
    #[serde(default)]
    pub runtime_observed_events_len: u64,
}

/// Profile identity data for the active profile's Signer tab identity block.
/// VAL-SIGNER-005: identity block shows device name, group pubkey, share pubkey.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct ProfileInfo {
    /// User-visible device name (from profile label).
    pub device_name: String,
    /// 64-char lowercase-hex share public key.
    pub share_pubkey: String,
    /// 64-char lowercase-hex group public key.
    pub group_pubkey: String,
    /// 64-char lowercase-hex profile id.
    pub profile_id: String,
}

/// One kind-10000 backup publish result recorded by the actor. Used as
/// shell-facing proof of the materialization side-effect so validators
/// can correlate the last publish with a hub row / materialization and
/// confirm the relay author filter holds. Production shells clear or
/// roll this slot as they re-import the same profile; tests inspect it
/// for the relay-side filtered proof in
/// `apps/igloo-mobile/library/evidence/mobile-relay-backup-publication-and-recovery-roundtrip/`.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct BackupPublishStatus {
    /// Materialization path that produced this event
    /// ("create" | "onboard" | "rotate" | "import" | "recover").
    pub source: String,
    /// Whether the publish hit at least one relay.
    pub success: bool,
    /// Hex-encoded Nostr event id when `success` is true.
    pub event_id: Option<String>,
    /// Hex-encoded Nostr author pubkey (derivative of the share secret,
    /// the canonical relay-side filter for VAL-BACKUP-001/002/004/006).
    pub author_pubkey: Option<String>,
    /// Number of bytes inside the encrypted `content` field.
    pub content_length: u32,
    /// Truncated prefix + length of the encrypted `content` field —
    /// never the raw ciphertext.
    pub content_redacted: String,
    /// Group public key the backup was published for.
    pub group_pubkey: Option<String>,
    /// Concatenated list of relay URLs the publish tried.
    pub relays_attempted: Vec<String>,
    /// Subset whose `["OK", …]` acks we observed.
    pub relays_published_to: Vec<String>,
    /// Error string when `success` is false.
    pub error: Option<String>,
    /// Unix timestamp the actor recorded this status at.
    pub recorded_at_secs: i64,
}

/// Dashboard state: active tab, signer runtime, permissions, settings, and profile identity.
/// Displayed when the user opens a stored profile from the hub.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize, Default)]
pub struct DashboardState {
    /// Active dashboard tab.
    pub active_tab: DashboardTab,
    /// Signer runtime console state.
    pub signer: SignerRuntimeState,
    /// Permissions policy editor state (VAL-PERM-001 through VAL-PERM-013).
    pub permissions: PermissionsState,
    /// Settings and maintenance state (VAL-SET-001 through VAL-SET-016).
    pub settings: SettingsState,
    /// Identity block data for the active profile.
    pub profile_info: Option<ProfileInfo>,
    /// Latest recorded kind-10000 backup publish result for this
    /// profile (VAL-BACKUP-001..006). `None` until the shell forwards
    /// `BackupPublishCompleted`. Replaced on every subsequent publish.
    #[serde(default)]
    pub last_backup_publish: Option<BackupPublishStatus>,
}

impl DashboardState {
    /// Build a dashboard with the given profile identity info.
    pub fn new(profile_info: ProfileInfo) -> Self {
        Self {
            active_tab: DashboardTab::Signer,
            signer: SignerRuntimeState::default(),
            permissions: PermissionsState::default(),
            settings: SettingsState::default(),
            profile_info: Some(profile_info),
            last_backup_publish: None,
        }
    }

    /// Reset to empty dashboard (used when no profile is active).
    pub fn empty() -> Self {
        Self {
            last_backup_publish: None,
            ..Self::default()
        }
    }
}

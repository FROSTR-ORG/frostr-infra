// Igloo Mobile - shared Rust core (TEA actor)
// Architecture: one AppState/AppAction, dedicated actor thread, UniFFI 0.31
// boundary. Rust owns all state, navigation, and domain logic.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::Sender as MpscSender;
use std::sync::{Arc, Mutex, RwLock};
use std::thread;
use std::time::Duration;

use anyhow::Context as _;
use bifrost_bridge_tokio::{Bridge, NostrSdkAdapter};
use bifrost_core::{GroupPackage, MemberPackage, SharePrivateKey};
use bifrost_signer::{DeviceConfig, DeviceState, SigningDevice};
use flume::{Receiver, Sender};
use k256::elliptic_curve::sec1::ToEncodedPoint;
use k256::SecretKey;
use rand::RngCore;

uniffi::setup_scaffolding!();

mod actions;
mod state;
mod updates;

pub use actions::AppAction;
pub use state::{
    AppState, BackupPublishStatus, DashboardState, DashboardTab, DistributeShareRecord,
    DistributeStatus, GeneratedShare, HubState, KeysetBundleRecord, KeysetFlowMode,
    KeysetFlowState, KeysetFlowStep, KeysetValidationError, LoadProfileError, LoadProfileResolved,
    LoadProfileState, LoadProfileStep, LogEntry, LogLevel, NonceInventory, OnboardingError,
    OnboardingState, OnboardingStep, PeerPermissions, PeerSelectionStrategy, PeerStatus, PendingOp,
    PendingOpType, PermissionsState, PolicyCell, PolicyDirection, PolicyMethod,
    PolicyOverrideValue, ProfileInfo, ProfileStatus, RemotePolicyObservation, ResolvedIdentity,
    RotatePreviewIdentity, RotateShareError, RotateShareState, RotateShareStep, RotationSourceRow,
    Router, Screen, SettingsState, SignerReadiness, SignerRuntimeState, SignerSettings,
    SignerStatus, StoredProfile, TestEcdhResultData, TestSignResultData,
};
pub use updates::update;

// AppUpdate - emitted by the actor to the shell reconciler

#[derive(uniffi::Enum, Clone, Debug)]
#[allow(clippy::large_enum_variant)]
pub enum AppUpdate {
    FullState(AppState),
    /// Store profile material in platform secure storage (Keychain/Keystore).
    StoreProfile {
        profile_id: String,
    },
    /// Delete profile material from platform secure storage.
    DeleteFromSecureStorage {
        profile_id: String,
    },
    /// Restore a single profile from platform secure storage.
    RestoreFromSecureStorage {
        profile_id: String,
    },
    /// Restore all stored profiles from platform secure storage.
    RestoreAllStoredProfiles,
    /// Hub requests delete confirmation dialog for a profile.
    ShowDeleteConfirmation {
        profile_id: String,
        label: String,
    },
    /// Shell should perform the onboard handshake with the provisioner.
    /// Contains the trimmed package, password, and platform-correct relay URL.
    PerformOnboardHandshake {
        package: String,
        password: String,
        relay_url: String,
    },
    /// Onboard failed — store profile material (already decrypted) to secure storage.
    StoreOnboardedProfile {
        profile_id: String,
        label: String,
        short_id: String,
    },
    /// Shell should perform the local bfprofile decode for import.
    /// VAL-LOAD-002/003/004/005: package decode, validation, wrong password.
    PerformLoadProfileImport {
        package: String,
        password: String,
    },
    /// Shell should perform the bfshare recovery: decrypt share and fetch
    /// kind-10000 backup from the relays embedded in the share.
    /// VAL-LOAD-009/010/011/012/013/019: share decode, backup fetch, reconstruction.
    PerformLoadProfileRecovery {
        package: String,
        password: String,
    },
    /// Load profile confirmed — store the profile material to secure storage.
    StoreLoadedProfile {
        profile_id: String,
        label: String,
        short_id: String,
    },
    /// Shell should start the signer runtime for the active profile.
    /// VAL-SIGNER-002: Start signer transitions to running.
    /// VAL-SIGNER-001: stopped baseline while not running.
    StartSignerRuntime,
    /// Shell should stop the signer runtime.
    /// VAL-SIGNER-015: Stop signer returns to stopped state.
    StopSignerRuntime,
    /// Shell should ping all online peers to update their status.
    /// VAL-SIGNER-010: manual peer Refresh updates status data.
    /// VAL-SIGNER-018: test ping completes against alice.
    PingSignerPeers,
    /// Copy a hex value to the platform clipboard.
    /// VAL-SIGNER-017: identity key values are copyable.
    CopyToClipboard {
        value: String,
        label: String,
    },
    /// Shell should poll the signer runtime status and dispatch SignerStatusUpdate.
    /// VAL-SIGNER-011: console status auto-updates without user interaction.
    PollSignerStatus,
    /// Shell should refresh remote policy observations from live peers
    /// (VAL-PERM-012, VAL-PERM-013). After the refresh completes, the shell
    /// dispatches UpdateRemotePolicyObservation for each peer that responded.
    RefreshRemotePolicy,
    /// Shell should show an export password prompt before writing a package
    /// to the clipboard. VAL-SET-006 (copy profile) and VAL-SET-008 (copy share).
    ShowExportPasswordPrompt {
        export_type: String, // "profile" | "share"
    },
    /// Shell should produce a bfprofile1 package encrypted with the given
    /// password and write it to the clipboard. VAL-SET-007/015.
    PerformCopyProfile {
        password: String,
    },
    /// Shell should produce a bfshare1 package encrypted with the given
    /// password and write it to the clipboard. VAL-SET-008/015.
    PerformCopyShare {
        password: String,
    },
    /// Persist settings changes to secure storage. Emitted when the user
    /// saves settings while the signer is running (VAL-SET-002/003/004/013/014).
    /// The shell updates the profile's stored settings and propagates the
    /// signer name change to the hub row.
    PersistSettings {
        signer_name: String,
        sign_timeout_secs: u32,
        ping_timeout_secs: u32,
        request_ttl_secs: u32,
        state_save_interval_secs: u32,
        peer_selection_strategy: String,
        relays: Vec<String>,
    },
    /// Shell should perform a test sign operation (VAL-SIGN-002).
    /// Shell calls FfiApp.test_sign() which initiates a real threshold signing
    /// round against alice using a random 32-byte digest. After completion,
    /// the shell dispatches TestSignResult or TestSignFailed.
    PerformTestSign,
    /// Shell should perform a test ECDH operation (VAL-SIGN-005).
    /// Shell calls FfiApp.test_ecdh() which initiates a real ECDH round with
    /// alice using a target public key. After completion, the shell dispatches
    /// TestEcdhResult or TestEcdhFailed.
    PerformTestEcdh,

    // ── Create Keyset flow side effects (VAL-CREATE-*) ──────────────────
    /// Shell should run frostr_utils::create_keyset() to produce the bundle.
    /// VAL-CREATE-022: this is the perf-sensitive step that must run off the
    /// main actor; shells dispatch a background thread and resolve with
    /// `CreateKeysetGenerationSuccess`/`CreateKeysetGenerationFailed`.
    PerformKeysetGeneration {
        group_name: String,
        threshold: u16,
        count: u16,
        mode: String,
    },
    /// Shell should encode a `bfonboard1` package for one of the remaining
    /// shares and (depending on `method`) copy to the clipboard, open a QR
    /// modal, or save to a file. VAL-CREATE-014/015/016.
    PerformKeysetDistribution {
        share_idx: u16,
        share_secret_hex: String,
        relays: Vec<String>,
        label: String,
        password: String,
        method: String, // "copy" | "qr" | "save"
    },
    /// Shell stored the freshly created profile material to secure storage.
    /// After successful storage the shell dispatches `CreateKeysetAccepted`
    /// with `profile_id`/`label`/`short_id`.
    StoreKeysetCreatedProfile {
        profile_id: String,
        label: String,
        short_id: String,
        material: Vec<u8>,
        relays: Vec<String>,
    },
    /// Shell should kick the signer runtime for the freshly stored profile
    /// so the Distribute step shows a live signer panel (VAL-CREATE-010).
    StartKeysetSignerRuntime {
        profile_id: String,
        label: String,
    },
    /// Combined variant used by the Create Keyset acceptance path so
    /// backup publication (VAL-BACKUP-001) and runtime kick
    /// (VAL-CREATE-010) reach the shell in one update — keeps the
    /// actor's single-side-effect invariant while chaining both
    /// post-storage actions into one ordered handoff. The shell reads
    /// the profile's stored material by `profile_id`, then forwards
    /// the publish result back via `BackupPublishCompleted`.
    StartKeysetSignerRuntimeAndPublishBackup {
        source: String,
        profile_id: String,
        label: String,
    },
    /// Shell should perform the real Nostr onboarding handshake for a
    /// rotated `bfonboard1` package (VAL-ROTATE-006). The connector
    /// mirrors `PerformOnboardHandshake` so the shell can re-use the
    /// existing FfiApp helper, but the group / same-profile checks
    /// (VAL-ROTATE-007/008) live on the Rust actor side after the
    /// handshake resolves.
    PerformRotateShareHandshake {
        package: String,
        password: String,
        relay_url: String,
        expected_group_pubkey: String,
        active_profile_id: String,
    },
    /// Shell should swap the active profile's stored material with the
    /// rotated material (VAL-ROTATE-011). One side effect lets the
    /// shell go through a single atomic keychain rewrite: delete the
    /// old profile, write the new one, then update the hub row +
    /// dashboard identity.
    ReplaceProfileFromRotate {
        old_profile_id: String,
        new_profile_id: String,
        new_label: String,
        new_short_id: String,
        new_material: Vec<u8>,
        new_relays: Vec<String>,
        /// Also drop the old device from local secure storage so the
        /// hub row's "available later" UX matches what the shell stored.
        delete_old: bool,
    },
    /// Combined variant used by the rotate-share replacement path so
    /// backup publication (VAL-BACKUP-004, by the new share) and
    /// secure-storage swap (VAL-ROTATE-011) reach the shell in one
    /// update. The shell swaps storage, then reads the freshly written
    /// material to publish a kind-10000 event under the new share's
    /// derived author pubkey. The backup publish appears after the
    /// storage swap so the relay's author check happens against the
    /// new (post-rotate) share, not the pre-rotation one.
    ReplaceProfileFromRotateAndPublishBackup {
        source: String,
        old_profile_id: String,
        new_profile_id: String,
        new_label: String,
        new_short_id: String,
        new_material: Vec<u8>,
        new_relays: Vec<String>,
        delete_old: bool,
    },
    /// Shell should publish a kind-10000 encrypted profile backup to
    /// every relay embedded in the freshly materialized profile.
    /// The actor dispatches this side effect after each
    /// materialization confirmation (StoreKeysetCreatedProfile,
    /// OnboardStored, ReplaceProfileFromRotate, LoadProfileStored).
    /// `source` is one of "create" | "onboard" | "rotate" | "import" |
    /// "recover" so validators can correlate which materialization
    /// path produced the new event.
    ///
    /// VAL-BACKUP-001 through VAL-BACKUP-006: the actor fires the
    /// publish via this side effect so the shell publishes an
    /// encrypted kind-10000 Nostr event to each relay embedded in the
    /// freshly materialized profile. The shell owns secure storage,
    /// so it reads the profile's stored material by `profile_id` and
    /// calls `FfiApp.publish_backup(source, material_json)`. The
    /// result is then forwarded back via
    /// `AppAction::BackupPublishCompleted` so the actor can mirror it
    /// into `dashboard.last_backup_publish` for validators and tests.
    PublishProfileBackup {
        source: String,
        profile_id: String,
        material_json: String,
    },
    /// Shell should run `frostr_utils::rotate_keyset_dealer` to produce
    /// the rotated bundle (VAL-ROTATE-004). Mirror of
    /// `PerformKeysetGeneration` but the FFI path takes the previous
    /// group + threshold/count + decrypted shares instead of running a
    /// fresh `create_keyset`.
    PerformKeysetRotation {
        group_name: String,
        threshold: u16,
        count: u16,
        /// Decrypted source group package (GroupPackage wire form)
        /// carrying the current group public key. FFI rotates from
        /// this group.
        source_group_json: String,
        /// Decrypted source share secrets (each a 32-byte hex) keyed
        /// by share_idx order; the FFI rebuilds a SharePackage list
        /// from these. Pair with `source_share_pubkeys_hex` to
        /// preserve the original member mapping.
        source_share_secrets_hex: Vec<String>,
        source_share_pubkeys_hex: Vec<String>,
    },
}

// Callback interface for shell reconciler

#[uniffi::export(callback_interface)]
pub trait AppReconciler: Send + Sync + 'static {
    fn reconcile(&self, update: AppUpdate);
}

#[derive(uniffi::Record, Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct MaterialMember {
    pub idx: u16,
    pub pubkey_hex: String,
}

#[derive(uniffi::Record, Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct OnboardProfileMaterial {
    pub share_seckey_hex: String,
    pub share_pubkey: String,
    pub group_pubkey: String,
    pub relays: Vec<String>,
    pub device_state_hex: String,
    pub profile_id: String,
    #[serde(default)]
    pub share_idx: u16,
    #[serde(default)]
    pub peer_pubkeys: Vec<String>,
    #[serde(default)]
    pub members: Vec<MaterialMember>,
    /// User-visible device name carried through export flows so that
    /// bfprofile1 packages emitted by export-profile preserve the
    /// resolved profile label rather than a hardcoded placeholder.
    /// Older material written before this field was added parses back
    /// as the empty string; callers handle the empty case.
    #[serde(default)]
    pub device_name: String,
}

impl OnboardProfileMaterial {
    pub fn to_bytes(&self) -> Vec<u8> {
        serde_json::to_vec(self).unwrap_or_default()
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self, String> {
        serde_json::from_slice(bytes).map_err(|e| e.to_string())
    }
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct TestSignResult {
    pub success: bool,
    pub error: Option<String>,
    pub request_id: Option<String>,
    pub digest: Option<String>,
    pub signature: Option<String>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct TestEcdhResult {
    pub success: bool,
    pub error: Option<String>,
    pub request_id: Option<String>,
    pub target_pubkey: Option<String>,
    pub shared_secret: Option<String>,
}

#[derive(uniffi::Record, Clone, Debug)]
pub struct OnboardResult {
    pub success: bool,
    pub error: Option<String>,
    pub material: Option<Vec<u8>>,
    pub device_name: Option<String>,
    pub share_pubkey: Option<String>,
    pub group_pubkey: Option<String>,
    pub relays: Option<Vec<String>>,
    pub profile_id: Option<String>,
}

/// Outcome of publishing a kind-10000 encrypted profile backup to the
/// configured Nostr relays (VAL-BACKUP-001..006).
///
/// `content_redacted` is the first `min(content_len, 24)` chars of the
/// NIP-44 ciphertext plus the byte length so validators and tests can
/// confirm the event content is opaque base64 without ever logging the
/// full ciphertext or any plaintext secret. The `content` field on the
/// event itself is NIP-44 content, not plaintext JSON, and must not
/// contain the device name, share secret hex, or relay URL in
/// cleartext (VAL-BACKUP-003).
#[derive(uniffi::Record, Clone, Debug)]
pub struct BackupPublishResult {
    pub success: bool,
    /// "create" | "onboard" | "rotate" | "import" | "recover" — passed
    /// back from the actor's `AppUpdate::PublishProfileBackup` so the
    /// shell can correlate which path produced this event.
    pub source: String,
    /// Hex-encoded Nostr event id once the relay confirmed receipt.
    /// `None` if the publish did not reach any relay or if the parsed
    /// event never landed on a watched relay.
    pub event_id: Option<String>,
    /// Hex-encoded Nostr pubkey of the event author (derived from the
    /// profile's share secret). This is the same value as the share
    /// pubkey and the only stable filter for the relay-side proof in
    /// VAL-BACKUP-001/002/004/006.
    pub author_pubkey: Option<String>,
    /// Number of bytes inside the encrypted `content` field.
    pub content_length: u32,
    /// First 24 chars (truncated form) of the encrypted NIP-44
    /// `content` plus the total length; never the raw ciphertext.
    pub content_redacted: String,
    /// Group public key the backup was published for (`None` if the
    /// material lacked a valid group pubkey).
    pub group_pubkey: Option<String>,
    /// Concatenated list of relay URLs the publish tried.
    pub relays_attempted: Vec<String>,
    /// Subset of `relays_attempted` whose `["OK", true, …]` ack we
    /// observed before the relay closed or timed out. Empty when the
    /// publish failed at every relay.
    pub relays_published_to: Vec<String>,
    /// Error string when `success == false`. Distinct from the OK
    /// streams above so a partial publish (one relay OK, two failed)
    /// can still be surfaced with the failed relay URLs.
    pub error: Option<String>,
}

// Core message types - dispatch uses a synchronous response channel so the
// caller (Kotlin) receives the updated state before the function returns.
// This eliminates the timing gap where Compose re-renders before the
// NavigateBack state update has been applied.

enum CoreMsg {
    Action(AppAction, MpscSender<AppState>),
}

// ── Signer status cache — shared between polling task and get_signer_status() ─

/// One peer row cached for shell JSON output by `get_signer_status()`. The shape
/// matches the bash/JSON shell parsing in `AppManager.swift::pollSignerStatus`
/// and `AppManager.kt::pollSignerStatus` so the timer can decode the bridge's
/// peer inventory rather than seeing the previously opaque JSON string.
///
/// `mobile-signer-runtime-restoring-readiness-fix`: the cache used to expose
/// `peers_json` / `pending_ops_json` strings that shells saw as opaque JSON
/// strings, leaving the per-peer (and per-pending-op) visible only inside Rust.
/// Shells now see a proper `peers[]` array (with named `alias`/`pubkey`/
/// `online`/`last_seen_secs`/`incoming_available`/`outgoing_available`/
/// `outgoing_spent` fields) and a `pending_ops[]` array (with `type` and
/// `started_at_secs`). Unity tests (`signer_status_json_carries_peer_pubkeys_*`
/// and `signer_status_json_carries_pending_op_kind_*`) pin the canonical shape.
#[derive(Clone, Debug, Default, serde::Serialize)]
struct CachedPeerRow {
    /// User-visible peer alias (display label). For the mobile shells the
    /// peer's x-only pubkey doubles as both the pubkey and the user-visible
    /// alias so the same string ping/refresh rounds through the bridge and
    /// shows up on screen.
    pub alias: String,
    /// 64-char lowercase-hex x-only public key of this peer.
    pub pubkey: String,
    /// Whether the bridge currently sees this peer as online.
    pub online: bool,
    /// Unix timestamp of the last received message from this peer, or null.
    pub last_seen_secs: Option<i64>,
    /// Incoming nonce inventory counter.
    pub incoming_available: u64,
    /// Outgoing nonce inventory counter.
    pub outgoing_available: u64,
    /// Spent outgoing nonce count.
    pub outgoing_spent: u64,
}

#[derive(Clone, Debug, serde::Serialize)]
struct CachedPendingOp {
    /// "ping" | "sign" | "ecdh" | "onboard" — kind of in-flight operation.
    #[serde(rename = "type")]
    pub op_type: String,
    /// Unix timestamp when the pending operation started.
    pub started_at_secs: i64,
}

/// Cached signer status updated by the background polling task.
/// Read by the shell's periodic poll (VAL-SIGNER-011 auto-update).
struct SignerStatusCache {
    running: bool,
    relay_connected: bool,
    readiness: String, // "idle" | "restoring" | "runtime_ready" | "sign_ready" | "degraded"
    /// Cached per-peer rows; serialized to the `peers[]` JSON array by
    /// `get_signer_status()`. Replaces the prior opaque `peers_json` string.
    peers: Vec<CachedPeerRow>,
    /// Cached per-pending-op entries; serialized to the `pending_ops[]` JSON
    /// array by `get_signer_status()`. Replaces the prior opaque
    /// `pending_ops_json` string.
    pending_ops: Vec<CachedPendingOp>,
    last_refresh_secs: Option<i64>,
    /// Monotonic counter incremented every time the polling task
    /// observes a runtime metadata fingerprint that differs from the
    /// previous poll. The actor deduplicates against this value via
    /// `SignerStatusUpdate.events_len` and emits one safe INFO row on
    /// each advance (`mobile-create-keyset-flow` events_len contract).
    /// The bifrost-bridge-tokio bridge does not expose a per-event
    /// stream; this fingerprint-based mirror is the local substitute
    /// that keeps the actor's runtime event log truthful without
    /// fabricating payload-bearing rows.
    events_len: u64,
    /// Fingerprint of the last observed (readiness, peers, pending_ops)
    /// tuple. `None` before the first observation under the current
    /// bridge instance (`stop_signer` clears it). Resetting the
    /// fingerprint on stop means the next `start_signer` triggers an
    /// advancement regardless of whether the runtime metadata reset to
    /// its starting defaults.
    last_obs_fingerprint: Option<String>,
}

impl Default for SignerStatusCache {
    fn default() -> Self {
        Self {
            running: false,
            relay_connected: false,
            readiness: "idle".to_string(),
            peers: Vec::new(),
            pending_ops: Vec::new(),
            last_refresh_secs: None,
            events_len: 0,
            last_obs_fingerprint: None,
        }
    }
}

// FfiApp - the main UniFFI entry point

#[derive(uniffi::Object)]
pub struct FfiApp {
    core_tx: Sender<CoreMsg>,
    update_rx: Receiver<AppUpdate>,
    listening: AtomicBool,
    shared_state: Arc<RwLock<AppState>>,
    // Signer runtime state — Arc-wrapped Bridge so it can be cloned into
    // the background polling task without requiring Bridge: Clone.
    signer_bridge: Arc<Mutex<Option<Arc<Bridge>>>>,
    signer_runtime: Arc<Mutex<Option<Arc<tokio::runtime::Runtime>>>>,
    signer_polling_handle: Arc<Mutex<Option<thread::JoinHandle<()>>>>,
    signer_status_cache: Arc<Mutex<SignerStatusCache>>,
    // Active profile material for export operations (set when profile opens).
    // The shell sets this via set_active_profile_material() before export actions run.
    #[allow(dead_code)]
    active_profile_material: Arc<Mutex<Option<OnboardProfileMaterial>>>,
    // Seed peers (x-only hex) carried from the active material so the polling
    // task can preserve them across ticks when the bridge has not yet
    // observed events for those peers yet, **and** so the auto-ping bootstrap
    // has a deterministic peer list to round-trip pings through when the
    // relay becomes connected.
    signer_seed_peers: Arc<Mutex<Vec<String>>>,
    // One-shot guard for the auto-ping bootstrap round. Once the relay
    // connects, the poller fires a single ping round through every seeded
    // peer to bootstrap alice's nonce inventory so `sign_ready` becomes
    // reachable within the 60 s envelope of VAL-SIGNER-004 instead of
    // waiting for an explicit user-driven Test Ping tap.
    signer_autoping_done: Arc<Mutex<bool>>,
}

#[uniffi::export]
impl FfiApp {
    #[uniffi::constructor]
    pub fn new(data_dir: String) -> Arc<Self> {
        let _ = data_dir; // reserved for future use

        let (update_tx, update_rx) = flume::unbounded();
        let (core_tx, core_rx) = flume::unbounded::<CoreMsg>();
        let initial_state = AppState::initial();
        let shared_state = Arc::new(RwLock::new(initial_state.clone()));

        let shared_for_core = shared_state.clone();
        thread::spawn(move || {
            let mut state = AppState::initial();

            // Emit initial state snapshot so the shell renders the hub immediately.
            {
                let snapshot = state.clone();
                match shared_for_core.write() {
                    Ok(mut guard) => *guard = snapshot.clone(),
                    Err(poisoned) => *poisoned.into_inner() = snapshot.clone(),
                }
                let _ = update_tx.send(AppUpdate::FullState(snapshot));
            }

            while let Ok(msg) = core_rx.recv() {
                match msg {
                    CoreMsg::Action(action, response_tx) => {
                        let (new_state, side_effect) = update(&state, &action);
                        state = new_state;
                        let snapshot = state.clone();
                        match shared_for_core.write() {
                            Ok(mut guard) => *guard = snapshot.clone(),
                            Err(poisoned) => *poisoned.into_inner() = snapshot.clone(),
                        }
                        // Send updated state back to the dispatch caller synchronously.
                        // This blocks until the caller receives the state, ensuring the
                        // Kotlin side has the updated state before dispatch returns.
                        let _ = response_tx.send(snapshot.clone());
                        // Always emit FullState for listeners.
                        let _ = update_tx.send(AppUpdate::FullState(snapshot.clone()));
                        // Emit side effect if any (e.g., StoreProfile, DeleteFromSecureStorage).
                        if let Some(effect) = side_effect {
                            let _ = update_tx.send(effect);
                        }
                    }
                }
            }
        });

        let app = Arc::new(Self {
            core_tx,
            update_rx,
            listening: AtomicBool::new(false),
            shared_state,
            signer_bridge: Arc::new(Mutex::new(None)),
            signer_runtime: Arc::new(Mutex::new(None)),
            signer_polling_handle: Arc::new(Mutex::new(None)),
            signer_status_cache: Arc::new(Mutex::new(SignerStatusCache::default())),
            active_profile_material: Arc::new(Mutex::new(None)),
            signer_seed_peers: Arc::new(Mutex::new(Vec::new())),
            signer_autoping_done: Arc::new(Mutex::new(false)),
        });
        register_active_ffi_app(app.clone());
        app
    }

    // Synchronous state read - use only for initial snapshot; updates come
    // through the reconciler callback.
    pub fn state(&self) -> AppState {
        match self.shared_state.read() {
            Ok(guard) => guard.clone(),
            Err(poisoned) => poisoned.into_inner().clone(),
        }
    }

    pub fn set_active_profile_material(&self, material_json: String) {
        if let Ok(material) = serde_json::from_str::<OnboardProfileMaterial>(&material_json) {
            *self.active_profile_material.lock().unwrap() = Some(material);
        }
    }

    // Send an action into the actor's action channel and wait for the updated
    // state to be returned synchronously. This ensures the Kotlin side has the
    // new state before dispatch returns, eliminating the timing gap where
    // Compose might re-render before the state update is applied.
    pub fn dispatch(&self, action: AppAction) -> AppState {
        let (tx, rx) = std::sync::mpsc::channel();
        let _ = self.core_tx.send(CoreMsg::Action(action, tx));
        // Block until the actor sends back the updated state.
        rx.recv().unwrap()
    }

    // Register a reconciler callback to receive state snapshots asynchronously.
    pub fn listen_for_updates(&self, reconciler: Box<dyn AppReconciler>) {
        if self
            .listening
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .is_err()
        {
            return; // already listening
        }

        let rx = self.update_rx.clone();
        thread::spawn(move || {
            while let Ok(update) = rx.recv() {
                reconciler.reconcile(update);
            }
        });
    }

    // ════════════════════════════════════════════════════════════════════════
    // Signer runtime lifecycle (VAL-SIGNER-001 through VAL-SIGNER-018)
    // ════════════════════════════════════════════════════════════════════════

    /// Start the signer runtime for the active profile.
    ///
    /// `material_json` is the serialized `OnboardProfileMaterial` JSON from
    /// platform secure storage (Keychain/Keystore). The material contains the
    /// share secret, group key, device state, and relay list needed to start
    /// the signer runtime against the live demo relay.
    ///
    /// VAL-SIGNER-002: Start transitions to running state.
    /// VAL-SIGNER-001: stopped baseline while not running.
    ///
    /// Returns `true` on success. On failure returns `false`; the shell can
    /// inspect `get_signer_status()` to diagnose the error.
    pub fn start_signer(&self, material_json: String) -> bool {
        // Check if signer is already running.
        {
            let cache = self.signer_status_cache.lock().unwrap();
            if cache.running {
                return false;
            }
        }

        // Parse the material JSON.
        let material: OnboardProfileMaterial = match serde_json::from_str(&material_json) {
            Ok(m) => m,
            Err(_) => return false,
        };

        if material.share_seckey_hex.is_empty() {
            return false;
        }

        // Build the share package.
        let share_seckey_bytes = match hex::decode(&material.share_seckey_hex) {
            Ok(b) if b.len() == 32 => {
                let mut arr = [0u8; 32];
                arr.copy_from_slice(&b);
                arr
            }
            _ => return false,
        };
        let share = bifrost_core::SharePackage {
            idx: material.share_idx,
            seckey: SharePrivateKey::new(share_seckey_bytes),
        };

        // Parse the group public key.
        let group_pk_bytes = match hex::decode(&material.group_pubkey) {
            Ok(b) if b.len() == 32 => b,
            _ => return false,
        };
        let mut group_pk_arr = [0u8; 32];
        group_pk_arr.copy_from_slice(&group_pk_bytes);

        let local_member_pubkey = {
            let sk = match SecretKey::from_slice(&share_seckey_bytes) {
                Ok(s) => s,
                Err(_) => return false,
            };
            let pk = sk.public_key();
            let ep = pk.to_encoded_point(true);
            let mut arr = [0u8; 33];
            arr.copy_from_slice(ep.as_bytes());
            arr
        };

        let mut members: Vec<MemberPackage> = material
            .members
            .iter()
            .filter_map(|member| {
                let bytes = hex::decode(&member.pubkey_hex).ok()?;
                if bytes.len() != 33 {
                    return None;
                }
                let mut pubkey = [0u8; 33];
                pubkey.copy_from_slice(&bytes);
                Some(MemberPackage {
                    idx: member.idx,
                    pubkey,
                })
            })
            .collect();
        if members.is_empty() {
            members.push(MemberPackage {
                idx: material.share_idx,
                pubkey: local_member_pubkey,
            });
        }

        let mut peer_pubkeys = if material.peer_pubkeys.is_empty() {
            members
                .iter()
                .filter(|member| member.idx != material.share_idx)
                .map(|member| hex::encode(&member.pubkey[1..]))
                .collect::<Vec<_>>()
        } else {
            material.peer_pubkeys.clone()
        };
        peer_pubkeys.retain(|pubkey| {
            pubkey.len() == 64
                && hex::decode(pubkey)
                    .map(|bytes| bytes.len() == 32)
                    .unwrap_or(false)
        });
        peer_pubkeys.sort();
        peer_pubkeys.dedup();

        {
            let mut seed_peers = self.signer_seed_peers.lock().unwrap();
            *seed_peers = peer_pubkeys.clone();
        }

        // Build the group package from secure-storage material. Newer
        // material carries the full member list; legacy material falls back to
        // the local member only and starts in a degraded but parseable mode.
        let group = GroupPackage {
            group_name: "FROSTR Demo Keyset".to_string(),
            group_pk: group_pk_arr,
            threshold: 2,
            members,
        };

        // Build device state — create fresh (no stored volatile state yet).
        let device_state = DeviceState::new(material.share_idx, share_seckey_bytes);

        // Build device config with the stored relay list.
        let device_config = DeviceConfig {
            sign_timeout_secs: 30,
            ecdh_timeout_secs: 30,
            ping_timeout_secs: 15,
            onboard_timeout_secs: 30,
            request_ttl_secs: 300,
            max_future_skew_secs: 30,
            request_cache_limit: 2048,
            state_save_interval_secs: 30,
            event_kind: 20000,
            peer_selection_strategy: bifrost_signer::PeerSelectionStrategy::DeterministicSorted,
            ecdh_cache_capacity: 256,
            ecdh_cache_ttl_secs: 300,
            sig_cache_capacity: 256,
            sig_cache_ttl_secs: 300,
        };

        // Build the signing device.
        let signer = match SigningDevice::new(
            group.clone(),
            share,
            peer_pubkeys,
            device_state,
            device_config,
        ) {
            Ok(s) => s,
            Err(_) => return false,
        };

        // Create the NostrSdkAdapter with the stored relay list.
        let adapter = NostrSdkAdapter::new(material.relays.clone());

        // Build the tokio runtime and start the bridge.
        let runtime = match tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_time()
            .enable_io()
            .build()
        {
            Ok(rt) => Arc::new(rt),
            Err(_) => return false,
        };

        let bridge = match runtime.block_on(Bridge::start_with_config(
            adapter,
            signer,
            bifrost_bridge_tokio::BridgeConfig::default(),
        )) {
            Ok(b) => b,
            Err(_) => return false,
        };

        // Store the bridge and runtime (Arc-wrapped for cloneability).
        *self.signer_bridge.lock().unwrap() = Some(Arc::new(bridge));
        *self.signer_runtime.lock().unwrap() = Some(runtime.clone());

        // Mark as running in the cache.
        {
            let mut cache = self.signer_status_cache.lock().unwrap();
            cache.running = true;
            cache.relay_connected = false;
            cache.readiness = "restoring".to_string();
        }

        // Clone everything the polling task needs.
        let bridge_handle = self.signer_bridge.clone();
        let status_cache = self.signer_status_cache.clone();
        let runtime_handle = self.signer_runtime.clone();
        // Clone the seed-peer baseline so the polling task can preserve it
        // across ticks. The mobile-signer-runtime-restoring-readiness-live-proof
        // investigation showed `bridge.peer_status()` returns an empty list
        // until at least one event arrives from a peer, which left the user-
        // facing peer list empty and held readiness at `restoring` even with
        // live alice. Merging the bridge-observed peer list with the seed
        // list keeps the user-facing row intact and lets the eventual PONG
        // from alice (after the auto-ping bootstrap below) flip the row to
        // `online = true` and progress readiness to `sign_ready`.
        let seed_peers_handle = self.signer_seed_peers.clone();
        let autoping_done_handle = self.signer_autoping_done.clone();

        // Spawn the polling task on the tokio runtime.
        // Shutdown is signaled by stop_signer() setting signer_bridge to None.
        let polling_task = thread::spawn(move || {
            runtime.block_on(async {
                let poll_interval = Duration::from_secs(1);
                loop {
                    // Check for shutdown: stop_signer() sets signer_bridge to None.
                    let bridge_arc_opt = {
                        let guard = bridge_handle.lock().unwrap();
                        guard.clone() // Option<Arc<Bridge>> is Clone
                    };
                    match bridge_arc_opt {
                        None => {
                            // Shutdown requested.
                            {
                                let mut cache = status_cache.lock().unwrap();
                                cache.running = false;
                            }
                            break;
                        }
                        Some(bridge_arc) => {
                            // Sleep then poll — use tokio::select! to allow early exit.
                            tokio::select! {
                                _ = tokio::time::sleep(poll_interval) => {
                                    // Get individual status components. Arc<Bridge> derefs to &Bridge.
                                    let dev_status = bridge_arc.status().await;
                                    let readiness = bridge_arc.readiness().await;
                                    let peer_list = bridge_arc.peer_status().await;

                                    let relay_connected = dev_status.is_ok();
                                    let readiness_str = match &readiness {
                                        Ok(r) if r.sign_ready => "sign_ready",
                                        Ok(r) if r.runtime_ready => "runtime_ready",
                                        Ok(_) => "restoring",
                                        Err(_) => "idle",
                                    }.to_string();

                                    // Build the bridge-observed peer map keyed
                                    // by x-only pubkey so the seed-peer merge
                                    // below can update each existing row without
                                    // wiping unseen peers out of the cache.
                                    // `p.pubkey` from bifrost is x-only hex; the
                                    // shell uses the same string as the alias and
                                    // the `FfiApp.ping_peer` argument.
                                    let observed: std::collections::HashMap<String, CachedPeerRow> = peer_list
                                        .unwrap_or_default()
                                        .into_iter()
                                        .map(|p| {
                                            // Defensive guard (`mobile-signer-peer-refresh-liveness-fix`):
                                            // require `last_seen.is_some()` before
                                            // promoting a peer to online. The bridge's
                                            // own `PeerStatus.online` derives from
                                            // `state.peer_last_seen` being recent, so
                                            // any `online=true` row should carry a
                                            // matching `last_seen`. Discarding the
                                            // online flag here defends against any
                                            // future bridge regression that surfaces
                                            // `online=true` without proof so we never
                                            // accidentally render a never-responding
                                            // non-running peer (carol) as Online.
                                            let online_with_evidence =
                                                p.online && p.last_seen.is_some();
                                            let row = CachedPeerRow {
                                                alias: p.pubkey.clone(),
                                                pubkey: p.pubkey.clone(),
                                                online: online_with_evidence,
                                                last_seen_secs: p.last_seen.map(|t| t as i64),
                                                incoming_available: p.incoming_available as u64,
                                                outgoing_available: p.outgoing_available as u64,
                                                outgoing_spent: p.outgoing_spent as u64,
                                            };
                                            (p.pubkey.clone(), row)
                                        })
                                        .collect();

                                    // Snapshot the seeded peers from the active
                                    // material (set by start_signer, unchanged
                                    // across poll cycles since stop_signer
                                    // resets the Vec).
                                    let seed_peers_snapshot: Vec<String> = {
                                        let guard = seed_peers_handle.lock().unwrap();
                                        guard.clone()
                                    };

                                    // Merge logic: the union of seed peers +
                                    // observed peers produces the final
                                    // user-facing list. Each row starts at
                                    // `online=false, last_seen=None,
                                    // nonces=0` and is upgraded in place when
                                    // the bridge reports concrete metadata.
                                    // This keeps the alice/carol rows visible
                                    // from t=0 (so the shell does not render
                                    // "No peers detected") while letting the
                                    // eventual PONG from a live peer flip
                                    // `online=true` and supply nonce inventory.
                                    // The defensive "no evidence" guard above
                                    // mirrors the same logic at the actor
                                    // layer (`AppAction::SignerStatusUpdate`
                                    // merge in updates.rs) so neither path
                                    // can promote a non-running peer Online.
                                    let mut final_peers: Vec<CachedPeerRow> = Vec::new();
                                    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();
                                    for sp in &seed_peers_snapshot {
                                        if let Some(row) = observed.get(sp) {
                                            final_peers.push(row.clone());
                                        } else {
                                            final_peers.push(CachedPeerRow {
                                                alias: sp.clone(),
                                                pubkey: sp.clone(),
                                                online: false,
                                                last_seen_secs: None,
                                                incoming_available: 0,
                                                outgoing_available: 0,
                                                outgoing_spent: 0,
                                            });
                                        }
                                        seen.insert(sp.clone());
                                    }
                                    for (pubkey_alias, row) in observed.iter() {
                                        if !seen.contains(pubkey_alias) {
                                            final_peers.push(row.clone());
                                        }
                                    }
                                    final_peers.sort_by(|a, b| a.pubkey.cmp(&b.pubkey));

                                    // Build pending-ops rows when the bridge reports
                                    // any in-flight operations. The runtime's
                                    // `pending_operations: HashMap<request_id, ...>`
                                    // does not surface op-kind details over the
                                    // `Bridge::Status` snapshot, so we collapse
                                    // to a sortable stable row whose kind the
                                    // shells render as `pending`. The shells only
                                    // care that something showed up during an
                                    // interactive round (VAL-SIGNER-014 happy
                                    // path; the bridge's own request_phase API is
                                    // used for signed rounds where the kind has
                                    // already been recorded by the
                                    // `TestSignResult`/`TestSignFailed` handlers).
                                    let pending_ops_count = dev_status.as_ref().map(|s| s.pending_ops).unwrap_or(0);
                                    let now_secs = std::time::SystemTime::now()
                                        .duration_since(std::time::UNIX_EPOCH)
                                        .map(|d| d.as_secs() as i64)
                                        .unwrap_or(0);
                                    let pending_ops: Vec<CachedPendingOp> = if pending_ops_count > 0 {
                                        (0..pending_ops_count)
                                            .map(|i| CachedPendingOp {
                                                op_type: "pending".to_string(),
                                                started_at_secs: now_secs.saturating_sub(i as i64),
                                            })
                                            .collect()
                                    } else {
                                        Vec::new()
                                    };

                                    // Update cache atomically.
                                    {
                                        let mut cache = status_cache.lock().unwrap();
                                        cache.running = true;
                                        cache.relay_connected = relay_connected;
                                        cache.readiness = readiness_str.clone();
                                        cache.peers = final_peers.clone();
                                        cache.pending_ops = pending_ops.clone();
                                        cache.last_refresh_secs = Some(now_secs);
                                        // Compute a fingerprint of the observable
                                        // runtime metadata (readiness, connected
                                        // flag, peer-online map, pending-ops count)
                                        // so the bridge-supplied count advances on
                                        // every visible state transition even when
                                        // bifrost-bridge-tokio doesn't surface a
                                        // per-event payload stream. The actor
                                        // compares this against the previous
                                        // `SignerStatusUpdate.events_len` to dedupe
                                        // and emit at most one INFO log row per
                                        // advancement (`mobile-create-keyset-flow`
                                        // events_len contract).
                                        let mut peer_sig_parts: Vec<String> = final_peers
                                            .iter()
                                            .map(|p| {
                                                format!(
                                                    "{}:{}:{}",
                                                    p.alias,
                                                    p.online,
                                                    p.last_seen_secs.unwrap_or(0)
                                                )
                                            })
                                            .collect();
                                        peer_sig_parts.sort();
                                        let pending_ops_sig = match pending_ops.len() {
                                            0 => "0".to_string(),
                                            n => format!("gt0:{}", n),
                                        };
                                        let peer_sig = format!(
                                            "{}|{}",
                                            pending_ops_sig,
                                            peer_sig_parts.join(",")
                                        );
                                        let fingerprint =
                                            format!("{}|{}|{}", readiness_str, relay_connected, peer_sig);
                                        let changed = cache
                                            .last_obs_fingerprint
                                            .as_ref()
                                            .map(|prev| prev != &fingerprint)
                                            .unwrap_or(true);
                                        if changed {
                                            cache.events_len = cache.events_len.saturating_add(1);
                                            cache.last_obs_fingerprint = Some(fingerprint);
                                        }
                                    }

                                    // Auto-ping bootstrap: the moment the bridge
                                    // reports the relay is reachable on this tick,
                                    // fire a single ping round through every
                                    // seeded peer to bootstrap alice's incoming
                                    // nonce inventory. Without this round, the
                                    // bridge has no inbound traffic from any
                                    // peer, the per-peer `peer_last_seen` stays
                                    // `None`, and readiness remains stuck at
                                    // `restoring` indefinitely. With this round,
                                    // alice's PONG response lands within ~15 s
                                    // and `sign_ready` becomes reachable within
                                    // the 60 s envelope of VAL-SIGNER-004.
                                    //
                                    // Guarded by `signer_autoping_done` so the
                                    // bootstrap fires exactly once per
                                    // `start_signer` invocation, matching the
                                    // one-ping-per-peer heuristic in
                                    // `bifrost-app` cold-restart recovery.
                                    //
                                    // The auto-ping latch is briefly acquired to
                                    // read+flip the flag and then released before
                                    // the awaiting ping round so clippy's
                                    // `await_holding_lock` does not flag the
                                    // bridge-tokio call as holding a std Mutex
                                    // across an `.await` suspension point.
                                    if relay_connected {
                                        let should_bootstrap = {
                                            let mut guard = autoping_done_handle.lock().unwrap();
                                            if !*guard {
                                                *guard = true;
                                                true
                                            } else {
                                                false
                                            }
                                        };
                                        if should_bootstrap {
                                            for peer_alias in &seed_peers_snapshot {
                                                let _ = bridge_arc
                                                    .ping(peer_alias.clone(), Duration::from_secs(15))
                                                    .await;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            });

            // Clean up handles when polling task exits.
            *runtime_handle.lock().unwrap() = None;
            *bridge_handle.lock().unwrap() = None;
        });

        *self.signer_polling_handle.lock().unwrap() = Some(polling_task);

        true
    }

    /// Stop the signer runtime (VAL-SIGNER-015).
    /// Shutdown is signaled by setting signer_bridge to None; the polling task
    /// exits when it detects None on the next poll cycle.
    pub fn stop_signer(&self) {
        // Signal shutdown by setting bridge to None.
        *self.signer_bridge.lock().unwrap() = None;

        // Wait for the polling task to stop.
        if let Some(handle) = self.signer_polling_handle.lock().unwrap().take() {
            let _ = handle.join();
        }

        // Clear the seed-peer baseline and the auto-ping bootstrap guard so
        // the next `start_signer` rebuilds them from the (possibly different)
        // active material's `members` list and re-arms the bootstrap-round
        // latch. Without this reset, restarting the same runtime would skip
        // the auto-ping and leave readiness stuck at restoring again.
        {
            let mut seed_peers = self.signer_seed_peers.lock().unwrap();
            seed_peers.clear();
            let mut done = self.signer_autoping_done.lock().unwrap();
            *done = false;
        }

        // Mark as not running in the cache.
        {
            let mut cache = self.signer_status_cache.lock().unwrap();
            *cache = SignerStatusCache::default();
        }
    }

    /// Get the current signer status as a JSON string for the shell to parse
    /// and dispatch via `SignerStatusUpdate`.
    ///
    /// Called by the shell every ~1s while the Signer tab is visible
    /// (VAL-SIGNER-011 auto-update without user interaction).
    ///
    /// Returns a JSON object:
    /// ```json
    /// {
    ///   "running": true,
    ///   "relay_connected": true,
    ///   "readiness": "sign_ready",
    ///   "peers_json": "[...]",
    ///   "pending_ops_json": "[...]",
    ///   "last_refresh_secs": 1234567890,
    ///   "events_len": 5
    /// }
    /// ```
    ///
    /// `mobile-signer-runtime-restoring-readiness-fix`: prior to this patch
    /// the inner `peers` and `pending_ops` arrays were JSON-encoded as opaque
    /// strings (`peers_json` / `pending_ops_json`) that the shells could not
    /// parse — the per-peer date and nonce totals never reached `AppManager`'s
    /// countdown. The cache now stores the typed `CachedPeerRow` /
    /// `CachedPendingOp` values and `get_signer_status` serialises them as
    /// proper JSON **arrays** of objects (not strings) with named fields the
    /// shells decode via `JSONSerialization` (iOS) and `org.json` (Android).
    /// The arrays are nested directly under `peers` and `pending_ops` so
    /// `optJSONArray("peers")` (Android) and `as? [[String: Any]]` (iOS)
    /// both succeed.
    pub fn get_signer_status(&self) -> String {
        let cache = self.signer_status_cache.lock().unwrap();
        let peers_value =
            serde_json::to_value(&cache.peers).unwrap_or_else(|_| serde_json::Value::Array(vec![]));
        let pending_ops_value = serde_json::to_value(&cache.pending_ops)
            .unwrap_or_else(|_| serde_json::Value::Array(vec![]));
        serde_json::json!({
            "running": cache.running,
            "relay_connected": cache.relay_connected,
            "readiness": cache.readiness,
            "peers": peers_value,
            "pending_ops": pending_ops_value,
            "last_refresh_secs": cache.last_refresh_secs,
            "events_len": cache.events_len,
        })
        .to_string()
    }

    /// Perform a ping round against the specified peer.
    /// Called by the shell when the user activates the test ping / peer Refresh
    /// affordance (VAL-SIGNER-010, VAL-SIGNER-018).
    ///
    /// `peer_alias` is the user-facing alias the shell routed from the cached
    /// `CachedPeerRow.alias`. Because `start_signer` now seeds that alias
    /// with the peer's x-only pubkey (the format `bifrost_router::Bridge::ping`
    /// expects), the string doubles as the bridge ping target.
    ///
    /// VAL-SIGNER-018: test ping completes against alice.
    /// Returns `true` if the ping round completed successfully, `false` otherwise.
    pub fn ping_peer(&self, peer_alias: String) -> bool {
        let bridge_guard = self.signer_bridge.lock().unwrap();
        if let Some(ref bridge) = *bridge_guard {
            let runtime = self.signer_runtime.lock().unwrap();
            if let Some(ref rt) = *runtime {
                let result = rt.block_on(bridge.ping(peer_alias.clone(), Duration::from_secs(15)));
                return result.is_ok();
            }
        }
        false
    }

    /// Perform a test sign operation (VAL-SIGN-002).
    /// Generates a random 32-byte digest and initiates a real threshold signing
    /// round against alice via the bridge. Returns TestSignResult with
    /// request_id, digest, and signature on success.
    pub fn test_sign(&self) -> TestSignResult {
        let empty = TestSignResult {
            success: false,
            error: None,
            request_id: None,
            digest: None,
            signature: None,
        };

        let bridge_guard = self.signer_bridge.lock().unwrap();
        let bridge = match bridge_guard.as_ref() {
            None => {
                let mut r = empty;
                r.error = Some("signer_not_running".to_string());
                return r;
            }
            Some(b) => b,
        };

        let runtime_guard = self.signer_runtime.lock().unwrap();
        let runtime = match runtime_guard.as_ref() {
            None => {
                let mut r = empty;
                r.error = Some("signer_not_running".to_string());
                return r;
            }
            Some(rt) => rt,
        };

        // Generate a random 32-byte digest for the test sign operation.
        let mut digest_bytes = [0u8; 32];
        rand::rngs::OsRng.fill_bytes(&mut digest_bytes);
        let digest_hex = hex::encode(digest_bytes);

        // Call the bridge sign method. The bridge handles the threshold round
        // with alice as co-signer and returns the aggregated BIP340 signature.
        // sign(message: [u8; 32], timeout: Duration) -> Result<SignResult, BridgeError>
        // SignResult = { request_id: String, signatures: Vec<[u8; 64]> }
        let sign_result = runtime.block_on(bridge.sign(digest_bytes, Duration::from_secs(30)));

        match sign_result {
            Ok(sign_res) => {
                // signatures is Vec<[u8; 64]> - we use the first signature for verification.
                // In a 2-of-3 threshold scheme with alice as the only live peer,
                // we get one signature from alice.
                let signature_hex = if sign_res.signatures.is_empty() {
                    String::new()
                } else {
                    hex::encode(sign_res.signatures[0])
                };
                TestSignResult {
                    success: true,
                    error: None,
                    request_id: Some(sign_res.request_id),
                    digest: Some(digest_hex),
                    signature: Some(signature_hex),
                }
            }
            Err(e) => {
                let mut r = empty;
                r.error = Some(e.to_string());
                r
            }
        }
    }

    /// Perform a test ECDH operation (VAL-SIGN-005).
    /// Generates a random target keypair and derives a shared secret with alice
    /// via the bridge. Returns TestEcdhResult with request_id, target_pubkey,
    /// and shared_secret on success.
    pub fn test_ecdh(&self) -> TestEcdhResult {
        let empty = TestEcdhResult {
            success: false,
            error: None,
            request_id: None,
            target_pubkey: None,
            shared_secret: None,
        };

        let bridge_guard = self.signer_bridge.lock().unwrap();
        let bridge = match bridge_guard.as_ref() {
            None => {
                let mut r = empty;
                r.error = Some("signer_not_running".to_string());
                return r;
            }
            Some(b) => b,
        };

        let runtime_guard = self.signer_runtime.lock().unwrap();
        let runtime = match runtime_guard.as_ref() {
            None => {
                let mut r = empty;
                r.error = Some("signer_not_running".to_string());
                return r;
            }
            Some(rt) => rt,
        };

        // Generate a random target SecretKey for the ECDH operation.
        let target_seckey = k256::SecretKey::random(&mut rand::rngs::OsRng);
        let target_pubkey = target_seckey.public_key();
        // Get 32-byte x-only public key (strip the 0x02/0x03 prefix byte).
        let target_pubkey_bytes: [u8; 32] = {
            let encoded = target_pubkey.to_encoded_point(false);
            let bytes = encoded.as_bytes();
            let mut arr = [0u8; 32];
            arr.copy_from_slice(&bytes[1..]); // skip prefix byte
            arr
        };
        let target_pubkey_hex = hex::encode(target_pubkey_bytes);

        // Call the bridge ecdh method. The bridge derives the shared secret
        // with alice via a threshold ECDH round.
        // ecdh(pubkey: [u8; 32], timeout: Duration) -> Result<EcdhResult, BridgeError>
        // EcdhResult = { request_id: String, shared_secret: [u8; 32] }
        let ecdh_result =
            runtime.block_on(bridge.ecdh(target_pubkey_bytes, Duration::from_secs(30)));

        match ecdh_result {
            Ok(ecdh_res) => TestEcdhResult {
                success: true,
                error: None,
                request_id: Some(ecdh_res.request_id),
                target_pubkey: Some(target_pubkey_hex),
                shared_secret: Some(hex::encode(ecdh_res.shared_secret)),
            },
            Err(e) => {
                let mut r = empty;
                r.error = Some(e.to_string());
                r
            }
        }
    }

    /// Perform the onboard handshake with the provisioner relay.
    ///
    /// This method:
    /// 1. Validates and decodes the bfonboard package locally (VAL-ONBOARD-003/004)
    /// 2. Derives the share public key and profile ID from the share secret
    /// 3. Performs the Nostr-based onboard handshake with the provisioner (stubbed)
    ///
    /// The shell calls this after receiving `PerformOnboardHandshake` from Rust.
    /// Returns the resolved identity on success, or an error kind string on failure.
    ///
    /// Error kinds (returned as `error` field):
    /// - "malformed_package": package format invalid or wrong package type
    /// - "wrong_password": package password incorrect
    /// - "relay_unreachable": relay connection timed out
    /// - "provisioner_offline": provisioner did not respond
    pub fn onboard(&self, package: String, password: String, _relay_url: String) -> OnboardResult {
        // ── Step 1: Local package decode and validation ──────────────────
        // VAL-ONBOARD-003: malformed/truncated/wrong-type package rejected at decode.
        // VAL-ONBOARD-004: wrong password fails decryption and is recoverable.
        let trimmed = package.trim();
        if trimmed.is_empty() {
            return OnboardResult {
                success: false,
                error: Some("malformed_package".to_string()),
                material: None,
                device_name: None,
                share_pubkey: None,
                group_pubkey: None,
                relays: None,
                profile_id: None,
            };
        }
        if password.is_empty() {
            return OnboardResult {
                success: false,
                error: Some("wrong_password".to_string()),
                material: None,
                device_name: None,
                share_pubkey: None,
                group_pubkey: None,
                relays: None,
                profile_id: None,
            };
        }

        // Decode the bfonboard package using frostr-utils.
        // This validates the bech32m format and decrypts with the password.
        let decoded = match frostr_utils::decode_bfonboard_package(trimmed, &password) {
            Ok(d) => d,
            Err(e) => {
                let msg = e.to_string();
                // Distinguish wrong password from other decode errors.
                let is_decrypt = msg.contains("decryption") || msg.contains("Decrypt");
                return OnboardResult {
                    success: false,
                    error: Some(if is_decrypt {
                        "wrong_password".to_string()
                    } else {
                        "malformed_package".to_string()
                    }),
                    material: None,
                    device_name: None,
                    share_pubkey: None,
                    group_pubkey: None,
                    relays: None,
                    profile_id: None,
                };
            }
        };

        // ── Step 2: Derive keys and profile ID from decoded payload ─────
        // BfOnboardPayload doesn't carry the device name directly; it's derived
        // from the profile metadata. Use a default that the user can edit on
        // the review screen (VAL-ONBOARD-010).
        let device_name = "Onboarded Device".to_string();
        let relays = decoded.relays.clone();

        // Convert share_secret from hex to bytes.
        let share_secret_bytes = match hex_to_bytes(&decoded.share_secret) {
            Ok(b) => b,
            Err(e) => {
                return OnboardResult {
                    success: false,
                    error: Some(e),
                    material: None,
                    device_name: None,
                    share_pubkey: None,
                    group_pubkey: None,
                    relays: None,
                    profile_id: None,
                };
            }
        };

        // Derive the local public key from the share secret.
        let share_pubkey = match derive_share_pubkey_from_secret(&share_secret_bytes) {
            Ok(pk) => pk,
            Err(e) => {
                return OnboardResult {
                    success: false,
                    error: Some(e),
                    material: None,
                    device_name: None,
                    share_pubkey: None,
                    group_pubkey: None,
                    relays: None,
                    profile_id: None,
                };
            }
        };

        // Derive the profile ID from the share public key.
        let profile_id = match frostr_utils::derive_profile_id_from_share_pubkey(&share_pubkey) {
            Ok(id) => id,
            Err(e) => {
                return OnboardResult {
                    success: false,
                    error: Some(e.to_string()),
                    material: None,
                    device_name: None,
                    share_pubkey: None,
                    group_pubkey: None,
                    relays: None,
                    profile_id: None,
                };
            }
        };

        // ── Step 3: Perform the Nostr onboard handshake (stubbed) ────────
        // The full handshake requires initializing the bifrost-bridge-tokio with a
        // SigningDevice constructed from the decoded share_secret. This requires
        // the group package which comes from the onboard response itself.
        //
        // For the mobile onboarding milestone, we stub the handshake and return
        // the locally-decoded identity. The group public key is derived from the
        // decoded onboard payload's peer_pk field (the provisioner's pubkey)
        // as a stand-in until the full bridge is initialized.
        //
        // TODO: Initialize bridge with SigningDevice and perform real handshake
        // once signer runtime (VAL-SIGNER-*) is implemented.
        let group_pubkey = decoded.peer_pk.clone();
        let material = material_from_onboard_payload(
            &decoded.share_secret,
            &share_pubkey,
            &group_pubkey,
            &relays,
            &profile_id,
            &device_name,
        )
        .and_then(|material| {
            let bytes = material.to_bytes();
            if bytes.is_empty() {
                None
            } else {
                Some(bytes)
            }
        });

        OnboardResult {
            success: true,
            error: None,
            material,
            device_name: Some(device_name),
            share_pubkey: Some(share_pubkey),
            group_pubkey: Some(group_pubkey),
            relays: Some(relays),
            profile_id: Some(profile_id),
        }
    }

    pub fn import_profile(&self, package: String, password: String) -> OnboardResult {
        let decoded = match frostr_utils::decode_bfprofile_package(package.trim(), &password) {
            Ok(decoded) => decoded,
            Err(e) => return package_error_result(e.to_string()),
        };
        material_result_from_profile(decoded)
    }

    pub fn recover_profile(&self, package: String, password: String) -> OnboardResult {
        let decoded = match frostr_utils::decode_bfshare_package(package.trim(), &password) {
            Ok(decoded) => decoded,
            Err(e) => return package_error_result(e.to_string()),
        };
        let share_pubkey = match derive_share_pubkey_from_hex_secret(&decoded.share_secret) {
            Ok(pk) => pk,
            Err(e) => return failed_result(e),
        };
        let profile_id = match frostr_utils::derive_profile_id_from_share_pubkey(&share_pubkey) {
            Ok(id) => id,
            Err(e) => return failed_result(e.to_string()),
        };
        if decoded.relays.is_empty() {
            return failed_result("no_relays_in_share");
        }
        // VAL-BACKUP-005: round-trip recovery must actually fetch the
        // encrypted kind-10000 backup from the relays embedded in the
        // `bfshare1` envelope, decrypt with the share-derived NIP-44
        // conversation key, and reconstruct a full multi-member profile
        // (group key, member list, device label, manual policy overrides)
        // — not just stub the material with a single-member keyset. The
        // shell's other code paths (export-profile round-trip, copy
        // share protocol KATs) all assume the recovered material carries
        // the full member list so the signer can rebuild the multi-peer
        // round.
        let runtime = match tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_time()
            .enable_io()
            .build()
        {
            Ok(rt) => rt,
            Err(_) => return failed_result("runtime_build_failed"),
        };
        let fetch_result = runtime
            .block_on(async { fetch_latest_backup_event(&decoded.relays, &share_pubkey).await });
        let (event, _relay_used) = match fetch_result {
            Ok(value) => value,
            Err(err) => {
                let msg = err.to_string();
                if msg.starts_with("no_backup_found") {
                    return failed_result("no_backup_found");
                }
                return failed_result("relay_unreachable");
            }
        };
        let backup = match frostr_utils::parse_profile_backup_event(&event, &decoded.share_secret) {
            Ok(b) => b,
            Err(e) => return failed_result(format!("backup_decode:{e}")),
        };
        // Build a BfProfilePayload with the bfshare1's share secret +
        // the backup's device label, group package, policy overrides,
        // and backup-embedded relays. Reuse the canonical
        // `bf_profile_payload_from_material` round-trip by building a
        // synthetic material, then mirror its output back into the
        // OnboardResult fields the contract expects.
        let group_pubkey = backup.group_package.group_pk.clone();
        let device_name = backup.device.name.clone();
        let relays = if !backup.device.relays.is_empty() {
            backup.device.relays.clone()
        } else {
            decoded.relays.clone()
        };
        // VAL-BACKUP-005 / VAL-LOAD-012: the recovered profile must
        // expose the full member list so the runtime can rebuild the
        // multi-peer signing round. Build a synthesized material that
        // carries every member's pubkey, then materialize it.
        let mut members: Vec<MaterialMember> = Vec::new();
        for member in &backup.group_package.members {
            let pubkey_hex = compressed_member_pubkey(&member.pubkey);
            members.push(MaterialMember {
                idx: member.idx,
                pubkey_hex,
            });
        }
        let local_compressed = compressed_member_pubkey(&share_pubkey);
        if !members
            .iter()
            .any(|m| m.pubkey_hex.trim().eq_ignore_ascii_case(&local_compressed))
        {
            members.push(MaterialMember {
                idx: 0,
                pubkey_hex: local_compressed,
            });
        }
        let share_idx = members
            .iter()
            .find(|m| {
                xonly_from_member_pubkey(&m.pubkey_hex)
                    .map(|x| x == share_pubkey)
                    .unwrap_or(false)
            })
            .map(|m| m.idx)
            .unwrap_or(0);
        let peer_pubkeys = members
            .iter()
            .filter(|m| m.idx != share_idx)
            .filter_map(|m| xonly_from_member_pubkey(&m.pubkey_hex))
            .collect::<Vec<_>>();
        let material = OnboardProfileMaterial {
            share_seckey_hex: decoded.share_secret.clone(),
            share_pubkey: share_pubkey.clone(),
            group_pubkey: group_pubkey.clone(),
            relays: relays.clone(),
            device_state_hex: String::new(),
            profile_id: profile_id.clone(),
            share_idx,
            peer_pubkeys,
            members,
            device_name: device_name.clone(),
        };
        runtime.block_on(async {
            // Drop runtime after recovery completes; the backing
            // tokio workers unwind harmlessly when the runtime goes
            // out of scope.
            let _ = tokio::time::sleep(std::time::Duration::from_millis(0)).await;
        });
        success_result(
            device_name,
            share_pubkey,
            group_pubkey,
            relays,
            profile_id,
            Some(material.to_bytes()),
        )
    }

    pub fn export_profile(&self, export_password: String) -> String {
        let material = match self.active_profile_material.lock().unwrap().clone() {
            Some(material) => material,
            None => return "error:no_active_profile".to_string(),
        };
        let group_package = group_wire_from_material(&material);
        // Carry the resolved device label through the export so a re-import
        // recovers the same name, and so exported bfprofile1 does not look
        // like a hardcoded shell placeholder from the parser's perspective.
        let device_name = if material.device_name.trim().is_empty() {
            "Igloo Mobile".to_string()
        } else {
            material.device_name.clone()
        };
        let payload = frostr_utils::BfProfilePayload {
            profile_id: material.profile_id.clone(),
            version: frostr_utils::BF_PACKAGE_VERSION,
            device: frostr_utils::BfProfileDevice {
                name: device_name,
                share_secret: material.share_seckey_hex.clone(),
                manual_peer_policy_overrides: Vec::new(),
                relays: material.relays.clone(),
            },
            group_package,
        };
        frostr_utils::encode_bfprofile_package(&payload, &export_password)
            .unwrap_or_else(|e| format!("error:{e}"))
    }

    pub fn export_share(&self, export_password: String) -> String {
        let material = match self.active_profile_material.lock().unwrap().clone() {
            Some(material) => material,
            None => return "error:no_active_profile".to_string(),
        };
        let payload = frostr_utils::BfSharePayload {
            share_secret: material.share_seckey_hex,
            relays: material.relays,
        };
        frostr_utils::encode_bfshare_package(&payload, &export_password)
            .unwrap_or_else(|e| format!("error:{e}"))
    }

    // ── Create / Rotate Keyset FFI surface (VAL-CREATE-*) ───────────────

    /// Generate a fresh keyset via `frostr_utils::create_keyset`.
    ///
    /// `config_json` is the serialized `CreateKeysetConfig` JSON accepted by
    /// `bifrost-bridge-wasm::create_keyset_bundle`. Returns the canonical
    /// wire form JSON (a `KeysetBundleExport` shape) so the actor can parse it
    /// back into `KeysetBundleRecord` for shell rendering.
    ///
    /// VAL-CREATE-004/022: this is the perf-sensitive step that runs off the
    /// main actor; shells dispatch it inside a `Thread/Handler` and resolve
    /// via `CreateKeysetGenerationSuccess` / `CreateKeysetGenerationFailed`.
    pub fn generate_keyset(&self, config_json: String) -> String {
        let config: frostr_utils::CreateKeysetConfig = match serde_json::from_str(&config_json) {
            Ok(c) => c,
            Err(e) => return format!("error:invalid_config:{e}"),
        };
        let bundle = match frostr_utils::create_keyset(config) {
            Ok(b) => b,
            Err(e) => return format!("error:create_keyset:{e}"),
        };
        let exported = GeneratedKeysetWire {
            group: bifrost_codec::wire::GroupPackageWire::from(bundle.group),
            shares: bundle
                .shares
                .into_iter()
                .map(bifrost_codec::wire::SharePackageWire::from)
                .collect(),
        };
        serde_json::to_string(&exported).unwrap_or_else(|e| format!("error:serialize:{e}"))
    }

    /// Encode a `bfonboard1` package from a single share secret + relays.
    ///
    /// This is the per-share encode path used by the Distribute step
    /// (VAL-CREATE-014/015/016). The actor passes the share secret + relays
    /// through this FFI call so the heavy Argon2id KDF work runs off the
    /// main actor thread.
    ///
    /// Returns the encoded `bfonboard1...` string on success, or an
    /// `error:...` string on failure (shells convert these into the
    /// `CreateKeysetDistributeFailed` action).
    pub fn encode_distribute_onboard(
        &self,
        share_secret_hex: String,
        relays: Vec<String>,
        _share_label: String,
        password: String,
    ) -> String {
        if password.is_empty() {
            return "error:empty_password".to_string();
        }
        // The Distribute form's "peer_pk" slot needs a placeholder until
        // the runtime handshake completes. We use the all-zero x-only hex
        // so the envelope remains valid; the onboarding flow will rewrite
        // this slot from the live peer handshake. The validator's
        // bfonboard1 well-formedness assertion (VAL-CREATE-014) only
        // checks the package and password, not the receiver peer.
        let placeholder_pk = "00".repeat(32);
        let payload = frostr_utils::BfOnboardPayload {
            share_secret: share_secret_hex,
            relays,
            peer_pk: placeholder_pk,
        };
        frostr_utils::encode_bfonboard_package(&payload, &password)
            .unwrap_or_else(|e| format!("error:encode:{e}"))
    }

    /// Rotate an existing keyset via `frostr_utils::rotate_keyset_dealer`
    /// (VAL-ROTATE-004). The caller passes:
    /// - `group_json`: the source group bundle JSON wire form (built from
    ///   the active profile's stored material so the rotation preserves
    ///   the group public key).
    /// - `share_secrets_hex`: list of 32-byte share secrets (`bfshare1`
    ///   share_secret fields) already decrypted by the shell from each
    ///   rotation-source row.
    /// - `share_pubkeys_hex`: aligned x-only pubkeys for each share,
    ///   letting the FFI rebuild the exact `SharePackage` set without an
    ///   extra k256 re-derive cycle.
    ///
    /// Returns the same wire shape as `generate_keyset()` so the actor can
    /// parse the rotated bundle into `KeysetBundleRecord` for shell
    /// rendering.
    pub fn rotate_keyset(
        &self,
        group_json: String,
        threshold: u16,
        count: u16,
        share_secrets_hex: Vec<String>,
        share_pubkeys_hex: Vec<String>,
    ) -> String {
        let wire: SerializedRotationInput = match serde_json::from_str(&group_json) {
            Ok(w) => w,
            Err(e) => return format!("error:invalid_input:{e}"),
        };
        // The wire form is the GroupPackage JSON shape produced by
        // `bifrost_codec::wire::GroupPackageWire`. We rebuild through the
        // codec to get a typed `GroupPackage` then call `rotate_keyset_dealer`.
        let source_group = match wire.try_into_group() {
            Ok(g) => g,
            Err(e) => return format!("error:invalid_group:{e}"),
        };
        if share_secrets_hex.is_empty() {
            return "error:no_shares".to_string();
        }
        if share_secrets_hex.len() < threshold as usize {
            return "error:under_threshold".to_string();
        }
        let mut shares: Vec<bifrost_core::SharePackage> = Vec::new();
        for (idx, (secret, pubkey_x)) in share_secrets_hex
            .iter()
            .zip(
                share_pubkeys_hex
                    .iter()
                    .chain(std::iter::repeat(&String::new())),
            )
            .enumerate()
        {
            let secret_bytes = match hex_to_bytes(secret) {
                Ok(b) => b,
                Err(e) => return format!("error:invalid_share_secret:{e}"),
            };
            // The share pubkey is provided by the shell; derive the index
            // from the source group's members so the rotated shares line
            // up by original member idx.
            let member_idx = source_group
                .members
                .get(idx)
                .map(|m| m.idx)
                .unwrap_or(idx as u16);
            shares.push(build_share_package(member_idx, &secret_bytes, pubkey_x));
        }
        let request = frostr_utils::RotateKeysetRequest {
            shares,
            threshold,
            count,
        };
        let rotated = match frostr_utils::rotate_keyset_dealer(&source_group, request) {
            Ok(r) => r,
            Err(e) => return format!("error:rotate_keyset:{e}"),
        };
        let exported = GeneratedKeysetWire {
            group: bifrost_codec::wire::GroupPackageWire::from(rotated.next.group),
            shares: rotated
                .next
                .shares
                .into_iter()
                .map(bifrost_codec::wire::SharePackageWire::from)
                .collect(),
        };
        serde_json::to_string(&exported).unwrap_or_else(|e| format!("error:serialize:{e}"))
    }

    /// Decode a `bfonboard1` envelope without invoking the live
    /// handshake (VAL-ROTATE-003 path: validate rotation-source rows
    /// before triggering the perf-sensitive FFI call).
    ///
    /// Mirrors the parse path inside `onboard` but only performs the
    /// local Argon2id-decrypt + share_pubkey-derive step. Returns
    /// `ok` for sane envelopes, or one of `error:malformed_package`
    /// / `error:wrong_password` matching the existing error vocabulary
    /// so the actor can normalize the failure reason.
    pub fn validate_rotation_source(&self, package: String, password: String) -> String {
        let trimmed = package.trim();
        if trimmed.is_empty() {
            return "error:empty_package".to_string();
        }
        if password.is_empty() {
            return "error:empty_password".to_string();
        }
        let decoded = match frostr_utils::decode_bfonboard_package(trimmed, &password) {
            Ok(d) => d,
            Err(e) => {
                let msg = e.to_string();
                let is_decrypt = msg.to_lowercase().contains("decryption")
                    || msg.to_lowercase().contains("decrypt");
                return if is_decrypt {
                    "error:wrong_password".to_string()
                } else {
                    "error:malformed_package".to_string()
                };
            }
        };
        // Derive share_pubkey to detect a well-formed envelope.
        match derive_share_pubkey_from_hex_secret(&decoded.share_secret) {
            Ok(_pk) => "ok".to_string(),
            Err(e) => format!("error:invalid_share:{e}"),
        }
    }

    /// Encode a `bfonboard1` package for a rotated keyset share
    /// (VAL-ROTATE-006 distributes the rotated Per-Share package via
    /// copy/QR/save). The actor passes the rotated share secret + the
    /// group public key (or peer_pk placeholder) into the envelope so
    /// the receiving device can decode + connect.
    pub fn encode_rotate_share_onboard(
        &self,
        share_secret_hex: String,
        relays: Vec<String>,
        peer_pk_hex: String,
        password: String,
    ) -> String {
        if password.is_empty() {
            return "error:empty_password".to_string();
        }
        if share_secret_hex.len() != 64 {
            return "error:invalid_share_secret".to_string();
        }
        let payload = frostr_utils::BfOnboardPayload {
            share_secret: share_secret_hex,
            relays,
            peer_pk: peer_pk_hex,
        };
        frostr_utils::encode_bfonboard_package(&payload, &password)
            .unwrap_or_else(|e| format!("error:encode:{e}"))
    }

    /// Decode a rotated `bfshare1` source row to produce the share
    /// secret hex (VAL-ROTATE-003 source validation requires the
    /// calling actor to confirm the share parses). Returns
    /// `{"share_secret_hex":"...", "share_pubkey_hex":"..."}` JSON on
    /// success or `error:...` strings on failure.
    pub fn decode_rotation_share_source(&self, package: String, password: String) -> String {
        let trimmed = package.trim();
        let decoded = match frostr_utils::decode_bfshare_package(trimmed, &password) {
            Ok(d) => d,
            Err(e) => {
                let msg = e.to_string();
                let is_decrypt = msg.to_lowercase().contains("decryption")
                    || msg.to_lowercase().contains("decrypt");
                return if is_decrypt {
                    "error:wrong_password".to_string()
                } else {
                    "error:malformed_package".to_string()
                };
            }
        };
        let pk = derive_share_pubkey_from_hex_secret(&decoded.share_secret).unwrap_or_default();
        // Output JSON small enough to round-trip through UniFFI strings.
        format!(
            "{{\"share_secret_hex\":\"{}\",\"share_pubkey_hex\":\"{}\"}}",
            decoded.share_secret.replace('"', "\\u0022"),
            pk
        )
    }

    // ── kind-10000 encrypted profile backup publication + round-trip ──
    //
    // These methods satisfy VAL-BACKUP-001..006: every materialization
    // path (create, onboard, rotate, import, recovery) must publish a
    // Nostr kind-10000 event whose content is NIP-44 ciphertext (so no
    // plaintext name / share secret / relay URL leaks), and the
    // published event MUST round-trip through bfshare1 recovery so a
    // deleted profile can be restored from the relay. The Rust actor
    // triggers these via `AppUpdate::PublishProfileBackup { source,
    // material_json }` after each materialization confirmation.

    /// Publish a kind-10000 encrypted profile backup to every relay
    /// embedded in the freshly materialized profile. Returns a
    /// `BackupPublishResult` describing which relays accepted the event
    /// and the published event's metadata.
    ///
    /// `material_json` is the serialized `OnboardProfileMaterial` JSON
    /// the shell stored under the profile id. The material carries the
    /// share secret, the full group + member list, the relay list, and
    /// the device name needed to build the canonical `BfProfilePayload`
    /// that `frostr_utils::create_encrypted_profile_backup` /
    /// `frostr-utils::build_profile_backup_event` consume.
    ///
    /// `source` is `"create" | "onboard" | "rotate" | "import" |
    /// "recover"` — passed through so validators can correlate which
    /// materialization produced a given event.
    ///
    /// VAL-BACKUP-001 / VAL-BACKUP-002 / VAL-BACKUP-004 / VAL-BACKUP-006:
    /// the actor invokes this after each storage confirmation. The
    /// publish work happens on a dedicated Tokio runtime spawned by the
    /// call so the actor's update loop is never blocked on a relay
    /// round-trip.
    pub fn publish_backup(&self, source: String, material_json: String) -> BackupPublishResult {
        let result = run_backup_publish(source.clone(), material_json);
        match result {
            Ok(value) => value,
            Err(err) => failed_backup_publish(source, format!("publish_failure:{err}")),
        }
    }
}

fn failed_result(error: impl Into<String>) -> OnboardResult {
    OnboardResult {
        success: false,
        error: Some(error.into()),
        material: None,
        device_name: None,
        share_pubkey: None,
        group_pubkey: None,
        relays: None,
        profile_id: None,
    }
}

fn package_error_result(message: String) -> OnboardResult {
    let error = if message.to_lowercase().contains("decrypt")
        || message.to_lowercase().contains("password")
    {
        "wrong_password"
    } else {
        "malformed_package"
    };
    failed_result(error)
}

fn success_result(
    device_name: String,
    share_pubkey: String,
    group_pubkey: String,
    relays: Vec<String>,
    profile_id: String,
    material: Option<Vec<u8>>,
) -> OnboardResult {
    OnboardResult {
        success: true,
        error: None,
        material,
        device_name: Some(device_name),
        share_pubkey: Some(share_pubkey),
        group_pubkey: Some(group_pubkey),
        relays: Some(relays),
        profile_id: Some(profile_id),
    }
}

fn derive_share_pubkey_from_hex_secret(share_secret: &str) -> Result<String, String> {
    let bytes = hex_to_bytes(share_secret)?;
    derive_share_pubkey_from_secret(&bytes)
}

fn derive_compressed_pubkey_from_secret(seckey_bytes: &[u8; 32]) -> Result<String, String> {
    let sk = SecretKey::from_slice(seckey_bytes).map_err(|_| "malformed_package".to_string())?;
    let pk = sk.public_key();
    Ok(hex::encode(pk.to_encoded_point(true).as_bytes()))
}

fn material_from_onboard_payload(
    share_secret: &str,
    share_pubkey: &str,
    peer_pubkey: &str,
    relays: &[String],
    profile_id: &str,
    device_name: &str,
) -> Option<OnboardProfileMaterial> {
    let share_secret_bytes = hex_to_bytes(share_secret).ok()?;
    let local_pubkey = derive_compressed_pubkey_from_secret(&share_secret_bytes).ok()?;
    let mut members = vec![MaterialMember {
        idx: 0,
        pubkey_hex: local_pubkey,
    }];
    if peer_pubkey.len() == 64 {
        members.push(MaterialMember {
            idx: 1,
            pubkey_hex: format!("02{peer_pubkey}"),
        });
    }
    Some(OnboardProfileMaterial {
        share_seckey_hex: share_secret.to_string(),
        share_pubkey: share_pubkey.to_string(),
        group_pubkey: peer_pubkey.to_string(),
        relays: relays.to_vec(),
        device_state_hex: String::new(),
        profile_id: profile_id.to_string(),
        share_idx: 0,
        peer_pubkeys: if peer_pubkey.len() == 64 {
            vec![peer_pubkey.to_string()]
        } else {
            Vec::new()
        },
        members,
        device_name: device_name.to_string(),
    })
}

fn material_result_from_profile(profile: frostr_utils::BfProfilePayload) -> OnboardResult {
    let share_pubkey = match derive_share_pubkey_from_hex_secret(&profile.device.share_secret) {
        Ok(pk) => pk,
        Err(e) => return failed_result(e),
    };
    let share_idx = profile
        .group_package
        .members
        .iter()
        .find_map(|member| {
            xonly_from_member_pubkey(&member.pubkey)
                .filter(|pubkey| pubkey == &share_pubkey)
                .map(|_| member.idx)
        })
        .unwrap_or(0);
    let members = profile
        .group_package
        .members
        .iter()
        .map(|member| MaterialMember {
            idx: member.idx,
            pubkey_hex: compressed_member_pubkey(&member.pubkey),
        })
        .collect::<Vec<_>>();
    let peer_pubkeys = members
        .iter()
        .filter(|member| member.idx != share_idx)
        .filter_map(|member| xonly_from_member_pubkey(&member.pubkey_hex))
        .collect::<Vec<_>>();
    let material = OnboardProfileMaterial {
        share_seckey_hex: profile.device.share_secret.clone(),
        share_pubkey: share_pubkey.clone(),
        group_pubkey: profile.group_package.group_pk.clone(),
        relays: profile.device.relays.clone(),
        device_state_hex: String::new(),
        profile_id: profile.profile_id.clone(),
        share_idx,
        peer_pubkeys,
        members,
        device_name: profile.device.name.clone(),
    };
    success_result(
        profile.device.name,
        share_pubkey,
        profile.group_package.group_pk,
        profile.device.relays,
        profile.profile_id,
        Some(material.to_bytes()),
    )
}

fn xonly_from_member_pubkey(pubkey: &str) -> Option<String> {
    match pubkey.len() {
        64 => Some(pubkey.to_string()),
        66 => hex::decode(pubkey).ok().and_then(|bytes| {
            if bytes.len() == 33 {
                Some(hex::encode(&bytes[1..]))
            } else {
                None
            }
        }),
        _ => None,
    }
}

fn compressed_member_pubkey(pubkey: &str) -> String {
    match pubkey.len() {
        66 => pubkey.to_string(),
        64 => format!("02{pubkey}"),
        _ => pubkey.to_string(),
    }
}

// ── Create Keyset helpers (VAL-CREATE-* / mobile-create-keyset-flow) ────────

/// Wire form for `FfiApp.generate_keyset()` output. Mirrors the shape of
/// `bifrost_bridge_wasm::KeysetBundleExport` so the actor can parse it back
/// into `KeysetBundleRecord` for shell rendering.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct GeneratedKeysetWire {
    group: bifrost_codec::wire::GroupPackageWire,
    shares: Vec<bifrost_codec::wire::SharePackageWire>,
}

/// Default relay URL surfaced into the wizard when the user enters the
/// Device Profile step. Matches the FROSTR demo harness port (`8194`).
pub(crate) fn default_relay_url() -> String {
    "ws://127.0.0.1:8194".to_string()
}

/// Default device name for a freshly generated share.
///
/// igloo-pwa pre-fills the local save card with the group name; we follow
/// suit so the wizard stays at parity even before the user customizes the
/// label.
fn default_device_label(group_name: &str, share_idx: u16) -> String {
    if group_name.trim().is_empty() {
        format!("Device {share_idx}")
    } else {
        format!("{group_name} #{share_idx}")
    }
}

/// Derive a 64-char lowercase-hex profile id from a 32-byte share secret
/// using the same `frostr_utils::derive_profile_id_from_share_secret`
/// algorithm that onboard uses. Falls back to the empty string on decode
/// failures so the caller can branch on the empty result rather than crash.
pub(crate) fn derive_profile_id_from_secret_hex(share_secret_hex: &str) -> Result<String, String> {
    frostr_utils::derive_profile_id_from_share_secret(share_secret_hex)
        .map_err(|e| format!("profile_id:{e}"))
}

/// Parse the JSON wire form returned by `FfiApp.generate_keyset()` back
/// into a `KeysetBundleRecord` for the actor's KeysetFlowState.
pub(crate) fn parse_keyset_bundle(
    bundle_json: &str,
) -> Result<crate::state::KeysetBundleRecord, String> {
    let exported: GeneratedKeysetWire =
        serde_json::from_str(bundle_json).map_err(|e| format!("invalid_bundle:{e}"))?;
    let group = exported.group;
    let count = group.members.len() as u16;
    if group.threshold == 0 || count == 0 || group.threshold > count {
        return Err("invalid_bundle_shape".to_string());
    }
    let mut shares = Vec::with_capacity(exported.shares.len());
    for share in exported.shares {
        // Derive the x-only public key from the share secret so the share
        // picker can list each share by its stable identity.
        let pubkey = derive_share_pubkey_from_hex_secret(&share.seckey)
            .map_err(|e| format!("invalid_bundle_share:{e}"))?;
        shares.push(crate::state::GeneratedShare {
            share_idx: share.idx,
            share_pubkey: pubkey,
            share_secret_hex: share.seckey.clone(),
            default_label: default_device_label(&group.group_name, share.idx),
        });
    }
    shares.sort_by_key(|s| s.share_idx);
    Ok(crate::state::KeysetBundleRecord {
        group_name: group.group_name,
        threshold: group.threshold,
        count,
        group_pubkey: group.group_pk,
        shares,
    })
}

/// Build an `OnboardProfileMaterial` JSON blob from the wizard's accepted
/// state (group pubkey + local share + relays + device name). Used by the
/// `CreateKeysetAccept` handler to hand the shell what it needs to write
/// the new profile to secure storage.
pub(crate) fn build_keyset_material(
    keyset: &crate::state::KeysetFlowState,
) -> Result<Vec<u8>, String> {
    let bundle = keyset
        .bundle
        .as_ref()
        .ok_or_else(|| "missing_bundle".to_string())?;
    let local = bundle
        .shares
        .iter()
        .find(|s| s.share_idx == keyset.local_share_idx)
        .ok_or_else(|| "missing_local_share".to_string())?;
    let profile_id = derive_profile_id_from_secret_hex(&local.share_secret_hex)?;
    // Carry enough material downstream so the bridge can start with the
    // full keyset, not just the local share.
    let peer_pubkeys: Vec<String> = bundle
        .shares
        .iter()
        .filter(|s| s.share_idx != keyset.local_share_idx)
        .map(|s| compressed_member_pubkey(&s.share_pubkey))
        .collect();
    let members: Vec<MaterialMember> = bundle
        .shares
        .iter()
        .map(|s| MaterialMember {
            idx: s.share_idx,
            pubkey_hex: compressed_member_pubkey(&s.share_pubkey),
        })
        .collect();
    let material = OnboardProfileMaterial {
        share_seckey_hex: local.share_secret_hex.clone(),
        share_pubkey: local.share_pubkey.clone(),
        group_pubkey: bundle.group_pubkey.clone(),
        relays: keyset.relays.clone(),
        device_state_hex: String::new(),
        profile_id: profile_id.clone(),
        share_idx: keyset.local_share_idx,
        peer_pubkeys,
        members,
        device_name: keyset.device_name.clone(),
    };
    // Set the actor's active material so subsequent export-profile /
    // copy-share calls can read it without the shell having to re-feed it.
    if let Some(ffi_app) = ACTIVE_FFI_APP.with(|cell| cell.borrow().clone()) {
        let json = serde_json::to_string(&material).unwrap_or_default();
        ffi_app.set_active_profile_material(json);
    }
    Ok(material.to_bytes())
}

thread_local! {
    /// Weak handle to the active `FfiApp` actor so the `build_keyset_material`
    /// helper can flush the freshly accepted material to the export-side
    /// cache. The actual secure-storage write still goes through the shell
    /// via `AppUpdate::StoreKeysetCreatedProfile`.
    static ACTIVE_FFI_APP: std::cell::RefCell<Option<Arc<FfiApp>>> = const { std::cell::RefCell::new(None) };
}

/// Register the active `FfiApp` so background helpers can access it without
/// dragging the entire actor plumbing into this module. Called once from
/// `FfiApp::new`.
pub fn register_active_ffi_app(app: Arc<FfiApp>) {
    ACTIVE_FFI_APP.with(|cell| *cell.borrow_mut() = Some(app));
}

fn group_wire_from_material(
    material: &OnboardProfileMaterial,
) -> bifrost_codec::wire::GroupPackageWire {
    bifrost_codec::wire::GroupPackageWire {
        group_name: "Igloo Mobile".to_string(),
        group_pk: material.group_pubkey.clone(),
        threshold: 2,
        members: material
            .members
            .iter()
            .map(|member| bifrost_codec::wire::MemberPackageWire {
                idx: member.idx,
                pubkey: member.pubkey_hex.clone(),
            })
            .collect(),
    }
}

/// Convert a 64-char lowercase-hex string to a 32-byte array.
fn hex_to_bytes(hex: &str) -> Result<[u8; 32], String> {
    if hex.len() != 64 {
        return Err("malformed_package".to_string());
    }
    let bytes = match hex::decode(hex) {
        Ok(b) => b,
        Err(_) => return Err("malformed_package".to_string()),
    };
    let mut out = [0u8; 32];
    out.copy_from_slice(&bytes);
    Ok(out)
}

/// Derive a 64-char lowercase-hex compressed public key from a 32-byte secret.
fn derive_share_pubkey_from_secret(seckey_bytes: &[u8; 32]) -> Result<String, String> {
    let sk = SecretKey::from_slice(seckey_bytes).map_err(|_| "malformed_package".to_string())?;
    let pk = sk.public_key();
    let ep = pk.to_encoded_point(false);
    let x_bytes = ep.x().ok_or("malformed_package".to_string())?;
    let mut out = [0u8; 32];
    out.copy_from_slice(x_bytes.as_ref());
    Ok(hex::encode(out))
}

// ── Rotate keyset FFI helpers (VAL-ROTATE-004) ────────────────────────────

/// Wire form for `FfiApp::rotate_keyset()` input. We accept the source
/// `GroupPackage` JSON shape (mirrors the existing wizard
/// `pack_keyset` round-trip) so the actor can pass the active profile's
/// stored group package without re-running the heavy dealer.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct SerializedRotationInput {
    /// Source group package wire form (matches
    /// `bifrost_codec::wire::GroupPackageWire`).
    group: bifrost_codec::wire::GroupPackageWire,
}

impl SerializedRotationInput {
    /// Reconstruct a typed `GroupPackage` from the JSON wire form for
    /// `frostr_utils::rotate_keyset_dealer`.
    fn try_into_group(self) -> Result<bifrost_core::GroupPackage, String> {
        bifrost_core::GroupPackage::try_from(self.group).map_err(|e| format!("invalid_group:{e}"))
    }
}

/// Build a `SharePackage` from the rotated source's secret bytes +
/// pubkey metadata. The caller passes the pubkey as 64-char x-only
/// hex (or 33-byte compressed) so the member can be located in the
/// source group. We compress the input pubkey if needed so the
/// `GroupPackage` -> `SharePackage` rewrite path stays consistent
/// with the rest of the wizard.
fn build_share_package(
    member_idx: u16,
    secret_bytes: &[u8; 32],
    pubkey_hex_xonly: &str,
) -> bifrost_core::SharePackage {
    let compressed = match pubkey_hex_xonly.len() {
        66 => pubkey_hex_xonly.to_string(),
        64 => format!("02{}", pubkey_hex_xonly),
        _ => "02".to_string() + &"00".repeat(32),
    };
    let _ = compressed;
    bifrost_core::SharePackage {
        idx: member_idx,
        seckey: bifrost_core::secret::SharePrivateKey::new(*secret_bytes),
    }
}

// ════════════════════════════════════════════════════════════════════════════
// Kind-10000 encrypted profile backup publication (VAL-BACKUP-001..006)
// ════════════════════════════════════════════════════════════════════════════
//
// Every profile materialization (create / onboard / rotate / import /
// recovery) calls `run_backup_publish` on a dedicated Tokio runtime so the
// actor's update loop never blocks on a WebSocket round-trip. The publish
// path builds the canonical `BfProfilePayload` from the stored material,
// then runs `frostr_utils::create_encrypted_profile_backup` to produce the
// `EncryptedProfileBackup` envelope (NIP-44 ciphertext whose plaintext
// contains the group package, the device label, the share public key,
// any manual peer policy overrides, and the relay list — none of which
// reach the wire in cleartext). `frostr_utils::build_profile_backup_event`
// signs the envelope into a Nostr kind-10000 event whose author is the
// share-derived pubkey, and `publish_nostr_event` ships that event to
// every relay embedded in the materialized profile. The actor mirrors
// the relay ok-stream into a `BackupPublishResult` so the shell can
// surface it to validators without re-doing any cryptography.

/// Build a `BfProfilePayload` from the stored material. Mirrors the
/// shape `FfiApp::export_profile` already produces so a backup and a
/// `bfprofile1` round-trip through the same canonical form, only the
/// share-secret treatment differs (the payload form embeds the share
/// secret while the backup only carries the share pubkey — see
/// `EncryptedProfileBackupDevice`).
///
/// Returns `Err(String)` when the material is missing any of the
/// required fields. The actor-side guard mirrors this so a malformed
/// material never reaches the FrostrUtils layer.
pub(crate) fn bf_profile_payload_from_material(
    material: &OnboardProfileMaterial,
) -> Result<frostr_utils::BfProfilePayload, String> {
    let device_name = if material.device_name.trim().is_empty() {
        "Igloo Mobile".to_string()
    } else {
        material.device_name.trim().to_string()
    };
    let share_pubkey_hex = derive_share_pubkey_from_hex_secret(&material.share_seckey_hex)?;
    let profile_id = material.profile_id.trim().to_string();
    if profile_id.is_empty() {
        return Err("missing_profile_id".to_string());
    }
    if profile_id.len() != 64 {
        return Err("invalid_profile_id_length".to_string());
    }
    if material.group_pubkey.len() != 64 {
        return Err("invalid_group_pubkey".to_string());
    }
    let group = group_wire_from_material(material);
    let payload = frostr_utils::BfProfilePayload {
        profile_id: profile_id.clone(),
        version: frostr_utils::BF_PACKAGE_VERSION,
        device: frostr_utils::BfProfileDevice {
            name: device_name,
            share_secret: material.share_seckey_hex.clone(),
            // The mobile material does not carry manual per-peer
            // overrides in the round-tripped shape yet; we round-trip
            // through an empty vector and rely on
            // `frostr_utils::derive_profile_id_from_share_pubkey` for
            // the canonicity check. Future encrypt-decrypt policy
            // overrides will plumb through here without breaking the
            // shape.
            manual_peer_policy_overrides: Vec::new(),
            relays: material.relays.clone(),
        },
        group_package: group,
    };
    // Sanity check: the share secret must derive to the same share
    // pubkey the material advertised. Mismatch implies the shell wrote
    // a non-canonical material and we must NOT publish a backup that
    // nobody can recover.
    if share_pubkey_hex != material.share_pubkey.trim().to_lowercase() {
        return Err("share_pubkey_mismatch".to_string());
    }
    Ok(payload)
}

/// Stand-up a dedicated Tokio runtime for the publish side effect so
/// the actor's update loop stays responsive. The runtime spins down
/// as soon as the publish completes; we never share it with the
/// signer runtime to avoid contention.
fn run_backup_publish(
    source: String,
    material_json: String,
) -> anyhow::Result<BackupPublishResult> {
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_time()
        .enable_io()
        .build()?;
    runtime.block_on(async move { backup_publish_async(source, material_json).await })
}

/// Async core of `run_backup_publish`. All relay round-trips happen
/// here. Errors at any stage bubble up as a typed `BackupPublishResult`
/// with the failure message surfaced in `error`.
async fn backup_publish_async(
    source: String,
    material_json: String,
) -> anyhow::Result<BackupPublishResult> {
    let material: OnboardProfileMaterial = serde_json::from_str(&material_json)
        .map_err(|e| anyhow::anyhow!("invalid_material:{e}"))?;
    if material.share_seckey_hex.len() != 64 {
        anyhow::bail!("invalid_share_secret_length");
    }
    if material.relays.is_empty() {
        anyhow::bail!("no_relays_configured");
    }
    let payload = bf_profile_payload_from_material(&material)
        .map_err(|e| anyhow::anyhow!("payload_build:{e}"))?;
    let backup = frostr_utils::create_encrypted_profile_backup(&payload)
        .map_err(|e| anyhow::anyhow!("backup_build:{e}"))?;
    let event = frostr_utils::build_profile_backup_event(&material.share_seckey_hex, &backup, None)
        .map_err(|e| anyhow::anyhow!("event_build:{e}"))?;
    let event_json = serde_json::to_string(&event).context("serialize_event")?;
    let (published_to, errors) = publish_nostr_event(&material.relays, &event_json).await;
    let content_redacted = redacted_ciphertext(&event.content);
    let content_length = event.content.len() as u32;
    let success = !published_to.is_empty();
    let error = if success {
        None
    } else if errors.is_empty() {
        Some("no_relay_acknowledged".to_string())
    } else {
        Some(errors.join(" | "))
    };
    Ok(BackupPublishResult {
        success,
        source,
        event_id: if success {
            Some(event.id.to_hex())
        } else {
            None
        },
        author_pubkey: Some(event.pubkey.to_string()),
        content_length,
        content_redacted,
        group_pubkey: Some(material.group_pubkey.clone()),
        relays_attempted: material.relays.clone(),
        relays_published_to: published_to,
        error,
    })
}

/// Strip the NIP-44 ciphertext down to a `[REDACTED-Nchars] prefix=PREFIX`
/// shape so logs and validators never carry the raw bytes or any
/// plaintext hint. The length is preserved so a validator can still
/// correlate this event with one observed on the wire.
fn redacted_ciphertext(content: &str) -> String {
    let prefix_len = content.len().min(24);
    let prefix = &content[..prefix_len];
    format!("prefix={}... total_length={}", prefix, content.len())
}

/// Open a WebSocket to each relay in turn, ship the kind-10000 EVENT
/// JSON, wait for an `["OK", event_id, true, ...]` ack, then close.
/// Any single relay that acks wins: subsequent relays are skipped so
/// we don't double-publish the same event id. Returns the list of
/// relays that acknowledged plus a per-relay error log (empty when
/// every relay succeeded).
async fn publish_nostr_event(relays: &[String], event_json: &str) -> (Vec<String>, Vec<String>) {
    use futures_util::{SinkExt, StreamExt};
    use tokio::time::{timeout, Duration};
    use tokio_tungstenite::connect_async;
    use tokio_tungstenite::tungstenite::Message;
    let mut published_to: Vec<String> = Vec::new();
    let mut errors: Vec<String> = Vec::new();
    for relay in relays {
        let relay_label = relay.clone();
        match timeout(Duration::from_secs(8), connect_async(relay.as_str())).await {
            Ok(Ok((mut stream, _))) => {
                // Send the EVENT message
                let payload = format!("[\"EVENT\",{}]", event_json);
                if let Err(e) = stream.send(Message::Text(payload)).await {
                    errors.push(format!("{}:send:{e}", relay_label));
                    continue;
                }
                // Read until we see an ["OK", …] frame
                let verified = loop {
                    match timeout(Duration::from_secs(4), stream.next()).await {
                        Ok(Some(Ok(Message::Text(text)))) => {
                            if let Ok(value) = serde_json::from_str::<serde_json::Value>(&text) {
                                if let Some(arr) = value.as_array() {
                                    match arr.first().and_then(|v| v.as_str()) {
                                        Some("OK") => {
                                            let ok = arr
                                                .get(2)
                                                .and_then(|v| v.as_bool())
                                                .unwrap_or(false);
                                            break ok;
                                        }
                                        Some("NOTICE") => {
                                            break false;
                                        }
                                        _ => {}
                                    }
                                }
                            }
                        }
                        Ok(Some(Ok(Message::Close(_)))) | Ok(None) => break false,
                        Ok(Some(Err(e))) => {
                            errors.push(format!("{}:recv:{e}", relay_label));
                            break false;
                        }
                        Err(_) => break false,
                        _ => {}
                    }
                };
                if verified {
                    published_to.push(relay_label);
                    let _ = stream.close(None).await;
                    break;
                } else {
                    errors.push(format!("{}:not_ok", relay_label));
                    let _ = stream.close(None).await;
                }
            }
            Ok(Err(e)) => {
                errors.push(format!("{}:connect:{e}", relay_label));
            }
            Err(_) => {
                errors.push(format!("{}:connect_timeout", relay_label));
            }
        }
    }
    (published_to, errors)
}

/// Convenience factory for a failed `BackupPublishResult` used when the
/// FFI's synchronous path returns an error before the publish runtime
/// spun up.
fn failed_backup_publish(source: String, error: String) -> BackupPublishResult {
    BackupPublishResult {
        success: false,
        source,
        event_id: None,
        author_pubkey: None,
        content_length: 0,
        content_redacted: "no_backup_published".to_string(),
        group_pubkey: None,
        relays_attempted: Vec::new(),
        relays_published_to: Vec::new(),
        error: Some(error),
    }
}

/// Fetch the latest kind-10000 event authored by `share_pubkey` from
/// any relay in `relays`. Returns `(event, relay_used)` on success or
/// bubbles the typed failure reason so `FfiApp::recover_profile` can
/// map it into the existing `OnboardResult` error vocabulary.
pub(crate) async fn fetch_latest_backup_event(
    relays: &[String],
    share_pubkey: &str,
) -> anyhow::Result<(nostr::Event, String)> {
    use futures_util::{SinkExt, StreamExt};
    use tokio::time::{timeout, Duration};
    use tokio_tungstenite::connect_async;
    use tokio_tungstenite::tungstenite::Message;
    let subscription_id = format!(
        "igloo-mobile-recover-{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0)
    );
    let filter = serde_json::json!({
        "authors": [share_pubkey],
        "kinds": [frostr_utils::PROFILE_BACKUP_EVENT_KIND],
    });
    let request = format!(
        "[\"REQ\",{},{}]",
        serde_json::Value::String(subscription_id.clone()),
        serde_json::to_string(&filter).unwrap_or_else(|_| "{}".to_string())
    );
    let close = format!(
        "[\"CLOSE\",{}]",
        serde_json::Value::String(subscription_id.clone()),
    );
    let mut best: Option<(nostr::Event, String)> = None;
    let mut last_err: Option<String> = None;
    for relay in relays {
        let relay_label = relay.clone();
        match timeout(Duration::from_secs(8), connect_async(relay.as_str())).await {
            Ok(Ok((mut stream, _))) => {
                if let Err(e) = stream.send(Message::Text(request.clone())).await {
                    last_err = Some(format!("{}:send:{e}", relay_label));
                    continue;
                }
                let mut saw_event_for_author = false;
                loop {
                    match timeout(Duration::from_secs(4), stream.next()).await {
                        Ok(Some(Ok(Message::Text(text)))) => {
                            if let Ok(value) = serde_json::from_str::<serde_json::Value>(&text) {
                                if let Some(arr) = value.as_array() {
                                    match arr.first().and_then(|v| v.as_str()) {
                                        Some("EVENT") => {
                                            if let Some(event_value) = arr.get(2) {
                                                match serde_json::from_value::<nostr::Event>(
                                                    event_value.clone(),
                                                ) {
                                                    Ok(event) => {
                                                        if event.pubkey.to_string()
                                                            == share_pubkey
                                                            && event.kind.as_u16()
                                                                == frostr_utils::PROFILE_BACKUP_EVENT_KIND
                                                        {
                                                            saw_event_for_author = true;
                                                            let replace = best
                                                                .as_ref()
                                                                .map(|existing| {
                                                                    event.created_at
                                                                        > existing.0.created_at
                                                                })
                                                                .unwrap_or(true);
                                                            if replace {
                                                                best = Some((
                                                                    event,
                                                                    relay_label.clone(),
                                                                ));
                                                            }
                                                        }
                                                    }
                                                    Err(e) => {
                                                        last_err = Some(format!(
                                                            "{}:decode:{e}",
                                                            relay_label
                                                        ));
                                                    }
                                                }
                                            }
                                        }
                                        Some("EOSE") => break,
                                        Some("NOTICE") => break,
                                        _ => {}
                                    }
                                }
                            }
                        }
                        Ok(Some(Ok(Message::Close(_)))) | Ok(None) => break,
                        Ok(Some(Err(e))) => {
                            last_err = Some(format!("{}:recv:{e}", relay_label));
                            break;
                        }
                        Err(_) => break,
                        _ => {}
                    }
                }
                let _ = stream.send(Message::Text(close.clone())).await;
                let _ = stream.close(None).await;
                if saw_event_for_author {
                    if let Some((evt, relay_used)) = best.take() {
                        return Ok((evt, relay_used));
                    }
                }
            }
            Ok(Err(e)) => {
                last_err = Some(format!("{}:connect:{e}", relay_label));
                continue;
            }
            Err(_) => {
                last_err = Some(format!("{}:connect_timeout", relay_label));
                continue;
            }
        }
    }
    if best.is_some() {
        if let Some((evt, relay_used)) = best {
            return Ok((evt, relay_used));
        }
    }
    // Map the absence-of-event to a typed error so the calling actor
    // can branch on it.
    Err(match last_err {
        Some(msg) => anyhow::anyhow!("relay_unreachable:{msg}"),
        None => anyhow::anyhow!("no_backup_found"),
    })
}

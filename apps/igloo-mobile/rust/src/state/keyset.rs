// ── Create / Rotate Keyset wizard state (VAL-CREATE-* / VAL-ROTATE-*) ───────

use serde::{Deserialize, Serialize};

/// Wizard mode selected on the CreateKeysetEntry screen.
///
/// VAL-CREATE-002 requires the Generate form to expose a mode selector
/// (new keyset vs rotate). VAL-ROTATE-001..004 toggle the rotation
/// source picker; both modes share the same wizard chrome.
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum KeysetFlowMode {
    /// Generate a fresh keyset from a new signing key.
    #[default]
    Create,
    /// Rotate an existing keyset (preserve the group public key).
    Rotate,
}

/// Progress step for the wizard. Drives UI label and gating on Restart
/// / Abandon / Finish actions.
///
/// - `Idle`: Initial state before the user enters the wizard.
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum KeysetFlowStep {
    /// Initial state — no action taken, the user is on the entry screen.
    #[default]
    Idle,
    /// Generation work in flight on the FFI thread (Argon2id dealer).
    /// VAL-CREATE-022 requires visible busy feedback during heavy keygen.
    Generating,
    /// Generation produced a valid bundle — wizard is on the Device Profile
    /// step with the share picker available.
    DeviceProfile,
    /// Wizard advanced to the Review step (read-only summary).
    Review,
    /// Wizard advanced to the Distribute step (per-share forms + status chips).
    Distribute,
    /// Generation failed — the wizard stays on the Generate screen and the
    /// failure is recoverable by editing inputs and re-tapping Generate.
    GenerationFailed,
}

/// Validation errors surfaced from the Generate step.
///
/// The arg name `KeysetValidationError` keeps the parity-oracle's
/// `validateKeysetShape` vocabulary visible to mobile validators and locks in
/// the four rejection branches the contract pins:
///
/// - `ThresholdGreaterThanCount` (4-of-3)
/// - `ThresholdZero` or `CountZero` (zero / cleared)
/// - `ThresholdOne` (core requires threshold >= 2)
/// - `EmptyGroupName`
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum KeysetValidationError {
    /// `threshold > count` (e.g. 4-of-3).
    ThresholdGreaterThanCount,
    /// User typed `0` or cleared the threshold field.
    ThresholdZero,
    /// User typed `0` or cleared the count field.
    CountZero,
    /// User typed `1` for threshold (core requires `>= 2`).
    ThresholdOne,
    /// Group name field is empty after trimming.
    EmptyGroupName,
}

impl KeysetValidationError {
    /// User-visible message for each rejection branch.
    pub fn message(&self) -> &'static str {
        match self {
            Self::ThresholdGreaterThanCount => "Threshold cannot exceed the total number of keys.",
            Self::ThresholdZero => "Threshold must be at least 1.",
            Self::CountZero => "Total key count must be at least 1.",
            Self::ThresholdOne => "Threshold must be at least 2.",
            Self::EmptyGroupName => "Group name is required.",
        }
    }
}

/// One row in the rotation-source picker (VAL-ROTATE-001).
///
/// Each row accepts a `bfshare1` package text plus its password; the
/// wizard validates them as the user edits. Persisted in
/// `KeysetFlowState::rotation_sources` so the picker survives back
/// navigation (VAL-CREATE-009 parity).
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct RotationSourceRow {
    /// Trimmed bfshare1 package text. Empty means the row is a blank
    /// widget waiting for the user to paste; non-empty means it has
    /// been claimed and re-fills on back navigation.
    pub package: String,
    /// bfshare1 password as entered (validated, not persisted).
    pub password: String,
    /// Whitelisted profile id this rotation source targets. Set when
    /// the source-profile picker binds the row to a stored profile.
    /// Empty means the row is unknown-profile until the shell resolves
    /// it.
    #[serde(default)]
    pub source_profile_id: String,
}

/// One share produced by keygen, surfaced for the share picker (VAL-CREATE-004,
/// VAL-CREATE-006, VAL-CREATE-008) and for the per-share Distribute forms
/// (VAL-CREATE-011/012).
///
/// The view model is serialized so an actor-driven snapshot carries it across
/// the generator → device-profile → review → distribute flow without re-runs.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct GeneratedShare {
    /// Identifier inside the keyset (matches `SharePackage.idx`).
    pub share_idx: u16,
    /// 64-char lowercase-hex compressed public key (33-byte form is rendered
    /// as x-only here so mobile validators can compare via accessibility
    /// value or copy affordance).
    pub share_pubkey: String,
    /// 32-byte share secret as 64-char lowercase hex. Kept here so the
    /// wizard can re-encode the share via the `bfonboard1` envelope on the
    /// Distribute step. Lives only inside the actor state; never sent to
    /// native logs.
    pub share_secret_hex: String,
    /// Default label for this share, derived from `group_name` + share_idx.
    /// The user can override it on the Distribute step (VAL-CREATE-011).
    pub default_label: String,
}

/// Result of the keygen FFI call, surfaced into state by the actor.
///
/// `bundle_json` is the canonical wire form produced by `frostr_utils::create_keyset`.
/// We carry the wire form (rather than re-parse it) so the actor has a stable
/// representation that survives rev/`serde` changes in `bifrost-codec`.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct KeysetBundleRecord {
    pub group_name: String,
    pub threshold: u16,
    pub count: u16,
    /// 64-char lowercase-hex group public key.
    pub group_pubkey: String,
    /// All shares produced by the dealer; the local device picks one and the
    /// Distribute step iterates over the remainder.
    pub shares: Vec<GeneratedShare>,
}

/// Per-share distribution status (VAL-CREATE-017). Each share form owns a
/// status chip recording the most recent distribution method (`copied`, `qr`,
/// or `saved`). Last-action-wins so re-using an action overwrites the chip.
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum DistributeStatus {
    #[default]
    /// No distribution attempt yet.
    Pending,
    /// Copy-to-clipboard succeeded.
    Copied,
    /// QR display modal opened.
    Qr,
    /// Save-to-file succeeded.
    Saved,
}

impl DistributeStatus {
    pub fn label(&self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Copied => "copied",
            Self::Qr => "qr",
            Self::Saved => "saved",
        }
    }
}

/// One row in the Distribute step. There is one DistributeShareRecord per
/// non-local share (VAL-CREATE-011), so for a 2-of-3 keyset where the
/// device took one share we have exactly two of these.
///
/// `status_chip` is what the user-facing chip displays (VAL-CREATE-017).
/// `last_package` is the most recently produced `bfonboard1` string for
/// that share — needed for QR display because heavy Argon2id KDF work
/// should not re-run every time the QR modal is dismissed (VAL-CREATE-022).
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct DistributeShareRecord {
    pub share_idx: u16,
    pub label: String,
    /// Package password as entered (validated separately per share).
    pub password: String,
    /// Confirm-password field for the double-input UX (VAL-CREATE-013).
    pub confirm_password: String,
    /// Most recent bfonboard1 package string for this share. Reset to
    /// empty when the password changes.
    pub last_package: String,
    /// Current distribution status chip (VAL-CREATE-017).
    pub status_chip: DistributeStatus,
}

/// The full Create / Rotate Keyset wizard state. Lives in `AppState.keyset`
/// so shells render snapshots re-guarded by `rev`.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct KeysetFlowState {
    /// Current wizard progress.
    pub step: KeysetFlowStep,
    /// Persistent validation error from the Generate step, cleared on the
    /// next successful validation pass.
    pub error: Option<KeysetValidationError>,
    /// Free-form error message surfaced when keygen or distribution fails.
    /// Lives separately so the typed `error` slot can keep validating form
    /// parity while runtime failures carry the FFI's raw error text.
    #[serde(default)]
    pub last_error_message: Option<String>,
    /// Wizard mode (Create vs Rotate) — VAL-CREATE-002 form parity.
    pub mode: KeysetFlowMode,
    /// Generate-step inputs: group name, threshold, count. Kept across
    /// the wizard so back navigation preserves values (VAL-CREATE-009).
    pub group_name: String,
    pub threshold: u16,
    pub count: u16,
    /// Generated bundle; filled when `step` reaches DeviceProfile+ and
    /// empty after `reset()`.
    pub bundle: Option<KeysetBundleRecord>,
    /// Selected local share idx (VAL-CREATE-004, VAL-CREATE-006).
    pub local_share_idx: u16,
    /// Device profile inputs: device name (prefilled from
    /// `group_name`+share-idx default), relay list pre-filled with the
    /// app default relay URL.
    pub device_name: String,
    pub relays: Vec<String>,
    /// One DistributeShareRecord per remaining (non-local) share.
    /// Empty until the wizard reaches the Distribute step.
    pub distribute: Vec<DistributeShareRecord>,
    /// Short profile id captured after Accept-and-Continue storage completes.
    /// Used by the Distribute step's embedded dashboard header on iOS.
    #[serde(default)]
    pub accepted_short_id: Option<String>,
    /// Rotation-mode source picker (VAL-ROTATE-001..004).
    ///
    /// Populated only when `mode == KeysetFlowMode::Rotate`. Each row
    /// accepts a `bfshare1` + password pair; absolute source-profile
    /// picker state is recorded via `rotate_source_profile_id` so the
    /// wizard can perform the under-threshold check
    /// (VAL-ROTATE-002) against the right stored profile.
    #[serde(default)]
    pub rotation_sources: Vec<RotationSourceRow>,
    /// Profile id the rotation source picker binds to (VAL-ROTATE-001).
    /// Empty means the picker is showing the placeholder.
    #[serde(default)]
    pub rotate_source_profile_id: String,
    /// Surface error for the rotation-source stage. Mirrors the
    /// typed `error` slot so the same inline-error UI handles both
    /// shape rejections (VAL-ROTATE-002, VAL-ROTATE-003).
    #[serde(default)]
    pub rotation_error: Option<String>,
}

impl KeysetFlowState {
    /// Initial state shown when the user opens the Create / Rotate Keyset
    /// wizard from the hub tile.
    pub fn new() -> Self {
        Self {
            step: KeysetFlowStep::Idle,
            error: None,
            last_error_message: None,
            mode: KeysetFlowMode::Create,
            group_name: String::new(),
            // igloo-pwa parity defaults (VAL-CREATE-002).
            threshold: 2,
            count: 3,
            bundle: None,
            local_share_idx: 0,
            device_name: String::new(),
            relays: Vec::new(),
            distribute: Vec::new(),
            accepted_short_id: None,
            rotation_sources: Vec::new(),
            rotate_source_profile_id: String::new(),
            rotation_error: None,
        }
    }

    /// Reset to a fresh idle state. Used on final abandonment
    /// (VAL-CREATE-020) and on `NavigateCreateKeyset` re-entry
    /// (VAL-CREATE-021).
    pub fn reset(&mut self) {
        *self = Self::new();
    }

    /// Validate the Generate-step inputs against the contract rules:
    /// - threshold > count → ThresholdGreaterThanCount
    /// - threshold == 0 → ThresholdZero
    /// - count == 0 → CountZero
    /// - threshold == 1 → ThresholdOne
    /// - trimmed group_name empty → EmptyGroupName
    ///
    /// Returns the first matching error or None when all rules pass.
    pub fn validate_generate(&self) -> Option<KeysetValidationError> {
        if self.threshold > self.count {
            return Some(KeysetValidationError::ThresholdGreaterThanCount);
        }
        if self.threshold == 0 {
            return Some(KeysetValidationError::ThresholdZero);
        }
        if self.count == 0 {
            return Some(KeysetValidationError::CountZero);
        }
        if self.threshold == 1 {
            return Some(KeysetValidationError::ThresholdOne);
        }
        if self.group_name.trim().is_empty() {
            return Some(KeysetValidationError::EmptyGroupName);
        }
        None
    }

    /// Build the Distribute records for the current bundle minus the
    /// local share. Each row prefills its label with the share's default
    /// (VAL-CREATE-011) and starts in `Pending` status.
    pub fn build_distribute_rows(&mut self) {
        let mut rows = Vec::new();
        if let Some(bundle) = &self.bundle {
            for share in &bundle.shares {
                if share.share_idx == self.local_share_idx {
                    continue;
                }
                rows.push(DistributeShareRecord {
                    share_idx: share.share_idx,
                    label: share.default_label.clone(),
                    password: String::new(),
                    confirm_password: String::new(),
                    last_package: String::new(),
                    status_chip: DistributeStatus::Pending,
                });
            }
        }
        self.distribute = rows;
    }

    /// Look up a Distribute row by share_idx. Used by all three
    /// distribution actions (VAL-CREATE-012/013/014/015/016/017).
    pub fn distribute_row(&self, share_idx: u16) -> Option<&DistributeShareRecord> {
        self.distribute
            .iter()
            .find(|row| row.share_idx == share_idx)
    }

    /// Mutable variant of `distribute_row`.
    pub fn distribute_row_mut(&mut self, share_idx: u16) -> Option<&mut DistributeShareRecord> {
        self.distribute
            .iter_mut()
            .find(|row| row.share_idx == share_idx)
    }

    /// Convenience for VAL-CREATE-021: the Distribute step is active when
    /// `step == Distribute` and at least one share remains.
    pub fn has_distribute(&self) -> bool {
        self.step == KeysetFlowStep::Distribute && !self.distribute.is_empty()
    }

    /// Number of valid rotation sources (both package and password set).
    /// Used by `validate_rotation_sources` for the under-threshold gate
    /// (VAL-ROTATE-002). Counts each non-empty, non-duplicate
    /// bfshare1 + password pair.
    pub fn valid_rotation_source_count(&self) -> usize {
        let mut seen_packages: Vec<&str> = Vec::new();
        let mut count: usize = 0;
        for row in &self.rotation_sources {
            let pkg = row.package.trim();
            let pw = row.password.trim();
            if pkg.is_empty() || pw.is_empty() {
                continue;
            }
            if seen_packages.contains(&pkg) {
                continue;
            }
            seen_packages.push(pkg);
            count += 1;
        }
        count
    }

    /// Validate the rotation-source stage (VAL-ROTATE-002, VAL-ROTATE-003).
    ///
    /// Returns the first encountered user-visible error message, or
    /// `None` when all source rows are valid and at least `threshold`
    /// distinct shares are present.
    pub fn validate_rotation_sources(&self, threshold: u16) -> Option<String> {
        if self.rotate_source_profile_id.trim().is_empty() {
            return Some("Pick a source profile to rotate.".to_string());
        }
        if self.rotation_sources.is_empty() {
            return Some("At least one rotation source is required.".to_string());
        }
        // Detect malformed + missing-password rows up-front so the
        // user fixes them in place rather than racing the threshold
        // check against possibly invalid rows.
        for (idx, row) in self.rotation_sources.iter().enumerate() {
            let pkg = row.package.trim();
            if pkg.is_empty() {
                return Some(format!("Rotation source {} is missing a package.", idx + 1));
            }
            if row.password.is_empty() {
                return Some(format!(
                    "Rotation source {} is missing a password.",
                    idx + 1
                ));
            }
        }
        let valid = self.valid_rotation_source_count();
        if (valid as u16) < threshold {
            return Some(format!(
                "Need at least {} valid rotation sources (have {}).",
                threshold, valid
            ));
        }
        None
    }
}

impl Default for KeysetFlowState {
    fn default() -> Self {
        Self::new()
    }
}

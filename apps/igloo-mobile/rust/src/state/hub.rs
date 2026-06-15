// ── Hub state ───────────────────────────────────────────────────────────────

use serde::{Deserialize, Serialize};

/// Profile availability status shown on hub rows.
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum ProfileStatus {
    #[default]
    Available,
    Active,
}

/// A stored profile summary shown as a hub row.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct StoredProfile {
    /// User-visible label (device name).
    pub label: String,
    /// Shortened profile id (8 hex chars).
    pub short_id: String,
    /// Full profile id (64 hex chars) for internal use / equality checks.
    pub profile_id: String,
    /// Profile availability / active status.
    pub status: ProfileStatus,
}

impl StoredProfile {
    pub fn new(label: String, profile_id: String, status: ProfileStatus) -> Self {
        let short_id = if profile_id.len() >= 8 {
            profile_id[..8].to_string()
        } else {
            profile_id.clone()
        };
        Self {
            label,
            short_id,
            profile_id,
            status,
        }
    }
}

/// Landing hub state: stored-profile list + the three entry tiles.
/// Entry tiles are always present (not rendered from data) so they don't
/// need explicit state — only the stored profile list is dynamic.
#[derive(uniffi::Record, Clone, Debug, Serialize, Deserialize)]
pub struct HubState {
    /// Sorted list of stored profiles (newest first).
    pub profiles: Vec<StoredProfile>,
}

impl HubState {
    /// Deliberate empty state shown on fresh installs with no stored profiles.
    pub fn empty() -> Self {
        Self {
            profiles: Vec::new(),
        }
    }

    /// Whether the hub should render an empty stored-profiles area.
    pub fn is_empty(&self) -> bool {
        self.profiles.is_empty()
    }
}

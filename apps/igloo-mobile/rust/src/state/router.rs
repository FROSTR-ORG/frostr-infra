// ── Router / Screen stack ────────────────────────────────────────────────────

use serde::{Deserialize, Serialize};

/// Screen stack — Rust owns navigation. Only the active screen is rendered.
#[derive(uniffi::Enum, Clone, Debug, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Screen {
    /// Landing hub: stored profiles + three entry tiles.
    Hub,
    /// Onboard Device flow — entry point.
    OnboardEntry,
    /// Onboard Device — paste package + password step.
    OnboardConnect,
    /// Onboard Device — resolved identity review + save step.
    OnboardReview,
    /// Load Profile flow — path choice.
    LoadProfileEntry,
    /// Load Profile — import bfprofile1 path.
    LoadProfileImport,
    /// Load Profile — recover from bfshare1 path.
    LoadProfileRecover,
    /// Load Profile — imported/recovered profile preview + confirm step.
    LoadProfileConfirm,
    /// Create / Rotate Keyset flow — path choice.
    CreateKeysetEntry,
    /// Create Keyset step 1: generate.
    CreateKeysetGenerate,
    /// Create Keyset step 2: device profile.
    CreateKeysetDeviceProfile,
    /// Create Keyset step 3: review.
    CreateKeysetReview,
    /// Create Keyset step 4: distribute.
    CreateKeysetDistribute,
    /// Dashboard — opened from hub stored-profile row.
    Dashboard,
    /// Rotate Share — connect rotated bfonboard1 package (VAL-ROTATE-005).
    RotateShare,
}

/// Rust-side navigation state. The actor advances this; shells only observe.
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Router {
    /// Current active screen.
    pub screen: Screen,
    /// Navigation history for back button (last = most recent previous screen).
    pub back_history: Vec<Screen>,
}

impl Default for Router {
    fn default() -> Self {
        Self {
            screen: Screen::Hub,
            back_history: Vec::new(),
        }
    }
}

impl Router {
    pub const HUB: Self = Self {
        screen: Screen::Hub,
        back_history: Vec::new(),
    };
}

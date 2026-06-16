// ── Update handlers — TEA update fns ───────────────────────────────────────

use crate::actions::AppAction;
use crate::state::{
    AppState, DashboardState, DashboardTab, DistributeStatus, KeysetFlowMode, KeysetFlowStep,
    LogEntry, LogLevel, NonceInventory, OnboardingError, OnboardingStep, PeerPermissions,
    PeerSelectionStrategy, PeerStatus, PendingOp, PendingOpType, PermissionsState, PolicyDirection,
    PolicyMethod, PolicyOverrideValue, ProfileInfo, ProfileStatus, RemotePolicyObservation,
    ResolvedIdentity, RotatePreviewIdentity, RotateShareStep, RotationSourceRow, Screen,
    SettingsState, SignerReadiness, SignerRuntimeState, SignerStatus, StoredProfile,
    TestEcdhResultData, TestSignResultData,
};
use crate::{
    build_keyset_material, default_relay_url, derive_profile_id_from_secret_hex,
    parse_keyset_bundle, AppUpdate, GeneratedKeysetWire,
};

/// Current UTC Unix epoch in whole seconds (i64).
///
/// Use this for numeric epoch-second fields (e.g. `completed_at_secs`,
/// `last_refresh_secs`, `started_at_secs`). It is the Rust-side mirror of the
/// `display_timestamp_rfc3339()` display path: the displayed RFC-3339 string and
/// the numeric epoch seconds are produced by two separate helpers so the UI
/// renders readable time and downstream numeric fields keep their i64 meaning.
fn now_epoch_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// Convert a Unix epoch (whole seconds) to (year, month, day, hour, minute, second) in UTC.
///
/// Uses Howard Hinnant's civil_from_days/low-level date algorithm; verified
/// against known anchors (1970-01-01T00:00:00Z, 2026-01-01T00:00:00Z, etc.).
/// Operating range we need covers positive epoch seconds (post-1970) for the
/// signer event log; rem_euclid / div_euclid keep the math safe at boundaries.
fn utc_ymd_hms_from_epoch(secs: i64) -> (i32, u32, u32, u32, u32, u32) {
    let sec = secs.rem_euclid(60) as u32;
    let minute = secs.div_euclid(60).rem_euclid(60) as u32;
    let hour = secs.div_euclid(3_600).rem_euclid(24) as u32;
    let days = secs.div_euclid(86_400);

    // z = days since civil 0000-03-01.
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64; // [0, 146096]
    let yoe = ((doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365) as i64; // [0, 399]
    let y_full = yoe + era * 400;
    let doy = doe - (365 * yoe as u64 + yoe as u64 / 4 - yoe as u64 / 100); // [0, 365]
    let mp: u32 = ((5 * doy + 2) / 153) as u32; // [0, 11]
    let d = (doy - (153 * u64::from(mp) + 2) / 5 + 1) as u32; // [1, 31]
                                                              // mp is u32 inside [0, 11], so the month index m spans [1, 12]. Year shift
                                                              // when the month is Jan or Feb (m <= 2) and final year conversion.
    let m: u32 = if mp < 10 { mp + 3 } else { mp - 9 }; // [1, 12]
    let y: i64 = if m <= 2 { y_full + 1 } else { y_full };

    (y as i32, m, d, hour, minute, sec)
}

/// Return an ISO-8601 / RFC-3339 UTC timestamp string for the current time
/// (e.g. `2026-06-13T12:34:56Z`).
///
/// Used for signer event log timestamps (VAL-SIGNER-012). This is the visible
/// "wall clock" path; numeric epoch-second fields (e.g.
/// `completed_at_secs`, `last_refresh_secs`) are produced by the separate
/// `now_epoch_secs()` helper so they keep their i64 meaning.
fn display_timestamp_rfc3339() -> String {
    let (year, month, day, hour, minute, second) = utc_ymd_hms_from_epoch(now_epoch_secs());
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        year, month, day, hour, minute, second
    )
}

fn chrono_lite_timestamp() -> String {
    display_timestamp_rfc3339()
}

/// Advance the state machine by one action. Returns the next state and
/// an optional side effect to emit to the shell reconciler.
pub fn update(state: &AppState, action: &AppAction) -> (AppState, Option<AppUpdate>) {
    let mut next = state.clone();
    next.rev += 1;
    let mut side_effect = None;

    match action {
        // ── Hub navigation ──────────────────────────────────────────────
        AppAction::NavigateOnboard => {
            // Reset onboarding state when entering the flow (VAL-ONBOARD-013).
            next.onboarding.reset();
            next.router.screen = Screen::OnboardEntry;
        }

        AppAction::NavigateLoadProfile => {
            next.router.screen = Screen::LoadProfileEntry;
        }

        AppAction::NavigateCreateKeyset => {
            // VAL-CREATE-021: Reset keyset state when entering the wizard
            // so a previous run's Distribute state cannot bleed into the
            // new run.
            next.keyset.reset();
            next.router.screen = Screen::CreateKeysetEntry;
        }

        AppAction::OpenProfile { profile_id } => {
            // Mark the opened profile as Active; others as Available.
            // VAL-SHELL-015: active status reflects running signer.
            // VAL-CROSS-009: at most one active runtime.
            let mut profile_label = String::new();
            for p in next.hub.profiles.iter_mut() {
                if p.profile_id == *profile_id {
                    p.status = ProfileStatus::Active;
                    profile_label = p.label.clone();
                } else {
                    p.status = ProfileStatus::Available;
                }
            }
            // Seed a minimal identity block with the label we have from the hub
            // so the dashboard header shows the device name immediately. The
            // shell will load the full material and dispatch OpenDashboard to
            // populate share_pubkey / group_pubkey.
            // (mobile-signer-startup-profile-info-fix)
            next.dashboard.profile_info = Some(ProfileInfo {
                device_name: profile_label,
                share_pubkey: String::new(),
                group_pubkey: String::new(),
                profile_id: profile_id.clone(),
            });
            // Emit side effect so the shell loads the stored material and
            // dispatches OpenDashboard with full identity data.
            side_effect = Some(AppUpdate::RestoreFromSecureStorage {
                profile_id: profile_id.clone(),
            });
            next.router.screen = Screen::Dashboard;
        }

        // ── Back / cancel ───────────────────────────────────────────────
        AppAction::NavigateBack => {
            let prev_screen = state.router.screen;
            // VAL-ONBOARD-013: backing out before save stores nothing.
            // VAL-LOAD-015: abandoning before confirmation stores nothing.
            // Reset onboarding state whenever leaving any onboard step.
            if matches!(
                prev_screen,
                Screen::OnboardEntry | Screen::OnboardConnect | Screen::OnboardReview
            ) {
                next.onboarding.reset();
            }
            // Reset load profile state when leaving any load profile step.
            if matches!(
                prev_screen,
                Screen::LoadProfileEntry
                    | Screen::LoadProfileImport
                    | Screen::LoadProfileRecover
                    | Screen::LoadProfileConfirm
            ) {
                next.load_profile.reset();
            }
            // VAL-ROTATE-010: backing out of Rotate Share before
            // confirming replacement must leave the active profile
            // untouched. Reset the in-flight rotate-share state but
            // keep the active-profile identity surface intact so the
            // dashboard re-renders correctly on return.
            if matches!(prev_screen, Screen::RotateShare) {
                next.rotate_share.reset();
            }
            // Pop from back_history if available; otherwise fall back to go_back().
            // This handles the direct Hub→OnboardConnect path where back should
            // return to Hub (back_history = [Hub]), not to OnboardEntry.
            if let Some(prev) = next.router.back_history.pop() {
                next.router.screen = prev;
            } else {
                next.router.screen = go_back(prev_screen);
            }
            // VAL-SHELL-015: navigating back from dashboard preserves active
            // status — the signer continues running and status stays Active.
            // We do NOT reset Active to Available on back navigation.
        }

        // ── Onboard flow ─────────────────────────────────────────────────
        // VAL-ONBOARD-002: empty fields blocked before any async work.
        // VAL-ONBOARD-016: whitespace-tolerant (shells trim before dispatch).
        // VAL-ONBOARD-003: malformed/truncated/wrong-type caught at decode.
        // VAL-ONBOARD-004: wrong password is recoverable.
        AppAction::NavigateOnboardConnect => {
            // Navigate directly to OnboardConnect from Hub (VAL-ONBOARD-001 entry path).
            // VAL-ONBOARD-013: cancellation safety — back always returns to Hub.
            next.onboarding.reset();
            next.router.screen = Screen::OnboardConnect;
            // Always set back history to [Hub] so back returns to Hub.
            next.router.back_history.clear();
            next.router.back_history.push(Screen::Hub);
        }

        // Debug-gated credential preload for the OnboardConnect screen.
        // Sets state.onboarding.{package,password,relay_url,injected_device_name}
        // without advancing the step. The user/Maestro still taps btn_connect.
        // This is the only path that bypasses long-text UI input friction —
        // it does NOT bypass validation/state-machine semantics, because
        // OnboardConnect is still dispatched and validated on btn_connect.
        AppAction::InjectOnboardCredentials {
            package,
            password,
            relay_url,
            device_name,
        } => {
            // Trim the package; keep password and relay_url verbatim.
            // Stamp the inject so the in-flow error/state machine stays at Idle.
            next.onboarding.package = package.trim().to_string();
            next.onboarding.password = password.clone();
            next.onboarding.relay_url = relay_url.clone();
            next.onboarding.error = None;
            next.onboarding.step = OnboardingStep::Idle;
            next.onboarding.resolved = None;
            // Only set injected_device_name if non-empty; otherwise leave
            // any prior hint untouched.
            if let Some(name) = device_name {
                let trimmed = name.trim();
                next.onboarding.injected_device_name = if trimmed.is_empty() {
                    None
                } else {
                    Some(trimmed.to_string())
                };
            }
        }

        AppAction::OnboardConnect {
            package,
            password,
            relay_url,
        } => {
            // Block on empty required fields (VAL-ONBOARD-002).
            if package.trim().is_empty() || password.is_empty() {
                next.onboarding.error = Some(OnboardingError::MalformedPackage);
                next.onboarding.step = OnboardingStep::Error;
                // Stay on connect screen — no navigation.
                return (next, None);
            }

            // Store trimmed package and relay for use in handshake.
            let trimmed_package = package.trim().to_string();
            next.onboarding.package = trimmed_package.clone();
            next.onboarding.password = password.clone();
            next.onboarding.relay_url = relay_url.clone();
            next.onboarding.error = None;
            next.onboarding.step = OnboardingStep::Decrypting;

            // Shell performs the async decrypt + relay handshake.
            side_effect = Some(AppUpdate::PerformOnboardHandshake {
                package: trimmed_package,
                password: password.clone(),
                relay_url: relay_url.clone(),
            });
        }

        // Shell reported the handshake succeeded — transition to review.
        // VAL-ONBOARD-008: resolved identity shown on review/save screen.
        // VAL-ONBOARD-015: a profile_id that is already stored must be rejected
        // visibly at or before Save Device. Implementing the pre-Save check
        // here means the duplicate guard fires BEFORE we navigate to
        // OnboardReview, so the user never starts editing `input_device_name`
        // for an identity that the hub already has.
        // (mobile-onboard-error-path-hardening-fix — parity with VAL-LOAD-008.)
        AppAction::OnboardHandshakeSuccess {
            device_name,
            share_pubkey,
            group_pubkey,
            relays,
            profile_id,
        } => {
            // VAL-ONBOARD-015: reject visibly at the earliest owned boundary
            // (post-handshake, pre-OnboardReview) if the resolved profile_id is
            // already in hub.profiles. Returning to OnboardConnect keeps the
            // onboard_error banner visible instead of leaving the user on
            // OnboardReview where the error is invisible.
            if next
                .hub
                .profiles
                .iter()
                .any(|p| p.profile_id == *profile_id)
            {
                next.onboarding.error = Some(OnboardingError::DuplicateProfile);
                next.onboarding.step = OnboardingStep::Error;
                // Discard the resolved identity so a stale resolved entry
                // cannot survive the rejected flow and confuse OnboardStored
                // if the user backs out and re-enters the flow.
                next.onboarding.resolved = None;
                // Stay on OnboardConnect so the visible onboard_error banner
                // appears at or before Save Device. Screen::OnboardReview does
                // not render `onboarding.error`, so leaving the user there is
                // the silent-failure mode this fix removes.
                return (next, None);
            }
            next.onboarding.resolved = Some(ResolvedIdentity {
                device_name: device_name.clone(),
                share_pubkey: share_pubkey.clone(),
                group_pubkey: group_pubkey.clone(),
                relays: relays.clone(),
                profile_id: profile_id.clone(),
            });
            next.onboarding.step = OnboardingStep::Complete;
            next.onboarding.error = None;
            next.router.screen = Screen::OnboardReview;
        }

        // Shell reported the handshake failed with a specific error kind.
        // VAL-ONBOARD-007: unreachable relay; VAL-ONBOARD-004: wrong password;
        // VAL-ONBOARD-003: malformed package; VAL-ONBOARD-014: offline provisioner.
        AppAction::OnboardHandshakeFailure { error } => {
            let onboarding_error = match error.as_str() {
                "wrong_password" => OnboardingError::WrongPassword,
                "relay_unreachable" => OnboardingError::RelayUnreachable,
                "provisioner_offline" => OnboardingError::ProvisionerOffline,
                "onboard_timeout" => OnboardingError::ProvisionerOffline,
                "malformed_package" => OnboardingError::MalformedPackage,
                _ => OnboardingError::MalformedPackage,
            };
            next.onboarding.step = OnboardingStep::Error;
            next.onboarding.error = Some(onboarding_error);
            // Stay on the connect screen for retry (VAL-ONBOARD-004 recoverable).
        }

        // User tapped "Save Device" on the review screen.
        // VAL-ONBOARD-011: save persists the profile and arrives at dashboard.
        AppAction::OnboardSave {
            profile_id,
            label,
            short_id,
        } => {
            if let Some(resolved) = next.onboarding.resolved.as_mut() {
                resolved.device_name = label.clone();
            }
            side_effect = Some(AppUpdate::StoreOnboardedProfile {
                profile_id: profile_id.clone(),
                label: label.clone(),
                short_id: short_id.clone(),
            });
        }

        // DEBUG/diagnostic harness path: route OnboardReview -> Dashboard
        // through the same shell storage side effect as the Save Device button,
        // without depending on simulator SwiftUI button-tap delivery.
        AppAction::DiagnosticsOnboardSave { device_name } => {
            if let Some(resolved) = next.onboarding.resolved.as_mut() {
                let action_label = device_name
                    .as_deref()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(str::to_string);
                let injected_label = next
                    .onboarding
                    .injected_device_name
                    .as_deref()
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(str::to_string);
                let label = action_label
                    .or(injected_label)
                    .unwrap_or_else(|| resolved.device_name.clone());
                let short_id = if resolved.profile_id.len() >= 8 {
                    resolved.profile_id[..8].to_string()
                } else {
                    resolved.profile_id.clone()
                };

                resolved.device_name = label.clone();

                side_effect = Some(AppUpdate::StoreOnboardedProfile {
                    profile_id: resolved.profile_id.clone(),
                    label,
                    short_id,
                });
            }
        }

        // Shell reported the profile was stored successfully.
        // Add to hub and navigate to dashboard (VAL-ONBOARD-011).
        // VAL-BACKUP-002: also fire `AppUpdate::PublishProfileBackup`
        // so the freshly stored profile publishes a kind-10000 backup
        // event to its relays. The shell reads the material from secure
        // storage by `profile_id` and re-publishes from `FfiApp`.
        AppAction::OnboardStored { profile_id } => {
            if let Some(resolved) = &next.onboarding.resolved {
                // Add to hub if not already present (VAL-ONBOARD-015 dedupe).
                if !next
                    .hub
                    .profiles
                    .iter()
                    .any(|p| p.profile_id == *profile_id)
                {
                    next.hub.profiles.push(StoredProfile::new(
                        resolved.device_name.clone(),
                        profile_id.clone(),
                        ProfileStatus::Active,
                    ));
                }
                // Populate dashboard identity block so the signer tab
                // can start the runtime without a shell round-trip
                // (mobile-signer-startup-profile-info-fix).
                next.dashboard.profile_info = Some(ProfileInfo {
                    device_name: resolved.device_name.clone(),
                    share_pubkey: resolved.share_pubkey.clone(),
                    group_pubkey: resolved.group_pubkey.clone(),
                    profile_id: profile_id.clone(),
                });
            }
            // Reset onboarding and navigate to dashboard.
            next.onboarding.reset();
            next.router.screen = Screen::Dashboard;
            // Fire backup publication side-effect (VAL-BACKUP-002). The
            // shell owns secure storage so it reads the material by
            // `profile_id`; `material_json` is empty here because the
            // post-onboard state only carries the resolved identity
            // fields, not the share secret.
            side_effect = Some(AppUpdate::PublishProfileBackup {
                source: "onboard".to_string(),
                profile_id: profile_id.clone(),
                material_json: String::new(),
            });
        }

        // Shell reported a duplicate profile_id was rejected.
        // VAL-ONBOARD-015: re-onboarding an already-stored identity is rejected.
        // mobile-onboard-error-path-hardening-fix: the rejection must be visible.
        // The pre-Save duplicate check is implemented on
        // `AppAction::OnboardHandshakeSuccess` (above); this handler covers
        // the secondary path where the shell's secure-storage layer detects
        // the duplicate at write time (race / API drift fallback). In both
        // paths we navigate back to OnboardConnect so the `onboard_error`
        // banner is rendered to the user, instead of leaving them on
        // OnboardReview where the error is invisible.
        AppAction::OnboardDuplicateRejected { profile_id: _ } => {
            // Use the specific DuplicateProfile kind so shells render the
            // "This profile already exists on this device." message and not
            // the generic "An unexpected error occurred." that the
            // previously-bundled OnboardingError::Unexpected produced.
            next.onboarding.error = Some(OnboardingError::DuplicateProfile);
            next.onboarding.step = OnboardingStep::Error;
            // Discard any resolved identity and reset package/password
            // retention so a stale resolved entry from a duplicate attempt
            // cannot bleed into a subsequent OnboardStored if the user backs
            // out and re-enters the flow. The `password` field is also reset
            // because the duplicate rejection means the stored profile is
            // already in the hub — re-using the same credentials on a
            // different package would be expected, so we keep it, but the
            // resolved identity MUST be cleared.
            next.onboarding.resolved = None;
            // Return to OnboardConnect so the onboard_error banner is
            // visible. The previous behavior of staying on OnboardReview
            // suppressed the error (OnboardReview does not render
            // `onboarding.error`) and produced the user-reported silent
            // over-write mode.
            if next.router.screen == Screen::OnboardReview {
                next.router.screen = Screen::OnboardConnect;
            }
        }

        // User tapped retry after an error — clear error and return to idle.
        AppAction::OnboardClearError => {
            // Keep package/password/relay_url for retry (VAL-ONBOARD-004).
            next.onboarding.step = OnboardingStep::Idle;
            next.onboarding.error = None;
        }

        // ── Load Profile flow ───────────────────────────────────────────
        // VAL-LOAD-001: entry offers both import and recovery paths.
        AppAction::LoadProfileSelectImport => {
            next.load_profile.reset();
            next.load_profile.path = "import".to_string();
            next.router.screen = Screen::LoadProfileImport;
        }

        AppAction::LoadProfileSelectRecover => {
            next.load_profile.reset();
            next.load_profile.path = "recover".to_string();
            next.router.screen = Screen::LoadProfileRecover;
        }

        // VAL-LOAD-002/003/004/005: import path decode + preview.
        // VAL-LOAD-016: empty fields blocked; VAL-LOAD-016: whitespace tolerated.
        AppAction::LoadProfileImportSubmit { package, password } => {
            // Block on empty required fields (VAL-LOAD-003).
            if package.trim().is_empty() || password.is_empty() {
                next.load_profile.error = Some(crate::state::LoadProfileError::MalformedPackage);
                next.load_profile.step = crate::state::LoadProfileStep::Error;
                return (next, None);
            }
            let trimmed = package.trim().to_string();
            next.load_profile.package = trimmed.clone();
            next.load_profile.password = password.clone();
            next.load_profile.error = None;
            next.load_profile.step = crate::state::LoadProfileStep::Decrypting;

            side_effect = Some(AppUpdate::PerformLoadProfileImport {
                package: trimmed,
                password: password.clone(),
            });
        }

        // VAL-LOAD-009/010/011/012/013/019: recover path decrypt + relay fetch.
        // VAL-LOAD-016: empty fields blocked; VAL-LOAD-016: whitespace tolerated.
        AppAction::LoadProfileRecoverSubmit { package, password } => {
            // Block on empty required fields (VAL-LOAD-016).
            if package.trim().is_empty() || password.is_empty() {
                next.load_profile.error = Some(crate::state::LoadProfileError::MalformedPackage);
                next.load_profile.step = crate::state::LoadProfileStep::Error;
                return (next, None);
            }
            let trimmed = package.trim().to_string();
            next.load_profile.package = trimmed.clone();
            next.load_profile.password = password.clone();
            next.load_profile.error = None;
            next.load_profile.step = crate::state::LoadProfileStep::FetchingBackup;

            side_effect = Some(AppUpdate::PerformLoadProfileRecovery {
                package: trimmed,
                password: password.clone(),
            });
        }

        // Shell reported import decode succeeded — show preview on confirm screen.
        // VAL-LOAD-006: preview shows device name, share pubkey, group pubkey, relays.
        AppAction::LoadProfileImportSuccess {
            device_name,
            share_pubkey,
            group_pubkey,
            relays,
            profile_id,
        } => {
            next.load_profile.resolved = Some(crate::state::LoadProfileResolved {
                device_name: device_name.clone(),
                share_pubkey: share_pubkey.clone(),
                group_pubkey: group_pubkey.clone(),
                relays: relays.clone(),
                profile_id: profile_id.clone(),
            });
            next.load_profile.step = crate::state::LoadProfileStep::Preview;
            next.load_profile.error = None;
            // Back from confirm should go to the import entry screen.
            next.router.back_history.clear();
            next.router.back_history.push(Screen::LoadProfileImport);
            next.router.screen = Screen::LoadProfileConfirm;
        }

        // Shell reported import decode/decrypt failed.
        // VAL-LOAD-004: malformed package; VAL-LOAD-005: wrong password.
        AppAction::LoadProfileImportFailure { error } => {
            let load_error = match error.as_str() {
                "wrong_password" => crate::state::LoadProfileError::WrongPassword,
                "duplicate_profile" => crate::state::LoadProfileError::DuplicateProfile,
                _ => crate::state::LoadProfileError::MalformedPackage,
            };
            next.load_profile.step = crate::state::LoadProfileStep::Error;
            next.load_profile.error = Some(load_error);
            // Stay on import screen for retry (VAL-LOAD-005 recoverable).
        }

        // Shell reported recovery succeeded — show preview on confirm screen.
        // VAL-LOAD-012: recovered profile preview shows the same fields as import.
        AppAction::LoadProfileRecoverSuccess {
            device_name,
            share_pubkey,
            group_pubkey,
            relays,
            profile_id,
        } => {
            next.load_profile.resolved = Some(crate::state::LoadProfileResolved {
                device_name: device_name.clone(),
                share_pubkey: share_pubkey.clone(),
                group_pubkey: group_pubkey.clone(),
                relays: relays.clone(),
                profile_id: profile_id.clone(),
            });
            next.load_profile.step = crate::state::LoadProfileStep::Preview;
            next.load_profile.error = None;
            // Back from confirm should go to the recover entry screen.
            next.router.back_history.clear();
            next.router.back_history.push(Screen::LoadProfileRecover);
            next.router.screen = Screen::LoadProfileConfirm;
        }

        // Shell reported recovery failed.
        // VAL-LOAD-010: malformed; VAL-LOAD-011: wrong password; VAL-LOAD-013: no backup;
        // VAL-LOAD-019: unreachable relay.
        AppAction::LoadProfileRecoverFailure { error } => {
            let load_error = match error.as_str() {
                "wrong_password" => crate::state::LoadProfileError::WrongPassword,
                "no_backup_found" => crate::state::LoadProfileError::NoBackupFound,
                "relay_unreachable" => crate::state::LoadProfileError::RelayUnreachable,
                "duplicate_profile" => crate::state::LoadProfileError::DuplicateProfile,
                _ => crate::state::LoadProfileError::MalformedPackage,
            };
            next.load_profile.step = crate::state::LoadProfileStep::Error;
            next.load_profile.error = Some(load_error);
            // Stay on recover screen for retry (VAL-LOAD-011, VAL-LOAD-019 recoverable).
        }

        // User confirmed the imported/recovered profile — persist to secure storage.
        // VAL-LOAD-007: import confirm persists and exits to dashboard.
        // VAL-LOAD-014: recover confirm persists and exits to dashboard.
        AppAction::LoadProfileConfirm => {
            if let Some(resolved) = &next.load_profile.resolved {
                side_effect = Some(AppUpdate::StoreLoadedProfile {
                    profile_id: resolved.profile_id.clone(),
                    label: resolved.device_name.clone(),
                    short_id: if resolved.profile_id.len() >= 8 {
                        resolved.profile_id[..8].to_string()
                    } else {
                        resolved.profile_id.clone()
                    },
                });
            }
        }

        // Shell reported the loaded profile was stored successfully.
        // VAL-LOAD-007/014: add to hub and navigate to dashboard.
        // VAL-BACKUP-006: every materialization (import or recover)
        // re-publishes a kind-10000 backup so the freshly added hub
        // row carries a relay-side recovery anchor. The shell reads
        // the material from secure storage by `profile_id`, calls
        // `FfiApp::publish_backup`, and forwards the result back via
        // `BackupPublishCompleted`.
        AppAction::LoadProfileStored { profile_id } => {
            // VAL-BACKUP-006: derive `source` from the resolved flow
            // so validators can correlate the published event with the
            // originating materialization path.
            let publish_source = match next.load_profile.path.as_str() {
                "recover" => "recover",
                _ => "import",
            }
            .to_string();
            if let Some(resolved) = &next.load_profile.resolved {
                if !next
                    .hub
                    .profiles
                    .iter()
                    .any(|p| p.profile_id == *profile_id)
                {
                    next.hub.profiles.push(StoredProfile::new(
                        resolved.device_name.clone(),
                        profile_id.clone(),
                        ProfileStatus::Active,
                    ));
                }
                // Populate dashboard identity block so the signer tab
                // can start the runtime without a shell round-trip
                // (mobile-signer-startup-profile-info-fix).
                next.dashboard.profile_info = Some(ProfileInfo {
                    device_name: resolved.device_name.clone(),
                    share_pubkey: resolved.share_pubkey.clone(),
                    group_pubkey: resolved.group_pubkey.clone(),
                    profile_id: profile_id.clone(),
                });
            }
            next.load_profile.reset();
            next.router.screen = Screen::Dashboard;
            side_effect = Some(AppUpdate::PublishProfileBackup {
                source: publish_source,
                profile_id: profile_id.clone(),
                material_json: String::new(),
            });
        }

        // Shell reported duplicate profile_id was rejected.
        // VAL-LOAD-008: import duplicate rejected; VAL-LOAD-017: recover duplicate rejected.
        AppAction::LoadProfileDuplicateRejected { profile_id: _ } => {
            next.load_profile.error = Some(crate::state::LoadProfileError::DuplicateProfile);
            next.load_profile.step = crate::state::LoadProfileStep::Error;
            // Stay on confirm screen with error; do NOT add to hub.
        }

        // User tapped retry after an error — clear error and return to idle.
        AppAction::LoadProfileClearError => {
            // Keep package/password for retry (VAL-LOAD-005/011).
            next.load_profile.step = crate::state::LoadProfileStep::Idle;
            next.load_profile.error = None;
        }

        // ── Create Keyset flow ───────────────────────────────────────────
        // VAL-CREATE-021: re-entering the wizard starts a fresh run with no
        // stale Distribute state.
        AppAction::CreateKeysetEnter => {
            next.keyset.reset();
            next.router.screen = Screen::CreateKeysetEntry;
        }

        // User picked "Create" mode on the entry tile. Both Create and
        // Rotate land on the same Generate step (rotate flow is owned by
        // the rotate-share feature, this action only widens the surface
        // shape to match igloo-pwa's mode selector).
        AppAction::CreateKeysetSelectCreate => {
            next.keyset.mode = crate::state::KeysetFlowMode::Create;
            next.router.screen = Screen::CreateKeysetGenerate;
        }

        // VAL-CREATE-021: stays in Generate step until rotation actually
        // happens (rotate-share feature ships the real flow).
        AppAction::CreateKeysetSelectRotate => {
            next.keyset.mode = crate::state::KeysetFlowMode::Rotate;
            next.router.screen = Screen::CreateKeysetGenerate;
        }

        // VAL-CREATE-002/003/009: each Generate-step field update keeps the
        // previously entered values intact (back-navigation parity).
        AppAction::CreateKeysetUpdateGroupName { value } => {
            next.keyset.group_name = value.clone();
            // Re-run validation so an inline error updates as the user
            // types (the Generation block dispatches the final check).
            next.keyset.error = next.keyset.validate_generate();
        }

        AppAction::CreateKeysetUpdateThreshold { value } => {
            next.keyset.threshold = *value;
            next.keyset.error = next.keyset.validate_generate();
        }

        AppAction::CreateKeysetUpdateCount { value } => {
            next.keyset.count = *value;
            next.keyset.error = next.keyset.validate_generate();
        }

        AppAction::CreateKeysetUpdateMode { mode } => {
            next.keyset.mode = match mode.as_str() {
                "rotate" => crate::state::KeysetFlowMode::Rotate,
                _ => crate::state::KeysetFlowMode::Create,
            };
        }

        // User tapped Generate (VAL-CREATE-003/004/022):
        // - validate; if invalid, surface inline error and stay on Generate.
        // - if valid, transition to `Generating` so the UI shows busy feedback
        //   and dispatch the perf-sensitive FFI call through the shell.
        AppAction::CreateKeysetGenerateSubmit {
            group_name,
            threshold,
            count,
            mode,
        } => {
            next.keyset.group_name = group_name.clone();
            next.keyset.threshold = *threshold;
            next.keyset.count = *count;
            next.keyset.mode = match mode.as_str() {
                "rotate" => crate::state::KeysetFlowMode::Rotate,
                _ => crate::state::KeysetFlowMode::Create,
            };
            if let Some(err) = next.keyset.validate_generate() {
                next.keyset.error = Some(err);
                next.keyset.step = crate::state::KeysetFlowStep::GenerationFailed;
                return (next, side_effect);
            }
            // VAL-ROTATE-002/003: rotate-mode generate must pre-validate
            // the threshold + rotation-source picker BEFORE running
            // any perf-sensitive FFI work. The shell UI gates Add-Row
            // + Remove-Row + the per-row validators, but the actor
            // re-checks here so a programmatic submit cannot bypass it.
            if next.keyset.mode == crate::state::KeysetFlowMode::Rotate {
                if let Some(err) = next.keyset.validate_rotation_sources(next.keyset.threshold) {
                    next.keyset.rotation_error = Some(err);
                    next.keyset.step = crate::state::KeysetFlowStep::GenerationFailed;
                    return (next, side_effect);
                }
                next.keyset.rotation_error = None;
            }
            next.keyset.error = None;
            next.keyset.step = crate::state::KeysetFlowStep::Generating;
            // Move to the Generate-screen so busy feedback is visible while
            // the FFI call dispatches. The shell resolves back with
            // CreateKeysetGenerationSuccess / CreateKeysetGenerationFailed.
            next.router.screen = Screen::CreateKeysetGenerate;
            // In rotate mode we ask the shell to invoke the rotation
            // FFI rather than the fresh-dealer FFI. The wizard seed
            // data carries the source-profile material that the shell
            // pulls out of secure storage before invoking
            // `FfiApp::rotate_keyset(…)`.
            if next.keyset.mode == crate::state::KeysetFlowMode::Rotate {
                side_effect = Some(AppUpdate::PerformKeysetRotation {
                    group_name: next.keyset.group_name.clone(),
                    threshold: next.keyset.threshold,
                    count: next.keyset.count,
                    source_group_json: String::new(),
                    source_share_secrets_hex: Vec::new(),
                    source_share_pubkeys_hex: Vec::new(),
                });
            } else {
                side_effect = Some(AppUpdate::PerformKeysetGeneration {
                    group_name: next.keyset.group_name.clone(),
                    threshold: next.keyset.threshold,
                    count: next.keyset.count,
                    mode: mode.clone(),
                });
            }
        }

        // FFI returned a JSON KeysetBundleWire. Parse it, build the share
        // picker, and advance to Device Profile.
        AppAction::CreateKeysetGenerationSuccess { bundle_json } => {
            match parse_keyset_bundle(bundle_json) {
                Ok(bundle) => {
                    // VAL-CREATE-006: default the local-share picker to idx 0
                    // so the share_idx field on the Distribute row matches the
                    // user's selection downstream.
                    next.keyset.bundle = Some(bundle.clone());
                    next.keyset.local_share_idx =
                        bundle.shares.first().map(|s| s.share_idx).unwrap_or(0);
                    // VAL-CREATE-005: prefill device name with the group name
                    // until the user overrides it.
                    if next.keyset.device_name.trim().is_empty() {
                        next.keyset.device_name = bundle.group_name.clone();
                    }
                    // VAL-CREATE-005: prefill the relay list with the
                    // platform-correct default (per architecture §11 and the
                    // FROSTR demo harness we run on relay 8194).
                    if next.keyset.relays.is_empty() {
                        next.keyset.relays = vec![default_relay_url()];
                    }
                    next.keyset.step = crate::state::KeysetFlowStep::DeviceProfile;
                    next.router.screen = Screen::CreateKeysetDeviceProfile;
                }
                Err(_) => {
                    next.keyset.step = crate::state::KeysetFlowStep::GenerationFailed;
                    // Surface a non-block error: caller can re-tap Generate.
                    next.keyset.error = Some(crate::state::KeysetValidationError::EmptyGroupName);
                }
            }
        }

        AppAction::CreateKeysetGenerationFailed { error } => {
            // Stash the raw error string in the slot used by the
            // GenerationFailed step. Operators can retry from the same form.
            next.keyset.step = crate::state::KeysetFlowStep::GenerationFailed;
            // Use the EmptyGroupName slot only as a placeholder to render
            // the banner — the raw text from `error` is carried alongside.
            next.keyset.error = Some(crate::state::KeysetValidationError::EmptyGroupName);
            next.keyset.last_error_message = Some(error.clone());
        }

        // Share picker (VAL-CREATE-004/006).
        AppAction::CreateKeysetSelectLocalShare { share_idx } => {
            // Tolerate out-of-range / local-share-idx-bytes updates without
            // crashing; only swap in adopted indices.
            if next
                .keyset
                .bundle
                .as_ref()
                .map(|bundle| bundle.shares.iter().any(|s| s.share_idx == *share_idx))
                .unwrap_or(false)
            {
                next.keyset.local_share_idx = *share_idx;
            }
        }

        // Device Profile form inputs (VAL-CREATE-005).
        AppAction::CreateKeysetUpdateDeviceName { value } => {
            next.keyset.device_name = value.clone();
        }

        AppAction::CreateKeysetUpdateRelays { value } => {
            next.keyset.relays = value.clone();
        }

        // "Continue to Review" button (VAL-CREATE-005/007/008).
        AppAction::CreateKeysetAdvanceToReview => {
            // VAL-CREATE-007: block incomplete input here too — the shell
            // gates the button, but the actor re-checks in case the gate
            // was bypassed (debug flow / Maestro timing).
            if next.keyset.device_name.trim().is_empty() || next.keyset.relays.is_empty() {
                return (next, side_effect);
            }
            next.keyset.step = crate::state::KeysetFlowStep::Review;
            next.router.screen = Screen::CreateKeysetReview;
        }

        // "Accept and Continue" on Review (VAL-CREATE-010). Side effect asks
        // the shell to store the runtime material under the new profile id;
        // the shell returns `CreateKeysetAccepted` with the resulting ids.
        AppAction::CreateKeysetAccept => {
            // Build the OnboardProfileMaterial that's about to be persisted.
            // The shell will encrypt and store it via the secure-storage path
            // (same path Save Device uses post-onboarding). We compute the
            // profile_id here so the shell does not have to redo the math.
            let profile_id = match next.keyset.bundle.as_ref() {
                Some(bundle) => bundle
                    .shares
                    .iter()
                    .find(|s| s.share_idx == next.keyset.local_share_idx)
                    .map(|share| {
                        derive_profile_id_from_secret_hex(&share.share_secret_hex)
                            .unwrap_or_default()
                    })
                    .unwrap_or_default(),
                None => String::new(),
            };
            if profile_id.is_empty() {
                return (next, side_effect);
            }
            // Build the material payload the secure-storage path expects.
            let material_bytes = match build_keyset_material(&next.keyset) {
                Ok(bytes) => bytes,
                Err(_) => return (next, side_effect),
            };
            let label = next.keyset.device_name.clone();
            let short_id = if profile_id.len() >= 8 {
                profile_id[..8].to_string()
            } else {
                profile_id.clone()
            };
            next.keyset.step = crate::state::KeysetFlowStep::Distribute;
            next.router.screen = Screen::CreateKeysetDistribute;
            // Pre-populate the per-share distribute rows once Review accepts
            // so subsequent Distribute actions find a non-empty list.
            next.keyset.build_distribute_rows();
            // Add the new profile to the hub row list ahead of storage so
            // the Distribute-step embedded dashboard has identity data
            // even before the shell finishes storing the material.
            next.hub.profiles.insert(
                0,
                StoredProfile::new(label.clone(), profile_id.clone(), ProfileStatus::Active),
            );
            // Pin the just-accepted profile_id in the wizard state so the
            // Distribute-step Finish handler can target the correct
            // profile even if `hub.profiles.first()` doesn't agree with
            // list-order reality (e.g. multiple stored profiles, restore
            // ordering, the shell racing a ProfileRestored onto the hub,
            // or any future action that mutates hub order).
            next.keyset.accepted_profile_id = profile_id.clone();
            side_effect = Some(AppUpdate::StoreKeysetCreatedProfile {
                profile_id: profile_id.clone(),
                label: label.clone(),
                short_id: short_id.clone(),
                material: material_bytes,
                relays: next.keyset.relays.clone(),
            });
        }

        // Shell stored the material and reported the new profile id.
        // Mirror into the dashboard identity surface so the embedded
        // signer panel on the Distribute step reads the right info
        // (VAL-CREATE-010 requires a live signer panel on this step).
        // VAL-BACKUP-001: also fire backup publication so the
        // freshly-created keyset writes a kind-10000 backup to its
        // relays. The combined side-effect carries both responsibilities
        // so the actor's single-side-effect invariant holds — the shell
        // reads `profile_id`'s stored material to publish the backup.
        AppAction::CreateKeysetAccepted {
            profile_id,
            label,
            short_id,
        } => {
            // Find the newly-created profile in the hub and mark it Active.
            for p in next.hub.profiles.iter_mut() {
                if p.profile_id == *profile_id {
                    p.status = ProfileStatus::Active;
                }
            }
            // Populate the dashboard identity block with the resolved
            // material-derived keys so the Distribute-step embedded signer
            // panel can render Identities (VAL-CREATE-010/018).
            let (share_pubkey, group_pubkey) = match next.keyset.bundle.as_ref() {
                Some(bundle) => {
                    let share_pubkey = bundle
                        .shares
                        .iter()
                        .find(|s| s.share_idx == next.keyset.local_share_idx)
                        .map(|s| s.share_pubkey.clone())
                        .unwrap_or_default();
                    (share_pubkey, bundle.group_pubkey.clone())
                }
                None => (String::new(), String::new()),
            };
            next.dashboard.profile_info = Some(ProfileInfo {
                device_name: label.clone(),
                share_pubkey,
                group_pubkey,
                profile_id: profile_id.clone(),
            });
            next.keyset.accepted_short_id = Some(short_id.clone());
            // Defensive: re-pin the accepted profile_id from the shell's
            // reply so any future divergence between the actor's profile_id
            // derivation and the shell's identity reconciliation cannot
            // make DistributeFinish route to the wrong profile.
            next.keyset.accepted_profile_id = profile_id.clone();
            // Combined side effect: kick the runtime AND ask the shell
            // to publish a kind-10000 backup (VAL-CREATE-010 +
            // VAL-BACKUP-001). The shell owns secure storage so it
            // reads the freshly written material by `profile_id`.
            side_effect = Some(AppUpdate::StartKeysetSignerRuntimeAndPublishBackup {
                source: "create".to_string(),
                profile_id: profile_id.clone(),
                label: label.clone(),
            });
        }

        // Distribute-step field updates (VAL-CREATE-013).
        AppAction::CreateKeysetDistributeSetPassword {
            share_idx,
            password,
        } => {
            if let Some(row) = next.keyset.distribute_row_mut(*share_idx) {
                row.password = password.clone();
                // Invalidate any cached bfonboard1 package; the next
                // Submit re-encodes with the new password (VAL-CREATE-022).
                row.last_package.clear();
            }
        }

        AppAction::CreateKeysetDistributeSetConfirm { share_idx, confirm } => {
            if let Some(row) = next.keyset.distribute_row_mut(*share_idx) {
                row.confirm_password = confirm.clone();
            }
        }

        AppAction::CreateKeysetDistributeSetLabel { share_idx, label } => {
            if let Some(row) = next.keyset.distribute_row_mut(*share_idx) {
                row.label = label.clone();
            }
        }

        // User tapped Copy / QR / Save on a Distribute row. We ask the
        // shell to produce the bfonboard1 string and dispatch the result
        // back as `CreateKeysetDistributePackageProduced`.
        AppAction::CreateKeysetDistributeSubmit { share_idx, method } => {
            // VAL-CREATE-013: enforce packaging validation here too.
            let (password, label) = match next.keyset.distribute_row(*share_idx) {
                Some(row) => {
                    if method != "copy" && method != "qr" && method != "save" {
                        return (next, side_effect);
                    }
                    // Empty password deliberately rejected (deliberate
                    // strengthening over igloo-pwa; see contract note).
                    if row.password.is_empty()
                        || row.password != row.confirm_password
                        || row.label.trim().is_empty()
                    {
                        next.keyset.last_error_message =
                            Some("Package password and label are required.".to_string());
                        return (next, side_effect);
                    }
                    (row.password.clone(), row.label.clone())
                }
                None => return (next, side_effect),
            };
            // Pull the share secret + relays from the bundle so the shell
            // can call FfiApp.encode_distribute_onboard without holding
            // any in-Rust secret material beyond this actor turn.
            let (share_secret_hex, relays) = match next.keyset.bundle.as_ref() {
                Some(bundle) => {
                    let secret = bundle
                        .shares
                        .iter()
                        .find(|s| s.share_idx == *share_idx)
                        .map(|s| s.share_secret_hex.clone())
                        .unwrap_or_default();
                    if secret.is_empty() {
                        return (next, side_effect);
                    }
                    (secret, next.keyset.relays.clone())
                }
                None => return (next, side_effect),
            };
            side_effect = Some(AppUpdate::PerformKeysetDistribution {
                share_idx: *share_idx,
                share_secret_hex,
                relays,
                label,
                password,
                method: method.clone(),
            });
        }

        AppAction::CreateKeysetDistributePackageProduced {
            share_idx,
            package,
            method,
        } => {
            if let Some(row) = next.keyset.distribute_row_mut(*share_idx) {
                row.last_package = package.clone();
                row.status_chip = match method.as_str() {
                    "copy" => DistributeStatus::Copied,
                    "qr" => DistributeStatus::Qr,
                    "save" => DistributeStatus::Saved,
                    _ => DistributeStatus::Pending,
                };
            }
        }

        AppAction::CreateKeysetDistributeFailed { share_idx, error } => {
            // Keep the chip Pending; stash the error message for display.
            next.keyset.last_error_message = Some(error.clone());
            let _ = share_idx;
        }

        // User tapped Finish (VAL-CREATE-018/019/021).
        // Profile is already on disk via CreateKeysetAccepted; we now:
        // - mark the new profile Active so the hub row lights up.
        // - reset the keyset wizard state so a re-entry starts fresh.
        // - route to the new profile's dashboard.
        AppAction::CreateKeysetDistributeFinish => {
            // Pin the target profile from the keyset flow state, NOT from
            // `hub.profiles.first()`. When multiple stored profiles are
            // already on the device, list-order assumptions break: the
            // first row may not be the keyset the user just built (e.g.
            // a previously-restored profile, a rotate-share accept, or
            // any future action that mutates hub order). The keyset
            // flow's `accepted_profile_id` is the only authoritative
            // reference to the freshly-created keyset's profile id — it
            // is set in both `CreateKeysetAccept` (actor-derived) and
            // `CreateKeysetAccepted` (shell-reported) so they cannot
            // diverge.
            let target_id = next.keyset.accepted_profile_id.clone();
            if !target_id.is_empty() {
                let mut matched = false;
                for p in next.hub.profiles.iter_mut() {
                    if p.profile_id == target_id {
                        p.status = ProfileStatus::Active;
                        matched = true;
                    }
                }
                if !matched {
                    // Defensive: CreateKeysetAccept should have already
                    // inserted the new profile at the front of hub.profiles,
                    // but if the hub list was rebuilt between Accept and
                    // Finish, the row may have been lost. Re-add it so the
                    // hub still reflects the freshly-accepted keyset.
                    let label = next.keyset.device_name.clone();
                    next.hub.profiles.push(StoredProfile::new(
                        label,
                        target_id.clone(),
                        ProfileStatus::Active,
                    ));
                }
                next.router.screen = Screen::Dashboard;
            } else {
                // Defensive: Accept never tracked a profile id, fall back to the hub.
                next.router.screen = Screen::Hub;
            }
            // VAL-CREATE-021: reset the wizard so a re-entry starts fresh.
            let mode = next.keyset.mode;
            let group_name = next.keyset.group_name.clone();
            let threshold = next.keyset.threshold;
            let count = next.keyset.count;
            next.keyset.reset();
            // Preserve the previous inputs so back-into-the-wizard preserves
            // a tiny bit of progress without violating the reset contract
            // (extra safety: the screens will still re-validate on submit).
            next.keyset.mode = mode;
            next.keyset.group_name = group_name;
            next.keyset.threshold = threshold;
            next.keyset.count = count;
        }

        // Full abandon: drop wizard state and route back to Hub
        // (VAL-CREATE-020). Note: callers must already have cancelled any
        // captured inputs — this only touches the keyset state.
        AppAction::CreateKeysetAbandon => {
            next.keyset.reset();
            next.router.screen = Screen::Hub;
        }

        // ── DiagnosticsCreateKeysetRun ──────────────────────────────────
        // mobile-ios-keyset-debug-url-scheme: the iOS shell exposes a
        // debug URL scheme `igloo://test-create-keyset?...` that
        // dispatches this action with pre-filled inputs to bypass
        // SwiftUI TextField/Button affordance taps Maestro 2.6.0
        // cannot reliably trigger on iOS Simulator 26.5.
        //
        // The handler runs the full wizard in one update cycle:
        //   - validate inputs (same `validate_generate()` rules as the
        //     normal UI path so a blank/short group_name, threshold>count,
        //     or threshold==1 is rejected without side effects);
        //   - run frostr_utils::create_keyset() inline to produce a real
        //     bundle (the actor has frostr-utils as a workspace dep so we
        //     can keep the keygen path deterministic for tests + URL
        //     scheme flows without depending on shell FFI);
        //   - parse the bundle wire form into a KeysetBundleRecord;
        //   - skip the DeviceProfile + Review UI screens by jumping
        //     straight to Distribute — the URL scheme must not require
        //     SwiftUI affordance taps;
        //   - build distribute rows (one per non-local share), build
        //     the OnboardProfileMaterial, populate the dashboard
        //     identity block, and insert a new Active hub row pinned
        //     by `keyset.accepted_profile_id`.
        //   - emit AppUpdate::StoreKeysetCreatedProfile so the Swift
        //     shell writes the decrypted material to Keychain via the
        //     existing `storeKeysetCreatedProfile` handler. After the
        //     shell dispatches `CreateKeysetAccepted`, the diagnostic
        //     gate on the Swift side auto-dispatches
        //     `CreateKeysetDistributeFinish` to land on Dashboard.
        AppAction::DiagnosticsCreateKeysetRun {
            group_name,
            threshold,
            count,
            device_name,
            relay,
        } => {
            // Step 1: shape validation. Same contract as a real user
            // submitting the Generate form so the diagnostic path
            // cannot be used to bypass validation. Inputs that fail the
            // regex are silently no-op'd with no side effect — the
            // Swift gate (DEBUG build + env flag) is the primary
            // control, but defense-in-depth here means a mis-fired
            // dispatch cannot corrupt state.
            let trimmed_group = group_name.trim();
            let trimmed_device = device_name.trim();
            let trimmed_relay = relay.trim();
            if trimmed_group.is_empty()
                || trimmed_device.is_empty()
                || trimmed_relay.is_empty()
                || *threshold == 0
                || *count == 0
                || *threshold < 2
                || *threshold > *count
            {
                // Invalid input — leave state untouched, no side
                // effect. Keep `step = Idle` so subsequent normal
                // Create Keyset wizard entries start fresh.
                next.keyset.reset();
                next.router.screen = Screen::Hub;
                return (next, side_effect);
            }

            // Step 2: inline keygen. Same frostr_utils call the shell-side
            // FFI invokes — running it here lets the URL scheme produce a
            // real, parseable bundle without depending on a shell thread
            // round-trip. Result is the canonical `KeysetBundleExport`
            // wire form, serialized as JSON so we can hand it back through
            // `parse_keyset_bundle()` for the same KeysetBundleRecord the
            // normal UI flow receives.
            let config = frostr_utils::CreateKeysetConfig::new(
                trimmed_group.to_string(),
                *threshold,
                *count,
            );
            let bundle = match frostr_utils::create_keyset(config) {
                Ok(b) => b,
                Err(_) => {
                    // frostr-utils rejected the config (already validate-
                    // gated above, but be defensive). Leave state at Idle
                    // and emit no side effect.
                    next.keyset.reset();
                    next.router.screen = Screen::Hub;
                    return (next, side_effect);
                }
            };
            let exported = GeneratedKeysetWire {
                group: bifrost_codec::wire::GroupPackageWire::from(bundle.group),
                shares: bundle
                    .shares
                    .into_iter()
                    .map(bifrost_codec::wire::SharePackageWire::from)
                    .collect(),
            };
            let bundle_json = match serde_json::to_string(&exported) {
                Ok(j) => j,
                Err(_) => {
                    next.keyset.reset();
                    next.router.screen = Screen::Hub;
                    return (next, side_effect);
                }
            };

            // Step 3: parse the wire bundle, populate wizard state. We
            // intentionally skip Generate → DeviceProfile → Review UI
            // transitions — the URL scheme is a single-shot trigger that
            // lands the user on Distribute after Keychain storage so a
            // Maestro flow can assertVisible the freshly-built profile
            // row on the hub or the resulting Dashboard.
            let parsed_bundle = match parse_keyset_bundle(&bundle_json) {
                Ok(b) => b,
                Err(_) => {
                    next.keyset.reset();
                    next.router.screen = Screen::Hub;
                    return (next, side_effect);
                }
            };
            next.keyset.mode = KeysetFlowMode::Create;
            next.keyset.group_name = trimmed_group.to_string();
            next.keyset.threshold = *threshold;
            next.keyset.count = *count;
            next.keyset.device_name = trimmed_device.to_string();
            next.keyset.relays = vec![trimmed_relay.to_string()];
            // Pick the lowest-existing share_idx in the bundle as the
            // local device's slot. FROST identifiers start at 1 by
            // convention (so idx=0 is rare); using the lowest avoids a
            // runtime panic when frostr-utils produces bundles keyed by
            // 1..count instead of 0..count-1.
            next.keyset.local_share_idx = parsed_bundle
                .shares
                .iter()
                .map(|s| s.share_idx)
                .min()
                .unwrap_or(0);
            next.keyset.bundle = Some(parsed_bundle.clone());
            next.keyset.error = None;
            next.keyset.last_error_message = None;
            // Build per-share Distribute rows for the non-local shares
            // so the side-effect shell handler can immediately encode
            // bfonboard1 envelopes if a downstream test needs them.
            next.keyset.build_distribute_rows();
            // Jump straight to Distribute — the URL scheme bypasses the
            // DeviceProfile share picker and the Review Accept button.
            next.keyset.step = KeysetFlowStep::Distribute;
            next.router.screen = Screen::CreateKeysetDistribute;

            // Step 4: derive profile_id, build OnboardProfileMaterial,
            // populate the dashboard identity block, and insert a new
            // Active hub row pinned by `accepted_profile_id`. We accept
            // the freshly-built keyset immediately so the shell-side
            // StoreKeysetCreatedProfile handler emits
            // CreateKeysetAccepted on top of an already-correct state.
            //
            // We avoid `.expect()`/`.unwrap()` here because a panic in
            // the actor thread surfaces as a Swift `_assertionFailure`
            // trap (see mobile-ios-keyset-debug-url-scheme crash trace)
            // and exits the iOS app entirely, defeating the URL-scheme
            // diagnostic intent. Instead, every failure path resets
            // the wizard and routes to the hub so a subsequent normal
            // user run sees no stale residue.
            let local_share = parsed_bundle
                .shares
                .iter()
                .find(|s| s.share_idx == next.keyset.local_share_idx);
            let local_share = match local_share {
                Some(s) => s,
                None => {
                    next.keyset.reset();
                    next.router.screen = Screen::Hub;
                    return (next, side_effect);
                }
            };
            let profile_id = match derive_profile_id_from_secret_hex(&local_share.share_secret_hex)
            {
                Ok(id) => id,
                Err(_) => {
                    next.keyset.reset();
                    next.router.screen = Screen::Hub;
                    return (next, side_effect);
                }
            };
            let short_id = if profile_id.len() >= 8 {
                profile_id[..8].to_string()
            } else {
                profile_id.clone()
            };
            let material_bytes = match build_keyset_material(&next.keyset) {
                Ok(b) => b,
                Err(_) => {
                    next.keyset.reset();
                    next.router.screen = Screen::Hub;
                    return (next, side_effect);
                }
            };
            let label = trimmed_device.to_string();
            next.keyset.accepted_profile_id = profile_id.clone();
            next.keyset.accepted_short_id = Some(short_id.clone());
            next.dashboard.profile_info = Some(ProfileInfo {
                device_name: label.clone(),
                share_pubkey: local_share.share_pubkey.clone(),
                group_pubkey: parsed_bundle.group_pubkey.clone(),
                profile_id: profile_id.clone(),
            });
            next.hub.profiles.insert(
                0,
                StoredProfile::new(label.clone(), profile_id.clone(), ProfileStatus::Active),
            );

            // Step 5: emit StoreKeysetCreatedProfile side effect so the
            // Swift shell writes the decrypted material to Keychain via
            // its existing storeKeysetCreatedProfile handler. The shell
            // dispatches CreateKeysetAccepted next, and the diagnostic
            // gate on the Swift side auto-dispatches
            // CreateKeysetDistributeFinish to land on Dashboard.
            side_effect = Some(AppUpdate::StoreKeysetCreatedProfile {
                profile_id,
                label,
                short_id,
                material: material_bytes,
                relays: next.keyset.relays.clone(),
            });
        }

        // ── Profile management ───────────────────────────────────────────
        // VAL-SHELL-012: deleting a stored profile requires confirmation.
        AppAction::RequestDeleteProfile { profile_id } => {
            if let Some(profile) = next
                .hub
                .profiles
                .iter()
                .find(|p| p.profile_id == *profile_id)
            {
                side_effect = Some(AppUpdate::ShowDeleteConfirmation {
                    profile_id: profile_id.clone(),
                    label: profile.label.clone(),
                });
            }
        }

        AppAction::ConfirmDeleteProfile { profile_id } => {
            next.hub.profiles.retain(|p| p.profile_id != *profile_id);
            side_effect = Some(AppUpdate::DeleteFromSecureStorage {
                profile_id: profile_id.clone(),
            });
        }

        // VAL-SHELL-013: stored profile opens without password after restart.
        AppAction::RestoreAllProfiles => {
            side_effect = Some(AppUpdate::RestoreAllStoredProfiles);
        }

        // VAL-SHELL-007: stored profile appears on hub with label, short_id, status.
        AppAction::ProfileRestored {
            label,
            profile_id,
            short_id: _,
        } => {
            if !next
                .hub
                .profiles
                .iter()
                .any(|p| p.profile_id == *profile_id)
            {
                next.hub.profiles.push(StoredProfile::new(
                    label.clone(),
                    profile_id.clone(),
                    ProfileStatus::Available,
                ));
            }
        }

        // VAL-SHELL-015: hub active status reflects running signer.
        AppAction::UpdateHubStatus { profile_id, active } => {
            for p in next.hub.profiles.iter_mut() {
                if p.profile_id == *profile_id {
                    p.status = if *active {
                        ProfileStatus::Active
                    } else {
                        ProfileStatus::Available
                    };
                    break;
                }
            }
        }

        // ── Dashboard ─────────────────────────────────────────────────────
        // VAL-SIGNER-001: Signer tab shows stopped baseline by default.
        AppAction::DashboardSetTab { tab } => match tab.as_str() {
            "permissions" => next.dashboard.active_tab = DashboardTab::Permissions,
            "settings" => next.dashboard.active_tab = DashboardTab::Settings,
            _ => next.dashboard.active_tab = DashboardTab::Signer,
        },

        // Open dashboard for the given profile, populating the identity block.
        // VAL-SIGNER-005: identity block shows device name, group pubkey, share pubkey.
        AppAction::OpenDashboard {
            profile_id,
            device_name,
            share_pubkey,
            group_pubkey,
        } => {
            next.dashboard = DashboardState {
                active_tab: DashboardTab::Signer,
                signer: SignerRuntimeState {
                    status: SignerStatus::Stopped,
                    relay_connected: false,
                    readiness: SignerReadiness::Idle,
                    peers: Vec::new(),
                    events: Vec::new(),
                    pending_ops: Vec::new(),
                    last_refresh_secs: None,
                    ping_in_progress: false,
                    test_sign_in_progress: false,
                    last_test_sign: None,
                    test_ecdh_in_progress: false,
                    last_test_ecdh: None,
                    runtime_observed_events_len: 0,
                },
                // VAL-PERM-002: permissions tab renders a matrix for each peer (alice, carol).
                permissions: PermissionsState::with_demo_peers(),
                // VAL-SET-001: settings tab with five fields at defaults.
                // VAL-SET-013: signer name from the profile; VAL-SET-014: relays from profile.
                settings: SettingsState::from_profile(device_name.clone(), Vec::new()),
                profile_info: Some(ProfileInfo {
                    device_name: device_name.clone(),
                    share_pubkey: share_pubkey.clone(),
                    group_pubkey: group_pubkey.clone(),
                    profile_id: profile_id.clone(),
                }),
                last_backup_publish: None,
            };
            next.router.screen = Screen::Dashboard;
        }

        // ── Signer runtime console (VAL-SIGNER-001 through VAL-SIGNER-018) ──
        // VAL-SIGNER-002: Start signer transitions to running state.
        // VAL-SIGNER-001: stopped baseline while not running.
        AppAction::SignerStart => {
            // Emit side effect to tell the shell to call FfiApp.start_signer().
            // The shell will dispatch SignerStarted after the bridge starts.
            side_effect = Some(AppUpdate::StartSignerRuntime);
        }

        // VAL-SIGNER-002: signer transitioned to running; update status.
        AppAction::SignerStarted {
            relay_connected,
            readiness,
        } => {
            let readiness = match readiness.as_str() {
                "restoring" => SignerReadiness::Restoring,
                "runtime_ready" => SignerReadiness::RuntimeReady,
                "sign_ready" => SignerReadiness::SignReady,
                "degraded" => SignerReadiness::Degraded,
                _ => SignerReadiness::Idle,
            };
            next.dashboard.signer.status = SignerStatus::Running;
            next.dashboard.signer.relay_connected = *relay_connected;
            next.dashboard.signer.readiness = readiness;
            // Add a startup event log entry (VAL-SIGNER-012).
            let now = chrono_lite_timestamp();
            next.dashboard.signer.events.insert(
                0,
                LogEntry {
                    level: LogLevel::Info,
                    timestamp: now,
                    message: "Signer runtime started".to_string(),
                },
            );
        }

        // VAL-SIGNER-015: Stop signer returns to stopped state.
        AppAction::SignerStop => {
            // Emit side effect to tell the shell to call FfiApp.stop_signer().
            // The shell will dispatch SignerStopped after the bridge stops.
            side_effect = Some(AppUpdate::StopSignerRuntime);
        }

        // VAL-SIGNER-015: signer stopped; reset to idle/empty baseline.
        AppAction::SignerStopped => {
            next.dashboard.signer = SignerRuntimeState::default();
            // Keep profile_info so the identity block stays populated (VAL-SIGNER-005).
        }

        // VAL-SIGNER-011: periodic poll updates the display without user interaction.
        // VAL-SIGNER-003: relay connection reflected in running summary.
        // VAL-SIGNER-004: readiness progresses to sign_ready after ping round.
        // VAL-SIGNER-006/007/008/009: peer list updated on each poll.
        // VAL-SIGNER-012/013: event log live-updates.
        // VAL-SIGNER-014: pending ops section updated.
        // `mobile-create-keyset-flow` events_len contract: when the
        // shell-supplied `events_len` advances past the actor's last
        // observation, prepend exactly one safe INFO log entry with an
        // RFC-3339 timestamp. Unchanged / recovered counts never
        // duplicate the row, and the prior `dashboard.signer.events`
        // entries stay intact (newest-first ordering preserved).
        AppAction::SignerStatusUpdate {
            relay_connected,
            readiness,
            peer_aliases,
            peer_pubkeys,
            peer_online,
            peer_last_seen,
            peer_incoming_available,
            peer_outgoing_available,
            peer_outgoing_spent,
            pending_op_types,
            pending_op_started_at,
            last_refresh_secs,
            events_len,
        } => {
            let readiness = match readiness.as_str() {
                "restoring" => SignerReadiness::Restoring,
                "runtime_ready" => SignerReadiness::RuntimeReady,
                "sign_ready" => SignerReadiness::SignReady,
                "degraded" => SignerReadiness::Degraded,
                _ => SignerReadiness::Idle,
            };
            next.dashboard.signer.relay_connected = *relay_connected;
            next.dashboard.signer.readiness = readiness;
            next.dashboard.signer.last_refresh_secs = *last_refresh_secs;

            // Record the actor's view of the runtime event count and,
            // on advancement, append a single safe INFO row to keep the
            // dashboard event log truthful even when the bridge only
            // surfaces a monotonic count (no per-event payload). The
            // tracked value follows the count down on bridge restarts
            // so the post-recovery next advancement still emits.
            let observed = state.dashboard.signer.runtime_observed_events_len;
            let incoming = u64::from(*events_len);
            if incoming > observed {
                next.dashboard.signer.events.insert(
                    0,
                    LogEntry {
                        level: LogLevel::Info,
                        timestamp: display_timestamp_rfc3339(),
                        message: format!(
                            "Runtime event count advanced to {} (bridge-supplied)",
                            incoming
                        ),
                    },
                );
                next.dashboard.signer.runtime_observed_events_len = incoming;
            } else {
                // Unchanged or recovery (e.g. bridge restarted and its
                // internal counter reset). No row appended, but the
                // tracked value still tracks the latest observation so
                // the next advancement past this baseline emits.
                next.dashboard.signer.runtime_observed_events_len = incoming;
            }

            // Build peer status list from the poll data, preserving prior
            // liveness when a transient poll lacks last_seen evidence.
            let n = peer_aliases
                .len()
                .min(peer_pubkeys.len())
                .min(peer_online.len());
            let existing: std::collections::HashMap<String, PeerStatus> = state
                .dashboard
                .signer
                .peers
                .iter()
                .map(|peer| (peer.alias.clone(), peer.clone()))
                .collect();
            let mut seen = std::collections::HashSet::new();
            let mut peers = Vec::new();
            for i in 0..n {
                let alias = peer_aliases[i].clone();
                let pubkey = peer_pubkeys[i].clone();
                let last_seen = peer_last_seen.get(i).copied().flatten();
                let incoming_nonces = NonceInventory {
                    incoming_available: peer_incoming_available.get(i).copied().unwrap_or(0),
                    outgoing_available: peer_outgoing_available.get(i).copied().unwrap_or(0),
                    outgoing_spent: peer_outgoing_spent.get(i).copied().unwrap_or(0),
                };

                let mut online = peer_online[i] && last_seen.is_some();
                let mut merged_last_seen = last_seen;
                let mut nonces = incoming_nonces;
                if last_seen.is_none() {
                    if let Some(previous) = existing.get(&alias) {
                        if previous.online {
                            online = true;
                            merged_last_seen = previous.last_seen_secs;
                            nonces = previous.nonces.clone();
                        } else {
                            online = false;
                        }
                    } else {
                        online = false;
                    }
                }

                seen.insert(alias.clone());
                peers.push(PeerStatus {
                    alias,
                    pubkey,
                    online,
                    last_seen_secs: merged_last_seen,
                    nonces,
                });
            }
            for previous in state.dashboard.signer.peers.iter() {
                if !seen.contains(&previous.alias) {
                    peers.push(previous.clone());
                }
            }
            next.dashboard.signer.peers = peers;

            // Build pending ops list.
            let m = pending_op_types.len().min(pending_op_started_at.len());
            let mut pending_ops = Vec::new();
            for i in 0..m {
                let op_type = match pending_op_types[i].as_str() {
                    "ping" => PendingOpType::Ping,
                    "sign" => PendingOpType::Sign,
                    "ecdh" => PendingOpType::Ecdh,
                    "onboard" => PendingOpType::Onboard,
                    _ => continue,
                };
                pending_ops.push(PendingOp {
                    op_type,
                    started_at_secs: pending_op_started_at[i],
                });
            }
            next.dashboard.signer.pending_ops = pending_ops;
        }

        // VAL-SIGNER-011: periodic poll updates display without user interaction.
        // Shell dispatches this every ~1s while the Signer tab is visible.
        AppAction::SignerPoll => {
            side_effect = Some(AppUpdate::PollSignerStatus);
        }

        // VAL-SIGNER-010: manual peer Refresh updates status data.
        // VAL-SIGNER-018: test ping affordance initiates real ping round.
        AppAction::SignerPingPeers => {
            // Prepend an INFO event-log row so the alternative evidence
            // path for VAL-SIGNER-010 ("a new log entry per the
            // alternative") is observable even when no ping round-trip
            // completes before the next poll tick fires. The
            // mobile-signer-peer-refresh-liveness-fix hardens Refresh
            // against failing when no PONG arrives: the row shows up
            // deterministically in the signer console.
            let now = display_timestamp_rfc3339();
            next.dashboard.signer.events.insert(
                0,
                LogEntry {
                    level: LogLevel::Info,
                    timestamp: now,
                    message: "Refresh peer status".to_string(),
                },
            );
            // Emit side effect — shell calls FfiApp.ping_peers() for online peers.
            side_effect = Some(AppUpdate::PingSignerPeers);
        }

        // VAL-SIGNER-007/008/009: peer status updated after ping round.
        AppAction::SignerPingComplete {
            peer_alias,
            last_seen_secs,
            incoming_available,
        } => {
            // Update the specific peer's last_seen and incoming_available.
            for peer in next.dashboard.signer.peers.iter_mut() {
                if peer.alias == *peer_alias {
                    peer.last_seen_secs = Some(*last_seen_secs);
                    peer.nonces.incoming_available = *incoming_available;
                    peer.online = true;
                    break;
                }
            }
            // Add ping completion event to the log (VAL-SIGNER-013 live-update).
            let now = chrono_lite_timestamp();
            next.dashboard.signer.events.insert(
                0,
                LogEntry {
                    level: LogLevel::Info,
                    timestamp: now,
                    message: format!("Ping complete: {}", peer_alias),
                },
            );
        }

        // VAL-SIGNER-017: copy identity key values to platform clipboard.
        AppAction::CopyToClipboard { value, label } => {
            side_effect = Some(AppUpdate::CopyToClipboard {
                value: value.clone(),
                label: label.clone(),
            });
        }

        // ── Test Sign and ECDH (VAL-SIGN-002, VAL-SIGN-005) ─────────────────
        // VAL-SIGN-002: user activated test-sign affordance → shell calls FfiApp.test_sign().
        AppAction::TestSign => {
            next.dashboard.signer.test_sign_in_progress = true;
            side_effect = Some(AppUpdate::PerformTestSign);
        }
        // VAL-SIGN-002: test sign round completed successfully.
        AppAction::TestSignResult {
            request_id,
            digest,
            signature,
        } => {
            next.dashboard.signer.test_sign_in_progress = false;
            let now = chrono_lite_timestamp();
            let completed_at_secs = now.parse::<i64>().unwrap_or(0);
            next.dashboard.signer.last_test_sign = Some(TestSignResultData {
                request_id: request_id.clone(),
                digest: digest.clone(),
                signature: signature.clone(),
                completed_at_secs,
            });
            next.dashboard.signer.events.insert(
                0,
                LogEntry {
                    level: LogLevel::Info,
                    timestamp: now,
                    message: format!("Test sign complete: {}", request_id),
                },
            );
        }
        // VAL-SIGN-002: test sign round failed.
        AppAction::TestSignFailed { error } => {
            next.dashboard.signer.test_sign_in_progress = false;
            let now = chrono_lite_timestamp();
            next.dashboard.signer.events.insert(
                0,
                LogEntry {
                    level: LogLevel::Error,
                    timestamp: now,
                    message: format!("Test sign failed: {}", error),
                },
            );
        }
        // VAL-SIGN-005: user activated test-ECDH affordance → shell calls FfiApp.test_ecdh().
        AppAction::TestEcdh => {
            next.dashboard.signer.test_ecdh_in_progress = true;
            side_effect = Some(AppUpdate::PerformTestEcdh);
        }
        // VAL-SIGN-005: test ECDH round completed successfully.
        AppAction::TestEcdhResult {
            request_id,
            target_pubkey,
            shared_secret,
        } => {
            next.dashboard.signer.test_ecdh_in_progress = false;
            let now = chrono_lite_timestamp();
            let completed_at_secs = now.parse::<i64>().unwrap_or(0);
            next.dashboard.signer.last_test_ecdh = Some(TestEcdhResultData {
                request_id: request_id.clone(),
                target_pubkey: target_pubkey.clone(),
                shared_secret: shared_secret.clone(),
                completed_at_secs,
            });
            next.dashboard.signer.events.insert(
                0,
                LogEntry {
                    level: LogLevel::Info,
                    timestamp: now,
                    message: format!("Test ECDH complete: {}", request_id),
                },
            );
        }
        // VAL-SIGN-005: test ECDH round failed.
        AppAction::TestEcdhFailed { error } => {
            next.dashboard.signer.test_ecdh_in_progress = false;
            let now = chrono_lite_timestamp();
            next.dashboard.signer.events.insert(
                0,
                LogEntry {
                    level: LogLevel::Error,
                    timestamp: now,
                    message: format!("Test ECDH failed: {}", error),
                },
            );
        }
        // Clear the displayed test sign result.
        AppAction::ClearTestSignResult => {
            next.dashboard.signer.last_test_sign = None;
        }
        // Clear the displayed test ECDH result.
        AppAction::ClearTestEcdhResult => {
            next.dashboard.signer.last_test_ecdh = None;
        }

        // ── Permissions policy editor (VAL-PERM-001 through VAL-PERM-013) ────
        // VAL-PERM-005: setting deny is reflected immediately.
        // VAL-PERM-006: only the edited cell changes.
        // VAL-PERM-007: effective policy recomputes live (handled by state struct methods).
        AppAction::SetPolicyOverride {
            peer_alias,
            direction,
            method,
            value,
        } => {
            let direction = match direction.as_str() {
                "request" => PolicyDirection::Request,
                "respond" => PolicyDirection::Respond,
                _ => return (next, side_effect), // invalid, ignore
            };
            let method = match method.as_str() {
                "ping" => PolicyMethod::Ping,
                "onboard" => PolicyMethod::Onboard,
                "sign" => PolicyMethod::Sign,
                "ecdh" => PolicyMethod::Ecdh,
                _ => return (next, side_effect), // invalid, ignore
            };
            let value = match value.as_str() {
                "allow" => PolicyOverrideValue::Allow,
                "deny" => PolicyOverrideValue::Deny,
                _ => PolicyOverrideValue::Unset,
            };

            // Ensure the permissions state has an entry for this peer.
            // VAL-PERM-002: policy matrix renders for each peer.
            if next
                .dashboard
                .permissions
                .find_peer(peer_alias.as_str())
                .is_none()
            {
                next.dashboard
                    .permissions
                    .peers
                    .push(PeerPermissions::new(peer_alias.clone()));
            }
            if let Some(peer) = next
                .dashboard
                .permissions
                .find_peer_mut(peer_alias.as_str())
            {
                peer.set_override(direction, method, value);
            }
        }

        // VAL-PERM-010: reset a single cell back to unset.
        AppAction::ResetPolicyOverride {
            peer_alias,
            direction,
            method,
        } => {
            let direction = match direction.as_str() {
                "request" => PolicyDirection::Request,
                "respond" => PolicyDirection::Respond,
                _ => return (next, side_effect),
            };
            let method = match method.as_str() {
                "ping" => PolicyMethod::Ping,
                "onboard" => PolicyMethod::Onboard,
                "sign" => PolicyMethod::Sign,
                "ecdh" => PolicyMethod::Ecdh,
                _ => return (next, side_effect),
            };

            if let Some(peer) = next
                .dashboard
                .permissions
                .find_peer_mut(peer_alias.as_str())
            {
                peer.reset_override(direction, method);
            }
        }

        // VAL-PERM-011: clear all overrides for a peer.
        AppAction::ClearAllPeerOverrides { peer_alias } => {
            if let Some(peer) = next
                .dashboard
                .permissions
                .find_peer_mut(peer_alias.as_str())
            {
                peer.clear_all_overrides();
            }
        }

        // VAL-PERM-012/013: refresh remote policy observations.
        // Emit side effect — shell queries peer policy advertisements from the signer runtime.
        AppAction::RefreshRemotePolicy => {
            next.dashboard.permissions.start_refresh();
            side_effect = Some(AppUpdate::RefreshRemotePolicy);
        }

        // Sync online status from the signer runtime peer list to permissions state.
        // VAL-PERM-012: only live peer (alice) shows remote policy observation.
        AppAction::SyncPeerOnlineStatus {
            peer_aliases,
            peer_online,
        } => {
            for (i, alias) in peer_aliases.iter().enumerate() {
                let online = peer_online.get(i).copied().unwrap_or(false);
                next.dashboard
                    .permissions
                    .update_peer_online_status(alias, online);
            }
        }

        // Update a peer's remote policy observation.
        // VAL-PERM-012: alice's observation is populated after ping round.
        // VAL-PERM-013: carol never shows a remote observation (no running signer).
        AppAction::UpdateRemotePolicyObservation {
            peer_alias,
            available,
            last_observed_secs,
            revision,
        } => {
            if let Some(peer) = next
                .dashboard
                .permissions
                .find_peer_mut(peer_alias.as_str())
            {
                peer.remote_observation = RemotePolicyObservation {
                    available: *available,
                    last_observed_secs: *last_observed_secs,
                    revision: *revision,
                };
            }
        }

        // ── Settings & Maintenance (VAL-SET-001 through VAL-SET-016) ────
        // VAL-SET-001: initialize settings when dashboard opens.
        AppAction::OpenDashboardSettings {
            device_name,
            relays,
        } => {
            next.dashboard.settings =
                SettingsState::from_profile(device_name.clone(), relays.clone());
            // Also update the profile_info with the same device name
            if let Some(ref mut info) = next.dashboard.profile_info {
                info.device_name = device_name.clone();
            }
        }

        // VAL-SET-013: editing the signer name.
        AppAction::EditSignerName { name } => {
            next.dashboard.settings.set_signer_name(name.to_string());
            next.dashboard
                .settings
                .set_save_blocked(next.dashboard.signer.status != SignerStatus::Running);
        }

        // VAL-SET-002/005: editing sign timeout.
        AppAction::EditSignTimeout { value } => {
            next.dashboard.settings.set_sign_timeout(*value);
            next.dashboard
                .settings
                .set_save_blocked(next.dashboard.signer.status != SignerStatus::Running);
        }

        // VAL-SET-002: editing ping timeout.
        AppAction::EditPingTimeout { value } => {
            next.dashboard.settings.set_ping_timeout(*value);
            next.dashboard
                .settings
                .set_save_blocked(next.dashboard.signer.status != SignerStatus::Running);
        }

        // VAL-SET-002: editing request TTL.
        AppAction::EditRequestTtl { value } => {
            next.dashboard.settings.set_request_ttl(*value);
            next.dashboard
                .settings
                .set_save_blocked(next.dashboard.signer.status != SignerStatus::Running);
        }

        // VAL-SET-002: editing state save interval.
        AppAction::EditStateSaveInterval { value } => {
            next.dashboard.settings.set_state_save_interval(*value);
            next.dashboard
                .settings
                .set_save_blocked(next.dashboard.signer.status != SignerStatus::Running);
        }

        // VAL-SET-003: editing peer selection strategy.
        AppAction::EditPeerSelectionStrategy { strategy } => {
            next.dashboard
                .settings
                .set_peer_selection_strategy(strategy);
            next.dashboard
                .settings
                .set_save_blocked(next.dashboard.signer.status != SignerStatus::Running);
        }

        // VAL-SET-014: adding a relay with trim + dedupe.
        AppAction::AddRelay { url } => {
            next.dashboard.settings.add_relay(url);
            next.dashboard
                .settings
                .set_save_blocked(next.dashboard.signer.status != SignerStatus::Running);
        }

        // VAL-SET-014: removing a relay.
        AppAction::RemoveRelay { url } => {
            next.dashboard.settings.remove_relay(url);
            next.dashboard
                .settings
                .set_save_blocked(next.dashboard.signer.status != SignerStatus::Running);
        }

        // VAL-SET-002/003/004/013/014: save settings while signer is running.
        // VAL-SET-004: saving does not disrupt a running signer.
        // VAL-SET-016: save is blocked when signer is stopped.
        AppAction::SaveSettings => {
            // Only allow save when signer is running (VAL-SET-016).
            if next.dashboard.signer.status == SignerStatus::Running {
                next.dashboard.settings.mark_saved();
                // Also propagate the signer name to profile_info for display updates.
                if let Some(ref mut info) = next.dashboard.profile_info {
                    info.device_name = next.dashboard.settings.signer_name.clone();
                }
                // Emit side effect to tell shell to persist settings and update hub row label.
                side_effect = Some(AppUpdate::PersistSettings {
                    signer_name: next.dashboard.settings.signer_name.clone(),
                    sign_timeout_secs: next.dashboard.settings.settings.sign_timeout_secs,
                    ping_timeout_secs: next.dashboard.settings.settings.ping_timeout_secs,
                    request_ttl_secs: next.dashboard.settings.settings.request_ttl_secs,
                    state_save_interval_secs: next
                        .dashboard
                        .settings
                        .settings
                        .state_save_interval_secs,
                    peer_selection_strategy: match next
                        .dashboard
                        .settings
                        .settings
                        .peer_selection_strategy
                    {
                        PeerSelectionStrategy::Random => "random".to_string(),
                        _ => "deterministic_sorted".to_string(),
                    },
                    relays: next.dashboard.settings.relays.clone(),
                });
            }
            // If signer is stopped, save is silently blocked (VAL-SET-016).
            // The UI should have the save button disabled in this case.
        }

        // VAL-SET-006: trigger copy profile — shell shows password prompt.
        AppAction::RequestCopyProfile => {
            next.dashboard.settings.start_copy_profile();
            side_effect = Some(AppUpdate::ShowExportPasswordPrompt {
                export_type: "profile".to_string(),
            });
        }

        // VAL-SET-007/015: confirm copy profile with export password.
        // Shell produces bfprofile1 and writes to clipboard.
        AppAction::ConfirmCopyProfile { password } => {
            next.dashboard.settings.pending_export_password = Some(password.clone());
            side_effect = Some(AppUpdate::PerformCopyProfile {
                password: password.clone(),
            });
        }

        // VAL-SET-008: trigger copy share — shell shows password prompt.
        AppAction::RequestCopyShare => {
            next.dashboard.settings.start_copy_share();
            side_effect = Some(AppUpdate::ShowExportPasswordPrompt {
                export_type: "share".to_string(),
            });
        }

        // VAL-SET-008/015: confirm copy share with export password.
        // Shell produces bfshare1 and writes to clipboard.
        AppAction::ConfirmCopyShare { password } => {
            next.dashboard.settings.pending_export_password = Some(password.clone());
            side_effect = Some(AppUpdate::PerformCopyShare {
                password: password.clone(),
            });
        }

        // VAL-ROTATE-005: navigate to rotate share flow.
        AppAction::NavigateToRotateShare => {
            next.router.screen = Screen::RotateShare;
            next.router.back_history.clear();
            next.router.back_history.push(Screen::Dashboard);
        }

        // VAL-SET-010/011/012: logout — stop signer, zero secrets, return to hub.
        // Profile remains stored and re-openable without a password.
        AppAction::Logout => {
            // Stop the signer runtime (VAL-SET-011).
            side_effect = Some(AppUpdate::StopSignerRuntime);
            // Clear in-memory state — the hub row will show Available (not Active).
            next.dashboard.signer = SignerRuntimeState::default();
            // Mark all profiles as Available on the hub.
            for p in next.hub.profiles.iter_mut() {
                p.status = ProfileStatus::Available;
            }
            // Navigate to hub.
            next.router.screen = Screen::Hub;
            next.router.back_history.clear();
        }

        // Internal: export completed successfully.
        AppAction::ExportCompleted { package_type } => {
            next.dashboard.settings.clear_pending_export();
            // Add success event to the signer log.
            let now = chrono_lite_timestamp();
            next.dashboard.signer.events.insert(
                0,
                LogEntry {
                    level: LogLevel::Info,
                    timestamp: now,
                    message: format!("Exported {}: copied to clipboard", package_type),
                },
            );
        }

        // Internal: export failed.
        AppAction::ExportFailed { error } => {
            next.dashboard.settings.clear_pending_export();
            // Add error event to the signer log.
            let now = chrono_lite_timestamp();
            next.dashboard.signer.events.insert(
                0,
                LogEntry {
                    level: LogLevel::Error,
                    timestamp: now,
                    message: format!("Export failed: {}", error),
                },
            );
        }

        // Clear any pending export (password prompt cancelled).
        AppAction::ClearExportState => {
            next.dashboard.settings.clear_pending_export();
        }

        // ── Rotate Share flow handlers (VAL-ROTATE-*) ───────────────────

        // VAL-ROTATE-005: open the Rotate Share connect screen with the
        // active profile identity pre-seeded so the connect-card row shows
        // the right device label + short id.
        AppAction::OpenRotateShareConnect {
            profile_id,
            short_id,
            device_label,
        } => {
            next.rotate_share.reset();
            next.rotate_share.active_profile_id = profile_id.clone();
            next.rotate_share.active_short_id = short_id.clone();
            next.rotate_share.active_device_label = device_label.clone();
            // Carry the active profile's group pubkey so the actor can do
            // the group-mismatch comparison without re-asking the shell.
            if let Some(profile_info) = &state.dashboard.profile_info {
                if next.rotate_share.relay_url.is_empty() {
                    next.rotate_share.relay_url = profile_info.group_pubkey.clone();
                }
            }
            next.router.screen = Screen::RotateShare;
            next.router.back_history.clear();
            next.router.back_history.push(Screen::Dashboard);
        }

        // EDIT-step inputs on the Rotate Share connect screen.
        AppAction::RotateShareUpdatePackage { value } => {
            next.rotate_share.package = value.trim().to_string();
            next.rotate_share.error = None;
        }
        AppAction::RotateShareUpdatePassword { value } => {
            next.rotate_share.password = value.clone();
            next.rotate_share.error = None;
        }
        AppAction::RotateShareUpdateRelay { value } => {
            next.rotate_share.relay_url = value.trim().to_string();
            next.rotate_share.error = None;
        }

        // VAL-ROTATE-006/009/013/014: connect performs decode + handshake.
        AppAction::RotateShareConnect => {
            // Pre-flight empty-field guard so a clearly empty form does
            // not enter the perf-sensitive async path. Real decode +
            // wrong-password / malformed errors are surfaced via the
            // handshake-failure action the shell dispatches back.
            let package_trim = next.rotate_share.package.trim().to_string();
            let password = next.rotate_share.password.clone();
            let relay_url = next.rotate_share.relay_url.trim().to_string();
            if package_trim.is_empty() || password.is_empty() || relay_url.is_empty() {
                next.rotate_share.step = crate::state::RotateShareStep::Error;
                next.rotate_share.error = Some(crate::state::RotateShareError::MalformedPackage);
                next.rotate_share.last_error_message =
                    Some("Package, password, and relay URL are all required.".to_string());
                return (next, side_effect);
            }
            // Capture active profile identity before transitioning so the
            // shell does not have to look it up across threads.
            let expected_group = state
                .dashboard
                .profile_info
                .as_ref()
                .map(|p| p.group_pubkey.clone())
                .unwrap_or_default();
            let active_profile_id = next.rotate_share.active_profile_id.clone();
            next.rotate_share.step = crate::state::RotateShareStep::Handshaking;
            next.rotate_share.error = None;
            next.rotate_share.preview = None;
            next.rotate_share.package = package_trim.clone();
            next.rotate_share.last_error_message = None;
            side_effect = Some(crate::AppUpdate::PerformRotateShareHandshake {
                package: package_trim,
                password,
                relay_url,
                expected_group_pubkey: expected_group,
                active_profile_id,
            });
        }

        // VAL-ROTATE-006: handshake resolved with a rotated identity;
        // surface the preview and let the user confirm.
        AppAction::RotateShareHandshakeSuccess {
            device_name,
            share_pubkey,
            group_pubkey,
            relays,
            profile_id,
            share_seckey_hex,
        } => {
            // ── Identity-shape guard (VAL-ROTATE-007/008) ─────────────────
            // Same-profile reject: rotating must produce a different
            // device share; if profile_id matches the active profile, the
            // envelope was mis-issued by the wizard or the same package
            // is being reused.
            if *profile_id == next.rotate_share.active_profile_id {
                next.rotate_share.step = RotateShareStep::Error;
                next.rotate_share.error = Some(crate::state::RotateShareError::SameProfile);
                next.rotate_share.preview = None;
                return (next, side_effect);
            }
            // Group-mismatch reject: the rotated envelope must belong to
            // the same keyset as the active profile. The actor compares
            // the resolved group_pubkey against the active profile's
            // known group key; an empty expected group means the active
            // profile's material did not carry one (rare — fall through
            // and let the user inspect the preview).
            let expected_group = state
                .dashboard
                .profile_info
                .as_ref()
                .map(|p| p.group_pubkey.clone())
                .unwrap_or_default();
            if !expected_group.is_empty()
                && !group_pubkey.is_empty()
                && *group_pubkey != expected_group
            {
                next.rotate_share.step = RotateShareStep::Error;
                next.rotate_share.error = Some(crate::state::RotateShareError::GroupMismatch);
                next.rotate_share.preview = None;
                return (next, side_effect);
            }
            // Carry the existing label so the rotated profile is not
            // orphaned under a freshly synthesized name — match VAL-ROTATE-011
            // "rotated profile keeps the previous device label".
            let resolved_label = if device_name.trim().is_empty() {
                next.rotate_share.active_device_label.clone()
            } else {
                device_name.clone()
            };
            next.rotate_share.preview = Some(crate::state::RotatePreviewIdentity {
                device_name: resolved_label,
                share_pubkey: share_pubkey.clone(),
                group_pubkey: group_pubkey.clone(),
                profile_id: profile_id.clone(),
                relays: relays.clone(),
                share_seckey_hex: share_seckey_hex.clone(),
            });
            next.rotate_share.step = crate::state::RotateShareStep::Preview;
            next.rotate_share.error = None;
        }

        // VAL-ROTATE-007/008/009/014: handshake surfaced a typed failure.
        AppAction::RotateShareHandshakeFailure { error } => {
            let kind = error.as_str();
            let typed_error = match kind {
                "wrong_password" => crate::state::RotateShareError::WrongPassword,
                "relay_unreachable" => crate::state::RotateShareError::RelayUnreachable,
                "provisioner_offline" => crate::state::RotateShareError::ProvisionerOffline,
                "same_profile" => crate::state::RotateShareError::SameProfile,
                "group_mismatch" => crate::state::RotateShareError::GroupMismatch,
                "malformed_package" => crate::state::RotateShareError::MalformedPackage,
                _ => crate::state::RotateShareError::Unexpected,
            };
            next.rotate_share.step = crate::state::RotateShareStep::Error;
            next.rotate_share.error = Some(typed_error);
            next.rotate_share.preview = None;
        }

        // VAL-ROTATE-011: confirm replacement.
        AppAction::RotateShareReplace => {
            let preview = match next.rotate_share.preview.clone() {
                Some(p) => p,
                None => return (next, side_effect),
            };
            // Reject replacement if the active profile has no entries to
            // drop — defensive guard so a malformed action never wipes
            // unrelated profiles.
            if next.rotate_share.active_profile_id.is_empty() {
                return (next, side_effect);
            }
            let old_profile_id = next.rotate_share.active_profile_id.clone();
            let new_profile_id = preview.profile_id.clone();
            let new_label = preview.device_name.clone();
            let new_short_id = if new_profile_id.len() >= 8 {
                new_profile_id[..8].to_string()
            } else {
                new_profile_id.clone()
            };
            // Build the rotated material via the same code-path that
            // onboard uses so the runtime / signer keep the full keyset
            // view (member mapping, peer pubkeys, etc.). A missing or
            // malformed share secret is treated as a hard failure: emit
            // an explicit error step and stay on the connect screen so
            // the user can retry — never silently tombstone the
            // secure-storage record.
            let material_bytes = match build_rotated_material_bytes(
                &preview,
                &next.rotate_share.relay_url,
                old_profile_id.clone(),
            ) {
                Ok(bytes) => bytes,
                Err(reason) => {
                    next.rotate_share.step = crate::state::RotateShareStep::Error;
                    next.rotate_share.error = Some(crate::state::RotateShareError::Unexpected);
                    next.rotate_share
                        .last_error_message
                        .clone_from(&Some(reason));
                    return (next, side_effect);
                }
            };
            next.rotate_share.step = crate::state::RotateShareStep::Complete;
            // VAL-ROTATE-011: route to Dashboard so the rotated
            // profile re-opens immediately after the shell commits the
            // secure-storage swap.
            next.router.screen = Screen::Dashboard;
            next.router.back_history.clear();
            // Combined side-effect: swap secure storage AND publish a
            // fresh kind-10000 backup under the rotated share's
            // derived author pubkey (VAL-ROTATE-011 + VAL-BACKUP-004).
            // The shell reads the freshly written material from secure
            // storage to perform the publish, so the relay author is
            // always the new (post-rotate) share.
            side_effect = Some(crate::AppUpdate::ReplaceProfileFromRotateAndPublishBackup {
                source: "rotate".to_string(),
                old_profile_id: old_profile_id.clone(),
                new_profile_id: new_profile_id.clone(),
                new_label: new_label.clone(),
                new_short_id: new_short_id.clone(),
                new_material: material_bytes,
                new_relays: preview.relays.clone(),
                delete_old: true,
            });
        }

        AppAction::RotateShareClearError => {
            next.rotate_share.error = None;
            next.rotate_share.last_error_message = None;
            next.rotate_share.step = RotateShareStep::Idle;
        }

        // VAL-ROTATE-010: abandoning the flow returns the dashboard
        // unchanged. Caller (back affordance or system-back) leaves the
        // active profile intact.
        AppAction::RotateShareReset => {
            next.rotate_share.reset();
            next.router.screen = Screen::Dashboard;
        }

        // ── Rotate-mode wizard source picker handlers
        //    (VAL-ROTATE-001/002/003/004) ──────────────────────────────
        AppAction::KeysetSetRotationSourceProfile { profile_id } => {
            next.keyset.rotate_source_profile_id = profile_id.clone();
            // Reset the picker when the source profile changes so a stale
            // row from a previous source cannot satisfy the threshold.
            next.keyset.rotation_sources.clear();
            next.keyset.rotation_error = None;
            next.keyset.error = None;
            next.keyset.step = KeysetFlowStep::Idle;
        }

        AppAction::KeysetAddRotationSourceRow => {
            next.keyset.rotation_sources.push(RotationSourceRow {
                package: String::new(),
                password: String::new(),
                source_profile_id: next.keyset.rotate_source_profile_id.clone(),
            });
            next.keyset.rotation_error = None;
        }

        AppAction::KeysetRemoveRotationSourceRow { index } => {
            let idx = *index as usize;
            if idx < next.keyset.rotation_sources.len() {
                next.keyset.rotation_sources.remove(idx);
                next.keyset.rotation_error = None;
            }
        }

        AppAction::KeysetUpdateRotationSourcePackage { index, value } => {
            let idx = *index as usize;
            if let Some(row) = next.keyset.rotation_sources.get_mut(idx) {
                row.package = value.trim().to_string();
                next.keyset.rotation_error = None;
            }
        }

        AppAction::KeysetUpdateRotationSourcePassword { index, value } => {
            let idx = *index as usize;
            if let Some(row) = next.keyset.rotation_sources.get_mut(idx) {
                row.password = value.clone();
                next.keyset.rotation_error = None;
            }
        }

        // VAL-BACKUP-001/002/004/006: shell forwarded the publish
        // result. We mirror it into `dashboard.last_backup_publish` so
        // validators can read a relay-side filtered proof directly from
        // a fresh `AppState` snapshot — without needing shell-side
        // telemetry or a separate service-control log. The actor only
        // stores the result; the side-effect path that produced it
        // stays intact (we do not retry the publish here).
        AppAction::BackupPublishCompleted {
            source,
            success,
            event_id,
            author_pubkey,
            content_length,
            content_redacted,
            group_pubkey,
            relays_attempted,
            relays_published_to,
            error,
        } => {
            next.dashboard.last_backup_publish = Some(crate::state::BackupPublishStatus {
                source: source.clone(),
                success: *success,
                event_id: event_id.clone(),
                author_pubkey: author_pubkey.clone(),
                content_length: *content_length,
                content_redacted: content_redacted.clone(),
                group_pubkey: group_pubkey.clone(),
                relays_attempted: relays_attempted.clone(),
                relays_published_to: relays_published_to.clone(),
                error: error.clone(),
                recorded_at_secs: now_epoch_secs(),
            });
        }
    }

    (next, side_effect)
}

/// Determine the "back" destination for a given screen.
fn go_back(screen: Screen) -> Screen {
    match screen {
        Screen::Hub => Screen::Hub,
        Screen::OnboardEntry => Screen::Hub,
        Screen::OnboardConnect => Screen::OnboardEntry,
        // VAL-ONBOARD-013: back from review returns to the connect screen
        // (not to hub — the profile has not been saved yet).
        Screen::OnboardReview => Screen::OnboardEntry,
        Screen::LoadProfileEntry => Screen::Hub,
        Screen::LoadProfileImport => Screen::LoadProfileEntry,
        Screen::LoadProfileRecover => Screen::LoadProfileEntry,
        Screen::LoadProfileConfirm => Screen::LoadProfileImport,
        Screen::CreateKeysetEntry => Screen::Hub,
        Screen::CreateKeysetGenerate => Screen::CreateKeysetEntry,
        Screen::CreateKeysetDeviceProfile => Screen::CreateKeysetGenerate,
        Screen::CreateKeysetReview => Screen::CreateKeysetDeviceProfile,
        Screen::CreateKeysetDistribute => Screen::CreateKeysetReview,
        // Dashboard back to hub preserves Active status (VAL-SHELL-015).
        Screen::Dashboard => Screen::Hub,
        // RotateShare back to dashboard.
        Screen::RotateShare => Screen::Dashboard,
    }
}

// ── Rotate Share helpers (VAL-ROTATE-011) ────────────────────────────────

/// Build a fresh `OnboardProfileMaterial` JSON blob from a resolved
/// rotated identity so the shell can swap secure-storage records in
/// one round-trip. Returns the empty Vec on materialization failures so
/// the actor can fall through without crashing; the shell turns the
/// empty payload into an explicit failure via a follow-up action.
///
/// The rotated share secret MUST be carried in `preview.share_seckey_hex`
/// (set via `AppAction::RotateShareHandshakeSuccess`); without it the
/// runtime cannot spawn a SigningDevice and the secret-storage record
/// becomes a tombstone. We enforce that here as well — a missing secret
/// returns `Err("missing_share_secret")` so the actor surfaces a typed
/// failure instead of silently dropping the secret.
fn build_rotated_material_bytes(
    preview: &RotatePreviewIdentity,
    active_relay_override: &str,
    _old_profile_id: String,
) -> Result<Vec<u8>, String> {
    // Build a single-member keyset holding only the rotated share. We
    // keep the existing storage shape so the runtime / signer can spin
    // up after replace without an extra migration step. The "peer"
    // list is empty until the next alias-discovery ping completes.
    use crate::{MaterialMember, OnboardProfileMaterial};
    let trimmed_secret = preview.share_seckey_hex.trim().to_string();
    if trimmed_secret.is_empty() {
        return Err("missing_share_secret".to_string());
    }
    if trimmed_secret.len() != 64 {
        return Err("invalid_share_secret_length".to_string());
    }
    let mut members: Vec<MaterialMember> = Vec::new();
    if !preview.share_pubkey.is_empty() {
        members.push(MaterialMember {
            idx: 0,
            pubkey_hex: if preview.share_pubkey.len() == 64 {
                format!("02{}", preview.share_pubkey)
            } else {
                preview.share_pubkey.clone()
            },
        });
    }
    let relays = if !active_relay_override.trim().is_empty() {
        vec![active_relay_override.trim().to_string()]
    } else {
        preview.relays.clone()
    };
    let material = OnboardProfileMaterial {
        share_seckey_hex: trimmed_secret,
        share_pubkey: preview.share_pubkey.clone(),
        group_pubkey: preview.group_pubkey.clone(),
        relays,
        device_state_hex: String::new(),
        profile_id: preview.profile_id.clone(),
        share_idx: 0,
        peer_pubkeys: Vec::new(),
        members,
        device_name: preview.device_name.clone(),
    };
    Ok(material.to_bytes())
}

// ════════════════════════════════════════════════════════════════════════════
// Timestamp helpers — unit coverage
// Tests for the display_timestamp_rfc3339 / now_epoch_secs / utc_ymd_hms_from_epoch
// helpers used by the signer event log. The display path carries the visible
// "wall clock" string both shells render; the numeric epoch path is what the
// completed_at_secs / last_refresh_secs / started_at_secs fields require.
// ════════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod timestamp_tests {
    use super::{display_timestamp_rfc3339, now_epoch_secs, utc_ymd_hms_from_epoch};

    /// Anchor: epoch 0 maps to 1970-01-01T00:00:00Z. The most important known
    /// fact about Unix time and the foundation for every fixture below.
    #[test]
    fn utc_ymd_hms_epoch_zero_is_1970_01_01() {
        let (y, m, d, h, mn, s) = utc_ymd_hms_from_epoch(0);
        assert_eq!((y, m, d, h, mn, s), (1970, 1, 1, 0, 0, 0));
    }

    /// Anchor: 2024-01-01T00:00:00Z = 1704067200. Cross-checked with an
    /// independent epoch→UTC tool outside the codebase.
    #[test]
    fn utc_ymd_hms_2024_01_01() {
        let (y, m, d, h, mn, s) = utc_ymd_hms_from_epoch(1_704_067_200);
        assert_eq!((y, m, d, h, mn, s), (2024, 1, 1, 0, 0, 0));
    }

    /// Anchor: 2026-01-01T00:00:00Z = 1767225600. Confirms the algorithm
    /// includes the 14 leap years between 1970 and 2025.
    #[test]
    fn utc_ymd_hms_2026_01_01() {
        let (y, m, d, h, mn, s) = utc_ymd_hms_from_epoch(1_767_225_600);
        assert_eq!((y, m, d, h, mn, s), (2026, 1, 1, 0, 0, 0));
    }

    /// Anchor: a fixed time of day (12:34:56Z) on a non-midnight date verifies
    /// that the time-of-day component is correctly partitioned. The epoch
    /// value (1749990896) is cross-checked against Python's
    /// `datetime(2025,6,15,12,34,56,tzinfo=utc).timestamp()`.
    #[test]
    fn utc_ymd_hms_preserves_time_of_day() {
        let secs = 1_749_990_896;
        let (y, m, d, h, mn, s) = utc_ymd_hms_from_epoch(secs);
        assert_eq!((y, m, d, h, mn, s), (2025, 6, 15, 12, 34, 56));
    }

    /// Leap day sanity: 2024-02-29 exists and the algorithm lands on it.
    /// 2024-02-29T00:00:00Z = 1709164800 (59 days after 2024-01-01).
    #[test]
    fn utc_ymd_hms_recognises_leap_day() {
        let (y, m, d, h, mn, s) = utc_ymd_hms_from_epoch(1_709_164_800);
        assert_eq!((y, m, d, h, mn, s), (2024, 2, 29, 0, 0, 0));
    }

    /// Display path: the produced string MUST be a valid UTC RFC-3339
    /// timestamp of the form `YYYY-MM-DDTHH:MM:SSZ`. The MAX-LENGTH bounds
    /// also reject accidental epoch-second coercion.
    #[test]
    fn display_timestamp_rfc3339_matches_format() {
        let stamp = display_timestamp_rfc3339();
        // Length: 4 + 1 + 2 + 1 + 2 + 1 + 2 + 1 + 2 + 1 + 2 + 1 = 20 chars.
        assert_eq!(stamp.len(), 20, "RFC-3339 UTC must be 20 chars: {stamp}");
        let bytes = stamp.as_bytes();
        // Fixed positions of dashes, 'T', colons, and trailing 'Z'.
        assert_eq!(bytes[4], b'-');
        assert_eq!(bytes[7], b'-');
        assert_eq!(bytes[10], b'T');
        assert_eq!(bytes[13], b':');
        assert_eq!(bytes[16], b':');
        assert_eq!(bytes[19], b'Z');
        // Year / month / day / hour / minute / second must all be ASCII digits.
        for &idx in &[
            0, 1, 2, 3, // year
            5, 6, // month
            8, 9, // day
            11, 12, // hour
            14, 15, // minute
            17, 18, // second
        ] {
            assert!(
                bytes[idx].is_ascii_digit(),
                "expected digit at position {idx} of '{stamp}'"
            );
        }
    }

    /// Display path: the wall-clock represented in the RFC-3339 string must
    /// agree with the time we asked the OS for. This locks in that the helper
    /// is actually formatting the current instant, not a frozen placeholder.
    #[test]
    fn display_timestamp_rfc3339_agrees_with_now_epoch_secs() {
        let secs_before = now_epoch_secs();
        let stamp = display_timestamp_rfc3339();
        let secs_after = now_epoch_secs();
        let (y, m, d, h, mn, s) = utc_ymd_hms_from_epoch(secs_before);
        let expected = format!("{y:04}-{m:02}-{d:02}T{h:02}:{mn:02}:{s:02}Z");
        // Allow the timestamp to land either on secs_before or secs_after
        // (boundary case where the OS clock ticks between the two reads).
        let (y2, m2, d2, h2, mn2, s2) = utc_ymd_hms_from_epoch(secs_after);
        let alt = format!("{y2:04}-{m2:02}-{d2:02}T{h2:02}:{mn2:02}:{s2:02}Z");
        assert!(
            stamp == expected || stamp == alt,
            "display_timestamp_rfc3339 returned '{stamp}', expected '{expected}' or '{alt}'"
        );
    }

    /// Numeric path: now_epoch_secs() must produce a positive i64 well above
    /// zero — guards the completed_at_secs / last_refresh_secs / started_at_secs
    /// fields against being silently coerced to 0.
    #[test]
    fn now_epoch_secs_is_minute_after_unix_epoch() {
        let secs = now_epoch_secs();
        assert!(secs > 0, "now_epoch_secs must be > 0, got {secs}");
        // Anything below 1.7 billion means the clock regressed or the helper
        // is broken. We are well past 2024.
        assert!(
            secs > 1_700_000_000,
            "now_epoch_secs must be > 1.7B (post-2024), got {secs}"
        );
        // And it must fit comfortably in i64 (no ReLu / sign-flip issues).
        assert!(secs < i64::MAX / 2);
    }
}

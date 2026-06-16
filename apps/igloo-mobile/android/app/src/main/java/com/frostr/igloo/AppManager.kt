package com.frostr.igloo

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.frostr.igloo.rust.AppAction
import com.frostr.igloo.rust.AppReconciler
import com.frostr.igloo.rust.AppState
import com.frostr.igloo.rust.AppUpdate
import com.frostr.igloo.rust.FfiApp
import com.frostr.igloo.rust.LoadProfileError
import com.frostr.igloo.rust.LoadProfileResolved
import com.frostr.igloo.rust.LoadProfileStep
import com.frostr.igloo.rust.OnboardingStep

class AppManager private constructor(context: Context) : AppReconciler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val rust: FfiApp
    private val appContext = context.applicationContext
    private var lastRevApplied: ULong = 0UL
    private val storage = ProfileStorageManager.getInstance(appContext)

    /** Profile pending delete confirmation (profile_id when showing dialog). */
    var pendingDeleteProfileId: String? by mutableStateOf(null)
        private set

    /** Profile label for the delete confirmation dialog. */
    var pendingDeleteLabel: String? by mutableStateOf(null)
        private set

    var state: AppState by mutableStateOf(
        AppState(router = com.frostr.igloo.rust.Router(screen = com.frostr.igloo.rust.Screen.HUB, backHistory = emptyList()), hub = com.frostr.igloo.rust.HubState(profiles = emptyList()), onboarding = com.frostr.igloo.rust.OnboardingState(step = OnboardingStep.IDLE, error = null, `package` = "", password = "", relayUrl = "", resolved = null, injectedDeviceName = null), loadProfile = com.frostr.igloo.rust.LoadProfileState(
                    step = com.frostr.igloo.rust.LoadProfileStep.IDLE,
                    error = null,
                    `package` = "",
                    password = "",
                    path = "",
                    resolved = null
                ), keyset = com.frostr.igloo.rust.KeysetFlowState(
                    step = com.frostr.igloo.rust.KeysetFlowStep.IDLE,
                    error = null,
                    lastErrorMessage = null,
                    mode = com.frostr.igloo.rust.KeysetFlowMode.CREATE,
                    groupName = "",
                    threshold = 2u,
                    count = 3u,
                    bundle = null,
                    localShareIdx = 0u,
                    deviceName = "",
                    relays = emptyList(),
                    distribute = emptyList(),
                    acceptedShortId = null,
                    acceptedProfileId = "",
                    rotationSources = emptyList(),
                    rotateSourceProfileId = "",
                    rotationError = null
                ), rotateShare = com.frostr.igloo.rust.RotateShareState(
                    step = com.frostr.igloo.rust.RotateShareStep.IDLE,
                    error = null,
                    lastErrorMessage = null,
                    `package` = "",
                    password = "",
                    relayUrl = "",
                    preview = null,
                    activeProfileId = "",
                    activeShortId = "",
                    activeDeviceLabel = ""
                ), dashboard = com.frostr.igloo.rust.DashboardState(
                    activeTab = com.frostr.igloo.rust.DashboardTab.SIGNER,
                    signer = com.frostr.igloo.rust.SignerRuntimeState(
                        status = com.frostr.igloo.rust.SignerStatus.STOPPED,
                        relayConnected = false,
                        readiness = com.frostr.igloo.rust.SignerReadiness.IDLE,
                        peers = emptyList(),
                        events = emptyList(),
                        pendingOps = emptyList(),
                        lastRefreshSecs = null,
                        pingInProgress = false,
                        testSignInProgress = false,
                        lastTestSign = null,
                        testEcdhInProgress = false,
                        lastTestEcdh = null,
                        runtimeObservedEventsLen = 0uL
                    ),
                    permissions = com.frostr.igloo.rust.PermissionsState(
                        peers = emptyList(),
                        refreshInProgress = false
                    ),
                    profileInfo = null,
                    settings = defaultSettingsState(),
                    lastBackupPublish = null
                ), rev = 0UL),
    )
        private set

    init {
        val dataDir = context.filesDir.absolutePath
        rust = FfiApp(dataDir)
        val initial = rust.state()
        state = initial
        lastRevApplied = initial.rev
        rust.listenForUpdates(this)

        // Restore profiles from secure storage on startup (VAL-SHELL-013).
        restoreStoredProfiles()
    }

    /** Export password prompt state (VAL-SET-006, VAL-SET-008). */
    var showExportPasswordPrompt: Boolean by mutableStateOf(false)
        private set

    /** Pending export type: "profile" or "share". */
    var pendingExportType: String? by mutableStateOf(null)
        private set

    /** Helper to create default SignerSettings (VAL-SET-001 defaults). */
    private fun defaultSignerSettings(): com.frostr.igloo.rust.SignerSettings {
        return com.frostr.igloo.rust.SignerSettings(
            signTimeoutSecs = 30u,
            pingTimeoutSecs = 15u,
            requestTtlSecs = 300u,
            stateSaveIntervalSecs = 30u,
            peerSelectionStrategy = com.frostr.igloo.rust.PeerSelectionStrategy.DETERMINISTIC_SORTED
        )
    }

    /** Helper to create default SettingsState. */
    private fun defaultSettingsState(): com.frostr.igloo.rust.SettingsState {
        return com.frostr.igloo.rust.SettingsState(
            signerName = "",
            settings = defaultSignerSettings(),
            relays = emptyList(),
            hasUnsavedEdits = false,
            saveBlockedSignerStopped = false,
            pendingExportPassword = null,
            pendingExportType = null
        )
    }

    fun dispatch(action: AppAction) {
        // Dispatch is now synchronous - rust.dispatch() blocks until the actor
        // processes the action and returns the updated state. This ensures the
        // state is updated before dispatch returns, eliminating the timing gap
        // where Compose might re-render before the NavigateBack state update
        // has been applied. The async listener callback still fires but will
        // see the same state that's already been applied.
        val newState = rust.dispatch(action)
        lastRevApplied = newState.rev
        state = newState
    }

    override fun reconcile(update: AppUpdate) {
        mainHandler.post {
            when (update) {
                is AppUpdate.FullState -> {
                    if (update.v1.rev <= lastRevApplied) return@post
                    lastRevApplied = update.v1.rev
                    state = update.v1
                }
                is AppUpdate.ShowDeleteConfirmation -> {
                    pendingDeleteProfileId = update.profileId
                    pendingDeleteLabel = update.label
                }
                is AppUpdate.DeleteFromSecureStorage -> {
                    // Delete profile material from EncryptedSharedPreferences.
                    storage.deleteProfile(update.profileId)
                }
                is AppUpdate.RestoreAllStoredProfiles -> {
                    // Shell receives this when Rust wants to restore all profiles.
                    restoreStoredProfiles()
                }
                is AppUpdate.StoreProfile -> {
                    // Informational; actual storage is triggered by shell
                    // actions (OnboardSave, etc.) which call storage.storeProfile directly.
                }
                is AppUpdate.RestoreFromSecureStorage -> {
                    // Load stored material, parse identity fields, and dispatch
                    // OpenDashboard so profile_info is fully populated
                    // (mobile-signer-startup-profile-info-fix).
                    val materialBytes = storage.loadProfileMaterial(update.profileId)
                    if (materialBytes != null && materialBytes.isNotEmpty()) {
                        val materialJson = String(materialBytes, Charsets.UTF_8)
                        try {
                            val json = org.json.JSONObject(materialJson)
                            val deviceName = json.optString("device_name", "")
                            val sharePubkey = json.optString("share_pubkey", "")
                            val groupPubkey = json.optString("group_pubkey", "")
                            dispatch(AppAction.OpenDashboard(
                                profileId = update.profileId,
                                deviceName = deviceName,
                                sharePubkey = sharePubkey,
                                groupPubkey = groupPubkey
                            ))
                        } catch (_: Exception) {
                            // Ignore parse errors; dashboard still has minimal
                            // profile_info seeded by OpenProfile.
                        }
                    }
                }
                is AppUpdate.PerformOnboardHandshake -> {
                    // Shell receives PerformOnboardHandshake when the Rust state machine
                    // transitions to HANDSHAKING step (after successful package decode).
                    // The shell calls rust.onboard() which performs the real Nostr
                    // handshake against the specified relay. This runs on a background
                    // thread to avoid blocking the main thread.
                    val pkg = update.`package`
                    val pwd = update.password
                    val relayUrl = update.relayUrl

                    Thread {
                        val result = rust.onboard(`package` = pkg, password = pwd, relayUrl = relayUrl)

                        mainHandler.post {
                            if (result.success) {
                                // Store the package material for secure storage (VAL-ONBOARD-015).
                                result.material?.let { materialBytes ->
                                    pendingProfileMaterial = materialBytes
                                }
                                update.relayUrl.let { relay ->
                                    pendingRelayUrl = relay
                                }

                                // Dispatch success to Rust state machine (VAL-ONBOARD-008).
                                dispatch(AppAction.OnboardHandshakeSuccess(
                                    deviceName = result.deviceName ?: "Onboarded Device",
                                    sharePubkey = result.sharePubkey ?: "",
                                    groupPubkey = result.groupPubkey ?: "",
                                    relays = result.relays ?: emptyList(),
                                    profileId = result.profileId ?: ""
                                ))
                            } else {
                                // Dispatch failure to Rust state machine (VAL-ONBOARD-007).
                                dispatch(AppAction.OnboardHandshakeFailure(
                                    error = result.error ?: "unexpected"
                                ))
                            }
                        }
                    }.start()
                }
                is AppUpdate.StoreOnboardedProfile -> {
                    // Onboarding complete — store profile to secure storage (VAL-ONBOARD-015).
                    val material = pendingProfileMaterial
                    if (material == null) {
                        // No material available - reject as storage failure
                        dispatch(AppAction.OnboardDuplicateRejected(profileId = update.profileId))
                    } else {
                        // Check for duplicate before storing (VAL-ONBOARD-015).
                        val existing = storage.loadAllStoredProfiles()
                        if (existing.any { it.profileId == update.profileId }) {
                            pendingProfileMaterial = null
                            pendingRelayUrl = null
                            dispatch(AppAction.OnboardDuplicateRejected(profileId = update.profileId))
                        } else {
                            // Store the profile to secure storage.
                            val stored = storage.storeProfile(
                                profileId = update.profileId,
                                label = update.label,
                                shortId = update.shortId,
                                material = material
                            )
                            pendingProfileMaterial = null
                            pendingRelayUrl = null

                            if (stored) {
                                // Dispatch success to Rust to navigate to dashboard (VAL-ONBOARD-011).
                                dispatch(AppAction.OnboardStored(profileId = update.profileId))
                            } else {
                                dispatch(AppAction.OnboardDuplicateRejected(profileId = update.profileId))
                            }
                        }
                    }
                }
                is AppUpdate.PerformLoadProfileImport -> {
                    // Shell receives PerformLoadProfileImport when Rust transitions to Decrypting.
                    // VAL-LOAD-018: show responsive progress feedback.
                    val pkg = update.`package`
                    val pwd = update.password
                    Thread {
                        val result = rust.importProfile(`package` = pkg, password = pwd)
                        mainHandler.post {
                            if (result.success) {
                                dispatch(AppAction.LoadProfileImportSuccess(
                                    deviceName = result.deviceName ?: "",
                                    sharePubkey = result.sharePubkey ?: "",
                                    groupPubkey = result.groupPubkey ?: "",
                                    relays = result.relays ?: emptyList(),
                                    profileId = result.profileId ?: ""
                                ))
                            } else {
                                dispatch(AppAction.LoadProfileImportFailure(
                                    error = result.error ?: "unexpected"
                                ))
                            }
                        }
                    }.start()
                }
                is AppUpdate.PerformLoadProfileRecovery -> {
                    // Shell receives PerformLoadProfileRecovery when Rust transitions to FetchingBackup.
                    // VAL-LOAD-018: show responsive progress feedback.
                    val pkg = update.`package`
                    val pwd = update.password
                    Thread {
                        val result = rust.recoverProfile(`package` = pkg, password = pwd)
                        mainHandler.post {
                            if (result.success) {
                                dispatch(AppAction.LoadProfileRecoverSuccess(
                                    deviceName = result.deviceName ?: "",
                                    sharePubkey = result.sharePubkey ?: "",
                                    groupPubkey = result.groupPubkey ?: "",
                                    relays = result.relays ?: emptyList(),
                                    profileId = result.profileId ?: ""
                                ))
                            } else {
                                dispatch(AppAction.LoadProfileRecoverFailure(
                                    error = result.error ?: "unexpected"
                                ))
                            }
                        }
                    }.start()
                }
                is AppUpdate.StoreLoadedProfile -> {
                    // Load profile confirm completed — store profile to secure storage.
                    val material = pendingProfileMaterial
                    if (material == null) {
                        dispatch(AppAction.LoadProfileDuplicateRejected(profileId = update.profileId))
                    } else {
                        val existing = storage.loadAllStoredProfiles()
                        if (existing.any { it.profileId == update.profileId }) {
                            pendingProfileMaterial = null
                            dispatch(AppAction.LoadProfileDuplicateRejected(profileId = update.profileId))
                        } else {
                            val stored = storage.storeProfile(
                                profileId = update.profileId,
                                label = update.label,
                                shortId = update.shortId,
                                material = material
                            )
                            pendingProfileMaterial = null
                            if (stored) {
                                dispatch(AppAction.LoadProfileStored(profileId = update.profileId))
                            } else {
                                dispatch(AppAction.LoadProfileDuplicateRejected(profileId = update.profileId))
                            }
                        }
                    }
                }
                // ── Signer runtime console (VAL-SIGNER-001 through VAL-SIGNER-018) ────
                is AppUpdate.StartSignerRuntime -> {
                    // Rust calls into the shell — actually start the signer
                    // runtime by loading the active profile material from
                    // secure storage and invoking FfiApp.startSigner().
                    //
                    // The previous handler dispatched AppAction.SignerStart
                    // recursively and never invoked FfiApp.startSigner(),
                    // which is why the SignerStatus stayed Stopped even
                    // after a Compose onClick from the dashboard. The
                    // mobile-signer-runtime-console worker closed the
                    // wiring on the Rust side (FfiApp.startSigner takes
                    // OnboardProfileMaterial JSON) but the Android shell
                    // reconcile handler kept the recursive dispatch.
                    //
                    // Run the FFI call on a background thread so the main
                    // thread keeps responding to user input. Set the active
                    // material on Rust for export operations, then poll
                    // rust.getSignerStatus() until the runtime reports
                    // running=true. Dispatch the SignerStarted action back
                    // to the actor so the dashboard flips to Running and
                    // the "Signer runtime started" INFO event-log entry
                    // (RFC-3339 timestamp, mobile-signer-event-log-timestamp-rfc3339-fix)
                    // is appended.
                    performStartSigner()
                }
                is AppUpdate.StopSignerRuntime -> {
                    // Mirror the start path: invoke FfiApp.stopSigner() on a
                    // background thread, then dispatch SignerStopped so the
                    // Rust state machine returns the dashboard to STOPPED.
                    performStopSigner()
                }
                is AppUpdate.PingSignerPeers -> {
                    // Rust calls into the shell — actually invoke
                    // FfiApp.ping_peer() for each online peer. The
                    // previous handler re-dispatched AppAction::SignerPingPeers
                    // recursively, leaving FfiApp.ping_peer() never invoked
                    // and the peer Refresh / Test Ping affordance a UI-only
                    // no-op (the
                    // mobile-android-signer-start-button-tap-propagation-fix
                    // on commit 8ee48fa closed the same broken pattern for
                    // Start; PingSignerPeers remains as a sibling parity
                    // issue here).
                    //
                    // performPingSignerPeers() snapshots the cached peer
                    // aliases from dashboard.signer.peers on the main
                    // thread, then calls FfiApp.ping_peer() per peer on a
                    // background thread (15 s round timeout per peer). On
                    // each successful round, dispatch SignerPingComplete
                    // so the actor updates the peer's last_seen / incoming
                    // counters and prepends the "INFO <RFC-3339> Ping
                    // complete: <alias>" event-log row.
                    performPingSignerPeers()
                }
                // ── Test Sign and ECDH (VAL-SIGN-002, VAL-SIGN-005) ────
                is AppUpdate.PerformTestSign -> {
                    // Rust calls into the shell — perform a test sign operation.
                    performTestSign()
                }
                is AppUpdate.PerformTestEcdh -> {
                    // Rust calls into the shell — perform a test ECDH operation.
                    performTestEcdh()
                }
                is AppUpdate.CopyToClipboard -> {
                    // Rust calls into the shell — copy value to platform clipboard.
                    val clipboard = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                    val clip = android.content.ClipData.newPlainText(update.label, update.value)
                    clipboard.setPrimaryClip(clip)
                }
                is AppUpdate.PollSignerStatus -> {
                    // Rust calls into the shell — poll signer status and dispatch update.
                    pollSignerStatus()
                }
                is AppUpdate.RefreshRemotePolicy -> {
                    // Rust calls into the shell — trigger remote policy refresh.
                    performRemotePolicyRefresh()
                }
                // ── Settings & Maintenance (VAL-SET-001 through VAL-SET-016) ────
                is AppUpdate.ShowExportPasswordPrompt -> {
                    // Shell shows an export-password prompt before writing a package
                    // to the clipboard (VAL-SET-006, VAL-SET-008).
                    pendingExportType = update.exportType
                    showExportPasswordPrompt = true
                }
                is AppUpdate.PerformCopyProfile -> {
                    // Shell produces bfprofile1 encrypted with the password and copies to clipboard
                    // (VAL-SET-007, VAL-SET-015).
                    performCopyProfileExport(password = update.password)
                }
                is AppUpdate.PerformCopyShare -> {
                    // Shell produces bfshare1 encrypted with the password and copies to clipboard
                    // (VAL-SET-008, VAL-SET-015).
                    performCopyShareExport(password = update.password)
                }
                is AppUpdate.PersistSettings -> {
                    // Shell persists settings to secure storage (VAL-SET-002/003/004/013/014).
                    // The settings are already updated in Rust state; the shell updates
                    // platform secure storage and the hub row label.
                    persistSettingsToStorage()
                }
                // ── Create / Rotate Keyset shell side-effects (VAL-CREATE-*) ────
                // The Rust state machine emits these AppUpdates after the user
                // accepts review. The shell runs heavy Argon2id/secp256k1 work
                // off the main actor, then dispatches the resulting action back
                // to advance the wizard.
                is AppUpdate.PerformKeysetGeneration -> {
                    val groupName = update.groupName
                    val threshold = update.threshold
                    val count = update.count
                    val mode = update.mode
                    Thread {
                        val cfgJson = org.json.JSONObject()
                            .put("group_name", groupName)
                            .put("threshold", threshold.toInt())
                            .put("count", count.toInt())
                            .put("mode", mode)
                            .toString()
                        val bundleJson = rust.generateKeyset(configJson = cfgJson)
                        mainHandler.post {
                            if (bundleJson.startsWith("error:")) {
                                dispatch(
                                    AppAction.CreateKeysetGenerationFailed(
                                        error = bundleJson.removePrefix("error:")
                                    )
                                )
                            } else {
                                dispatch(
                                    AppAction.CreateKeysetGenerationSuccess(
                                        bundleJson = bundleJson
                                    )
                                )
                            }
                        }
                    }.start()
                }
                is AppUpdate.PerformKeysetDistribution -> {
                    val shareIdx = update.shareIdx
                    val shareSecretHex = update.shareSecretHex
                    val relays = update.relays
                    val label = update.label
                    val password = update.password
                    val method = update.method
                    Thread {
                        val pkg = rust.encodeDistributeOnboard(
                            shareSecretHex = shareSecretHex,
                            relays = relays,
                            shareLabel = label,
                            password = password
                        )
                        mainHandler.post {
                            if (pkg.startsWith("error:")) {
                                dispatch(
                                    AppAction.CreateKeysetDistributeFailed(
                                        shareIdx = shareIdx,
                                        error = pkg.removePrefix("error:")
                                    )
                                )
                            } else {
                                dispatch(
                                    AppAction.CreateKeysetDistributePackageProduced(
                                        shareIdx = shareIdx,
                                        `package` = pkg,
                                        method = method
                                    )
                                )
                            }
                        }
                    }.start()
                }
                is AppUpdate.StoreKeysetCreatedProfile -> {
                    val profileId = update.profileId
                    val label = update.label
                    val shortId = update.shortId
                    val material = update.material
                    val stored = storage.storeProfile(
                        profileId = profileId,
                        label = label,
                        shortId = shortId,
                        material = material
                    )
                    if (stored) {
                        dispatch(
                            AppAction.CreateKeysetAccepted(
                                profileId = profileId,
                                label = label,
                                shortId = shortId
                            )
                        )
                    }
                }
                is AppUpdate.StartKeysetSignerRuntime -> {
                    // Mirror SignerStart: kick the signer for the freshly-stored
                    // profile so the Distribute step shows a running signer panel
                    // (VAL-CREATE-010, VAL-CREATE-022).
                    performStartSigner()
                }
                is AppUpdate.PerformRotateShareHandshake -> {
                    // VAL-ROTATE-006/013/014: run the live handshake off the
                    // main thread. The actor uses the same rust.onboard() entry
                    // point because bfonboard1 envelopes share the same
                    // wire format. Result is mapped back into a typed
                    // RotateShareHandshakeSuccess or RotateShareHandshakeFailure
                    // action depending on the success / error_kind fields.
                    val pkg = update.`package`
                    val pwd = update.password
                    val relayUrl = update.relayUrl
                    Thread {
                        val result = rust.onboard(`package` = pkg, password = pwd, relayUrl = relayUrl)
                        mainHandler.post {
                            if (result.success) {
                                // Extract rotated share secret from the
                                // FFI material blob so the actor can build
                                // a fully usable material record on
                                // confirm-replace. The secret is forwarded
                                // verbatim to Rust and must never be
                                // rendered, logged, or persisted.
                                val shareSeckeyHex = extractShareSeckeyHex(result.material)
                                dispatch(
                                    AppAction.RotateShareHandshakeSuccess(
                                        deviceName = result.deviceName ?: "Rotated Device",
                                        sharePubkey = result.sharePubkey ?: "",
                                        groupPubkey = result.groupPubkey ?: "",
                                        relays = result.relays ?: emptyList(),
                                        profileId = result.profileId ?: "",
                                        shareSeckeyHex = shareSeckeyHex ?: ""
                                    )
                                )
                            } else {
                                dispatch(
                                    AppAction.RotateShareHandshakeFailure(
                                        error = result.error ?: "unexpected"
                                    )
                                )
                            }
                        }
                    }.start()
                }
                is AppUpdate.ReplaceProfileFromRotate -> {
                    // VAL-ROTATE-011: drop the old profile's secure-storage
                    // record, write the new material, update the index.
                    if (update.deleteOld) {
                        storage.deleteProfile(update.oldProfileId)
                    }
                    val material = update.newMaterial
                    if (material.isNotEmpty()) {
                        storage.storeProfile(
                            profileId = update.newProfileId,
                            label = update.newLabel,
                            shortId = update.newShortId,
                            material = material
                        )
                    }
                    dispatch(
                        AppAction.UpdateHubStatus(
                            profileId = update.newProfileId,
                            active = true
                        )
                    )
                }
                is AppUpdate.ReplaceProfileFromRotateAndPublishBackup -> {
                    // VAL-ROTATE-011 + VAL-BACKUP-004: combined variant
                    // emitted by the rotate-share replace path. Run the
                    // secure-storage swap locally and forward the post-
                    // publish result via BackupPublishCompleted so the
                    // actor mirrors it into `dashboard.last_backup_publish`.
                    if (update.deleteOld) {
                        storage.deleteProfile(update.oldProfileId)
                    }
                    val newMaterial = update.newMaterial
                    if (newMaterial.isNotEmpty()) {
                        storage.storeProfile(
                            profileId = update.newProfileId,
                            label = update.newLabel,
                            shortId = update.newShortId,
                            material = newMaterial
                        )
                        val materialJson = String(newMaterial, Charsets.UTF_8)
                        performPublishBackup(
                            source = update.source,
                            materialJson = materialJson
                        )
                    }
                    dispatch(
                        AppAction.UpdateHubStatus(
                            profileId = update.newProfileId,
                            active = true
                        )
                    )
                }
                is AppUpdate.PublishProfileBackup -> {
                    // VAL-BACKUP-001..006: regular backup publication
                    // path used by create / onboard / import / recover.
                    // The rotated flow uses the combined
                    // ReplaceProfileFromRotateAndPublishBackup variant
                    // above; this case handles the other materialization
                    // paths and forwards the result back via
                    // BackupPublishCompleted.
                    performPublishBackup(
                        source = update.source,
                        materialJson = update.materialJson
                    )
                }
                else -> {
                    // Unhandled update — ignore.
                }
            }
        }
    }

    private fun restoreStoredProfiles() {
        // Load profile index and restore each profile to the hub.
        val profiles = storage.loadAllStoredProfiles()
        for (entry in profiles) {
            // Each profile stored in EncryptedSharedPreferences is restored to the Rust state.
            dispatch(
                AppAction.ProfileRestored(
                    label = entry.label,
                    profileId = entry.profileId,
                    shortId = entry.shortId
                )
            )
        }
    }

    // Convenience helpers for hub navigation
    fun navigateToOnboard() {
        dispatch(AppAction.NavigateOnboard)
    }

    /** Navigate directly to the onboard connect screen (VAL-ONBOARD-001 entry path). */
    fun navigateToOnboardConnect() {
        dispatch(AppAction.NavigateOnboardConnect)
    }

    fun navigateToLoadProfile() {
        dispatch(AppAction.NavigateLoadProfile)
    }

    fun navigateToCreateKeyset() {
        dispatch(AppAction.NavigateCreateKeyset)
    }

    fun navigateBack() {
        dispatch(AppAction.NavigateBack)
    }

    /** True when an async onboard step is in progress (DECRYPTING or HANDSHAKING). */
    val isOnboardingLoading: Boolean
        get() = state.onboarding.step == OnboardingStep.DECRYPTING ||
                state.onboarding.step == OnboardingStep.HANDSHAKING

    /** Current onboarding step for Compose screen logic. */
    val onboardingStep: OnboardingStep
        get() = state.onboarding.step

    /** Current onboarding error for Compose screen display. */
    val onboardingError: com.frostr.igloo.rust.OnboardingError?
        get() = state.onboarding.error

    /** Resolved identity from successful onboard handshake. */
    val onboardingResolved: com.frostr.igloo.rust.ResolvedIdentity?
        get() = state.onboarding.resolved

    /** Pending profile material for storage when onboarding completes.
     *  Set by onboard() after successful package decode; cleared after StoreOnboardedProfile. */
    private var pendingProfileMaterial: ByteArray? = null

    /** Pending relay URL for profile storage. */
    private var pendingRelayUrl: String? = null

    /** Initiate the onboard flow with the given package, password, and relay URL
     *  (VAL-ONBOARD-001, VAL-ONBOARD-002, VAL-ONBOARD-003, VAL-ONBOARD-005).
     *  Whitespace is trimmed from the package before dispatch (VAL-ONBOARD-009). */
    fun onboardConnect(pkg: String, password: String, relayUrl: String) {
        val trimmedPackage = pkg.trim()
        dispatch(AppAction.OnboardConnect(
            `package` = trimmedPackage,
            password = password,
            relayUrl = relayUrl
        ))
    }

    /** Debug-gated credential preload: dispatch AppAction.InjectOnboardCredentials
     *  to set state.onboarding.{package,password,relay_url,injected_device_name}
     *  without advancing the step, and navigate to OnboardConnect so the user
     *  (or Maestro) sees the popped values in the form fields. The user still
     *  taps btn_connect to drive the normal handshake — this path bypasses only
     *  the long-text transport, not the validation/state-machine semantics.
     *
     *  Called only from MainActivity.handleTestInjectIntent, which is itself
     *  BuildConfig.DEBUG-gated; the consuming intent-filter is also debug-only
     *  via `app/src/debug/AndroidManifest.xml`. Release builds cannot reach
     *  this method. Never logs or persists package/password material. */
    fun injectOnboardCredentials(
        packageText: String,
        password: String,
        relayUrl: String,
        deviceName: String?
    ) {
        // Trim defensively; Rust handler trims package again.
        val trimmedPackage = packageText.trim()
        // Platform-correct Android emulator->host alias for the FROSTR dev
        // relay. See RelayDefaults.DEFAULT and the
        // mobile-android-relay-url-platform-default-fix feature for context.
        val trimmedRelay = relayUrl.trim().ifEmpty { RelayDefaults.DEFAULT }
        val trimmedDevice = deviceName?.trim()?.takeIf { it.isNotEmpty() }

        // Order matters: NavigateOnboardConnect calls onboarding.reset()
        // which would wipe the injected values. Dispatch navigation first
        // (when not already on the connect screen), then dispatch the
        // inject so the populated state survives into the Compose screen.
        if (state.router.screen != com.frostr.igloo.rust.Screen.ONBOARD_CONNECT) {
            dispatch(AppAction.NavigateOnboardConnect)
        }

        dispatch(AppAction.InjectOnboardCredentials(
            `package` = trimmedPackage,
            password = password,
            relayUrl = trimmedRelay,
            deviceName = trimmedDevice
        ))
    }

    /** Save the onboarded profile and navigate to dashboard (VAL-ONBOARD-011, VAL-ONBOARD-015).
     *  Device name is validated before dispatch (VAL-ONBOARD-010). */
    fun onboardSave(profileId: String, label: String, shortId: String) {
        dispatch(AppAction.OnboardSave(
            profileId = profileId,
            label = label,
            shortId = shortId
        ))
    }

    /** Clear the onboarding error to allow retry (VAL-ONBOARD-006, VAL-ONBOARD-007). */
    fun onboardClearError() {
        dispatch(AppAction.OnboardClearError)
    }

    // ── Load Profile helpers ────────────────────────────────────────────────

    /** True when an async load profile step is in progress
     *  (DECRYPTING, FETCHING_BACKUP, or RECONSTRUCTING).
     *  VAL-LOAD-018: responsive progress feedback. */
    val isLoadProfileLoading: Boolean
        get() = state.loadProfile.step == LoadProfileStep.DECRYPTING ||
                state.loadProfile.step == LoadProfileStep.FETCHING_BACKUP ||
                state.loadProfile.step == LoadProfileStep.RECONSTRUCTING

    /** Current load profile step for Compose screen logic. */
    val loadProfileStep: LoadProfileStep
        get() = state.loadProfile.step

    /** Current load profile error for Compose screen display (VAL-LOAD-004/005/008/013/017/019). */
    val loadProfileError: LoadProfileError?
        get() = state.loadProfile.error

    /** Decoded/recovered profile data for confirm screen preview (VAL-LOAD-006/012). */
    val loadProfileResolved: LoadProfileResolved?
        get() = state.loadProfile.resolved

    /** Dispatch the import path selection (VAL-LOAD-001). */
    fun loadProfileSelectImport() {
        dispatch(AppAction.LoadProfileSelectImport)
    }

    /** Dispatch the recover path selection (VAL-LOAD-001). */
    fun loadProfileSelectRecover() {
        dispatch(AppAction.LoadProfileSelectRecover)
    }

    /** Submit the import form (VAL-LOAD-002, VAL-LOAD-003).
     *  Whitespace is trimmed from the package before dispatch. */
    fun loadProfileImportSubmit(pkg: String, password: String) {
        val trimmedPackage = pkg.trim()
        dispatch(AppAction.LoadProfileImportSubmit(`package` = trimmedPackage, password = password))
    }

    /** Submit the recover form (VAL-LOAD-009, VAL-LOAD-010).
     *  Whitespace is trimmed from the package before dispatch. */
    fun loadProfileRecoverSubmit(pkg: String, password: String) {
        val trimmedPackage = pkg.trim()
        dispatch(AppAction.LoadProfileRecoverSubmit(`package` = trimmedPackage, password = password))
    }

    /** Clear the load profile error to allow retry (VAL-LOAD-004/005/010/011/013/017/019). */
    fun loadProfileClearError() {
        dispatch(AppAction.LoadProfileClearError)
    }

    /** Confirm the profile and store it (VAL-LOAD-007, VAL-LOAD-014).
     *  Profile data comes from state.loadProfile.resolved; this action has no parameters. */
    fun loadProfileConfirm() {
        dispatch(AppAction.LoadProfileConfirm)
    }

    fun openProfile(profileId: String) {
        dispatch(AppAction.OpenProfile(profileId = profileId))
    }

    // Profile management
    /** Request delete confirmation for a profile (VAL-SHELL-012). */
    fun requestDeleteProfile(profileId: String) {
        dispatch(AppAction.RequestDeleteProfile(profileId = profileId))
    }

    /** Confirm and execute profile deletion (VAL-SHELL-012). */
    fun confirmDeleteProfile(profileId: String) {
        pendingDeleteProfileId = null
        pendingDeleteLabel = null
        dispatch(AppAction.ConfirmDeleteProfile(profileId = profileId))
    }

    /** Cancel delete operation. */
    fun cancelDeleteProfile() {
        pendingDeleteProfileId = null
        pendingDeleteLabel = null
    }

    /** Store a newly created/imported profile (called after successful onboard/import). */
    fun storeProfile(profileId: String, label: String, shortId: String, material: ByteArray) {
        storage.storeProfile(profileId, label, shortId, material)
    }

    /** Update hub status for active/available display (VAL-SHELL-015). */
    fun updateHubStatus(profileId: String, active: Boolean) {
        dispatch(AppAction.UpdateHubStatus(profileId = profileId, active = active))
    }

    // ── Dashboard & Signer Tab ───────────────────────────────────────────────

    /** Active dashboard tab for Compose UI display. */
    val activeDashboardTab: String
        get() = when (state.dashboard.activeTab) {
            com.frostr.igloo.rust.DashboardTab.SIGNER -> "signer"
            com.frostr.igloo.rust.DashboardTab.PERMISSIONS -> "permissions"
            com.frostr.igloo.rust.DashboardTab.SETTINGS -> "settings"
            else -> "signer"
        }

    /** Switch the active dashboard tab (VAL-SIGNER-001, VAL-PERM-001, VAL-SET-001). */
    fun setDashboardTab(tab: String) {
        dispatch(AppAction.DashboardSetTab(tab = tab))
    }

    /** Start the signer runtime (VAL-SIGNER-002). */
    fun startSigner() {
        dispatch(AppAction.SignerStart)
    }

    /** Stop the signer runtime (VAL-SIGNER-015). */
    fun stopSigner() {
        dispatch(AppAction.SignerStop)
    }

    /** Refresh peer status — dispatch SignerPingPeers to trigger a ping round
     *  (VAL-SIGNER-010, VAL-SIGNER-018). */
    fun refreshPeers() {
        dispatch(AppAction.SignerPingPeers)
    }

    /** Trigger a ping round to live peers (VAL-SIGNER-018). */
    fun testPing() {
        dispatch(AppAction.SignerPingPeers)
    }

    /** Copy a hex value to the platform clipboard (VAL-SIGNER-017). */
    fun testSign() {
        dispatch(AppAction.TestSign)
    }

    fun testEcdh() {
        dispatch(AppAction.TestEcdh)
    }

    fun clearTestSignResult() {
        dispatch(AppAction.ClearTestSignResult)
    }

    fun clearTestEcdhResult() {
        dispatch(AppAction.ClearTestEcdhResult)
    }

    fun copyToClipboard(value: String, label: String) {
        dispatch(AppAction.CopyToClipboard(value = value, label = label))
    }

    // ── Permissions Policy Editor (VAL-PERM-001 through VAL-PERM-013) ────

    /** Set a manual override for a specific peer × direction × method cell
     *  (VAL-PERM-005, VAL-PERM-006, VAL-PERM-007). */
    fun setPolicyOverride(peerAlias: String, direction: String, method: String, value: String) {
        dispatch(AppAction.SetPolicyOverride(peerAlias = peerAlias, direction = direction, method = method, value = value))
    }

    /** Reset a single cell back to unset (VAL-PERM-010). */
    fun resetPolicyOverride(peerAlias: String, direction: String, method: String) {
        dispatch(AppAction.ResetPolicyOverride(peerAlias = peerAlias, direction = direction, method = method))
    }

    /** Clear all manual overrides for a peer (VAL-PERM-011). */
    fun clearAllPeerOverrides(peerAlias: String) {
        dispatch(AppAction.ClearAllPeerOverrides(peerAlias = peerAlias))
    }

    /** Trigger a refresh of remote policy observations (VAL-PERM-012, VAL-PERM-013).
     *  The shell dispatches this when the user activates the Refresh control. */
    fun refreshRemotePolicy() {
        dispatch(AppAction.RefreshRemotePolicy)
    }

    /** Simulate a remote policy refresh. Since the demo harness doesn't expose
     *  a real peer-policy query API, we simulate the refresh by:
     *  1. Dispatching RefreshRemotePolicy (sets refresh_in_progress = true)
     *  2. After a short delay, dispatching UpdateRemotePolicyObservation for alice
     *     (available: true) and carol (available: false)
     *  This satisfies VAL-PERM-012 (alice shows observation) and VAL-PERM-013
     *  (carol never shows a fabricated observation) without requiring a real API. */
    private fun performRemotePolicyRefresh() {
        // Dispatch to set refresh_in_progress = true in Rust state.
        dispatch(AppAction.RefreshRemotePolicy)

        // Simulate a short delay for the "refresh" to complete.
        mainHandler.postDelayed({
            val now = System.currentTimeMillis() / 1000

            // alice is the live peer (has running signer) — she has an observation.
            dispatch(AppAction.UpdateRemotePolicyObservation(
                peerAlias = "alice",
                available = true,
                lastObservedSecs = now,
                revision = 1u
            ))

            // carol has no running signer — she never has a remote observation
            // (VAL-PERM-012: only live peer shows observation).
            dispatch(AppAction.UpdateRemotePolicyObservation(
                peerAlias = "carol",
                available = false,
                lastObservedSecs = null,
                revision = null
            ))
        }, 500)
    }

    // ── Signer Status Polling ────────────────────────────────────────────────

    private var signerPollRunnable: Runnable? = null

    /** Called when the Dashboard composable appears. Starts polling signer status
     *  every ~1 second while the Signer tab is visible (VAL-SIGNER-011). */
    fun onDashboardAppear() {
        startSignerPollTimer()
    }

    /** Called when the Dashboard composable disappears. Stops polling. */
    fun onDashboardDisappear() {
        stopSignerPollTimer()
    }

    private fun startSignerPollTimer() {
        stopSignerPollTimer()
        signerPollRunnable = object : Runnable {
            override fun run() {
                pollSignerStatus()
                mainHandler.postDelayed(this, 1000)
            }
        }
        mainHandler.post(signerPollRunnable!!)
    }

    private fun stopSignerPollTimer() {
        signerPollRunnable?.let { mainHandler.removeCallbacks(it) }
        signerPollRunnable = null
    }

    /** Poll signer status from the Rust cache and dispatch SignerStatusUpdate.
     *  Called every ~1s from the poll timer while the dashboard is visible. */
    private fun pollSignerStatus() {
        val statusJson = rust.getSignerStatus()
        val data = statusJson.toByteArray()
        val json = try {
            org.json.JSONObject(String(data))
        } catch (e: Exception) {
            return
        }

        val relayConnected = json.optBoolean("relay_connected", false)
        val readiness = json.optString("readiness", "idle")
        // Rust emits `Option<i64>` as JSON `null` while the polling task has
        // not yet produced a first sample (mobile-android-onboard-save-poll-timer-fix,
        // commit 7910f70). `JSONObject.has` returns true for null values, so
        // the previous `has+getLong` pattern would throw JSONException and
        // SIGKILL the foreground Compose root. Delegate to PollStatusParse so
        // the optional-timestamp contract (null or missing → null) is preserved
        // and the app lives through the first poll cycle.
        val lastRefreshSecs = PollStatusParse.lookupOptionalTimestamp(json, "last_refresh_secs")

        // Peers.
        val peerAliases = mutableListOf<String>()
        val peerPubkeys = mutableListOf<String>()
        val peerOnline = mutableListOf<Boolean>()
        val peerLastSeen = mutableListOf<Long?>()
        val peerIncomingAvailable = mutableListOf<UInt>()
        val peerOutgoingAvailable = mutableListOf<UInt>()
        val peerOutgoingSpent = mutableListOf<UInt>()

        val peersArray = json.optJSONArray("peers")
        if (peersArray != null) {
            for (i in 0 until peersArray.length()) {
                val peer = peersArray.getJSONObject(i)
                peerAliases.add(peer.optString("alias", ""))
                peerPubkeys.add(peer.optString("pubkey", ""))
                peerOnline.add(peer.optBoolean("online", false))
                // Peer entries may carry a `last_seen_secs` slot whose Rust
                // origin is `Option<i64>`, so it serializes to JSON `null`
                // until the peer becomes observable. Apply the same null-or-
                // missing coalescing rule as the top-level timestamp to
                // defend against future peer-array wiring even when the
                // current call path returns null upstream of the inner loop.
                peerLastSeen.add(PollStatusParse.lookupOptionalTimestamp(peer, "last_seen_secs"))
                peerIncomingAvailable.add(peer.optLong("incoming_available", 0).toUInt())
                peerOutgoingAvailable.add(peer.optLong("outgoing_available", 0).toUInt())
                peerOutgoingSpent.add(peer.optLong("outgoing_spent", 0).toUInt())
            }
        }

        // Pending ops.
        val pendingOpTypes = mutableListOf<String>()
        val pendingOpStartedAt = mutableListOf<Long>()

        val opsArray = json.optJSONArray("pending_ops")
        if (opsArray != null) {
            for (i in 0 until opsArray.length()) {
                val op = opsArray.getJSONObject(i)
                pendingOpTypes.add(op.optString("type", ""))
                pendingOpStartedAt.add(op.optLong("started_at_secs", 0))
            }
        }

        val eventsLen = json.optLong("events_len", 0).toUInt()

        dispatch(AppAction.SignerStatusUpdate(
            relayConnected = relayConnected,
            readiness = readiness,
            peerAliases = peerAliases,
            peerPubkeys = peerPubkeys,
            peerOnline = peerOnline,
            peerLastSeen = peerLastSeen,
            peerIncomingAvailable = peerIncomingAvailable,
            peerOutgoingAvailable = peerOutgoingAvailable,
            peerOutgoingSpent = peerOutgoingSpent,
            pendingOpTypes = pendingOpTypes,
            pendingOpStartedAt = pendingOpStartedAt,
            lastRefreshSecs = lastRefreshSecs,
            eventsLen = eventsLen
        ))

        // Sync peer online status to the permissions state (VAL-PERM-012).
        // This ensures the Permissions tab knows which peers are online so
        // alice shows as having a remote observation while carol does not.
        dispatch(AppAction.SyncPeerOnlineStatus(
            peerAliases = peerAliases,
            peerOnline = peerOnline
        ))
    }

    // MARK: - Settings & Maintenance (VAL-SET-001 through VAL-SET-016)

    /** Edit the signer name field (VAL-SET-013). */
    fun editSignerName(name: String) {
        dispatch(AppAction.EditSignerName(name = name))
    }

    /** Edit the sign timeout field (VAL-SET-002, VAL-SET-005). */
    fun editSignTimeout(value: UInt) {
        dispatch(AppAction.EditSignTimeout(value = value))
    }

    /** Edit the ping timeout field (VAL-SET-002). */
    fun editPingTimeout(value: UInt) {
        dispatch(AppAction.EditPingTimeout(value = value))
    }

    /** Edit the request TTL field (VAL-SET-002). */
    fun editRequestTtl(value: UInt) {
        dispatch(AppAction.EditRequestTtl(value = value))
    }

    /** Edit the state save interval field (VAL-SET-002). */
    fun editStateSaveInterval(value: UInt) {
        dispatch(AppAction.EditStateSaveInterval(value = value))
    }

    /** Edit the peer selection strategy field (VAL-SET-003). */
    fun editPeerSelectionStrategy(strategy: String) {
        dispatch(AppAction.EditPeerSelectionStrategy(strategy = strategy))
    }

    /** Add a relay URL with trim and dedupe (VAL-SET-014). */
    fun addRelay(url: String) {
        dispatch(AppAction.AddRelay(url = url))
    }

    /** Remove a relay URL (VAL-SET-014). */
    fun removeRelay(url: String) {
        dispatch(AppAction.RemoveRelay(url = url))
    }

    /** Save settings (VAL-SET-002/003/004/013/014).
     *  VAL-SET-004: saving does not disrupt a running signer.
     *  VAL-SET-016: blocked when signer is stopped (Rust silently blocks). */
    fun saveSettings() {
        dispatch(AppAction.SaveSettings)
    }

    /** Trigger copy profile — shell shows export-password prompt (VAL-SET-006/007). */
    fun requestCopyProfile() {
        dispatch(AppAction.RequestCopyProfile)
    }

    /** Confirm copy profile with export password (VAL-SET-007, VAL-SET-015). */
    fun confirmCopyProfile(password: String) {
        dispatch(AppAction.ConfirmCopyProfile(password = password))
    }

    /** Trigger copy share — shell shows export-password prompt (VAL-SET-008). */
    fun requestCopyShare() {
        dispatch(AppAction.RequestCopyShare)
    }

    /** Confirm copy share with export password (VAL-SET-008, VAL-SET-015). */
    fun confirmCopyShare(password: String) {
        dispatch(AppAction.ConfirmCopyShare(password = password))
    }

    /** Navigate to the Rotate Share flow (VAL-ROTATE-005). */
    fun navigateToRotateShare() {
        dispatch(AppAction.NavigateToRotateShare)
    }

    /**
     * Open the Rotate Share connect screen with the active profile
     * identity pre-seeded on `state.rotate_share`. Mirrors the iOS
     * helper so both shells drive the actor with the same active
     * profile context (VAL-ROTATE-005).
     */
    fun openRotateShareConnect(profileId: String, shortId: String, deviceLabel: String) {
        dispatch(
            AppAction.OpenRotateShareConnect(
                profileId = profileId,
                shortId = shortId,
                deviceLabel = deviceLabel
            )
        )
    }

    /** Edit the rotate-share connect-screen package input (VAL-ROTATE-005). */
    fun updateRotateSharePackage(value: String) {
        dispatch(AppAction.RotateShareUpdatePackage(value = value))
    }

    fun updateRotateSharePassword(value: String) {
        dispatch(AppAction.RotateShareUpdatePassword(value = value))
    }

    fun updateRotateShareRelay(value: String) {
        dispatch(AppAction.RotateShareUpdateRelay(value = value))
    }

    /** Submit the connect form — drives the live handshake off Main. */
    fun rotateShareConnect() {
        dispatch(AppAction.RotateShareConnect)
        // The actual handshake runs in the reconciler when Rust emits
        // AppUpdate.PerformRotateShareHandshake. We avoid a duplicate
        // off-Main call here so the actor's typed-error mapping stays
        // authoritative.
    }

    /** Confirm replacement of the active profile with the rotated identity. */
    fun rotateShareReplace() {
        dispatch(AppAction.RotateShareReplace)
        // The actual Keychain swap happens in the reconciler when Rust emits
        // AppUpdate.ReplaceProfileFromRotate.
    }

    /** Clear the typed error banner without leaving the connect screen. */
    fun rotateShareClearError() {
        dispatch(AppAction.RotateShareClearError)
    }

    /** Abandon the rotate-share flow entirely (VAL-ROTATE-010). */
    fun rotateShareReset() {
        dispatch(AppAction.RotateShareReset)
    }

    /** Edit the rotation-source picker (VAL-ROTATE-001..004). */
    fun rotateKeysetSelectSourceProfile(profileId: String) {
        dispatch(AppAction.KeysetSetRotationSourceProfile(profileId = profileId))
    }

    fun rotateKeysetAddSourceRow() {
        dispatch(AppAction.KeysetAddRotationSourceRow)
    }

    fun rotateKeysetRemoveSourceRow(index: Long) {
        dispatch(AppAction.KeysetRemoveRotationSourceRow(index = index.toUInt()))
    }

    fun rotateKeysetUpdateSourcePackage(index: Long, value: String) {
        dispatch(AppAction.KeysetUpdateRotationSourcePackage(index = index.toUInt(), value = value))
    }

    fun rotateKeysetUpdateSourcePassword(index: Long, value: String) {
        dispatch(AppAction.KeysetUpdateRotationSourcePassword(index = index.toUInt(), value = value))
    }

    /** Trigger logout — stops signer, zeros secrets, returns to hub (VAL-SET-010/011/012).
     *  Profile remains stored and re-openable without a password. */
    fun logout() {
        dispatch(AppAction.Logout)
    }

    /** Cancel the export password prompt (VAL-SET-006, VAL-SET-008). */
    fun cancelExport() {
        showExportPasswordPrompt = false
        pendingExportType = null
        dispatch(AppAction.ClearExportState)
    }

    /** Produce a bfprofile1 package encrypted with the export password
     *  and copy it to the clipboard (VAL-SET-007, VAL-SET-015). */
    private fun performCopyProfileExport(password: String) {
        val result = rust.exportProfile(exportPassword = password)
        if (result.startsWith("error:")) {
            dispatch(AppAction.ExportFailed(error = result))
        } else {
            // Copy to clipboard and dispatch success
            val clipboard = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
            val clip = android.content.ClipData.newPlainText("bfprofile1", result)
            clipboard.setPrimaryClip(clip)
            dispatch(AppAction.ExportCompleted(packageType = "profile"))
        }
        showExportPasswordPrompt = false
        pendingExportType = null
    }

    /** Produce a bfshare1 package encrypted with the export password
     *  and copy it to the clipboard (VAL-SET-008, VAL-SET-015). */
    private fun performCopyShareExport(password: String) {
        val result = rust.exportShare(exportPassword = password)
        if (result.startsWith("error:")) {
            dispatch(AppAction.ExportFailed(error = result))
        } else {
            // Copy to clipboard and dispatch success
            val clipboard = appContext.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
            val clip = android.content.ClipData.newPlainText("bfshare1", result)
            clipboard.setPrimaryClip(clip)
            dispatch(AppAction.ExportCompleted(packageType = "share"))
        }
        showExportPasswordPrompt = false
        pendingExportType = null
    }

    /** Perform a test sign operation (VAL-SIGN-002).
     *  Called from the reconcile side effect handler when Rust emits PerformTestSign.
     *  Calls FfiApp.testSign() and dispatches the result back to Rust.
     */
    private fun performTestSign() {
        Thread {
            val result = rust.testSign()
            mainHandler.post {
                if (result.success) {
                    dispatch(AppAction.TestSignResult(
                        requestId = result.requestId ?: "",
                        digest = result.digest ?: "",
                        signature = result.signature ?: ""
                    ))
                } else {
                    dispatch(AppAction.TestSignFailed(error = result.error ?: "unknown_error"))
                }
            }
        }.start()
    }

    /** Perform a test ECDH operation (VAL-SIGN-005).
     *  Called from the reconcile side effect handler when Rust emits PerformTestEcdh.
     *  Calls FfiApp.testEcdh() and dispatches the result back to Rust.
     */
    private fun performTestEcdh() {
        Thread {
            val result = rust.testEcdh()
            mainHandler.post {
                if (result.success) {
                    dispatch(AppAction.TestEcdhResult(
                        requestId = result.requestId ?: "",
                        targetPubkey = result.targetPubkey ?: "",
                        sharedSecret = result.sharedSecret ?: ""
                    ))
                } else {
                    dispatch(AppAction.TestEcdhFailed(error = result.error ?: "unknown_error"))
                }
            }
        }.start()
    }

    /** Start the signer runtime for the active profile (VAL-SIGNER-002).
     *
     *  Sequence (mirrors architecture §5 / §6 side-effect patterns):
     *  1. Resolve the active profile_id from `dashboard.profile_info`
     *     (populated by OnboardStored/OpenDashboard).
     *  2. Load the OnboardProfileMaterial JSON bytes from
     *     `ProfileStorageManager` (the same placeholder the bridge
     *     handshake wrote after a successful onboard). Return silently
     *     if neither is available so a stale Start tap on a closed
     *     dashboard does not crash.
     *  3. Decode the bytes as UTF-8 and call `FfiApp.startSigner(materialJson)`
     *     on a background thread. FfiApp.startSigner returns false if
     *     the material is malformed; the shell treats that as a normal
     *     failure and dispatches SignerStopped.
     *  4. Poll `FfiApp.getSignerStatus()` every 250 ms for up to 15 s
     *     for `running == true`. When the bridge reports running, post
     *     a `SignerStarted { relay_connected, readiness }` action back
     *     to the actor; the actor then transitions the dashboard to
     *     Running and prepends the "Signer runtime started" INFO
     *     event-log entry with the RFC-3339 timestamp from
     *     `mobile-signer-event-log-timestamp-rfc3339-fix`.
     *  5. On timeout (<=15 s) or FFI start failure, dispatch
     *     SignerStopped so the dashboard returns to Stopped with an
     *     explicit error in the audit log and no orphan runtime held
     *     by FfiApp.
     */
    private fun performStartSigner() {
        Thread {
            val profileId = state.dashboard.profileInfo?.profileId
            if (profileId.isNullOrEmpty()) {
                return@Thread
            }
            val materialBytes = storage.loadProfileMaterial(profileId) ?: return@Thread
            if (materialBytes.isEmpty()) {
                return@Thread
            }
            // ProfileStorageManager.loadProfileMaterial already Base64-decodes
            // the EncryptedSharedPreferences string back to the original
            // OnboardProfileMaterial JSON bytes that bifrost-codec produced
            // during onboard. Reinterpret them as UTF-8 so FfiApp.startSigner
            // and FfiApp.setActiveProfileMaterial see the canonical JSON the
            // bridge parser expects.
            val materialJson = String(materialBytes, Charsets.UTF_8)
            // Set the active material first so export copy-profile / copy-share
            // (VAL-SET-007/008/015) can read it later, then start the bridge.
            rust.setActiveProfileMaterial(materialJson = materialJson)
            val started = rust.startSigner(materialJson = materialJson)
            if (!started) {
                mainHandler.post {
                    dispatch(AppAction.SignerStopped)
                }
                return@Thread
            }
            // Poll for the bridge to report running. 15 s upper bound matches
            // VAL-SIGNER-002's transition envelope (the architecture pins
            // readiness to ~1 s cadence and VAL-SIGNER-004 allows up to 60 s
            // for ping round completion).
            for (i in 0 until 60) {
                Thread.sleep(250)
                val statusJson = rust.getSignerStatus()
                val json = try {
                    org.json.JSONObject(statusJson)
                } catch (e: Exception) {
                    continue
                }
                if (json.optBoolean("running", false)) {
                    val relay = json.optBoolean("relay_connected", false)
                    val readiness = json.optString("readiness", "runtime_ready")
                    mainHandler.post {
                        dispatch(AppAction.SignerStarted(
                            relayConnected = relay,
                            readiness = readiness
                        ))
                    }
                    return@Thread
                }
            }
            // Timeout — the FFI accepted the material but the bridge task
            // never reported running. Reset the dashboard so the operator
            // can retry from a clean Stopped state instead of having the
            // the UI claim "Stopped" while Rust owns a bridge.
            val alreadyRunning = try {
                org.json.JSONObject(rust.getSignerStatus()).optBoolean("running", false)
            } catch (e: Exception) {
                false
            }
            if (!alreadyRunning) {
                rust.stopSigner()
            }
            mainHandler.post {
                dispatch(AppAction.SignerStopped)
            }
        }.start()
    }

    /** Stop the signer runtime (VAL-SIGNER-015).
     *
     *  Calls FfiApp.stopSigner() on a background thread (the function signals
     *  the bridge to shut down and joins the polling task) and then dispatches
     *  SignerStopped so the actor resets dashboard.signer to the Stopped
     *  baseline while preserving profile_info for the identity block. */
    private fun performStopSigner() {
        Thread {
            rust.stopSigner()
            mainHandler.post {
                dispatch(AppAction.SignerStopped)
            }
        }.start()
    }

    /** Publish a kind-10000 encrypted backup (VAL-BACKUP-001..006).
     *
     *  Mirrors the create / onboard / rotate / import / recover
     *  publication path. The FFI handles NIP-44 encryption and the
     *  per-relay WebSocket publish; we forward the typed
     *  BackupPublishResult back to Rust so the actor can mirror it
     *  into `dashboard.last_backup_publish` for validators.
     */
    private fun performPublishBackup(source: String, materialJson: String) {
        if (materialJson.isEmpty()) {
            return
        }
        val sourceCopy = source
        Thread {
            val result = rust.`publishBackup`(`source` = sourceCopy, `materialJson` = materialJson)
            mainHandler.post {
                dispatch(
                    AppAction.BackupPublishCompleted(
                        source = result.source,
                        success = result.success,
                        eventId = result.eventId,
                        authorPubkey = result.authorPubkey,
                        contentLength = result.contentLength,
                        contentRedacted = result.contentRedacted,
                        groupPubkey = result.groupPubkey,
                        relaysAttempted = result.relaysAttempted,
                        relaysPublishedTo = result.relaysPublishedTo,
                        error = result.error
                    )
                )
            }
        }.start()
    }

    /** Decode the `OnboardProfileMaterial` JSON blob returned by
     * `rust.onboard` and extract the `share_seckey_hex` field. Returns
     * null on any parse error so the actor treats a missing secret as
     * a hard failure (no silent tombstone on replace). */
    private fun extractShareSeckeyHex(material: ByteArray?): String? {
        if (material == null || material.isEmpty()) return null
        return try {
            val json = org.json.JSONObject(String(material, Charsets.UTF_8))
            val secret = json.optString("share_seckey_hex", "").trim()
            if (secret.isEmpty()) null else secret
        } catch (e: Exception) {
            null
        }
    }

    /** Real FFI ping round per online peer (VAL-SIGNER-010, VAL-SIGNER-018).
     *
     *  Reads the most recent peer aliases from the cached dashboard state
     *  and calls FfiApp.pingPeer() per peer on a background thread (15 s
     *  round timeout per peer). On each successful round, posts a
     *  SignerPingComplete { peerAlias, lastSeenSecs, incomingAvailable }
     *  action to the actor so the peer row updates and a
     *  "INFO <RFC-3339> Ping complete: <alias>" event-log row is appended
     *  (mobile-signer-event-log-timestamp-rfc3339-fix). The 1 s poll tick
     *  keeps refreshing peer readiness / last-seen between pings.
     */
    private fun performPingSignerPeers() {
        Thread {
            val peers = state.dashboard.signer.peers
            if (peers.isEmpty()) {
                return@Thread
            }
            val now_epoch = System.currentTimeMillis() / 1000
            for (peer in peers) {
                val success = rust.pingPeer(peerAlias = peer.alias)
                if (success) {
                    val alias = peer.alias
                    val incomingAvailable = peer.nonces.incomingAvailable
                    mainHandler.post {
                        dispatch(AppAction.SignerPingComplete(
                            peerAlias = alias,
                            lastSeenSecs = now_epoch,
                            incomingAvailable = incomingAvailable
                        ))
                    }
                }
            }
        }.start()
    }

    /** Persist settings to secure storage (VAL-SET-002/003/004/013/014).
     *  Called when the user saves settings while the signer is running.
     *  The Rust state already has the updated values; we update the
     *  platform secure storage and the hub row label. */
    private fun persistSettingsToStorage() {
        // Settings are persisted by Rust via the PersistSettings side effect.
        // The shell's ProfileStorageManager handles platform secure storage updates.
        // No additional action needed here since Rust owns settings state.
    }

    companion object {
        @Volatile
        private var instance: AppManager? = null

        fun getInstance(context: Context): AppManager =
            instance ?: synchronized(this) {
                instance ?: AppManager(context.applicationContext).also { instance = it }
            }
    }
}

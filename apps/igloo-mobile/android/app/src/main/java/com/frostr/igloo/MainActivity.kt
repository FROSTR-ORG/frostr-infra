package com.frostr.igloo

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.frostr.igloo.ui.MainApp
import com.frostr.igloo.ui.theme.AppTheme

class MainActivity : ComponentActivity() {
    private lateinit var manager: AppManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        manager = AppManager.getInstance(applicationContext)
        setContent {
            AppTheme {
                MainApp(manager = manager)
            }
        }
        // Handle any test-inject intent that fired the activity. In debug
        // builds only, the manifest adds an intent-filter for the
        // `com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD` action so Maestro/
        // adb helpers can preload the OnboardConnect form. Release builds
        // ignore the action — BuildConfig.DEBUG gates this code path so
        // production code never observes the test entry point.
        handleTestInjectIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Forward subsequent intents (after the activity is already alive)
        // to the same handler so Maestro can re-preload or replace the
        // pending inject values mid-session.
        handleTestInjectIntent(intent)
    }

    /**
     * Debug-only test injection: parses the bfonboard package, password,
     * relay URL, and optional device name off an explicitly-tagged test intent
     * and forwards them to AppManager.injectOnboardCredentials, which
     * dispatches a single Rust action that preloads the OnboardConnect
     * state without advancing the step. The user/Maestro still taps
     * btn_connect to drive the normal handshake.
     *
     * Gated by BuildConfig.DEBUG so release builds ignore the action even if
     * the intent-filter somehow leaks into a release manifest. Empty or
     * missing extras are ignored — no side effects on the running app.
     */
    private fun handleTestInjectIntent(intent: Intent?) {
        if (intent == null) return
        if (!BuildConfig.DEBUG) return
        if (intent.action == ACTION_DEBUG_TEST_SAVE_SETTINGS) {
            val signTimeout = if (intent.hasExtra(EXTRA_SIGN_TIMEOUT_SECS)) {
                intent.getIntExtra(EXTRA_SIGN_TIMEOUT_SECS, -1).takeIf { it > 0 }?.toUInt()
            } else {
                null
            }
            val peerSelectionStrategy = intent
                .getStringExtra(EXTRA_PEER_SELECTION_STRATEGY)
                ?.trim()
                ?.ifEmpty { null }

            manager.testSaveSettings(
                signTimeoutSecs = signTimeout,
                peerSelectionStrategy = peerSelectionStrategy
            )
            return
        }

        if (intent.action == ACTION_DEBUG_TEST_SAVE_TO_DASHBOARD) {
            val deviceNameExtra = intent.getStringExtra(EXTRA_DEVICE_NAME)?.trim()?.ifEmpty { null }
            manager.testOnboardSaveToDashboard(deviceName = deviceNameExtra)
            return
        }

        if (intent.action == ACTION_DEBUG_TEST_EXPORT_ACTION) {
            val kind = intent.getStringExtra(EXTRA_EXPORT_KIND)?.trim().orEmpty()
            val password = intent.getStringExtra(EXTRA_PASSWORD).orEmpty()
            manager.testExportAction(kind = kind, password = password)
            return
        }

        if (intent.action == ACTION_DEBUG_TEST_LOAD_PROFILE) {
            val mode = intent.getStringExtra(EXTRA_LOAD_MODE)?.trim().orEmpty()
            val packageExtra = intent.getStringExtra(EXTRA_PACKAGE)?.trim().orEmpty()
            val password = intent.getStringExtra(EXTRA_PASSWORD).orEmpty()
            manager.testLoadProfileAction(mode = mode, pkg = packageExtra, password = password)
            return
        }

        if (intent.action == ACTION_DEBUG_TEST_LOAD_PROFILE_CONFIRM) {
            manager.testLoadProfileConfirm()
            return
        }

        if (intent.action == ACTION_DEBUG_TEST_CREATE_KEYSET) {
            val groupName = intent.getStringExtra(EXTRA_GROUP_NAME)?.trim().orEmpty()
            val threshold = intent.getIntExtra(EXTRA_THRESHOLD, -1)
            val count = intent.getIntExtra(EXTRA_COUNT, -1)
            val deviceName = intent.getStringExtra(EXTRA_DEVICE_NAME)?.trim().orEmpty()
            val relay = intent.getStringExtra(EXTRA_RELAY_URL)?.trim().orEmpty()
            manager.testCreateKeyset(
                groupName = groupName,
                threshold = threshold,
                count = count,
                deviceName = deviceName,
                relay = relay.ifEmpty { DEFAULT_RELAY_URL },
                autoFinish = intent.getBooleanExtra(EXTRA_AUTO_FINISH, true)
            )
            return
        }

        if (intent.action == ACTION_DEBUG_TEST_KEYSET_DISTRIBUTE_PASSWORD) {
            val shareIdx = intent.getIntExtra(EXTRA_SHARE_IDX, -1)
            val password = intent.getStringExtra(EXTRA_PASSWORD).orEmpty()
            manager.testKeysetDistributePassword(shareIdx = shareIdx, password = password)
            return
        }

        if (intent.action == ACTION_DEBUG_TEST_ROTATE_SHARE) {
            val packageExtra = intent.getStringExtra(EXTRA_PACKAGE)?.trim().orEmpty()
            val password = intent.getStringExtra(EXTRA_PASSWORD).orEmpty()
            val relay = intent.getStringExtra(EXTRA_RELAY_URL)?.trim().orEmpty()
            manager.testRotateShareAction(
                pkg = packageExtra,
                password = password,
                relay = relay.ifEmpty { DEFAULT_RELAY_URL }
            )
            return
        }

        if (intent.action == ACTION_DEBUG_TEST_ROTATE_SHARE_REPLACE) {
            manager.testRotateShareReplace()
            return
        }

        if (intent.action != ACTION_DEBUG_TEST_INJECT_ONBOARD) return

        val packageExtra = intent.getStringExtra(EXTRA_PACKAGE)?.trim().orEmpty()
        val passwordExtra = intent.getStringExtra(EXTRA_PASSWORD).orEmpty()
        val relayExtra = intent.getStringExtra(EXTRA_RELAY_URL)?.trim().orEmpty()
        val deviceNameExtra = intent.getStringExtra(EXTRA_DEVICE_NAME)?.trim().orEmpty().ifEmpty { null }

        // Refuse to act on empty payloads so a stray intent cannot wipe a
        // mid-progress user edit. The minimum requirement is non-empty
        // package + password so the inject does not destabilize the form.
        if (packageExtra.isEmpty() || passwordExtra.isEmpty()) {
            return
        }

        manager.injectOnboardCredentials(
            packageText = packageExtra,
            password = passwordExtra,
            relayUrl = relayExtra.ifEmpty { DEFAULT_RELAY_URL },
            deviceName = deviceNameExtra
        )

        if (intent.getBooleanExtra(EXTRA_CONNECT, false)) {
            manager.onboardConnect(
                pkg = packageExtra,
                password = passwordExtra,
                relayUrl = relayExtra.ifEmpty { DEFAULT_RELAY_URL }
            )
        }
    }

    companion object {
        // Debug-only action advertised by src/debug/AndroidManifest.xml. The
        // base app id is com.frostr.igloo and debug variant suffix .dev so
        // the fully qualified action stays stable across debug identifier
        // changes.
        internal const val ACTION_DEBUG_TEST_INJECT_ONBOARD =
            "com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD"
        internal const val ACTION_DEBUG_TEST_SAVE_SETTINGS =
            "com.frostr.igloo.DEBUG_TEST_SAVE_SETTINGS"
        internal const val ACTION_DEBUG_TEST_SAVE_TO_DASHBOARD =
            "com.frostr.igloo.DEBUG_TEST_SAVE_TO_DASHBOARD"
        internal const val ACTION_DEBUG_TEST_EXPORT_ACTION =
            "com.frostr.igloo.DEBUG_TEST_EXPORT_ACTION"
        internal const val ACTION_DEBUG_TEST_LOAD_PROFILE =
            "com.frostr.igloo.DEBUG_TEST_LOAD_PROFILE"
        internal const val ACTION_DEBUG_TEST_LOAD_PROFILE_CONFIRM =
            "com.frostr.igloo.DEBUG_TEST_LOAD_PROFILE_CONFIRM"
        internal const val ACTION_DEBUG_TEST_CREATE_KEYSET =
            "com.frostr.igloo.DEBUG_TEST_CREATE_KEYSET"
        internal const val ACTION_DEBUG_TEST_KEYSET_DISTRIBUTE_PASSWORD =
            "com.frostr.igloo.DEBUG_TEST_KEYSET_DISTRIBUTE_PASSWORD"
        internal const val ACTION_DEBUG_TEST_ROTATE_SHARE =
            "com.frostr.igloo.DEBUG_TEST_ROTATE_SHARE"
        internal const val ACTION_DEBUG_TEST_ROTATE_SHARE_REPLACE =
            "com.frostr.igloo.DEBUG_TEST_ROTATE_SHARE_REPLACE"

        internal const val EXTRA_PACKAGE = "package"
        internal const val EXTRA_PASSWORD = "password"
        internal const val EXTRA_RELAY_URL = "relay"
        internal const val EXTRA_DEVICE_NAME = "device_name"
        internal const val EXTRA_CONNECT = "connect"
        internal const val EXTRA_EXPORT_KIND = "kind"
        internal const val EXTRA_LOAD_MODE = "mode"
        internal const val EXTRA_SIGN_TIMEOUT_SECS = "sign_timeout_secs"
        internal const val EXTRA_PEER_SELECTION_STRATEGY = "peer_selection_strategy"
        internal const val EXTRA_GROUP_NAME = "group_name"
        internal const val EXTRA_THRESHOLD = "threshold"
        internal const val EXTRA_COUNT = "count"
        internal const val EXTRA_AUTO_FINISH = "auto_finish"
        internal const val EXTRA_SHARE_IDX = "share_idx"

        // Default relay URL used when the test intent omits `relay`. The
        // Android emulator's host loopback is 10.0.2.2 by convention.
        // Sourced from RelayDefaults so this companion-object literal is
        // not a second copy of the platform default — Compose forms and
        // the debug intent path both point at the same single source of
        // truth (mobile-android-relay-url-platform-default-fix).
        internal const val DEFAULT_RELAY_URL: String = RelayDefaults.DEFAULT
    }
}

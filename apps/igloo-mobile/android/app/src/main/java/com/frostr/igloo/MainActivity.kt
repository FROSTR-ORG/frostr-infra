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
    }

    companion object {
        // Debug-only action advertised by src/debug/AndroidManifest.xml. The
        // base app id is com.frostr.igloo and debug variant suffix .dev so
        // the fully qualified action stays stable across debug identifier
        // changes.
        internal const val ACTION_DEBUG_TEST_INJECT_ONBOARD =
            "com.frostr.igloo.DEBUG_TEST_INJECT_ONBOARD"

        internal const val EXTRA_PACKAGE = "package"
        internal const val EXTRA_PASSWORD = "password"
        internal const val EXTRA_RELAY_URL = "relay"
        internal const val EXTRA_DEVICE_NAME = "device_name"

        // Default relay URL used when the test intent omits `relay`. The
        // Android emulator's host loopback is 10.0.2.2 by convention.
        // Sourced from RelayDefaults so this companion-object literal is
        // not a second copy of the platform default — Compose forms and
        // the debug intent path both point at the same single source of
        // truth (mobile-android-relay-url-platform-default-fix).
        internal const val DEFAULT_RELAY_URL: String = RelayDefaults.DEFAULT
    }
}

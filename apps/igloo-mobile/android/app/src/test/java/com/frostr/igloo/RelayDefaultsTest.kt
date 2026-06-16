package com.frostr.igloo

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guardrail tests for the Android relay-URL default
 * (`mobile-android-relay-url-platform-default-fix`).
 *
 * Before the fix, the Android Compose `RotateShareConnectScreen` form
 * pre-filled with `ws://127.0.0.1:8194` (the iOS Simulator value),
 * which leaves the user staring at a relay-connection-timeout error on
 * the Android emulator because the emulator's host-loopback alias is
 * `10.0.2.2`, not `127.0.0.1`. The fix introduces the single-source
 * `RelayDefaults.DEFAULT` constant for the Android shell.
 *
 * These tests do not exercise Compose UI or the live relay; they pin the
 * constant string itself so a future regression that re-introduces the
 * iOS-Simulator default or silently drops the platform-correct alias
 * is caught at unit-test time without booting the emulator.
 *
 * Run via:
 *   source ~/.config/frostr/rmp-mobile-env.zsh &&
 *     cd apps/igloo-mobile/android &&
 *     ./gradlew :app:testDebugUnitTest --tests com.frostr.igloo.RelayDefaultsTest
 */
class RelayDefaultsTest {

    /**
     * The Android default MUST be `ws://10.0.2.2:8194` — the platform-
     * correct alias for the host's `127.0.0.1:8194` when running inside
     * the QEMU-based Android emulator. Any other value silently breaks
     * the handshake for every Android user who does not override the
     * form field.
     */
    @Test
    fun android_default_uses_emulator_host_loopback_alias() {
        assertEquals(
            "ws://10.0.2.2:8194",
            RelayDefaults.DEFAULT,
        )
    }

    /**
     * The default URL must be a syntactically valid ws:// URL and carry
     * the FROSTR demo harness port `8194`. Forms that mistakenly insert
     * a placeholder hostname or a different port would push the user
     * into a synthetic network misconfiguration that hides the real
     * bug (wrong platform default).
     */
    @Test
    fun android_default_is_well_formed_ws_url_with_demo_port() {
        val default = RelayDefaults.DEFAULT
        assertNotNull(default)
        assertTrue(
            "default URL must start with ws://, got '$default'",
            default.startsWith("ws://"),
        )
        assertTrue(
            "default URL must target the FROSTR demo harness port 8194, got '$default'",
            default.endsWith(":8194"),
        )
    }

    /**
     * Guard against accidentally re-introducing the iOS Simulator
     * host-loopback value. The Android emulator cannot reach the host
     * via `127.0.0.1`; this is the exact string the original bug used
     * and is the regression we want to lock down in unit-test form.
     */
    @Test
    fun android_default_is_not_ios_simulator_loopback() {
        assertEquals(
            false,
            RelayDefaults.DEFAULT.contains("127.0.0.1"),
        )
    }
}

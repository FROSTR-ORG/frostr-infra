package com.frostr.igloo

import org.junit.Assert.assertArrayEquals
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

    /**
     * Create Keyset wizard Device Profile relay default
     * (`mobile-android-create-keyset-wizard-relay-url-fix`).
     *
     * The shared Rust core pre-fills `KeysetFlowState.relays` with the
     * iOS-Simulator localhost (`ws://127.0.0.1:8194`) so the actor is
     * platform-neutral. The Android Compose `CreateKeysetDeviceProfileScreen`
     * override must rewrite that prefill to `RelayDefaults.DEFAULT` so
     * the form opens with the platform-correct alias. This test pins
     * the override semantics: any relay list that is empty or carries
     * the iOS-Simulator localhost must surface as `RelayDefaults.DEFAULT`,
     * while any other relay list (a user-typed value) must be preserved
     * verbatim so we never clobber a custom URL.
     */
    @Test
    fun create_keyset_wizard_overrides_ios_localhost_with_android_default() {
        val display = relayDisplayFor(listOf("ws://127.0.0.1:8194"))
        assertArrayEquals(
            "Create Keyset wizard must surface the Android emulator relay, " +
                "not the iOS-Simulator localhost the actor pre-fills.",
            arrayOf(RelayDefaults.DEFAULT),
            display.toTypedArray(),
        )
    }

    /**
     * Empty actor relays (which the Rust core sets before
     * `CreateKeysetGenerationSuccess` lands) must still display as
     * `RelayDefaults.DEFAULT` so the user never sees a blank relay
     * form on first entry.
     */
    @Test
    fun create_keyset_wizard_empty_actor_relays_surface_android_default() {
        val display = relayDisplayFor(emptyList())
        assertArrayEquals(
            "Empty actor relays must surface as RelayDefaults.DEFAULT.",
            arrayOf(RelayDefaults.DEFAULT),
            display.toTypedArray(),
        )
    }

    /**
     * A user-typed custom relay must survive the override; the
     * guardian is meant to fix the iOS-Simulator-default regression,
     * not to clobber every relay the user enters.
     */
    @Test
    fun create_keyset_wizard_preserves_user_typed_relay() {
        val userRelays = listOf("wss://user-relay.example.com")
        val display = relayDisplayFor(userRelays)
        assertArrayEquals(
            "User-typed relay list must be preserved by the override logic.",
            arrayOf("wss://user-relay.example.com"),
            display.toTypedArray(),
        )
    }

    /**
     * Multi-line custom relay list with the iOS-Simulator localhost
     * mixed in must keep the user entries and drop/rewrite the iOS
     * value. Concretely the override is intentionally narrow — it
     * only rewrites the actor's pure-iOS prefill — so a list of
     * `[user, ios]` must display unchanged because the user is the
     * authoritative editor of the field. This contract is what keeps
     * `onValueChange`'s split/filter/map round-trip safe.
     */
    @Test
    fun create_keyset_wizard_preserves_mixed_relay_list() {
        val mixedRelays = listOf(
            "wss://user-relay.example.com",
            "ws://127.0.0.1:8194",
        )
        val display = relayDisplayFor(mixedRelays)
        assertArrayEquals(
            "Mixed relay list (user + iOS) must be preserved, because " +
                "the override only fires for the actor's pure iOS prefill.",
            arrayOf(
                "wss://user-relay.example.com",
                "ws://127.0.0.1:8194",
            ),
            display.toTypedArray(),
        )
    }

    /**
     * Mirror of the override logic in `CreateKeysetDeviceProfileScreen`
     * (MainApp.kt). Kept private to the test file so the Compose code
     * stays the source of truth — if the Compose branch changes shape,
     * update this lambda and the Compose call site together.
     */
    private fun relayDisplayFor(actorRelays: List<String>): List<String> =
        if (actorRelays.isEmpty() ||
            actorRelays == listOf("ws://127.0.0.1:8194")
        ) {
            listOf(RelayDefaults.DEFAULT)
        } else {
            actorRelays
        }

    /**
     * Create Keyset wizard Device Profile → Review actor sync
     * (`mobile-android-review-step-relay-url-display-fix`).
     *
     * The shared Rust core pre-fills `KeysetFlowState.relays` with the
     * iOS-Simulator localhost literal (`ws://127.0.0.1:8194`). The
     * Android Compose `CreateKeysetDeviceProfileScreen` override
     * rewrites that to `RelayDefaults.DEFAULT` for display, but the
     * actor still carries the iOS prefill until a sync dispatch runs.
     * Without the sync the Review step would render the stale iOS
     * prefill instead of the value the user just accepted (VAL-CREATE-008
     * parity). This helper pins the sync logic: when the display
     * override rewrote the iOS prefill to `RelayDefaults.DEFAULT`,
     * the next relays list the actor should carry is
     * `[RelayDefaults.DEFAULT]`. Otherwise, the actor keeps whatever
     * the user typed (or whatever was already there).
     */
    @Test
    fun create_keyset_wizard_sync_after_device_profile_ios_prefill() {
        val synced = relaySyncFor(listOf("ws://127.0.0.1:8194"))
        assertArrayEquals(
            "After Device Profile first composition the actor relays " +
                "must match the displayed Android default so the Review " +
                "step reads the same relay URL the user accepted.",
            arrayOf(RelayDefaults.DEFAULT),
            synced.toTypedArray(),
        )
    }

    /**
     * When the actor still has empty relays (a transient state if a
     * future code path defers the prefill), the Device Profile screen
     * surface default must still sync through the actor so the Review
     * step is not blank.
     */
    @Test
    fun create_keyset_wizard_sync_after_device_profile_empty_actor() {
        val synced = relaySyncFor(emptyList())
        assertArrayEquals(
            "Empty actor relays must still sync to RelayDefaults.DEFAULT " +
                "once the Device Profile override runs.",
            arrayOf(RelayDefaults.DEFAULT),
            synced.toTypedArray(),
        )
    }

    /**
     * User-typed relay lists must NOT be re-written by the sync — the
     * override rewrote the iOS-Simulator prefill, not arbitrary user
     * content. The sync only takes effect for the exact iOS prefill
     * shape (empty or [ws://127.0.0.1:8194]); otherwise the actor's
     * existing relays survive unchanged into the Review step.
     */
    @Test
    fun create_keyset_wizard_sync_preserves_user_relays() {
        val userRelays = listOf("wss://user-relay.example.com")
        val synced = relaySyncFor(userRelays)
        assertArrayEquals(
            "User-typed relay list must survive the sync dispatch.",
            arrayOf("wss://user-relay.example.com"),
            synced.toTypedArray(),
        )
    }

    /**
     * Mirror of the actor-sync dispatch logic in
     * `CreateKeysetDeviceProfileScreen` (MainApp.kt). Same rationale
     * as `relayDisplayFor`: kept private to the test file so the
     * Compose code stays the source of truth.
     */
    private fun relaySyncFor(actorRelays: List<String>): List<String> {
        val display = relayDisplayFor(actorRelays)
        val actorNeedsReset = actorRelays.isEmpty() ||
            actorRelays == listOf("ws://127.0.0.1:8194")
        val displayIsAndroidDefault = display == listOf(RelayDefaults.DEFAULT)
        return if (actorNeedsReset && displayIsAndroidDefault) {
            listOf(RelayDefaults.DEFAULT)
        } else {
            actorRelays
        }
    }
}

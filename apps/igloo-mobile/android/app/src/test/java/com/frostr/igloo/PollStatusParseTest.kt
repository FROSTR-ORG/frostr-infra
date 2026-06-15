package com.frostr.igloo

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Focused regression tests for the JSON null-or-missing timestamp contract
 * used by `AppManager.pollSignerStatus()` on the Android Save→Dashboard
 * path.
 *
 * Background:
 * `FfiApp.getSignerStatus()` returns a JSON object whose optional timestamp
 * fields (`last_refresh_secs` at the top level, `last_seen_secs` on each
 * peer entry) are serialized from `Option<i64>` on the Rust side. While the
 * polling task has not yet produced a first sample, those values serialize
 * to JSON `null`. Android's `org.json.JSONObject.has(key)` returns `true`
 * for keys whose value is `null`, so the naive `if (has(k)) getLong(k)`
 * pattern previously in `AppManager.pollSignerStatus` threw `JSONException`
 * and SIGKILLed the foreground Compose root (see
 * `apps/igloo-mobile/library/evidence/VAL-ONBOARD-android-save-poll-timer-crash/`,
 * commit `7910f70`).
 *
 * These tests assert the fix's contract without touching the live signer
 * runtime or the bridge:
 *
 *  - A key whose value is present and numeric round-trips as a `Long`.
 *  - A key whose value is present and explicitly `null` round-trips as
 *    `null` (and does not throw).
 *  - A key that is missing entirely round-trips as `null`.
 *  - Coercion to `0` is explicitly forbidden: the optional timestamp
 *    semantics are preserved.
 *
 * The test is runnable via
 *   source ~/.config/frostr/rmp-mobile-env.zsh && \
 *     cd apps/igloo-mobile/android && \
 *     ./gradlew :app:testDebugUnitTest --tests com.frostr.igloo.PollStatusParseTest
 */
class PollStatusParseTest {

    /** Present and numeric: round-trips as Long, never coerced. */
    @Test
    fun present_long_returns_value() {
        val json = JSONObject().apply {
            put("last_refresh_secs", 1234567890L)
        }
        assertEquals(
            1234567890L,
            PollStatusParse.lookupOptionalTimestamp(json, "last_refresh_secs"),
        )
    }

    /** Present with JSON null: must NOT throw and must return Kotlin null. */
    @Test
    fun present_json_null_returns_kotlin_null() {
        val json = JSONObject().apply {
            put("last_refresh_secs", JSONObject.NULL)
        }
        assertNull(PollStatusParse.lookupOptionalTimestamp(json, "last_refresh_secs"))
    }

    /** Key missing entirely: returns Kotlin null (no JSONException). */
    @Test
    fun missing_key_returns_kotlin_null() {
        val json = JSONObject().apply {
            put("readiness", "idle")
        }
        assertNull(PollStatusParse.lookupOptionalTimestamp(json, "last_refresh_secs"))
    }

    /**
     * Present but the underlying value is missing altogether (empty object):
     * this is the edge case where a Rust struct with `Option::None` would
     * produce JSON with no key at all. Same contract as `missing_key_returns_kotlin_null`.
     */
    @Test
    fun empty_object_returns_kotlin_null() {
        val json = JSONObject()
        assertNull(PollStatusParse.lookupOptionalTimestamp(json, "last_refresh_secs"))
    }

    /**
     * Per-peer `last_seen_secs` covers the second crash surface area
     * (`AppManager.kt:759` for the previous `has+getLong` pattern).
     * Same null-or-missing coalescing must apply to the inner peer object.
     */
    @Test
    fun per_peer_present_null_returns_kotlin_null() {
        val peer = JSONObject().apply {
            put("alias", "alice")
            put("online", true)
            put("last_seen_secs", JSONObject.NULL)
        }
        assertNull(PollStatusParse.lookupOptionalTimestamp(peer, "last_seen_secs"))
    }

    @Test
    fun per_peer_present_long_returns_value() {
        val peer = JSONObject().apply {
            put("alias", "alice")
            put("online", true)
            put("last_seen_secs", 1718254800L)
        }
        assertEquals(
            1718254800L,
            PollStatusParse.lookupOptionalTimestamp(peer, "last_seen_secs"),
        )
    }

    @Test
    fun per_peer_missing_returns_kotlin_null() {
        val peer = JSONObject().apply {
            put("alias", "carol")
            put("online", false)
        }
        assertNull(PollStatusParse.lookupOptionalTimestamp(peer, "last_seen_secs"))
    }

    /**
     * Optional-timestamp semantics are preserved: a missing/null field MUST
     * NOT be coerced to a default `0`. This guards the documented invariant
     * that a separate contract decision would be required to change the
     * timestamp semantics, and that this fix is purely defensive.
     */
    @Test
    fun missing_timestamp_is_never_coerced_to_zero() {
        val peers = mutableListOf<JSONObject>()
        peers.add(JSONObject()) // missing key entirely
        peers.add(JSONObject().apply { put("last_seen_secs", JSONObject.NULL) }) // explicit null

        for (peer in peers) {
            val value = PollStatusParse.lookupOptionalTimestamp(peer, "last_seen_secs")
            // 0L would be a coercion; null is the only acceptable return.
            assertNull("peer entry must not coerce missing/null to 0", value)
        }
    }
}

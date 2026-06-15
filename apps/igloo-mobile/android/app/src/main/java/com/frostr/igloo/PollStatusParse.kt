package com.frostr.igloo

import org.json.JSONObject

/**
 * Helpers for parsing the JSON snapshot returned by
 * `FfiApp.getSignerStatus()` on the Android shell.
 *
 * `getSignerStatus()` is called from `AppManager.pollSignerStatus()` on the
 * main looper roughly every second while the dashboard is visible
 * (VAL-SIGNER-011). The returned object contains two optional timestamp
 * fields that Rust serializes as `Option<i64>`:
 *
 * - top-level `last_refresh_secs`
 * - per-peer `last_seen_secs` (inside each `peers[]` element)
 *
 * When the underlying Rust value is `None`, serde_json emits the key with
 * a `null` value. Android's `org.json.JSONObject.has(key)` returns `true`
 * for keys whose value is `null`, so the naive `if (has(k)) getLong(k)`
 * pattern — which previously lived in `AppManager.pollSignerStatus` —
 * throws `JSONException: Value null ... cannot be converted to long` and
 * kills the foreground Compose root, taking down the Onboard Save → Dashboard
 * path (mobile-android-onboard-save-poll-timer-fix, evidence captured at
 * commit `7910f70` under
 * `apps/igloo-mobile/library/evidence/VAL-ONBOARD-android-save-poll-timer-crash/`).
 *
 * These helpers coalesce the three states a timestamp field may be in:
 *
 * 1. key absent                → `null`
 * 2. key present, value `null` → `null`
 * 3. key present, numeric value → the `Long`
 *
 * They intentionally never coerce unknown timestamps to `0`; the timestamp
 * semantics stay optional and downstream consumers continue to behave like
 * the existing iOS implementation, which uses Swift's `as? Int64` to allow
 * both null and missing to round-trip as a Kotlin `null`.
 */
internal object PollStatusParse {
    /**
     * Returns the long value of an optional timestamp key on a JSON object.
     *
     * - Missing key, key with `JSONObject.NULL` value, or non-numeric value
     *   → returns `null` and never throws `JSONException`.
     * - Numeric value → returns that value as `Long`.
     *
     * `org.json.JSONObject.NULL` is the sentinel object returned by
     * `JSONObject.null` and what `isNull(key)` matches on; we test both
     * `has(key)` and `isNull(key)` so that an absent key, an explicitly
     * null value, and a value that is `JSONObject.NULL` all collapse to the
     * same Kotlin `null`.
     *
     * Sibling to `[lookupOptionalTimestamp]`, kept inline-friendly because
     * `peer` data is itself a JSON object whose field is sometimes
     * syntactically present but semantically null.
     */
    fun lookupOptionalTimestamp(json: JSONObject, key: String): Long? {
        if (!json.has(key) || json.isNull(key)) {
            return null
        }
        return try {
            json.getLong(key)
        } catch (_: org.json.JSONException) {
            // Defensive: if the value is present and non-null but not a
            // long (e.g. an `Int` that overflows on read, or a misencoded
            // string), preserve the existing contract of "unknown timestamp
            // stays null" rather than hallucinating a value.
            null
        }
    }
}

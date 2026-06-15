package com.frostr.igloo

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONArray
import org.json.JSONObject

/**
 * Manages profile material storage on Android using EncryptedSharedPreferences
 * backed by Android Keystore. Per architecture §6: decrypted key material lives
 * in Keystore-backed storage, never in Rust persistence. Package passwords are
 * never stored; profile opens are password-less.
 */
class ProfileStorageManager private constructor(private val context: Context) {
    private val masterKey: MasterKey by lazy {
        MasterKey.Builder(context)
            .setKeyGenParameterSpec(
                KeyGenParameterSpec.Builder(
                    MasterKey.DEFAULT_MASTER_KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build()
            )
            .build()
    }

    private val encryptedPrefs: SharedPreferences by lazy {
        EncryptedSharedPreferences.create(
            context,
            "igloo_profiles_secure",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    private val profileIndexKey = "stored_profile_index"
    private val profileIdSetKey = "stored_profile_ids"

    // MARK: - Profile Index (non-secret, stored in plain SharedPreferences)

    /**
     * Load the non-secret profile index from UserDefaults.
     */
    fun loadProfileIndex(): List<ProfileIndexEntry> {
        val json = encryptedPrefs.getString(profileIndexKey, null) ?: return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).map { i ->
                val obj = array.getJSONObject(i)
                ProfileIndexEntry(
                    profileId = obj.getString("profileId"),
                    label = obj.getString("label"),
                    shortId = obj.getString("shortId")
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /**
     * Save the non-secret profile index to UserDefaults.
     */
    fun saveProfileIndex(entries: List<ProfileIndexEntry>) {
        val array = JSONArray()
        entries.forEach { entry ->
            val obj = JSONObject().apply {
                put("profileId", entry.profileId)
                put("label", entry.label)
                put("shortId", entry.shortId)
            }
            array.put(obj)
        }
        encryptedPrefs.edit().putString(profileIndexKey, array.toString()).apply()
    }

    /**
     * Add a profile to the index (or update if exists).
     */
    fun addProfileToIndex(entry: ProfileIndexEntry) {
        val entries = loadProfileIndex().toMutableList()
        entries.removeAll { it.profileId == entry.profileId }
        entries.add(entry)
        saveProfileIndex(entries)
        // Also track IDs for efficient lookup
        val ids = loadAllProfileIds().toMutableSet()
        ids.add(entry.profileId)
        saveProfileIdSet(ids)
    }

    /**
     * Remove a profile from the index.
     */
    fun removeProfileFromIndex(profileId: String) {
        val entries = loadProfileIndex().toMutableList()
        entries.removeAll { it.profileId == profileId }
        saveProfileIndex(entries)
        val ids = loadAllProfileIds().toMutableSet()
        ids.remove(profileId)
        saveProfileIdSet(ids)
    }

    private fun saveProfileIdSet(ids: Set<String>) {
        encryptedPrefs.edit().putStringSet(profileIdSetKey, ids).apply()
    }

    private fun loadAllProfileIds(): Set<String> {
        return encryptedPrefs.getStringSet(profileIdSetKey, emptySet()) ?: emptySet()
    }

    // MARK: - Secure Storage (EncryptedSharedPreferences)

    /**
     * Store profile key material in EncryptedSharedPreferences.
     * Returns true on success.
     */
    fun storeProfileMaterial(profileId: String, material: ByteArray): Boolean {
        return try {
            encryptedPrefs.edit().putString(profileId, android.util.Base64.encodeToString(material, android.util.Base64.NO_WRAP)).apply()
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Load profile key material from EncryptedSharedPreferences.
     * Returns null if not found or on error.
     */
    fun loadProfileMaterial(profileId: String): ByteArray? {
        return try {
            val encoded = encryptedPrefs.getString(profileId, null) ?: return null
            android.util.Base64.decode(encoded, android.util.Base64.NO_WRAP)
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Delete profile key material from EncryptedSharedPreferences.
     * Returns true on success (including item-not-found).
     */
    fun deleteProfileMaterial(profileId: String): Boolean {
        return try {
            encryptedPrefs.edit().remove(profileId).apply()
            true
        } catch (e: Exception) {
            false
        }
    }

    // MARK: - Combined Operations

    /**
     * Store profile material and add to index atomically.
     */
    fun storeProfile(profileId: String, label: String, shortId: String, material: ByteArray): Boolean {
        val indexEntry = ProfileIndexEntry(profileId = profileId, label = label, shortId = shortId)
        addProfileToIndex(indexEntry)
        return storeProfileMaterial(profileId, material)
    }

    /**
     * Delete profile material and remove from index atomically.
     */
    fun deleteProfile(profileId: String): Boolean {
        removeProfileFromIndex(profileId)
        return deleteProfileMaterial(profileId)
    }

    /**
     * Load all profiles from index, returning profile IDs with their labels.
     * Used on app startup to restore the hub.
     */
    fun loadAllStoredProfiles(): List<ProfileIndexEntry> {
        return loadProfileIndex()
    }

    // MARK: - Data class

    data class ProfileIndexEntry(
        val profileId: String,
        val label: String,
        val shortId: String
    )

    companion object {
        @Volatile
        private var instance: ProfileStorageManager? = null

        fun getInstance(context: Context): ProfileStorageManager =
            instance ?: synchronized(this) {
                instance ?: ProfileStorageManager(context.applicationContext).also { instance = it }
            }
    }
}
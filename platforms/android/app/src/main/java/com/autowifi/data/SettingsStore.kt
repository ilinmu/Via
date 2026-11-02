package com.autowifi.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Settings live in plain SharedPreferences; Wi-Fi passphrases live only in
 * encrypted storage. There is deliberately no plaintext fallback: if the
 * encrypted store cannot be opened, the password setters throw and the UI
 * reports the failure instead of silently storing a secret.
 */
class SettingsStore(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(FILE_PLAIN, Context.MODE_PRIVATE)

    private val secure: SharedPreferences? = runCatching {
        val context = context.applicationContext
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            FILE_SECURE,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }.getOrNull()

    val secureStorageAvailable: Boolean get() = secure != null

    var ssidP: String
        get() = prefs.getString(KEY_SSID_P, "").orEmpty()
        set(value) = prefs.edit().putString(KEY_SSID_P, value).apply()

    var ssidB: String
        get() = prefs.getString(KEY_SSID_B, "").orEmpty()
        set(value) = prefs.edit().putString(KEY_SSID_B, value).apply()

    var intervalSeconds: Int
        get() = prefs.getInt(KEY_INTERVAL, DEFAULT_INTERVAL).coerceIn(MIN_INTERVAL, MAX_INTERVAL)
        set(value) = prefs.edit().putInt(KEY_INTERVAL, value.coerceIn(MIN_INTERVAL, MAX_INTERVAL)).apply()

    var language: String
        get() = prefs.getString(KEY_LANGUAGE, "zh").orEmpty().ifEmpty { "zh" }
        set(value) = prefs.edit().putString(KEY_LANGUAGE, value).apply()

    var running: Boolean
        get() = prefs.getBoolean(KEY_RUNNING, false)
        set(value) = prefs.edit().putBoolean(KEY_RUNNING, value).apply()

    var launchAtBoot: Boolean
        get() = prefs.getBoolean(KEY_LAUNCH_AT_BOOT, false)
        set(value) = prefs.edit().putBoolean(KEY_LAUNCH_AT_BOOT, value).apply()

    var passwordP: String
        get() = secure?.getString(KEY_PASSWORD_P, "").orEmpty()
        set(value) = writeSecret(KEY_PASSWORD_P, value)

    var passwordB: String
        get() = secure?.getString(KEY_PASSWORD_B, "").orEmpty()
        set(value) = writeSecret(KEY_PASSWORD_B, value)

    private fun writeSecret(key: String, value: String) {
        val store = secure ?: throw IllegalStateException("Encrypted storage is unavailable")
        val editor = store.edit()
        if (value.isEmpty()) editor.remove(key) else editor.putString(key, value)
        if (!editor.commit()) throw IllegalStateException("Unable to write encrypted storage")
    }

    companion object {
        const val MIN_INTERVAL = 5
        const val MAX_INTERVAL = 3600
        const val DEFAULT_INTERVAL = 15

        private const val FILE_PLAIN = "autowifi"
        private const val FILE_SECURE = "autowifi_secure"
        private const val KEY_SSID_P = "ssid_p"
        private const val KEY_SSID_B = "ssid_b"
        private const val KEY_INTERVAL = "interval_seconds"
        private const val KEY_LANGUAGE = "language"
        private const val KEY_RUNNING = "running"
        private const val KEY_LAUNCH_AT_BOOT = "launch_at_boot"
        private const val KEY_PASSWORD_P = "password_p"
        private const val KEY_PASSWORD_B = "password_b"
    }
}

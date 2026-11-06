package io.github.ilinmu.via.data

import android.content.Context
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.os.SystemClock
import kotlinx.coroutines.delay

data class NetworkCredential(val ssid: String, val password: String)

/**
 * Android's Wi-Fi API does not allow an app to force a connection. The best a
 * normal app can do is register [WifiNetworkSuggestion]s and let the system
 * pick one; scanning is rate limited and only gives SSIDs when location
 * permission is granted.
 */
class WifiRepository(context: Context) {
    private val wifiManager =
        context.applicationContext.getSystemService(WifiManager::class.java)

    private var cachedNetworks: Set<String> = emptySet()
    private var lastScanElapsedMs = 0L

    @Synchronized
    private fun cachedNetworks(now: Long, force: Boolean): Set<String>? =
        if (!force && now - lastScanElapsedMs < SCAN_CACHE_MS && cachedNetworks.isNotEmpty()) {
            cachedNetworks
        } else {
            null
        }

    @Synchronized
    private fun storeScanResult(fresh: Set<String>, now: Long) {
        // `startScan()` succeeding does not mean the result list is ready yet.
        // Only a non-empty result can prove that the cache should be replaced;
        // an empty one may be throttling rather than a real disappearance.
        if (fresh.isNotEmpty()) {
            cachedNetworks = fresh
            lastScanElapsedMs = now
        }
    }

    fun isWifiEnabled(): Boolean = wifiManager?.isWifiEnabled == true

    @Suppress("DEPRECATION")
    fun currentSsid(): String? {
        val manager = wifiManager ?: return null
        if (!manager.isWifiEnabled) return null
        val info = runCatching { manager.connectionInfo }.getOrNull() ?: return null
        val raw = info.ssid ?: return null
        if (raw.isEmpty() || raw == UNKNOWN_SSID) return null
        return raw.trim('"').ifEmpty { null }
    }

    /**
     * Starts a scan and returns the visible SSIDs. Results are cached briefly
     * because Android throttles background scans; an empty fresh result keeps
     * the previous cache instead of reporting every network as missing.
     */
    @Suppress("DEPRECATION")
    suspend fun scan(force: Boolean = false): Set<String> {
        val manager = wifiManager ?: return emptySet()
        val now = SystemClock.elapsedRealtime()
        cachedNetworks(now, force)?.let { return it }
        if (!manager.isWifiEnabled) return cachedNetworks

        val started = runCatching { manager.startScan() }.getOrDefault(false)
        if (!started) return cachedNetworks
        delay(SCAN_SETTLE_MS)

        val fresh = runCatching {
            manager.scanResults
                .mapNotNull { it.SSID?.trim('"') }
                .filter { it.isNotEmpty() }
                .toSet()
        }.getOrDefault(emptySet())

        storeScanResult(fresh, now)
        return if (fresh.isNotEmpty()) fresh else cachedNetworks
    }

    /**
     * Replaces this app's Wi-Fi suggestions with the configured P/B networks.
     * Returns false when the system rejected the request (for example because
     * a passphrase is too short) or when the caller lacks permission.
     */
    fun applySuggestions(credentials: List<NetworkCredential>): Boolean {
        return applySuggestions(credentials, priorityNetwork = null)
    }

    /**
     * Registers P and B together. When a policy action asks the system to
     * prefer one of them, that network gets a higher suggestion priority but
     * the other one remains registered so it can still be used as a fallback.
     */
    fun applySuggestions(
        credentials: List<NetworkCredential>,
        priorityNetwork: String?,
    ): Boolean {
        val manager = wifiManager ?: return false
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val existing = manager.networkSuggestions
                if (!existing.isNullOrEmpty()) manager.removeNetworkSuggestions(existing)
            }
            var rejected = false
            val suggestions = credentials
                .distinctBy { it.ssid.trim() }
                .mapNotNull { credential ->
                    val ssid = credential.ssid.trim()
                    if (ssid.isEmpty()) return@mapNotNull null
                    val builder = WifiNetworkSuggestion.Builder().setSsid(ssid)
                    if (credential.password.isNotEmpty()) {
                        if (credential.password.length !in 8..63) {
                            // The system would ignore the suggestion without any
                            // error, so report the failure to the caller.
                            rejected = true
                            return@mapNotNull null
                        }
                        builder.setWpa2Passphrase(credential.password)
                    } else {
                        builder.setIsEnhancedOpen(false)
                    }
                    // setPriority accepts any non-negative int; the API exposes
                    // no public MAX_PRIORITY constant. A larger number wins
                    // among this app's suggestions (API 29+).
                    builder.setPriority(
                        if (ssid == priorityNetwork?.trim()) {
                            TARGET_SUGGESTION_PRIORITY
                        } else {
                            FALLBACK_SUGGESTION_PRIORITY
                        }
                    )
                    builder.build()
                }
            if (suggestions.isEmpty()) return !rejected
            manager.addNetworkSuggestions(suggestions) ==
                WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS && !rejected
        }.getOrDefault(false)
    }

    private companion object {
        const val UNKNOWN_SSID = "<unknown ssid>"
        const val SCAN_SETTLE_MS = 2_500L
        const val SCAN_CACHE_MS = 20_000L
        const val TARGET_SUGGESTION_PRIORITY = 1
        const val FALLBACK_SUGGESTION_PRIORITY = 0
    }
}

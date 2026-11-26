package via.internal.nativewifi

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.Uri
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import dev.mygo.*
import java.util.concurrent.CopyOnWriteArrayList

fun makeController(): Controller = AndroidController()

private class AndroidController : Controller {
    private val context: Context get() = Native.context
    private val wifiManager = context.applicationContext.getSystemService(WifiManager::class.java)
    private val connectivityManager = context.applicationContext.getSystemService(ConnectivityManager::class.java)
    private val notificationManager = context.applicationContext.getSystemService(NotificationManager::class.java)

    private var cachedNetworks: List<Network> = emptyList()
    private var lastScanElapsedMs: Long = 0L

    private val watchers = CopyOnWriteArrayList<(String) -> kotlin.Unit>()
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    @Suppress("DEPRECATION")
    override fun currentSSID(): String {
        connectivitySSID()?.let { return it }
        val mgr = wifiManager ?: return ""
        if (!mgr.isWifiEnabled) return ""
        val raw = runCatching { mgr.connectionInfo?.ssid }.getOrNull()
        return cleanSSID(raw)
    }

    private fun connectivitySSID(): String? = runCatching {
        val mgr = connectivityManager ?: return@runCatching null
        val active = mgr.activeNetwork?.let { mgr.getNetworkCapabilities(it) }
        ssidOf(active)?.let { return@runCatching it }
        mgr.allNetworks.firstNotNullOfOrNull { net ->
            ssidOf(mgr.getNetworkCapabilities(net))
        }
    }.getOrNull()

    private fun ssidOf(caps: NetworkCapabilities?): String? {
        if (caps == null) return null
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            caps.transportInfo as? WifiInfo
        } else {
            null
        } ?: return null
        val cleaned = cleanSSID(info.ssid)
        return cleaned.ifEmpty { null }
    }

    private fun cleanSSID(raw: String?): String {
        if (raw.isNullOrEmpty() || raw == UNKNOWN_SSID) return ""
        return raw.trim('"')
    }

    override fun locationStatus(): String {
        val fineGranted = context.checkSelfPermission(
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val nearbyGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.checkSelfPermission(
                Manifest.permission.NEARBY_WIFI_DEVICES
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        return if (fineGranted && nearbyGranted) "authorizedAlways" else "denied"
    }

    override fun requestLocation() {
        openLocationSettings()
    }

    override fun openLocationSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", context.packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        runCatching { context.startActivity(intent) }
    }

    @Suppress("DEPRECATION")
    @Synchronized
    override fun scan(): List<Network> {
        if (locationStatus() != "authorizedAlways") {
            return emptyList()
        }
        val mgr = wifiManager ?: return emptyList()
        val now = SystemClock.elapsedRealtime()
        if (now - lastScanElapsedMs < SCAN_CACHE_MS && cachedNetworks.isNotEmpty()) {
            return cachedNetworks
        }
        if (!mgr.isWifiEnabled) return cachedNetworks

        runCatching { mgr.startScan() }
        val fresh = runCatching {
            val best = LinkedHashMap<String, Network>()
            for (res in mgr.scanResults) {
                val ssid = res.SSID?.trim('"').orEmpty()
                if (ssid.isEmpty()) continue
                val secured = res.capabilities.contains("WPA", ignoreCase = true) ||
                    res.capabilities.contains("WEP", ignoreCase = true) ||
                    res.capabilities.contains("SAE", ignoreCase = true)
                val net = Network(ssid = ssid, rssi = res.level.toLong(), secured = secured)
                val prev = best[ssid]
                if (prev == null || net.rssi > prev.rssi) {
                    best[ssid] = net
                }
            }
            best.values.sortedWith(compareByDescending<Network> { it.rssi }.thenBy { it.ssid })
        }.getOrDefault(emptyList())

        if (fresh.isNotEmpty()) {
            cachedNetworks = fresh
            lastScanElapsedMs = now
        }
        return if (fresh.isNotEmpty()) fresh else cachedNetworks
    }

    override fun connect(ssid: String, password: String) {
        applySuggestions(ssid, password, "", "", ssid)
    }

    @Synchronized
    override fun watchSSIDChanges(onChange: (String) -> kotlin.Unit): AutoCloseable {
        watchers.add(onChange)
        ensureNetworkCallback()
        return NativeCloser {
            watchers.remove(onChange)
            if (watchers.isEmpty()) {
                clearNetworkCallback()
            }
        }
    }

    override fun watchPermissionChanges(onChange: (String) -> kotlin.Unit): AutoCloseable {
        return NativeCloser {}
    }

    private fun ensureNetworkCallback() {
        if (networkCallback != null) return
        val mgr = connectivityManager ?: return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: android.net.Network, caps: NetworkCapabilities) {
                val ssid = currentSSID()
                for (w in watchers) w(ssid)
            }

            override fun onLost(network: android.net.Network) {
                val ssid = currentSSID()
                for (w in watchers) w(ssid)
            }
        }
        val req = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()
        if (runCatching { mgr.registerNetworkCallback(req, cb) }.isSuccess) {
            networkCallback = cb
        }
    }

    private fun clearNetworkCallback() {
        val cb = networkCallback ?: return
        networkCallback = null
        runCatching { connectivityManager?.unregisterNetworkCallback(cb) }
    }

    override fun renderTrayIcon(badge: String, paused: Boolean, darkBar: Boolean): ByteArray {
        throw NativeUnsupportedException()
    }

    override fun applySuggestions(
        ssidP: String,
        pwdP: String,
        ssidB: String,
        pwdB: String,
        preferSSID: String,
    ) {
        val mgr = wifiManager ?: throw NativeUnsupportedException()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val existing = mgr.networkSuggestions
            if (!existing.isNullOrEmpty()) {
                mgr.removeNetworkSuggestions(existing)
            }
        }
        val pairs = listOf(ssidP.trim() to pwdP, ssidB.trim() to pwdB)
            .filter { it.first.isNotEmpty() }
            .distinctBy { it.first }
        if (pairs.isEmpty()) return

        val suggestions = ArrayList<WifiNetworkSuggestion>()
        for ((ssid, pwd) in pairs) {
            val b = WifiNetworkSuggestion.Builder().setSsid(ssid)
            if (pwd.isNotEmpty()) {
                if (pwd.length !in 8..63) {
                    throw NativeException("via", 2, "WPA passphrase must be 8..63 characters")
                }
                b.setWpa2Passphrase(pwd)
            } else {
                b.setIsEnhancedOpen(false)
            }
            b.setPriority(if (ssid == preferSSID.trim()) 1 else 0)
            suggestions.add(b.build())
        }
        val status = mgr.addNetworkSuggestions(suggestions)
        if (status != WifiManager.STATUS_NETWORK_SUGGESTIONS_SUCCESS) {
            throw NativeException("via", status, "addNetworkSuggestions failed: $status")
        }
    }

    override fun updateGuardNotification(running: Boolean, title: String, subtitle: String) {
        val nm = notificationManager ?: return
        if (!running) {
            nm.cancel(NOTIFICATION_ID)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                "Via Wi-Fi Guard",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                setShowBadge(false)
            }
            nm.createNotificationChannel(ch)
        }
        val n = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_notify_sync_noanim)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setOngoing(true)
            .build()
        nm.notify(NOTIFICATION_ID, n)
    }

    private companion object {
        const val UNKNOWN_SSID = "<unknown ssid>"
        const val SCAN_CACHE_MS = 20_000L
        const val CHANNEL_ID = "via_guard"
        const val NOTIFICATION_ID = 1001
    }
}

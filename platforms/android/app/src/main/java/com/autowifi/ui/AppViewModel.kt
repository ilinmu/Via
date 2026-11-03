package com.autowifi.ui

import android.Manifest
import android.app.Application
import android.content.pm.PackageManager
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.autowifi.L10n
import com.autowifi.data.SettingsStore
import com.autowifi.data.WifiRepository
import com.autowifi.service.MonitorStateBus
import com.autowifi.service.WifiMonitorService
import kotlinx.coroutines.launch

class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val store = SettingsStore(application)
    private val repository = WifiRepository(application)
    private val app: Application = application

    val monitor = MonitorStateBus.state

    var ssidP by mutableStateOf(store.ssidP)
    var ssidB by mutableStateOf(store.ssidB)
    var passwordP by mutableStateOf(store.passwordP)
    var passwordB by mutableStateOf(store.passwordB)
    var language by mutableStateOf(store.language)
        private set
    var intervalText by mutableStateOf(store.intervalSeconds.toString())
    var launchAtBoot by mutableStateOf(store.launchAtBoot)
        private set

    var currentSsid by mutableStateOf<String?>(null)
        private set

    var isScanning by mutableStateOf(false)
        private set
    var scanResults by mutableStateOf<List<String>>(emptyList())
        private set
    var scanMessage by mutableStateOf<String?>(null)
        private set

    var saveError by mutableStateOf<String?>(null)
        private set
    var savedOnce by mutableStateOf(false)
        private set

    // The wizard runs until it is finished or skipped once; afterwards it is
    // available from Settings ("Run setup again").
    var showWizard by mutableStateOf(!store.setupCompleted)
    var wizardStep by mutableStateOf(0)

    init {
        refreshCurrentSsid()
    }

    fun t(key: String): String = L10n.t(key, language)

    fun eventName(key: String): String = L10n.event(key, language)

    fun hasPermissions(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            app,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val nearby = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                app,
                Manifest.permission.NEARBY_WIFI_DEVICES,
            ) == PackageManager.PERMISSION_GRANTED
        return fine && nearby
    }

    fun refreshCurrentSsid() {
        currentSsid = if (hasPermissions()) {
            runCatching { repository.currentSsid() }.getOrNull()
        } else {
            null
        }
    }

    fun chooseLanguage(value: String) {
        language = value
        store.language = value
    }

    fun updateLaunchAtBoot(value: Boolean) {
        launchAtBoot = value
        store.launchAtBoot = value
    }

    fun onIntervalChanged(value: String) {
        intervalText = value.filter { it.isDigit() }.take(4)
    }

    fun commitInterval() {
        val value = intervalText.toIntOrNull()
            ?.coerceIn(SettingsStore.MIN_INTERVAL, SettingsStore.MAX_INTERVAL)
            ?: store.intervalSeconds
        intervalText = value.toString()
        if (store.intervalSeconds != value) {
            store.intervalSeconds = value
            restartIfRunning()
        }
    }

    fun useCurrentNetwork(primary: Boolean) {
        val ssid = currentSsid ?: return
        if (primary) ssidP = ssid else ssidB = ssid
    }

    fun validationError(): String? {
        val p = ssidP.trim()
        val b = ssidB.trim()
        return when {
            p.isEmpty() -> "missing_primary"
            b.isEmpty() -> "missing_backup"
            p.equals(b, ignoreCase = true) -> "same_network_error"
            passwordP.isNotEmpty() && passwordP.length !in 8..63 -> "invalid_password"
            passwordB.isNotEmpty() && passwordB.length !in 8..63 -> "invalid_password"
            else -> null
        }
    }

    fun save(): Boolean {
        val error = validationError()
        if (error != null) {
            saveError = error
            return false
        }
        return runCatching {
            val p = ssidP.trim()
            val b = ssidB.trim()
            store.ssidP = p
            store.ssidB = b
            store.passwordP = passwordP
            store.passwordB = passwordB
            val interval = intervalText.toIntOrNull()
                ?.coerceIn(SettingsStore.MIN_INTERVAL, SettingsStore.MAX_INTERVAL)
                ?: store.intervalSeconds
            store.intervalSeconds = interval
            intervalText = interval.toString()
            ssidP = p
            ssidB = b
            saveError = null
            savedOnce = true
            restartIfRunning()
            true
        }.getOrElse {
            saveError = "storage_error"
            false
        }
    }

    fun startMonitoring() {
        if (!hasPermissions()) {
            saveError = "permission_needed"
            return
        }
        if (!save()) return
        store.running = true
        WifiMonitorService.start(app)
    }

    fun stopMonitoring() {
        store.running = false
        WifiMonitorService.stop(app)
        MonitorStateBus.markStopped()
    }

    fun checkNow() {
        if (!store.running) return
        WifiMonitorService.refresh(app)
    }

    fun ensureService() {
        if (!store.running) return
        if (MonitorStateBus.state.value.running) {
            WifiMonitorService.refresh(app)
        } else {
            WifiMonitorService.start(app)
        }
    }

    fun scan() {
        if (!hasPermissions()) {
            scanMessage = "scan_needs_permission"
            return
        }
        if (isScanning) return
        viewModelScope.launch {
            isScanning = true
            val found = runCatching { repository.scan(force = true) }
                .getOrDefault(emptySet())
                .sorted()
            scanResults = found
            scanMessage = if (found.isEmpty()) "no_networks" else null
            isScanning = false
        }
    }

    fun goToStep(step: Int) {
        val target = step.coerceIn(0, 2)
        if (target == 2) {
            val error = validationError()
            if (error != null) {
                saveError = error
                return
            }
        }
        saveError = null
        wizardStep = target
    }

    fun finishWizard(start: Boolean) {
        if (!save()) return
        if (start) startMonitoring()
        store.setupCompleted = true
        showWizard = false
    }

    fun skipWizard() {
        store.setupCompleted = true
        showWizard = false
    }

    fun rerunWizard() {
        wizardStep = 0
        showWizard = true
    }

    private fun restartIfRunning() {
        if (!store.running) return
        // Restart in place: stopping the service first raced with the old
        // loop, which kept the previous Wi-Fi suggestions (and passwords)
        // registered after a password edit.
        WifiMonitorService.restart(app)
    }
}

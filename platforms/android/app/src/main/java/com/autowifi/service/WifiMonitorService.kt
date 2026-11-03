package com.autowifi.service

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.autowifi.L10n
import com.autowifi.MainActivity
import com.autowifi.R
import com.autowifi.data.NetworkCredential
import com.autowifi.data.SettingsStore
import com.autowifi.data.WifiRepository
import com.autowifi.policy.PolicyAction
import com.autowifi.policy.PolicyEngine
import com.autowifi.policy.PolicyResult
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Foreground service running the shared policy loop.
 *
 * Android cannot force a Wi-Fi connection, so an `associate` action is turned
 * into a best-effort refresh of the system's Wi-Fi suggestions. The result is
 * reported as success when the target SSID is already joined, otherwise as a
 * timeout, which lets the shared core apply its normal cooldown instead of
 * retrying every few seconds.
 */
class WifiMonitorService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private lateinit var settings: SettingsStore
    private lateinit var repository: WifiRepository

    private var loop: Job? = null
    private var engine: PolicyEngine? = null

    // Notification content only changes when the role or connection changes,
    // not on every policy tick.
    private var notificationKey: String? = null

    @Volatile
    private var refreshRequested = false

    private val logs = ArrayDeque<String>()

    override fun onCreate() {
        super.onCreate()
        settings = SettingsStore(this)
        repository = WifiRepository(this)
        createNotificationChannel()
        startForegroundCompat()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                settings.running = false
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_REFRESH -> refreshRequested = true
        }
        startLoop()
        return START_STICKY
    }

    override fun onDestroy() {
        loop?.cancel()
        loop = null
        scope.cancel()
        // runLoop releases the engine in its finally block.
        engine = null
        MonitorStateBus.markStopped()
        super.onDestroy()
    }

    private fun startLoop() {
        if (loop?.isActive == true) {
            refreshRequested = true
            return
        }
        loop = scope.launch { runLoop() }
    }

    private suspend fun runLoop() {
        val ssidP = settings.ssidP.trim()
        val ssidB = settings.ssidB.trim()
        if (ssidP.isEmpty() || ssidB.isEmpty()) {
            settings.running = false
            publishStopped()
            stopSelf()
            return
        }

        // Suggestions are registered up front; the system joins them on its own.
        repository.applySuggestions(
            listOf(
                NetworkCredential(ssidP, settings.passwordP),
                NetworkCredential(ssidB, settings.passwordB),
            )
        )

        val policy = runCatching { PolicyEngine(ssidP, ssidB) }.getOrElse {
            addLog("stopped")
            settings.running = false
            publishStopped()
            stopSelf()
            return
        }
        engine = policy
        var firstRun = true

        try {
            while (currentCoroutineContext().isActive) {
                val permission = if (hasPermissions()) {
                    PolicyEngine.PERMISSION_AUTHORIZED
                } else {
                    PolicyEngine.PERMISSION_DENIED
                }
                val current = repository.currentSsid()
                val now = System.currentTimeMillis()

                val result = if (firstRun) {
                    firstRun = false
                    policy.start(now, permission, current)
                } else {
                    policy.checkBegin(now, permission, current)
                }

                if (result != null) {
                    publish(result.snapshot)
                    handleActions(policy, result.actions, depth = 0)
                }

                val intervalMs = settings.intervalSeconds * 1000L
                val nextAt = System.currentTimeMillis() + intervalMs
                publish(policy.snapshot(), nextCheckAtMs = nextAt)
                waitForNextTick(intervalMs)
            }
        } finally {
            policy.close()
            if (engine === policy) engine = null
        }
    }

    private suspend fun waitForNextTick(intervalMs: Long) {
        var waited = 0L
        while (currentCoroutineContext().isActive && waited < intervalMs && !refreshRequested) {
            delay(TICK_STEP_MS)
            waited += TICK_STEP_MS
        }
        refreshRequested = false
    }

    private suspend fun handleActions(policy: PolicyEngine, actions: List<PolicyAction>, depth: Int) {
        for (action in actions) {
            if (!currentCoroutineContext().isActive) return
            when (action.kind) {
                "scan" -> {
                    val networks = repository.scan()
                    val now = System.currentTimeMillis()
                    val next = when (action.purpose) {
                        "priorityClassification" ->
                            policy.classificationResult(settings.ssidP in networks, now)
                        "backupCheck", "backupFailover", "backupRecovery" ->
                            policy.backupScanResult(settings.ssidB in networks, now)
                        else -> policy.scanResult(settings.ssidP in networks, now)
                    }
                    if (next != null) {
                        publish(next.snapshot)
                        if (depth < MAX_ACTION_DEPTH) {
                            handleActions(policy, next.actions, depth + 1)
                        }
                    }
                }
                "associate" -> {
                    val target = action.ssid ?: continue
                    val generation = policy.associationStarted(target, System.currentTimeMillis())
                    repository.applySuggestions(listOf(credentialFor(target)))
                    val joined = waitForSsid(target, ASSOCIATION_TIMEOUT_MS)
                    val outcome = if (joined) {
                        PolicyEngine.OUTCOME_SUCCESS
                    } else {
                        PolicyEngine.OUTCOME_TIMEOUT
                    }
                    val next = policy.associationResult(
                        target,
                        generation,
                        outcome,
                        System.currentTimeMillis(),
                    )
                    if (next != null) {
                        publish(next.snapshot)
                        if (depth < MAX_ACTION_DEPTH) {
                            handleActions(policy, next.actions, depth + 1)
                        }
                    }
                }
                "checkNow" -> {
                    if (depth < MAX_ACTION_DEPTH) {
                        val permission = if (hasPermissions()) {
                            PolicyEngine.PERMISSION_AUTHORIZED
                        } else {
                            PolicyEngine.PERMISSION_DENIED
                        }
                        val next = policy.checkBegin(
                            System.currentTimeMillis(),
                            permission,
                            repository.currentSsid(),
                        )
                        if (next != null) {
                            publish(next.snapshot)
                            handleActions(policy, next.actions, depth + 1)
                        }
                    }
                }
                "refreshStatus" -> publish(policy.snapshot())
                "waitForPermission" -> publish(policy.snapshot())
                "log" -> {
                    action.event?.let {
                        addLog(it)
                        publish(policy.snapshot())
                    }
                }
                "stop" -> {
                    settings.running = false
                    addLog("stopped")
                    publish(policy.snapshot()?.copy(running = false) ?: stoppedSnapshot(), nextCheckAtMs = 0L)
                    stopSelf()
                    return
                }
            }
        }
    }

    private fun credentialFor(ssid: String): NetworkCredential {
        val password = when (ssid) {
            settings.ssidP -> settings.passwordP
            settings.ssidB -> settings.passwordB
            else -> ""
        }
        return NetworkCredential(ssid, password)
    }

    private suspend fun waitForSsid(target: String, timeoutMs: Long): Boolean {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (currentCoroutineContext().isActive && SystemClock.elapsedRealtime() < deadline) {
            if (repository.currentSsid() == target) return true
            delay(1_000L)
        }
        return repository.currentSsid() == target
    }

    private fun hasPermissions(): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val nearby = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.NEARBY_WIFI_DEVICES,
            ) == PackageManager.PERMISSION_GRANTED
        return fine && nearby
    }

    private fun addLog(event: String) {
        logs.addFirst(event)
        while (logs.size > MAX_LOGS) logs.removeLast()
    }

    private fun publish(snapshot: com.autowifi.policy.PolicySnapshot?, nextCheckAtMs: Long = 0L) {
        val current = snapshot ?: stoppedSnapshot()
        val state = MonitorState(
            running = current.running,
            currentSsid = current.currentSsid ?: repository.currentSsid(),
            role = current.role,
            permission = current.permission,
            lastEvent = logs.firstOrNull(),
            nextCheckAtMs = nextCheckAtMs,
            logs = logs.toList(),
            updatedAtMs = System.currentTimeMillis(),
        )
        MonitorStateBus.publish(state)
        updateNotification(state)
    }

    private fun updateNotification(state: MonitorState) {
        val key = "${settings.language}|${state.running}|${state.role}|${state.currentSsid}"
        if (key == notificationKey) return
        notificationKey = key

        val manager = getSystemService(NotificationManager::class.java) ?: return
        runCatching { manager.notify(NOTIFICATION_ID, buildNotification(state)) }
    }

    private fun publishStopped() {
        MonitorStateBus.markStopped()
    }

    private fun stoppedSnapshot() = com.autowifi.policy.PolicySnapshot(
        running = false,
        role = "none",
        permission = "unknown",
        currentSsid = repository.currentSsid(),
        isAssociating = false,
        cooldownUntilMs = null,
        cooldownTarget = null,
    )

    private fun createNotificationChannel() {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.notification_channel_name),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.notification_channel_description)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun startForegroundCompat() {
        val initial = MonitorState(
            running = true,
            currentSsid = runCatching { repository.currentSsid() }.getOrNull(),
        )
        notificationKey =
            "${settings.language}|${initial.running}|${initial.role}|${initial.currentSsid}"

        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(initial),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
        )
    }

    /**
     * The notification is the Android counterpart of the macOS menu bar icon:
     * its small icon tracks running/paused and the connected role, and the
     * text names the current network.
     */
    private fun buildNotification(state: MonitorState): Notification {
        val language = settings.language
        val text = when {
            !state.running -> L10n.t("status_paused", language)
            state.currentSsid.isNullOrBlank() -> L10n.t("status_not_connected", language)
            else -> "${state.currentSsid} · ${L10n.role(state.role, language)}"
        }

        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // The platform builder is used because NotificationCompat has no
        // Icon overload for the small icon; minSdk 29 covers this API.
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setSmallIcon(StatusIconRenderer.smallIcon(this, state.running, state.role))
            .setLargeIcon(StatusIconRenderer.largeIcon(this, state.running, state.role))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openIntent)
            .setPriority(Notification.PRIORITY_LOW)
            .build()
    }

    companion object {
        const val ACTION_START = "com.autowifi.action.START"
        const val ACTION_STOP = "com.autowifi.action.STOP"
        const val ACTION_REFRESH = "com.autowifi.action.REFRESH"

        private const val CHANNEL_ID = "autowifi_monitor"
        private const val NOTIFICATION_ID = 41
        private const val MAX_ACTION_DEPTH = 8
        private const val MAX_LOGS = 50
        private const val TICK_STEP_MS = 500L
        private const val ASSOCIATION_TIMEOUT_MS = 10_000L

        fun start(context: Context) {
            val intent = Intent(context, WifiMonitorService::class.java)
                .setAction(ACTION_START)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, WifiMonitorService::class.java))
        }

        fun refresh(context: Context) {
            val intent = Intent(context, WifiMonitorService::class.java)
                .setAction(ACTION_REFRESH)
            ContextCompat.startForegroundService(context, intent)
        }
    }
}

package io.github.ilinmu.via.policy

import org.json.JSONObject

/** One action emitted by the shared policy engine. */
data class PolicyAction(
    val kind: String,
    val purpose: String? = null,
    val ssid: String? = null,
    val role: String? = null,
    val reason: String? = null,
    val event: String? = null,
)

data class PolicySnapshot(
    val running: Boolean,
    val role: String,
    val permission: String,
    val currentSsid: String?,
    val isAssociating: Boolean,
    val cooldownUntilMs: Long?,
    val cooldownTarget: String?,
) {
    companion object {
        fun fromJson(obj: JSONObject) = PolicySnapshot(
            running = obj.optBoolean("running"),
            role = obj.optString("role", "none"),
            permission = obj.optString("permission", "unknown"),
            currentSsid = obj.optNullableString("currentSsid"),
            isAssociating = obj.optBoolean("isAssociating"),
            cooldownUntilMs = if (obj.isNull("cooldownUntilMs")) null else obj.optLong("cooldownUntilMs"),
            cooldownTarget = obj.optNullableString("cooldownTarget"),
        )
    }
}

data class PolicyResult(
    val actions: List<PolicyAction>,
    val snapshot: PolicySnapshot,
)

/**
 * Kotlin wrapper around the shared Rust policy engine (libvia_jni.so).
 *
 * The engine is not thread safe; the monitor service keeps one instance on its
 * own coroutine. All strings leaving the bridge are JSON.
 */
class PolicyEngine(ssidP: String, ssidB: String) : AutoCloseable {
    private var handle: Long = nativeNew(ssidP, ssidB)

    fun setConfig(ssidP: String, ssidB: String) {
        if (handle != 0L) nativeSetConfig(handle, ssidP, ssidB)
    }

    fun start(nowMs: Long, permission: Int, currentSsid: String?): PolicyResult? =
        parse(nativeStart(handle, nowMs, permission, currentSsid.orEmpty()))

    fun stop(): PolicyResult? = parse(nativeStop(handle))

    fun checkBegin(nowMs: Long, permission: Int, currentSsid: String?): PolicyResult? =
        parse(nativeCheckBegin(handle, nowMs, permission, currentSsid.orEmpty()))

    fun scanResult(found: Boolean, nowMs: Long): PolicyResult? =
        parse(nativeScanResult(handle, found, nowMs))

    fun classificationResult(priorityVisible: Boolean, nowMs: Long): PolicyResult? =
        parse(nativeClassificationResult(handle, priorityVisible, nowMs))

    fun backupScanResult(found: Boolean, nowMs: Long): PolicyResult? =
        parse(nativeBackupScanResult(handle, found, nowMs))

    fun associationStarted(ssid: String, nowMs: Long): Long =
        nativeAssociationStarted(handle, ssid, nowMs)

    fun associationResult(
        ssid: String,
        generation: Long,
        outcome: Int,
        nowMs: Long,
    ): PolicyResult? = parse(nativeAssociationResult(handle, ssid, generation, outcome, nowMs))

    fun lateAssociationResult(
        ssid: String,
        generation: Long,
        succeeded: Boolean,
        nowMs: Long,
    ): PolicyResult? = parse(nativeLateAssociationResult(handle, ssid, generation, succeeded, nowMs))

    fun observedChange(previousSsid: String?, newSsid: String?, nowMs: Long): PolicyResult? =
        parse(nativeObservedChange(handle, previousSsid.orEmpty(), newSsid.orEmpty(), nowMs))

    fun snapshot(): PolicySnapshot? {
        if (handle == 0L) return null
        return runCatching { PolicySnapshot.fromJson(JSONObject(nativeSnapshot(handle))) }.getOrNull()
    }

    fun roleFor(ssid: String): Int = nativeRole(handle, ssid)

    fun cooldownActive(ssid: String, nowMs: Long): Boolean =
        nativeCooldownActive(handle, ssid, nowMs)

    fun isRecentProgrammaticBackup(nowMs: Long): Boolean =
        nativeIsRecentProgrammaticBackup(handle, nowMs)

    fun isCurrentGeneration(generation: Long): Boolean =
        nativeIsCurrentGeneration(handle, generation)

    override fun close() {
        if (handle != 0L) {
            nativeFree(handle)
            handle = 0L
        }
    }

    private fun parse(raw: String?) = parsePolicyResult(raw)

    private external fun nativeNew(ssidP: String, ssidB: String): Long

    private external fun nativeFree(handle: Long)

    private external fun nativeSetConfig(handle: Long, ssidP: String, ssidB: String)

    private external fun nativeStart(
        handle: Long,
        nowMs: Long,
        permission: Int,
        currentSsid: String,
    ): String?

    private external fun nativeStop(handle: Long): String?

    private external fun nativeCheckBegin(
        handle: Long,
        nowMs: Long,
        permission: Int,
        currentSsid: String,
    ): String?

    private external fun nativeScanResult(handle: Long, found: Boolean, nowMs: Long): String?

    private external fun nativeClassificationResult(
        handle: Long,
        priorityVisible: Boolean,
        nowMs: Long,
    ): String?

    private external fun nativeBackupScanResult(handle: Long, found: Boolean, nowMs: Long): String?

    private external fun nativeAssociationStarted(handle: Long, ssid: String, nowMs: Long): Long

    private external fun nativeAssociationResult(
        handle: Long,
        ssid: String,
        generation: Long,
        outcome: Int,
        nowMs: Long,
    ): String?

    private external fun nativeLateAssociationResult(
        handle: Long,
        ssid: String,
        generation: Long,
        succeeded: Boolean,
        nowMs: Long,
    ): String?

    private external fun nativeObservedChange(
        handle: Long,
        previousSsid: String,
        newSsid: String,
        nowMs: Long,
    ): String?

    private external fun nativeSnapshot(handle: Long): String

    private external fun nativeRole(handle: Long, ssid: String): Int

    private external fun nativeCooldownActive(handle: Long, ssid: String, nowMs: Long): Boolean

    private external fun nativeIsRecentProgrammaticBackup(handle: Long, nowMs: Long): Boolean

    private external fun nativeIsCurrentGeneration(handle: Long, generation: Long): Boolean

    companion object {
        const val PERMISSION_UNKNOWN = 0
        const val PERMISSION_AUTHORIZED = 1
        const val PERMISSION_DENIED = 2

        const val OUTCOME_SUCCESS = 0
        const val OUTCOME_TIMEOUT = 1
        const val OUTCOME_FAILURE = 2

        init {
            System.loadLibrary("via_jni")
        }
    }
}

internal fun JSONObject.optNullableString(name: String): String? {
    if (!has(name) || isNull(name)) return null
    val value = optString(name, "")
    return value.ifEmpty { null }
}

/**
 * Parses the JSON emitted by the JNI bridge. Kept outside [PolicyEngine] so
 * JVM unit tests can exercise it without loading `libvia_jni.so`.
 */
internal fun parsePolicyResult(raw: String?): PolicyResult? {
    if (raw.isNullOrEmpty()) return null
    return runCatching {
        val root = JSONObject(raw)
        val array = root.optJSONArray("actions")
        val actions = buildList {
            if (array != null) {
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    add(
                        PolicyAction(
                            kind = item.optString("kind"),
                            purpose = item.optNullableString("purpose"),
                            ssid = item.optNullableString("ssid"),
                            role = item.optNullableString("role"),
                            reason = item.optNullableString("reason"),
                            event = item.optNullableString("event"),
                        )
                    )
                }
            }
        }
        PolicyResult(
            actions = actions,
            snapshot = PolicySnapshot.fromJson(root.getJSONObject("snapshot")),
        )
    }.getOrNull()
}

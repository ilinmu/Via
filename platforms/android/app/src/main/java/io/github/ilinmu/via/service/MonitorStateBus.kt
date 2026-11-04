package io.github.ilinmu.via.service

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class MonitorState(
    val running: Boolean = false,
    val currentSsid: String? = null,
    val role: String = "none",
    val permission: String = "unknown",
    val lastEvent: String? = null,
    val nextCheckAtMs: Long = 0L,
    val logs: List<String> = emptyList(),
    val updatedAtMs: Long = 0L,
)

/** Latest monitor state, shared by the foreground service and the UI. */
object MonitorStateBus {
    private val _state = MutableStateFlow(MonitorState())
    val state: StateFlow<MonitorState> = _state.asStateFlow()

    fun publish(value: MonitorState) {
        _state.value = value
    }

    fun markStopped() {
        _state.value = _state.value.copy(
            running = false,
            nextCheckAtMs = 0L,
            updatedAtMs = System.currentTimeMillis(),
        )
    }
}

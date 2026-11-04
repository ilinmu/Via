package io.github.ilinmu.via.service

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MonitorStateBusTest {
    @Test
    fun publishReplacesState() {
        val state = MonitorState(
            running = true,
            currentSsid = "NetworkP",
            role = "priority",
            permission = "authorized",
            lastEvent = "priorityConnected",
            nextCheckAtMs = 1_700_000_000_000,
            logs = listOf("priorityConnected"),
            updatedAtMs = 42,
        )

        MonitorStateBus.publish(state)

        assertEquals(state, MonitorStateBus.state.value)
    }

    @Test
    fun markStoppedKeepsConnectionAndClearsCountdown() {
        MonitorStateBus.publish(
            MonitorState(
                running = true,
                currentSsid = "NetworkB",
                lastEvent = "automaticFailover",
                nextCheckAtMs = 1_700_000_000_000,
            )
        )

        MonitorStateBus.markStopped()

        val state = MonitorStateBus.state.value
        assertFalse(state.running)
        assertEquals(0L, state.nextCheckAtMs)
        assertEquals("NetworkB", state.currentSsid)
        assertEquals("automaticFailover", state.lastEvent)
        assertTrue(state.updatedAtMs > 0L)
    }
}

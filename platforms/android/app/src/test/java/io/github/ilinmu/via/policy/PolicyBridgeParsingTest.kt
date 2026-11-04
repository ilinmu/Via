package io.github.ilinmu.via.policy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PolicyBridgeParsingTest {
    @Test
    fun parsesActionsAndSnapshot() {
        val raw = """
            {
              "actions": [
                {"kind": "scan", "purpose": "priorityCheck"},
                {"kind": "associate", "ssid": "NetworkB", "role": "backup"}
              ],
              "snapshot": {
                "running": true,
                "role": "priority",
                "permission": "authorized",
                "currentSsid": "NetworkP",
                "isAssociating": false,
                "cooldownUntilMs": 1700000000000,
                "cooldownTarget": "NetworkB"
              }
            }
        """.trimIndent()

        val result = parsePolicyResult(raw)!!

        assertEquals(2, result.actions.size)
        assertEquals("scan", result.actions[0].kind)
        assertEquals("priorityCheck", result.actions[0].purpose)
        assertNull(result.actions[0].ssid)
        assertEquals("associate", result.actions[1].kind)
        assertEquals("NetworkB", result.actions[1].ssid)
        assertEquals("backup", result.actions[1].role)

        val snapshot = result.snapshot
        assertTrue(snapshot.running)
        assertEquals("priority", snapshot.role)
        assertEquals("authorized", snapshot.permission)
        assertEquals("NetworkP", snapshot.currentSsid)
        assertEquals(1_700_000_000_000L, snapshot.cooldownUntilMs)
        assertEquals("NetworkB", snapshot.cooldownTarget)
    }

    @Test
    fun parsesEmptyActionListAndNullCooldown() {
        val raw = """
            {
              "actions": [],
              "snapshot": {
                "running": false,
                "role": "none",
                "permission": "unknown",
                "currentSsid": null,
                "isAssociating": false,
                "cooldownUntilMs": null,
                "cooldownTarget": null
              }
            }
        """.trimIndent()

        val result = parsePolicyResult(raw)!!

        assertTrue(result.actions.isEmpty())
        assertNull(result.snapshot.currentSsid)
        assertNull(result.snapshot.cooldownUntilMs)
        assertNull(result.snapshot.cooldownTarget)
    }

    @Test
    fun parsesLogEventReason() {
        val raw = """
            {
              "actions": [{"kind": "log", "event": "started", "reason": "started"}],
              "snapshot": {"running": true, "role": "none", "permission": "authorized"}
            }
        """.trimIndent()

        val result = parsePolicyResult(raw)!!

        assertEquals("log", result.actions[0].kind)
        assertEquals("started", result.actions[0].event)
        assertEquals("started", result.actions[0].reason)
    }

    @Test
    fun rejectsMissingOrMalformedPayloads() {
        assertNull(parsePolicyResult(null))
        assertNull(parsePolicyResult(""))
        assertNull(parsePolicyResult("not json"))
        assertNull(parsePolicyResult("""{"actions": []}"""))
    }
}

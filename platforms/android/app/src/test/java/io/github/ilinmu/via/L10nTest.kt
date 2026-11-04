package io.github.ilinmu.via

import org.junit.Assert.assertEquals
import org.junit.Test

class L10nTest {
    @Test
    fun knownKeysAreLocalized() {
        assertEquals("状态", L10n.t("tab_status", "zh"))
        assertEquals("Status", L10n.t("tab_status", "en"))
        assertEquals("优先网络", L10n.t("role_priority", "zh"))
        assertEquals("Priority", L10n.t("role_priority", "en"))
    }

    @Test
    fun unknownKeyFallsBackToKey() {
        assertEquals("missing_key", L10n.t("missing_key", "zh"))
        assertEquals("missing_key", L10n.t("missing_key", "en"))
    }

    @Test
    fun unknownLanguageFallsBackToChinese() {
        assertEquals("状态", L10n.t("tab_status", "fr"))
    }

    @Test
    fun eventsUseEventPrefix() {
        assertEquals("已开始监控", L10n.event("started", "zh"))
        assertEquals("Monitoring started", L10n.event("started", "en"))
        assertEquals("event_unknown", L10n.event("unknown", "zh"))
    }

    @Test
    fun rolesMapKnownValues() {
        assertEquals("优先网络", L10n.role("priority", "zh"))
        assertEquals("Backup", L10n.role("backup", "en"))
        assertEquals("未连接", L10n.role("none", "zh"))
        assertEquals("未连接", L10n.role("something-else", "zh"))
    }
}

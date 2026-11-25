package io.github.ilinmu.via

import org.junit.Assert.assertEquals
import org.junit.Test

class L10nTest {
    @Test
    fun knownKeysAreLocalized() {
        assertEquals("状态", L10n.t("tab_status", "zh"))
        assertEquals("Status", L10n.t("tab_status", "en"))
        assertEquals("首选网络", L10n.t("role_priority", "zh"))
        assertEquals("Preferred network", L10n.t("role_priority", "en"))
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
        assertEquals("已开启自动切换", L10n.event("started", "zh"))
        assertEquals("Auto-switch turned on", L10n.event("started", "en"))
        assertEquals("event_unknown", L10n.event("unknown", "zh"))
    }

    @Test
    fun durationsUseReadableUnits() {
        assertEquals("45 秒", L10n.duration(45, "zh"))
        assertEquals("1 分 30 秒", L10n.duration(90, "zh"))
        assertEquals("1 hr 30 min", L10n.duration(5400, "en"))
    }

    @Test
    fun rolesMapKnownValues() {
        assertEquals("首选网络", L10n.role("priority", "zh"))
        assertEquals("Backup network", L10n.role("backup", "en"))
        assertEquals("未连接", L10n.role("none", "zh"))
        assertEquals("未连接", L10n.role("something-else", "zh"))
    }
}

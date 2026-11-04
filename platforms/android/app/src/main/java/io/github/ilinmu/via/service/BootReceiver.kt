package io.github.ilinmu.via.service

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import io.github.ilinmu.via.data.SettingsStore

/** Restarts monitoring after a reboot when the user asked for it. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val settings = SettingsStore(context)
        if (settings.running && settings.launchAtBoot) {
            WifiMonitorService.start(context)
        }
    }
}

package io.github.ilinmu.via

import java.util.Locale

/** Minimal in-app localization, matching the macOS and Windows shells. */
object L10n {
    private val strings: Map<String, Pair<String, String>> = mapOf(
        "app_name" to ("Via" to "Via"),
        "tab_status" to ("状态" to "Status"),
        "tab_networks" to ("网络" to "Networks"),
        "tab_settings" to ("设置" to "Settings"),

        "status_title" to ("当前连接" to "Current connection"),
        "status_not_connected" to ("未连接 Wi-Fi" to "Wi-Fi not connected"),
        "status_running" to ("自动切换已开启" to "Auto-switch is on"),
        "status_paused" to ("自动切换已关闭" to "Auto-switch is off"),
        "status_waiting_permission" to ("等待定位权限" to "Waiting for location access"),
        "status_next_check" to ("下次检查" to "Next check"),
        "next_check_at_format" to ("%s：%s" to "%s: %s"),
        "status_checking_now" to ("正在检查…" to "Checking…"),
        "status_check_now" to ("立即检查" to "Check now"),
        "status_refresh" to ("刷新" to "Refresh"),
        "status_scan" to ("扫描网络" to "Scan for networks"),
        "status_scanning" to ("正在扫描…" to "Scanning…"),
        "status_no_networks" to ("没有找到网络" to "No networks found"),
        "status_permission_banner" to (
            "需要定位权限，才能读取当前 Wi-Fi 名称并扫描附近网络。" to
                "Location access is needed to read the current Wi-Fi name and scan nearby networks."
        ),
        "status_android_note" to (
            "Android 可能调整最终连接的网络。" to
                "Android may adjust the final network connection."
        ),
        "status_setup_hint" to (
            "先设置首选网络和备用网络，才能开启自动切换。" to
                "Set a preferred and a backup network to turn on auto-switch."
        ),
        "auto_switch" to ("自动切换" to "Auto-switch"),
        "auto_switch_hint" to (
            "首选网络不可用时，自动连接备用网络。" to
                "Connects to your backup network when the preferred one is unavailable."
        ),
        "role_priority" to ("首选网络" to "Preferred network"),
        "role_backup" to ("备用网络" to "Backup network"),
        "role_other" to ("其他网络" to "Other network"),
        "role_none" to ("未连接" to "Not connected"),

        "grant_permission" to ("允许访问" to "Allow access"),
        "open_settings" to ("打开系统设置" to "Open System Settings"),
        "permission_granted" to ("已授权" to "Allowed"),
        "permission_denied" to ("未授权" to "Not allowed"),
        "permission_needed" to ("需要定位权限才能开启自动切换" to "Location access is needed to turn on auto-switch"),
        "permissions_title" to ("定位权限" to "Location access"),

        "networks_title" to ("网络" to "Networks"),
        "networks_hint" to (
            "首选网络优先连接；不可用时改用备用网络。密码可留空。" to
                "Stay on the preferred network, and use the backup when it is unavailable. Passwords are optional."
        ),
        "priority_network" to ("首选网络" to "Preferred network"),
        "backup_network" to ("备用网络" to "Backup network"),
        "ssid_label" to ("网络名称" to "Network name"),
        "password" to ("密码" to "Password"),
        "show_password" to ("显示密码" to "Show password"),
        "hide_password" to ("隐藏密码" to "Hide password"),
        "use_current" to ("使用当前网络" to "Use current network"),
        "scan_networks" to ("扫描网络" to "Scan for networks"),
        "scanning" to ("正在扫描…" to "Scanning…"),
        "no_networks" to ("没有找到网络。请稍后再试。" to "No networks found. Try again."),
        "scan_needs_permission" to ("需要定位权限才能扫描。" to "Location access is needed to scan."),
        "scan_first" to (
            "扫描附近网络后，可在这里选择。" to
                "Scan for nearby networks, then choose one here."
        ),
        "save_changes" to ("保存更改" to "Save changes"),
        "saved" to ("已保存" to "Saved"),
        "unsaved" to ("有未保存的更改" to "Unsaved changes"),
        "missing_primary" to ("请输入首选网络的名称。" to "Enter a name for the preferred network."),
        "missing_backup" to ("请输入备用网络的名称。" to "Enter a name for the backup network."),
        "same_network_error" to (
            "首选网络和备用网络不能相同。" to "The preferred and backup networks must be different."
        ),
        // Android only accepts WPA2 passphrases of 8-63 characters in a
        // network suggestion; shorter ones are silently unusable.
        "invalid_password" to (
            "密码需为 8–63 个字符，或留空表示开放网络。" to
                "A password must be 8–63 characters, or blank for an open network."
        ),
        "storage_error" to ("无法保存到加密存储" to "Unable to save to encrypted storage"),
        "service_start_failed" to (
            "无法启动后台服务，请在状态页重新开启。" to
                "Couldn't start the background service. Turn it on again from Status."
        ),
        "networks_found" to ("发现 %d 个网络" to "%d networks found"),
        "networks_found_one" to ("发现 1 个网络" to "1 network found"),

        "settings_title" to ("设置" to "Settings"),
        "general" to ("通用" to "General"),
        "language" to ("语言" to "Language"),
        "check_frequency" to ("检查间隔" to "Check interval"),
        "seconds_unit" to ("秒" to "sec"),
        "interval_hint" to ("5 秒到 1 小时。超出范围会自动调整。" to "From 5 seconds to 1 hour. Out-of-range values are adjusted."),
        "interval_summary_format" to ("每 %s 检查一次" to "Checks every %s"),
        "start_on_boot" to ("开机时启动" to "Start at boot"),
        "android_limits" to ("Android 的系统限制" to "Android limitations"),
        "android_limits_body" to (
            "Android 不允许应用静默切换网络。Via 会向系统登记首选和备用网络，由系统在合适的时机切换；后台扫描频率也由系统控制。" to
                "Android doesn't let apps switch networks silently. Via registers your preferred and backup networks with the system, which switches when appropriate; background scans are also rate-limited."
        ),
        "about" to ("关于" to "About"),
        "version" to ("版本" to "Version"),
        "privacy" to (
            "只在本机运行。Wi-Fi 名称和密码不会上传，密码保存在加密存储中。" to
                "Runs on this device only. Wi-Fi names and passwords are never uploaded; passwords use encrypted storage."
        ),
        "stop_monitoring" to ("关闭自动切换" to "Turn off auto-switch"),
        "rerun_setup" to ("重新设置" to "Set up again"),

        "wizard_step" to ("第 %d 步，共 3 步" to "Step %d of 3"),
        "wizard_permission_title" to ("允许使用定位服务" to "Allow location access"),
        "wizard_permission_body" to (
            "Android 用定位权限读取当前 Wi-Fi 名称并扫描附近网络。信息只在本机使用。" to
                "Android uses location access to read the current Wi-Fi name and scan nearby networks. Nothing is uploaded."
        ),
        "wizard_permission_settings_hint" to (
            "没有看到提示？可在系统设置中允许。" to "No prompt? Allow access in System Settings."
        ),
        "wizard_networks_title" to ("设置常用网络" to "Set up your networks"),
        "wizard_networks_body" to (
            "首选网络优先连接；不可用时，自动改用备用网络。" to
                "Via stays on your preferred network and uses the backup when it drops."
        ),
        "wizard_finish_title" to ("准备就绪" to "Ready to go"),
        "wizard_finish_body" to (
            "开启后，Via 会在后台保持首选网络。" to
                "Turn on auto-switch and Via will keep you on your preferred network."
        ),
        "wizard_back" to ("上一步" to "Back"),
        "wizard_next" to ("下一步" to "Next"),
        "wizard_start" to ("保存并开启" to "Save and turn on"),
        "wizard_save_only" to ("仅保存" to "Save only"),
        "wizard_skip" to ("跳过" to "Skip"),
        "wizard_continue" to ("继续" to "Continue"),
        "not_set" to ("未设置" to "Not set"),
        "open_networks" to ("前往网络" to "Go to networks"),

        "event_started" to ("已开启自动切换" to "Auto-switch turned on"),
        "event_stopped" to ("已关闭自动切换" to "Auto-switch turned off"),
        "event_priorityConnected" to ("已连接首选网络" to "Connected to the preferred network"),
        "event_priorityVisibleWaiting" to ("首选网络可用，等待系统切换" to "Preferred network available; waiting for the system"),
        "event_networkDisconnectedWaiting" to ("网络已断开，正在等待" to "Network disconnected; waiting"),
        "event_automaticFailover" to ("已自动切换到备用网络" to "Switched to the backup automatically"),
        "event_priorityLostConnectingBackup" to ("首选网络不可用，正在连接备用网络" to "Preferred network unavailable; connecting the backup"),
        "event_backupConnectedPNotFound" to ("已连接备用网络，未发现首选网络" to "On the backup; preferred network not found"),
        "event_neitherFound" to ("没有找到首选或备用网络" to "Neither network was found"),
        "event_backupNotFound" to ("没有找到备用网络" to "Backup network not found"),
        "event_backupNotFoundWaiting" to ("没有找到备用网络，继续等待" to "Backup not found; waiting"),
        "event_previousBackupReconnect" to ("重新连接之前的备用网络" to "Reconnecting the previous backup network"),
        "event_systemJoinedBackup" to ("系统已连接备用网络" to "The system joined the backup network"),
        "event_treatingAsFallback" to ("作为备用网络处理" to "Treating it as a backup network"),
        "event_cooldownSkipped" to ("冷却中，暂时跳过" to "Cooling down; skipping this round"),
        "event_associationSuccess" to ("连接成功" to "Connected"),
        "event_associationTimeout" to (
            "连接超时，请检查密码和信号" to "Connection timed out — check the password and signal"
        ),
        "event_associationFailure" to ("连接失败" to "Connection failed"),
        "event_associationLateSuccess" to ("稍后已连接" to "Connected shortly after"),
        "event_associationLateFailure" to ("稍后连接失败" to "Connection failed shortly after"),
        "event_permissionRequired" to ("需要定位权限" to "Location access needed"),
        "event_priorityVisibleUnknown" to (
            "无法确认首选网络状态，保持当前连接" to
                "Could not verify the preferred network; keeping the current connection"
        ),
        "duration_seconds" to ("%d 秒" to "%d sec"),
        "duration_minutes" to ("%d 分钟" to "%d min"),
        "duration_minutes_seconds" to ("%d 分 %d 秒" to "%d min %d sec"),
        "duration_hours" to ("%d 小时" to "%d hr"),
        "duration_hours_minutes" to ("%d 小时 %d 分" to "%d hr %d min"),
        "notification_network" to ("%s（%s）" to "%s (%s)"),
    )

    fun t(key: String, language: String): String {
        val value = strings[key] ?: return key
        return if (language == "en") value.second else value.first
    }

    fun tf(key: String, language: String, vararg args: Any): String =
        String.format(Locale.getDefault(), t(key, language), *args)

    /** Localized label for a policy log event such as `priorityConnected`. */
    fun event(key: String, language: String): String = t("event_$key", language)

    fun role(role: String, language: String): String = when (role) {
        "priority" -> t("role_priority", language)
        "backup" -> t("role_backup", language)
        "other" -> t("role_other", language)
        else -> t("role_none", language)
    }

    /** Human-readable duration for the check interval. */
    fun duration(seconds: Int, language: String): String {
        val total = seconds.coerceAtLeast(0)
        val hours = total / 3600
        val minutes = (total % 3600) / 60
        val rest = total % 60
        return when {
            hours > 0 && minutes > 0 ->
                tf("duration_hours_minutes", language, hours, minutes)
            hours > 0 -> tf("duration_hours", language, hours)
            minutes > 0 && rest > 0 ->
                tf("duration_minutes_seconds", language, minutes, rest)
            minutes > 0 -> tf("duration_minutes", language, minutes)
            else -> tf("duration_seconds", language, rest)
        }
    }
}

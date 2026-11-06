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
        "status_not_connected" to ("未连接" to "Not connected"),
        "status_running" to ("自动切换已开启" to "Auto-switch is on"),
        "status_paused" to ("自动切换已关闭" to "Auto-switch is off"),
        "status_waiting_permission" to ("等待权限" to "Waiting for permission"),
        "status_next_check" to ("下次检查" to "Next check"),
        "status_checking_now" to ("正在检查" to "Checking now"),
        "status_check_now" to ("立即检查" to "Check now"),
        "status_refresh" to ("刷新状态" to "Refresh status"),
        "status_scan" to ("扫描网络" to "Scan networks"),
        "status_scanning" to ("正在扫描…" to "Scanning…"),
        "status_no_networks" to ("未发现网络" to "No networks found"),
        "status_permission_banner" to (
            "Android 需要定位权限才能读取当前 Wi-Fi 名称和扫描附近网络。" to
                "Android needs location permission to read the current Wi-Fi name and scan nearby networks."
        ),
        "status_android_note" to (
            "Android 由系统决定最终连接；应用注册 Wi-Fi 建议，不能静默强制切换。" to
                "Android decides the final connection; the app registers Wi-Fi suggestions and cannot force a switch."
        ),
        "auto_switch" to ("自动切换" to "Auto-switch"),
        "auto_switch_hint" to (
            "优先连接 P；P 不可用时使用 B。监控由前台服务运行。" to
                "Prefers P, then falls back to B. Monitoring runs in a foreground service."
        ),
        "role_priority" to ("优先网络" to "Priority"),
        "role_backup" to ("备用网络" to "Backup"),
        "role_other" to ("其他网络" to "Other"),
        "role_none" to ("未连接" to "Not connected"),

        "grant_permission" to ("授予权限" to "Grant permission"),
        "open_settings" to ("打开系统设置" to "Open settings"),
        "permission_granted" to ("已授权" to "Granted"),
        "permission_denied" to ("未授权" to "Not granted"),
        "permission_needed" to ("需要定位权限才能开始" to "Location permission is required to start"),
        "permissions_title" to ("权限" to "Permissions"),

        "networks_title" to ("网络" to "Networks"),
        "networks_hint" to (
            "P 是优先网络，B 是备用网络。密码留空表示开放网络。" to
                "P is the priority network and B the backup. Leave the password blank for open networks."
        ),
        "priority_network" to ("优先网络 (P)" to "Priority network (P)"),
        "backup_network" to ("备用网络 (B)" to "Backup network (B)"),
        "ssid_label" to ("网络名称 (SSID)" to "Network name (SSID)"),
        "password" to ("密码" to "Password"),
        "show_password" to ("显示密码" to "Show password"),
        "hide_password" to ("隐藏密码" to "Hide password"),
        "use_current" to ("使用当前网络" to "Use current network"),
        "scan_networks" to ("扫描网络" to "Scan networks"),
        "scanning" to ("正在扫描…" to "Scanning…"),
        "no_networks" to ("未发现网络，请检查 Wi-Fi 状态或稍后重试" to "No networks found; check Wi-Fi or try again"),
        "scan_needs_permission" to ("需要定位权限才能扫描" to "Location permission is required to scan"),
        "scan_first" to (
            "先扫描附近网络，再从这里选择" to
                "Scan for nearby networks, then choose one here"
        ),
        "save_changes" to ("保存更改" to "Save changes"),
        "saved" to ("已保存" to "Saved"),
        "unsaved" to ("有未保存的更改" to "Unsaved changes"),
        "missing_primary" to ("请填写优先网络" to "Enter the priority network"),
        "missing_backup" to ("请填写备用网络" to "Enter the backup network"),
        "same_network_error" to ("优先和备用网络不能相同" to "Priority and backup must be different"),
        // Android only accepts WPA2 passphrases of 8-63 characters in a
        // network suggestion; shorter ones are silently unusable.
        "invalid_password" to (
            "密码需为 8–63 个字符，或留空表示开放网络" to
                "A password must be 8–63 characters, or blank for an open network"
        ),
        "storage_error" to ("无法写入加密存储" to "Unable to write encrypted storage"),
        "networks_found" to ("发现 %d 个网络" to "%d networks found"),

        "settings_title" to ("设置" to "Settings"),
        "general" to ("通用" to "General"),
        "language" to ("语言" to "Language"),
        "check_frequency" to ("检查间隔" to "Check interval"),
        "seconds_unit" to ("秒" to "seconds"),
        "interval_hint" to ("范围 5–3600 秒" to "Range 5–3600 seconds"),
        "start_on_boot" to ("开机自动监控" to "Start monitoring on boot"),
        "android_limits" to ("Android 限制" to "Android limitations"),
        "android_limits_body" to (
            "系统不允许应用静默强制连接或持续后台扫描。应用会注册 P/B 的 Wi-Fi 建议，由系统在合适的时机切换；扫描频率也受系统限制。" to
                "Android does not allow apps to force a connection or scan continuously in the background. The app registers P/B Wi-Fi suggestions and the system switches when appropriate; scans are rate-limited."
        ),
        "about" to ("关于" to "About"),
        "version" to ("版本" to "Version"),
        "privacy" to (
            "仅本机运行；SSID 和密码不会上传。密码保存在加密存储中。" to
                "Runs on this device only; SSIDs and passwords are never uploaded. Passwords use encrypted storage."
        ),
        "stop_monitoring" to ("停止监控" to "Stop monitoring"),
        "rerun_setup" to ("重新运行设置向导" to "Run setup again"),

        "wizard_step" to ("第 %d 步，共 3 步" to "Step %d of 3"),
        "wizard_permission_title" to ("授予定位权限" to "Allow location access"),
        "wizard_permission_body" to (
            "Android 用定位权限来读取当前 Wi-Fi 名称和扫描附近网络。应用不会上传位置。" to
                "Android uses location permission to read the current Wi-Fi name and scan nearby networks. Nothing is uploaded."
        ),
        "wizard_networks_title" to ("选择优先和备用网络" to "Choose priority and backup networks"),
        "wizard_networks_body" to (
            "优先网络会优先连接；不可用时自动使用备用网络。" to
                "Connect to the priority network first, then fall back to the backup."
        ),
        "wizard_finish_title" to ("完成" to "Finish"),
        "wizard_finish_body" to (
            "配置已保存。开启监控后，应用会在前台服务中按间隔检查网络。" to
                "Settings saved. Once monitoring is on, the app checks the network from a foreground service."
        ),
        "wizard_back" to ("上一步" to "Back"),
        "wizard_next" to ("下一步" to "Next"),
        "wizard_start" to ("开启监控" to "Start monitoring"),
        "wizard_save_only" to ("仅保存" to "Save only"),
        "wizard_skip" to ("跳过" to "Skip"),
        "wizard_continue" to ("继续" to "Continue"),
        "not_set" to ("未设置" to "Not set"),

        "event_started" to ("已开始监控" to "Monitoring started"),
        "event_stopped" to ("已停止监控" to "Monitoring stopped"),
        "event_priorityConnected" to ("已连接优先网络" to "Connected to the priority network"),
        "event_priorityVisibleWaiting" to ("优先网络可见，等待系统切换" to "Priority network visible; waiting for the system"),
        "event_networkDisconnectedWaiting" to ("网络已断开，等待" to "Network disconnected; waiting"),
        "event_automaticFailover" to ("自动切换到备用网络" to "Automatically switched to the backup"),
        "event_priorityLostConnectingBackup" to ("优先网络丢失，正在连接备用网络" to "Priority lost; connecting the backup"),
        "event_backupConnectedPNotFound" to ("已连接备用网络，未发现优先网络" to "On backup; priority not found"),
        "event_neitherFound" to ("未发现优先或备用网络" to "Neither network was found"),
        "event_backupNotFound" to ("未发现备用网络" to "Backup network not found"),
        "event_backupNotFoundWaiting" to ("未发现备用网络，继续等待" to "Backup not found; waiting"),
        "event_previousBackupReconnect" to ("重新连接之前的备用网络" to "Reconnecting the previous backup"),
        "event_systemJoinedBackup" to ("系统已连接备用网络" to "The system joined the backup network"),
        "event_treatingAsFallback" to ("作为回退网络处理" to "Treating it as a fallback network"),
        "event_cooldownSkipped" to ("冷却中，暂时跳过" to "Cooling down; skipping this round"),
        "event_associationSuccess" to ("连接成功" to "Connection succeeded"),
        "event_associationTimeout" to (
            "连接超时，请检查密码和信号" to "Connection timed out — check the password and signal"
        ),
        "event_associationFailure" to ("连接失败" to "Connection failed"),
        "event_associationLateSuccess" to ("连接稍后成功" to "Connection succeeded later"),
        "event_associationLateFailure" to ("连接稍后失败" to "Connection failed later"),
        "event_permissionRequired" to ("需要权限" to "Permission required"),
        "event_priorityVisibleUnknown" to (
            "无法确认优先网络状态，保持当前连接" to
                "Could not verify the priority network; keeping the current connection"
        ),
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
}

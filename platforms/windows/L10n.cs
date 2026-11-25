namespace Via.Windows;

public static class L10n
{
    public static string Language { get; set; } = "zh";

    public static string T(string key)
    {
        var table = Language == "en" ? English : Chinese;
        return table.TryGetValue(key, out var value) ? value : key;
    }

    public static string NetworksFound(int count)
    {
        return count == 1
            ? T("networks_found_one")
            : string.Format(T("networks_found_format"), count);
    }

    public static string Duration(int seconds)
    {
        var total = Math.Max(0, seconds);
        var hours = total / 3600;
        var minutes = (total % 3600) / 60;
        var rest = total % 60;
        if (hours > 0)
        {
            return minutes > 0
                ? string.Format(T("duration_hours_minutes"), hours, minutes)
                : string.Format(T("duration_hours"), hours);
        }
        if (minutes > 0)
        {
            return rest > 0
                ? string.Format(T("duration_minutes_seconds"), minutes, rest)
                : string.Format(T("duration_minutes"), minutes);
        }
        return string.Format(T("duration_seconds"), rest);
    }

    private static readonly Dictionary<string, string> Chinese = new()
    {
        ["app_title"] = "Via",
        ["app_subtitle"] = "Wi-Fi 自动切换",
        ["tab_status"] = "状态",
        ["tab_networks"] = "网络",
        ["tab_settings"] = "设置",
        ["current_network"] = "当前连接",
        ["role"] = "网络角色",
        ["status_running"] = "运行中",
        ["status_restarting"] = "正在重启",
        ["status_paused"] = "已关闭",
        ["auto_switch"] = "自动切换",
        ["auto_switch_hint"] = "首选网络不可用时，自动连接备用网络。",
        ["next_check"] = "下次检查",
        ["scan_networks"] = "扫描网络",
        ["scanning"] = "正在扫描…",
        ["refresh_status"] = "刷新",
        ["last_message"] = "最近状态",
        ["networks_description"] = "连接首选网络；它不可用时改用备用网络。",
        ["priority_network"] = "首选网络",
        ["backup_network"] = "备用网络",
        ["password"] = "密码",
        ["show_passwords"] = "显示密码",
        ["scan_hint"] = "扫描附近的网络，或直接输入名称。",
        ["networks_found_format"] = "发现 {0} 个网络",
        ["networks_found_one"] = "发现 1 个网络",
        ["not_configured_hint"] = "请先完成网络设置。",
        ["permission_needed"] = "需要权限才能继续。",
        ["start_failed"] = "自动切换暂时无法开启，请稍后重试。",
        ["summary_format"] = "{0}：{1}",
        ["invalid_password"] = "密码需为 8–63 个字符，或留空表示开放网络。",
        ["save_changes"] = "保存更改",
        ["saved"] = "已保存",
        ["missing_primary"] = "请输入首选网络的名称。",
        ["missing_backup"] = "请输入备用网络的名称。",
        ["same_network"] = "首选网络和备用网络不能相同。",
        ["password_optional"] = "密码可以留空，适用于开放网络。",
        ["no_networks"] = "没有找到网络。请稍后再试。",
        ["settings_general"] = "通用",
        ["language"] = "语言",
        ["interval"] = "检查间隔",
        ["seconds"] = "秒",
        ["interval_summary_format"] = "每 {0} 检查一次",
        ["interval_range"] = "5 秒到 1 小时。超出范围会自动调整。",
        ["launch_at_login"] = "登录时启动",
        ["launch_at_login_hint"] = "登录后在通知区域运行。",
        ["settings_saved"] = "设置已保存。",
        ["about"] = "关于",
        ["version"] = "版本",
        ["privacy_note"] = "Wi-Fi 名称、密码和位置只在本机使用；密码保存在 Windows 凭据管理器中。",
        ["quit_app"] = "退出 Via",
        ["open_app"] = "打开 Via",
        ["role_none"] = "未连接",
        ["role_priority"] = "首选网络",
        ["role_backup"] = "备用网络",
        ["role_other"] = "其他网络",
        ["not_connected"] = "未连接 Wi-Fi",
        ["waiting"] = "等待中",
        ["monitor_started"] = "已开启自动切换",
        ["monitor_stopped"] = "已关闭自动切换",
        ["monitor_stopped_manual"] = "你手动切换了网络，自动切换已关闭。",
        ["monitor_restarting_format"] = "监控异常，正在重启：{0}（{1} 秒后重试）",
        ["monitor_failed_format"] = "自动切换已停止：{0}",
        ["scan_failed"] = "扫描失败，请确认 Wi-Fi 已开启。",
        ["scan_empty_unknown"] = "扫描结果为空，无法确认首选网络状态，保持当前连接。",
        ["event_priorityWaiting"] = "首选网络可用，等待系统切换。",
        ["event_disconnectedWaiting"] = "网络已断开，正在等待。",
        ["event_connectingBackup"] = "首选网络不可用，正在连接备用网络。",
        ["event_backupWaiting"] = "已连接备用网络，未发现首选网络。",
        ["event_neitherFound"] = "没有找到首选或备用网络。",
        ["event_backupNotFound"] = "没有找到备用网络。",
        ["event_backupWaitingAgain"] = "没有找到备用网络，继续等待。",
        ["event_previousBackup"] = "正在重新连接之前的备用网络。",
        ["event_systemJoinedBackup"] = "系统已连接备用网络。",
        ["event_treatingAsFallback"] = "作为备用网络处理。",
        ["event_cooldown"] = "冷却中，暂时跳过。",
        ["event_associated"] = "连接成功。",
        ["event_associationTimeout"] = "连接超时，请检查密码和信号。",
        ["event_lateSuccess"] = "稍后已连接。",
        ["event_lateFailure"] = "稍后连接失败。",
        ["connect_failed"] = "连接失败",
        ["windows_limits"] = "Windows 决定最终连接的网络。Via 会维护首选和备用网络，并在合适的时机发起切换。",
        ["rerun_setup"] = "重新设置",
        ["wizard_welcome_title"] = "欢迎使用 Via",
        ["wizard_welcome_body"] = "Via 会在首选网络不可用时连接备用网络。先用两步完成设置。",
        ["wizard_networks_title"] = "设置常用网络",
        ["wizard_networks_body"] = "扫描附近的网络后从列表选择，也可以直接输入名称。",
        ["wizard_finish_title"] = "准备就绪",
        ["wizard_finish_body"] = "开启自动切换后，Via 会在通知区域持续运行。",
        ["wizard_step_format"] = "第 {0} 步，共 3 步",
        ["wizard_back"] = "上一步",
        ["wizard_next"] = "下一步",
        ["wizard_skip"] = "跳过",
        ["wizard_start"] = "保存并开启",
        ["wizard_save_only"] = "仅保存",
        ["duration_seconds"] = "{0} 秒",
        ["duration_minutes"] = "{0} 分钟",
        ["duration_minutes_seconds"] = "{0} 分 {1} 秒",
        ["duration_hours"] = "{0} 小时",
        ["duration_hours_minutes"] = "{0} 小时 {1} 分"
    };

    private static readonly Dictionary<string, string> English = new()
    {
        ["app_title"] = "Via",
        ["app_subtitle"] = "Wi-Fi auto-switch",
        ["tab_status"] = "Status",
        ["tab_networks"] = "Networks",
        ["tab_settings"] = "Settings",
        ["current_network"] = "Current connection",
        ["role"] = "Network role",
        ["status_running"] = "On",
        ["status_restarting"] = "Restarting",
        ["status_paused"] = "Off",
        ["auto_switch"] = "Auto-switch",
        ["auto_switch_hint"] = "Connects to your backup network when the preferred one is unavailable.",
        ["next_check"] = "Next check",
        ["scan_networks"] = "Scan for networks",
        ["scanning"] = "Scanning…",
        ["refresh_status"] = "Refresh",
        ["last_message"] = "Latest status",
        ["networks_description"] = "Stay on your preferred network, and use the backup when it is unavailable.",
        ["priority_network"] = "Preferred network",
        ["backup_network"] = "Backup network",
        ["password"] = "Password",
        ["show_passwords"] = "Show passwords",
        ["scan_hint"] = "Scan for nearby networks, or enter a name.",
        ["networks_found_format"] = "{0} networks found",
        ["networks_found_one"] = "1 network found",
        ["not_configured_hint"] = "Finish setting up your networks first.",
        ["permission_needed"] = "Permission is required to continue.",
        ["start_failed"] = "Auto-switch couldn't start. Try again in a moment.",
        ["summary_format"] = "{0}: {1}",
        ["invalid_password"] = "A password must be 8–63 characters, or blank for an open network.",
        ["save_changes"] = "Save changes",
        ["saved"] = "Saved",
        ["missing_primary"] = "Enter a name for the preferred network.",
        ["missing_backup"] = "Enter a name for the backup network.",
        ["same_network"] = "The preferred and backup networks must be different.",
        ["password_optional"] = "Leave the password empty for open networks.",
        ["no_networks"] = "No networks found. Try again.",
        ["settings_general"] = "General",
        ["language"] = "Language",
        ["interval"] = "Check interval",
        ["seconds"] = "sec",
        ["interval_summary_format"] = "Checks every {0}",
        ["interval_range"] = "From 5 seconds to 1 hour. Out-of-range values are adjusted.",
        ["launch_at_login"] = "Launch at login",
        ["launch_at_login_hint"] = "Runs in the notification area after you log in.",
        ["settings_saved"] = "Settings saved.",
        ["about"] = "About",
        ["version"] = "Version",
        ["privacy_note"] = "Wi-Fi names, passwords, and location stay on this PC; passwords are stored in Windows Credential Manager.",
        ["quit_app"] = "Quit Via",
        ["open_app"] = "Open Via",
        ["role_none"] = "Not connected",
        ["role_priority"] = "Preferred network",
        ["role_backup"] = "Backup network",
        ["role_other"] = "Other network",
        ["not_connected"] = "Wi-Fi not connected",
        ["waiting"] = "Waiting",
        ["monitor_started"] = "Auto-switch turned on",
        ["monitor_stopped"] = "Auto-switch turned off",
        ["monitor_stopped_manual"] = "You switched networks manually, so auto-switch turned off.",
        ["monitor_restarting_format"] = "Monitoring error; restarting in {1}s: {0}",
        ["monitor_failed_format"] = "Auto-switch stopped: {0}",
        ["scan_failed"] = "Scan failed. Check that Wi-Fi is enabled.",
        ["scan_empty_unknown"] = "The scan was empty; preferred availability is unknown. Keeping the current connection.",
        ["event_priorityWaiting"] = "Preferred network available; waiting for the system.",
        ["event_disconnectedWaiting"] = "Network disconnected; waiting.",
        ["event_connectingBackup"] = "Preferred network unavailable; connecting the backup.",
        ["event_backupWaiting"] = "On the backup; preferred network not found.",
        ["event_neitherFound"] = "Neither network was found.",
        ["event_backupNotFound"] = "Backup network not found.",
        ["event_backupWaitingAgain"] = "Backup not found; waiting.",
        ["event_previousBackup"] = "Reconnecting the previous backup network.",
        ["event_systemJoinedBackup"] = "The system joined the backup network.",
        ["event_treatingAsFallback"] = "Treating it as a backup network.",
        ["event_cooldown"] = "Cooling down; skipping this round.",
        ["event_associated"] = "Connected.",
        ["event_associationTimeout"] = "Connection timed out; check the password and signal.",
        ["event_lateSuccess"] = "Connected shortly after.",
        ["event_lateFailure"] = "Connection failed shortly after.",
        ["connect_failed"] = "Connection failed",
        ["windows_limits"] = "Windows chooses the final network. Via keeps your preferred and backup networks and starts a switch when appropriate.",
        ["rerun_setup"] = "Set up again",
        ["wizard_welcome_title"] = "Welcome to Via",
        ["wizard_welcome_body"] = "Via connects to your backup network when the preferred one is unavailable. Two quick steps to set it up.",
        ["wizard_networks_title"] = "Set Up Your Networks",
        ["wizard_networks_body"] = "Scan for nearby networks and pick one from the list, or type a name.",
        ["wizard_finish_title"] = "Ready to Go",
        ["wizard_finish_body"] = "Once auto-switch is on, Via keeps running in the notification area.",
        ["wizard_step_format"] = "Step {0} of 3",
        ["wizard_back"] = "Back",
        ["wizard_next"] = "Next",
        ["wizard_skip"] = "Skip",
        ["wizard_start"] = "Save and turn on",
        ["wizard_save_only"] = "Save only",
        ["duration_seconds"] = "{0} sec",
        ["duration_minutes"] = "{0} min",
        ["duration_minutes_seconds"] = "{0} min {1} sec",
        ["duration_hours"] = "{0} hr",
        ["duration_hours_minutes"] = "{0} hr {1} min"
    };
}

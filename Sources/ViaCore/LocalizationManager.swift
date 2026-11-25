import Foundation
import Combine

@MainActor
public class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()
    
    public enum Language: String {
        case chinese = "zh-Hans"
        case english = "en"
    }
    
    @Published public var language: Language {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "AppLanguage")
        }
    }
    
    private init() {
        let savedLang = UserDefaults.standard.string(forKey: "AppLanguage") ?? Language.chinese.rawValue
        self.language = Language(rawValue: savedLang) ?? .chinese
    }
    
    public func toggleLanguage() {
        language = (language == .chinese) ? .english : .chinese
    }
    
    public func localizedString(_ key: String) -> String {
        switch language {
        case .chinese:
            return chineseStrings[key] ?? key
        case .english:
            return englishStrings[key] ?? key
        }
    }
    
    private let chineseStrings: [String: String] = [
        "app_title": "Via",
        "app_subtitle": "Wi-Fi 自动切换",
        "scan_networks": "扫描网络",
        "scanning": "正在扫描…",
        "priority_network": "首选网络",
        "backup_network": "备用网络",
        "select_network": "选择网络",
        "password": "密码",
        "start_monitoring": "开启自动切换",
        "stop_monitoring": "关闭自动切换",
        "help": "使用说明",
        "help_content": """
        Via 会在首选网络不可用时连接备用网络，并在首选网络恢复后切回。

        为什么需要定位权限
        macOS 把 Wi-Fi 名称视为位置信息。没有定位权限，Via 无法读取网络名称或扫描附近的网络。所有信息只在本机使用。

        手动切换网络时
        如果你在系统 Wi-Fi 菜单中换了网络，Via 会关闭自动切换，避免和你的选择冲突。回到“状态”可以重新开启。
        """,
        "permission_hint": "没有找到网络。请检查定位服务是否已允许 Via 使用。",
        "scan_success": "扫描完成",
        "ssid_placeholder": "输入网络名称，或先扫描",
        "help_tooltip": "查看使用说明",
        "language_tooltip": "切换语言",
        "quit_tooltip": "退出 Via",
        "launch_at_login_tooltip": "登录时自动启动",
        "permission_pending": "等待授权",
        "minimum_interval_hint": "最小间隔为 %d 秒，更小的值会调整为 %d 秒。",
        "auto_switch": "自动切换",
        "auto_switch_enable": "开启自动切换",
        "auto_switch_disable": "关闭自动切换",
        "status_active": "运行中",
        "status_paused": "已关闭",
        "next_check": "下次检查",
        "seconds_short": "%d 秒",
        "mode": "模式",
        "automatic": "自动",
        "manual": "手动",
        "role_priority": "首选网络",
        "role_backup": "备用网络",
        "role_other": "其他网络",
        "role_offline": "未连接",
        "not_connected": "未连接 Wi-Fi",
        "location_permission_denied": "需要定位权限",
        "wifi_unavailable": "没有可用的 Wi-Fi",
        "networks_found_count": "发现 %d 个网络",
        "networks_found_one": "发现 1 个网络",
        "network_discovery": "附近网络",
        "automation_settings": "自动切换",
        "local_only": "仅本机",
        "check_frequency": "检查间隔",
        "seconds_unit": "秒",
        "configured": "已设置",
        "not_configured": "未设置",
        "open_location_settings": "打开系统设置",
        "location_permission_hint": "定位权限已关闭。请在系统设置中允许 Via 使用定位服务。",
        "show_password": "显示密码",
        "hide_password": "隐藏密码",
        "menu_cut": "剪切",
        "menu_copy": "复制",
        "menu_paste": "粘贴",
        "menu_select_all": "全选",
        "launch_at_login_pending_hint": "登录项还在等待系统批准。请在“登录项”中允许 Via。",
        "open_login_items_settings": "打开登录项设置",
        "credential_storage_warning": "密码暂时没能存入钥匙串。你的更改已保留，Via 会自动重试。",
        "configure_networks_hint": "先设置首选网络和备用网络，才能开启自动切换。",
        "tab_status": "状态",
        "tab_networks": "网络",
        "tab_settings": "设置",
        "tab_accessibility_label": "面板分区",
        "auto_switch_description": "首选网络不可用时，自动连接备用网络。",
        "status_checking": "正在检查…",
        "starting": "正在开启…",
        "status_waiting_permission": "等待定位权限",
        "setup_required_hint": "网络还没有设置。",
        "continue_setup": "继续设置",
        "go_to_networks": "前往网络",
        "refresh_status": "刷新",
        "unsaved_changes": "有未保存的更改",
        "not_set": "未设置",
        "networks_title": "网络",
        "networks_description": "连接首选网络；它不可用时改用备用网络。",
        "network_scan_hint": "扫描附近的网络，或直接输入名称。",
        "no_networks_found": "没有找到网络。请稍后再试。",
        "save_changes": "保存更改",
        "saved": "已保存",
        "networks_auto_save": "密码保存在本机钥匙串，不会上传。",
        "same_network_error": "首选网络和备用网络不能相同。",
        "missing_primary": "请输入首选网络的名称。",
        "missing_backup": "请输入备用网络的名称。",
        "password_optional_hint": "密码可以留空，适用于开放网络。",
        "ssid_label": "网络名称",
        "permission_grant": "允许访问",
        "permission_granted": "已允许",
        "permission_open_settings": "打开系统设置",
        "permission_always_required": "请在定位服务中将 Via 设为“始终”。",
        "permission_always_hint": "定位权限需要设为“始终”，自动切换才能在后台运行。",
        "permission_always_needed": "需要“始终”权限",
        "permission_required_for_automation": "自动切换需要定位权限才能读取 Wi-Fi 名称。",
        "permission_label": "定位权限",
        "settings_title": "设置",
        "general_settings": "通用",
        "automatic_settings": "自动切换",
        "launch_at_login": "登录时启动",
        "launch_at_login_description": "登录后在菜单栏运行。",
        "language": "语言",
        "about": "关于",
        "version": "版本",
        "privacy_note": "Wi-Fi 名称、密码和位置只在本机使用，不会上传。",
        "quit_app": "退出 Via",
        "rerun_setup": "重新设置",
        "interval_range_hint": "5 秒到 1 小时。超出范围会自动调整。",
        "interval_summary": "每 %@ 检查一次",
        "interval_adjusted_format": "已调整为 %@",
        "onboarding_step_format": "%d / %d",
        "onboarding_permission_title": "允许使用定位服务",
        "onboarding_permission_body": "macOS 把 Wi-Fi 名称视为位置信息。允许后，Via 才能读取当前网络并扫描附近网络。",
        "onboarding_permission_later_hint": "也可以先跳过，手动输入网络名称。自动切换仍需要定位权限。",
        "onboarding_permission_granted": "已允许",
        "onboarding_permission_settings_hint": "没有看到系统提示？",
        "onboarding_permission_required_hint": "开启自动切换前，请允许 Via 使用定位服务，并选择“始终”。",
        "onboarding_networks_title": "设置常用网络",
        "onboarding_networks_body": "首选网络优先连接；不可用时，自动改用备用网络。",
        "onboarding_networks_hint": "两个网络都需要填写，且不能相同。密码可留空。",
        "onboarding_finish_title": "准备就绪",
        "onboarding_finish_body": "开启自动切换后，Via 会在后台保持首选网络。",
        "onboarding_back": "上一步",
        "onboarding_next": "下一步",
        "onboarding_skip": "跳过",
        "onboarding_start": "保存并开启",
        "onboarding_save_only": "仅保存",
        "onboarding_privacy_note": "Wi-Fi 名称、密码和位置只在本机使用。",
        "status_manual_stopped": "你手动切换了网络，自动切换已关闭。",
        "resume_auto_switch": "重新开启",
        "status_explanation_priority": "已连接首选网络，正在保持连接。",
        "status_explanation_backup": "首选网络不可用，已连接备用网络，正在等待首选网络恢复。",
        "status_explanation_other": "当前连接其他网络，正在等待首选网络。",
        "status_explanation_offline": "正在等待网络连接。",
        "start_unavailable_permission": "需要定位权限才能开启自动切换。",
        "start_unavailable_networks": "先设置首选网络和备用网络。",
        "duration_seconds": "%d 秒",
        "duration_minutes": "%d 分钟",
        "duration_minutes_seconds": "%d 分 %d 秒",
        "duration_hours": "%d 小时",
        "duration_hours_minutes": "%d 小时 %d 分",
        "connection_permission_hint": "允许定位后即可读取网络名称。",
        "connection_wifi_off_hint": "请确认 Wi-Fi 已开启。",
        "use_current": "使用当前网络"
    ]

    private let englishStrings: [String: String] = [
        "app_title": "Via",
        "app_subtitle": "Wi-Fi auto-switch",
        "scan_networks": "Scan for networks",
        "scanning": "Scanning…",
        "priority_network": "Preferred network",
        "backup_network": "Backup network",
        "select_network": "Choose a network",
        "password": "Password",
        "start_monitoring": "Turn on auto-switch",
        "stop_monitoring": "Turn off auto-switch",
        "help": "How it works",
        "help_content": """
        Via connects to your backup network when the preferred one is unavailable, then switches back when it returns.

        Why location access
        macOS treats Wi-Fi names as location data. Without access, Via cannot read network names or scan nearby networks. Everything stays on this Mac.

        Switching networks yourself
        If you pick a network from the system Wi-Fi menu, Via turns off auto-switch so it does not override your choice. Turn it back on from Status.
        """,
        "permission_hint": "No networks found. Check that Via is allowed in Location Services.",
        "scan_success": "Scan complete",
        "ssid_placeholder": "Enter a name, or scan first",
        "help_tooltip": "View how it works",
        "language_tooltip": "Change language",
        "quit_tooltip": "Quit Via",
        "launch_at_login_tooltip": "Open automatically at login",
        "permission_pending": "Waiting for permission",
        "minimum_interval_hint": "The shortest interval is %d seconds; smaller values become %d seconds.",
        "auto_switch": "Auto-switch",
        "auto_switch_enable": "Turn on auto-switch",
        "auto_switch_disable": "Turn off auto-switch",
        "status_active": "On",
        "status_paused": "Off",
        "next_check": "Next check",
        "seconds_short": "%ds",
        "mode": "Mode",
        "automatic": "Automatic",
        "manual": "Manual",
        "role_priority": "Preferred network",
        "role_backup": "Backup network",
        "role_other": "Other network",
        "role_offline": "Not connected",
        "not_connected": "Wi-Fi not connected",
        "location_permission_denied": "Location access needed",
        "wifi_unavailable": "Wi-Fi unavailable",
        "networks_found_count": "%d networks found",
        "networks_found_one": "1 network found",
        "network_discovery": "Nearby networks",
        "automation_settings": "Auto-switch",
        "local_only": "On this Mac",
        "check_frequency": "Check interval",
        "seconds_unit": "sec",
        "configured": "Set",
        "not_configured": "Not set",
        "open_location_settings": "Open System Settings",
        "location_permission_hint": "Location access is off. Allow Via in System Settings.",
        "show_password": "Show password",
        "hide_password": "Hide password",
        "menu_cut": "Cut",
        "menu_copy": "Copy",
        "menu_paste": "Paste",
        "menu_select_all": "Select All",
        "launch_at_login_pending_hint": "Login Items is waiting for approval. Allow Via in Login Items.",
        "open_login_items_settings": "Open Login Items",
        "credential_storage_warning": "The password could not be saved to the keychain yet. Your change is kept and Via will retry.",
        "configure_networks_hint": "Set a preferred and a backup network to turn on auto-switch.",
        "tab_status": "Status",
        "tab_networks": "Networks",
        "tab_settings": "Settings",
        "tab_accessibility_label": "Panel sections",
        "auto_switch_description": "Connects to your backup network when the preferred one is unavailable.",
        "status_checking": "Checking…",
        "starting": "Turning on…",
        "status_waiting_permission": "Waiting for location access",
        "setup_required_hint": "Your networks aren't set up yet.",
        "continue_setup": "Continue setup",
        "go_to_networks": "Go to networks",
        "refresh_status": "Refresh",
        "unsaved_changes": "Unsaved changes",
        "not_set": "Not set",
        "networks_title": "Networks",
        "networks_description": "Stay on your preferred network, and use the backup when it is unavailable.",
        "network_scan_hint": "Scan for nearby networks, or enter a name.",
        "no_networks_found": "No networks found. Try again.",
        "save_changes": "Save changes",
        "saved": "Saved",
        "networks_auto_save": "Passwords stay in the macOS keychain.",
        "same_network_error": "The preferred and backup networks must be different.",
        "missing_primary": "Enter a name for the preferred network.",
        "missing_backup": "Enter a name for the backup network.",
        "password_optional_hint": "Leave the password empty for open networks.",
        "ssid_label": "Network name",
        "permission_grant": "Allow access",
        "permission_granted": "Allowed",
        "permission_open_settings": "Open System Settings",
        "permission_always_required": "In Location Services, set Via to “Always.”",
        "permission_always_hint": "Set location access to “Always” so auto-switch can run in the background.",
        "permission_always_needed": "“Always” needed",
        "permission_required_for_automation": "Auto-switch needs location access to read Wi-Fi names.",
        "permission_label": "Location access",
        "settings_title": "Settings",
        "general_settings": "General",
        "automatic_settings": "Auto-switch",
        "launch_at_login": "Launch at login",
        "launch_at_login_description": "Runs in the menu bar after you log in.",
        "language": "Language",
        "about": "About",
        "version": "Version",
        "privacy_note": "Wi-Fi names, passwords, and location stay on this Mac.",
        "quit_app": "Quit Via",
        "rerun_setup": "Set up again",
        "interval_range_hint": "From 5 seconds to 1 hour. Out-of-range values are adjusted.",
        "interval_summary": "Checks every %@",
        "interval_adjusted_format": "Adjusted to %@",
        "onboarding_step_format": "%d / %d",
        "onboarding_permission_title": "Allow location access",
        "onboarding_permission_body": "macOS treats Wi-Fi names as location data. Allow access so Via can read the current network and scan nearby ones.",
        "onboarding_permission_later_hint": "You can skip and enter names manually. Auto-switch still needs location access.",
        "onboarding_permission_granted": "Allowed",
        "onboarding_permission_settings_hint": "No prompt?",
        "onboarding_permission_required_hint": "Before you turn on auto-switch, allow Via to use Location Services and choose “Always.”",
        "onboarding_networks_title": "Set up your networks",
        "onboarding_networks_body": "Via stays on your preferred network and uses the backup when it drops.",
        "onboarding_networks_hint": "Both networks are required and must be different. Passwords are optional.",
        "onboarding_finish_title": "Ready to go",
        "onboarding_finish_body": "Turn on auto-switch and Via will keep you on your preferred network.",
        "onboarding_back": "Back",
        "onboarding_next": "Next",
        "onboarding_skip": "Skip",
        "onboarding_start": "Save and turn on",
        "onboarding_save_only": "Save only",
        "onboarding_privacy_note": "Wi-Fi names, passwords, and location stay on this Mac.",
        "status_manual_stopped": "You switched networks manually, so auto-switch turned off.",
        "resume_auto_switch": "Turn on again",
        "status_explanation_priority": "Connected to your preferred network.",
        "status_explanation_backup": "Your preferred network is unavailable. Using the backup until it returns.",
        "status_explanation_other": "Connected to another network while waiting for your preferred network.",
        "status_explanation_offline": "Waiting for a Wi-Fi connection.",
        "start_unavailable_permission": "Location access is needed to turn on auto-switch.",
        "start_unavailable_networks": "Set a preferred and a backup network first.",
        "duration_seconds": "%d sec",
        "duration_minutes": "%d min",
        "duration_minutes_seconds": "%d min %d sec",
        "duration_hours": "%d hr",
        "duration_hours_minutes": "%d hr %d min",
        "connection_permission_hint": "Allow location access to read Wi-Fi names.",
        "connection_wifi_off_hint": "Make sure Wi-Fi is turned on.",
        "use_current": "Use current network"
    ]

    /// Human-readable duration for countdowns and interval summaries. Raw
    /// seconds are hard to read once they pass a minute.
    public func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            if minutes > 0 {
                return String(format: localizedString("duration_hours_minutes"), hours, minutes)
            }
            return String(format: localizedString("duration_hours"), hours)
        }
        if minutes > 0 {
            if seconds > 0 {
                return String(format: localizedString("duration_minutes_seconds"), minutes, seconds)
            }
            return String(format: localizedString("duration_minutes"), minutes)
        }
        return String(format: localizedString("duration_seconds"), seconds)
    }

    public func networksFound(_ count: Int) -> String {
        if count == 1 {
            return localizedString("networks_found_one")
        }
        return String(format: localizedString("networks_found_count"), count)
    }
}

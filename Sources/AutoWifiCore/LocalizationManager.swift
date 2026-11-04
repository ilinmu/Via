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
        "app_subtitle": "智能网络切换中枢",
        "scan_networks": "扫描网络",
        "scanning": "扫描中...",
        "priority_network": "优先网络 (P)",
        "backup_network": "备用网络 (B)",
        "select_network": "选择网络...",
        "password": "密码",
        "start_monitoring": "开启自动切换",
        "stop_monitoring": "停止自动切换",
        "help": "使用说明",
        "help_content": """
        使用说明：

        1. 状态：查看当前 Wi-Fi、自动切换和下次检查；在这里开启或关闭自动切换。
        2. 网络：设置优先网络 P 和备用网络 B；扫描后可点下拉选择，修改后点“保存更改”。
        3. 设置：登录时启动、语言、检查间隔、使用说明和版本信息。

        首次使用会显示三步向导：
        授权定位 → 选择 P/B → 开启自动切换。

        ❓ 为什么需要定位权限？
        macOS 将 Wi-Fi 名称视为位置信息。没有权限时无法读取当前 SSID 或扫描附近网络；
        应用只在本地使用，不会上传位置。

        工作原理：
        - 优先保持连接 P。
        - P 丢失时自动连接 B。
        - 在 B 上定期检查 P，恢复后切回 P。

        状态图标：
        - P：自动切换开启，当前连接优先网络。
        - B：自动切换开启，当前连接备用网络。
        - 红点：自动切换已停止。

        ⚠️ 注意：
        自动切换开启时手动切换网络，应用会停止监控并显示红点；需要时重新开启。
        如果定位权限被撤销，自动切换会保留开启状态并等待权限。

        🔒 隐私说明：
        Wi-Fi 密码保存在本机 macOS 钥匙串中，绝不会上传到任何服务器。
        """,
        "permission_hint": "⚠️ 未找到网络。请检查系统设置 > 隐私与安全性 > 定位服务权限。",
        "scan_success": "✅ 扫描完成",
        "ssid_placeholder": "输入 SSID 或扫描选择",
        "help_tooltip": "查看帮助",
        "language_tooltip": "切换语言",
        "quit_tooltip": "退出应用",
        "launch_at_login_tooltip": "开机自动启动",
        "permission_pending": "等待权限...",
        "minimum_interval_hint": "最小间隔为 %d 秒，输入更小值会自动校正。",
        "auto_switch": "自动切换",
        "status_active": "运行中",
        "status_paused": "已暂停",
        "next_check": "下次检查",
        "seconds_short": "%.0f 秒",
        "mode": "控制模式",
        "automatic": "自动",
        "manual": "手动",
        "role_priority": "优先网络",
        "role_backup": "备用网络",
        "role_other": "其他网络",
        "role_offline": "未连接",
        "not_connected": "未连接网络",
        "location_permission_denied": "需要定位权限",
        "wifi_unavailable": "Wi-Fi 不可用",
        "networks_found_count": "发现 %d 个网络",
        "network_discovery": "网络发现",
        "automation_settings": "自动化设置",
        "local_only": "仅本机",
        "check_frequency": "检测频率",
        "seconds_unit": "秒",
        "configured": "已配置",
        "not_configured": "待配置",
        "open_location_settings": "打开系统设置",
        "location_permission_hint": "定位权限被拒绝，无法读取或扫描 Wi-Fi 名称。",
        "show_password": "显示密码",
        "hide_password": "隐藏密码",
        "menu_cut": "剪切",
        "menu_copy": "复制",
        "menu_paste": "粘贴",
        "menu_select_all": "全选",
        "launch_at_login_pending_hint": "开机启动正在等待系统批准，请在“登录项”中允许。",
        "open_login_items_settings": "打开登录项设置",
        "credential_storage_warning": "密码暂时无法写入钥匙串，已保留本机旧副本；修复后会自动重试。",
        "configure_networks_hint": "请先填写优先网络 (P) 和备用网络 (B) 的 SSID。",
        "tab_status": "状态",
        "tab_networks": "网络",
        "tab_settings": "设置",
        "tab_accessibility_label": "面板分区",
        "auto_switch_description": "优先网络 (P) 不可用时，自动连接备用网络 (B)。",
        "status_checking": "正在检查...",
        "starting": "正在开启...",
        "status_waiting_permission": "等待定位权限",
        "setup_required_hint": "网络设置尚未完成。",
        "continue_setup": "继续设置",
        "go_to_networks": "去设置",
        "refresh_status": "刷新状态",
        "unsaved_changes": "有未保存的更改",
        "not_set": "未设置",
        "networks_title": "网络",
        "networks_description": "优先连接优先网络 (P)；优先网络不可用时切换到备用网络 (B)。",
        "network_scan_hint": "扫描附近网络，或直接输入 SSID。",
        "no_networks_found": "未发现网络，请稍后重试。",
        "save_changes": "保存更改",
        "saved": "已保存",
        "networks_auto_save": "保存后生效；密码保存在本机钥匙串中。",
        "same_network_error": "优先网络和备用网络不能相同。",
        "missing_primary": "请填写优先网络的 SSID。",
        "missing_backup": "请填写备用网络的 SSID。",
        "password_optional_hint": "密码可以留空，适用于开放网络。",
        "ssid_label": "SSID",
        "permission_grant": "授权定位",
        "permission_granted": "已授权定位",
        "permission_open_settings": "打开系统设置",
        "permission_always_required": "需要允许“始终”定位访问。",
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
        "privacy_note": "仅在本机读取 Wi-Fi 名称；不会上传 SSID、密码或位置。",
        "quit_app": "退出应用",
        "rerun_setup": "重新运行设置向导",
        "interval_range_hint": "范围 5–3600 秒；输入超出范围会自动校正。",
        "onboarding_step_format": "%d / %d",
        "onboarding_permission_title": "允许读取 Wi-Fi 名称",
        "onboarding_permission_body": "macOS 将 Wi-Fi 名称视为位置信息。授权后，应用才能读取当前网络并扫描附近网络。",
        "onboarding_permission_later_hint": "也可以先跳过，手动输入 SSID；自动切换需要定位权限。",
        "onboarding_permission_granted": "已授权",
        "onboarding_networks_title": "选择优先和备用网络",
        "onboarding_networks_body": "优先保持连接 P；P 不可用时自动切换到 B。",
        "onboarding_networks_hint": "两个网络都需要填写，且不能相同；密码可留空。",
        "onboarding_finish_title": "准备就绪",
        "onboarding_finish_body": "确认配置后开启自动切换，或只保存配置稍后开启。",
        "onboarding_back": "上一步",
        "onboarding_next": "下一步",
        "onboarding_skip": "跳过",
        "onboarding_start": "开启自动切换",
        "onboarding_save_only": "仅保存",
        "onboarding_privacy_note": "Wi-Fi 名称、密码和位置只在本机使用。"
    ]
    
    private let englishStrings: [String: String] = [
        "app_title": "Via",
        "app_subtitle": "Intelligent network switching",
        "scan_networks": "Scan Networks",
        "scanning": "Scanning...",
        "priority_network": "Priority Network (P)",
        "backup_network": "Backup Network (B)",
        "select_network": "Select Network...",
        "password": "Password",
        "start_monitoring": "Enable Auto-Switch",
        "stop_monitoring": "Disable Auto-Switch",
        "help": "Help",
        "permission_pending": "Permission Pending...",
        "help_content": """
        How to use:

        1. Status: See the current Wi-Fi, auto-switch, and next check; enable or disable auto-switch here.
        2. Networks: Set Priority P and Backup B. Scan and pick a network from the menu, then click "Save Changes".
        3. Settings: Launch at login, language, check interval, help, and version.

        The first run shows a three-step setup:
        Allow Location → Choose P/B → Enable Auto-Switch.

        ❓ Why Location Permission?
        macOS treats Wi-Fi names as location data. Without access, the app cannot read the current SSID
        or scan nearby networks. Everything is processed locally and never uploaded.

        How it works:
        - Stay on Network P whenever possible.
        - If P is lost, connect to B.
        - While on B, periodically check for P and switch back when it returns.

        Status Icons:
        - P: Auto-switch is on and the current network is Priority.
        - B: Auto-switch is on and the current network is Backup.
        - Red dot: Auto-switch is stopped.

        ⚠️ Note:
        Manually switching networks while auto-switch is on stops monitoring and shows a red dot.
        Enable auto-switch again to resume.
        If location access is revoked, auto-switch stays on and waits for permission.

        🔒 Privacy Note:
        Wi-Fi passwords are stored in the macOS keychain and are never uploaded to any server.
        """,
        "permission_hint": "⚠️ No networks found. Check System Settings > Privacy & Security > Location Services.",
        "scan_success": "✅ Scan Complete",
        "ssid_placeholder": "Enter SSID or Scan",
        "help_tooltip": "View Help",
        "language_tooltip": "Switch Language",
        "quit_tooltip": "Quit Application",
        "launch_at_login_tooltip": "Launch automatically at login",
        "minimum_interval_hint": "Minimum interval is %d seconds. Smaller values are corrected automatically.",
        "auto_switch": "Auto-Switch",
        "status_active": "Active",
        "status_paused": "Paused",
        "next_check": "Next Check",
        "seconds_short": "%.0fs",
        "mode": "Control Mode",
        "automatic": "Automatic",
        "manual": "Manual",
        "role_priority": "Priority",
        "role_backup": "Backup",
        "role_other": "Other Network",
        "role_offline": "Offline",
        "not_connected": "Not Connected",
        "location_permission_denied": "Location Access Needed",
        "wifi_unavailable": "Wi-Fi Unavailable",
        "networks_found_count": "%d networks found",
        "network_discovery": "DISCOVERY",
        "automation_settings": "Automation",
        "local_only": "LOCAL ONLY",
        "check_frequency": "CHECK FREQUENCY",
        "seconds_unit": "SEC",
        "configured": "Configured",
        "not_configured": "Set Up",
        "open_location_settings": "Open System Settings",
        "location_permission_hint": "Location access is denied; Wi-Fi names cannot be read or scanned.",
        "show_password": "Show password",
        "hide_password": "Hide password",
        "menu_cut": "Cut",
        "menu_copy": "Copy",
        "menu_paste": "Paste",
        "menu_select_all": "Select All",
        "launch_at_login_pending_hint": "Launch at login is waiting for approval in Login Items.",
        "open_login_items_settings": "Open Login Items Settings",
        "credential_storage_warning": "The password could not be saved to the Keychain. The local fallback copy was kept and migration will retry.",
        "configure_networks_hint": "Enter both the Priority Network (P) and Backup Network (B) SSIDs first.",
        "tab_status": "Status",
        "tab_networks": "Networks",
        "tab_settings": "Settings",
        "tab_accessibility_label": "Panel sections",
        "auto_switch_description": "Connect to Backup Network (B) automatically when Priority Network (P) is unavailable.",
        "status_checking": "Checking...",
        "starting": "Starting...",
        "status_waiting_permission": "Waiting for Location Access",
        "setup_required_hint": "Network setup is not complete.",
        "continue_setup": "Continue Setup",
        "go_to_networks": "Open Networks",
        "refresh_status": "Refresh",
        "unsaved_changes": "Unsaved changes",
        "not_set": "Not set",
        "networks_title": "Networks",
        "networks_description": "Connect to Priority Network (P) first; switch to Backup Network (B) when it is unavailable.",
        "network_scan_hint": "Scan nearby networks or enter an SSID.",
        "no_networks_found": "No networks found. Try again.",
        "save_changes": "Save Changes",
        "saved": "Saved",
        "networks_auto_save": "Changes apply after saving; passwords stay in the macOS keychain.",
        "same_network_error": "Priority and Backup networks must be different.",
        "missing_primary": "Enter the Priority network SSID.",
        "missing_backup": "Enter the Backup network SSID.",
        "password_optional_hint": "Leave the password empty for open networks.",
        "ssid_label": "SSID",
        "permission_grant": "Allow Location",
        "permission_granted": "Location allowed",
        "permission_open_settings": "Open System Settings",
        "permission_always_required": "“Always” location access is required.",
        "permission_required_for_automation": "Auto-switch needs location access to read Wi-Fi names.",
        "permission_label": "Location Access",
        "settings_title": "Settings",
        "general_settings": "General",
        "automatic_settings": "Auto-Switch",
        "launch_at_login": "Launch at Login",
        "launch_at_login_description": "Run in the menu bar after you log in.",
        "language": "Language",
        "about": "About",
        "version": "Version",
        "privacy_note": "Wi-Fi names are read locally; SSIDs, passwords, and location are never uploaded.",
        "quit_app": "Quit App",
        "rerun_setup": "Run Setup Again",
        "interval_range_hint": "5–3600 seconds. Out-of-range values are corrected.",
        "onboarding_step_format": "%d / %d",
        "onboarding_permission_title": "Allow Wi-Fi Name Access",
        "onboarding_permission_body": "macOS treats Wi-Fi names as location data. Via needs this access to read the current network and scan nearby networks.",
        "onboarding_permission_later_hint": "You can skip and enter SSIDs manually; auto-switch still requires location access.",
        "onboarding_permission_granted": "Location access granted",
        "onboarding_networks_title": "Choose Priority and Backup",
        "onboarding_networks_body": "Stay on Priority P; switch to Backup B when P is unavailable.",
        "onboarding_networks_hint": "Both networks are required and must be different. Passwords are optional.",
        "onboarding_finish_title": "You're Ready",
        "onboarding_finish_body": "Confirm the setup and enable auto-switch, or save it for later.",
        "onboarding_back": "Back",
        "onboarding_next": "Next",
        "onboarding_skip": "Skip",
        "onboarding_start": "Enable Auto-Switch",
        "onboarding_save_only": "Save Only",
        "onboarding_privacy_note": "Wi-Fi names, passwords, and location stay on this Mac."
    ]
}

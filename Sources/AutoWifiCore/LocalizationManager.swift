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
        "app_title": "自动 Wi-Fi 助手",
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
        
        1. 点击 "扫描网络" 获取当前可用 Wi-Fi。
        2. 设置 "优先网络 (P)"：这是您最想连接的网络。
        3. 设置 "备用网络 (B)"：当 P 不可用时连接的网络。
        4. 输入对应的 Wi-Fi 密码。
        5. 点击 "开始监控"。
        
        ❓ 为什么需要定位权限？
        macOS 系统出于隐私保护，将 Wi-Fi 名称 (SSID) 视为位置信息。
        如果不授予此权限，应用将无法获取当前连接的 Wi-Fi 名称，也无法扫描周围的网络。
        本应用仅在本地使用此权限，不会上传您的位置信息。
        
        工作原理：
        - 程序会优先保持连接网络 P。
        - 如果 P 丢失，会自动连接 B。
        - 连接 B 时，会定期检查 P 是否恢复，恢复后自动切回 P。
        
        状态图标说明：
        - P (下标): 自动切换开启，当前连接优先网络。
        - B (下标): 自动切换开启，当前连接备用网络。
        - 🔴 (红点): 自动切换已停止。
        
        ⚠️ 注意：
        如果在开启状态下手动切换网络，程序会自动停止监控并在图标上显示红点。
        如需恢复，请再次点击 "开启自动切换"。
        
        🔒 隐私说明：
        您的 Wi-Fi 密码保存在本机 macOS 钥匙串中，绝不会上传到任何服务器。
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
        "launch_at_login_pending_hint": "开机启动正在等待系统批准，请在“登录项”中允许。",
        "open_login_items_settings": "打开登录项设置",
        "credential_storage_warning": "密码暂时无法写入钥匙串，已保留本机旧副本；修复后会自动重试。",
        "configure_networks_hint": "请先填写优先网络 (P) 和备用网络 (B) 的 SSID。"
    ]
    
    private let englishStrings: [String: String] = [
        "app_title": "Auto-Wifi Helper",
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
        
        1. Click "Scan Networks" to find available Wi-Fi.
        2. Set "Priority Network (P)": Your preferred network.
        3. Set "Backup Network (B)": Network to use when P is lost.
        4. Enter passwords for both networks.
        5. Click "Start Monitoring".
        
        ❓ Why Location Permission?
        macOS treats Wi-Fi SSID as location data.
        Without this permission, the app cannot see your current network name or scan for nearby networks.
        This data is processed locally and never uploaded.
        
        How it works:
        - App prioritizes connection to Network P.
        - If P is lost, it connects to B.
        - While on B, it periodically checks for P and switches back if found.
        
        Status Icons:
        - P (Subscript): Auto-switch ON, connected to Priority.
        - B (Subscript): Auto-switch ON, connected to Backup.
        - 🔴 (Red Dot): Auto-switch STOPPED.
        
        ⚠️ Note:
        If you manually switch networks while enabled, the app will stop monitoring and show a red dot.
        Click "Enable Auto-Switch" again to resume.
        
        🔒 Privacy Note:
        Your Wi-Fi passwords are stored in the macOS Keychain and are NEVER uploaded to any server.
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
        "launch_at_login_pending_hint": "Launch at login is waiting for approval in Login Items.",
        "open_login_items_settings": "Open Login Items Settings",
        "credential_storage_warning": "The password could not be saved to the Keychain. The local fallback copy was kept and migration will retry.",
        "configure_networks_hint": "Enter both the Priority Network (P) and Backup Network (B) SSIDs first."
    ]
}

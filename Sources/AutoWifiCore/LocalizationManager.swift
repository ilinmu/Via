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
        "scan_networks": "扫描网络",
        "scanning": "扫描中...",
        "networks_found": "个网络已找到",
        "priority_network": "优先网络 (P)",
        "backup_network": "备用网络 (B)",
        "select_network": "选择网络...",
        "password": "密码",
        "check_interval": "检查间隔 (秒):",
        "start_monitoring": "开启自动切换",
        "stop_monitoring": "停止自动切换",
        "help": "使用说明",
        "quit": "退出应用",
        "status_idle": "就绪",
        "status_monitoring": "监控中...",
        "log_title": "运行日志",
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
        您的 Wi-Fi 密码仅保存在本地设备上，绝不会上传到任何服务器。
        """,
        "permission_hint": "⚠️ 未找到网络。请检查系统设置 > 隐私与安全性 > 定位服务权限。",
        "scan_success": "✅ 扫描完成",
        "ssid_placeholder": "输入 SSID 或扫描选择",
        "help_tooltip": "查看帮助",
        "language_tooltip": "切换语言",
        "quit_tooltip": "退出应用",
        "launch_at_login_tooltip": "开机自动启动",
        "current_network": "当前网络",
        "next_check_in": "下次检查还剩 %.0f 秒",
        "permission_pending": "等待权限...",
        "minimum_interval_hint": "最小间隔为 %d 秒，输入更小值会自动校正。",
        "status_card_title": "运行状态",
        "latest_log": "最近日志"
    ]
    
    private let englishStrings: [String: String] = [
        "app_title": "Auto-Wifi Helper",
        "scan_networks": "Scan Networks",
        "scanning": "Scanning...",
        "networks_found": "networks found",
        "priority_network": "Priority Network (P)",
        "backup_network": "Backup Network (B)",
        "select_network": "Select Network...",
        "password": "Password",
        "check_interval": "Check Interval (sec):",
        "start_monitoring": "Enable Auto-Switch",
        "stop_monitoring": "Disable Auto-Switch",
        "help": "Help",
        "quit": "Quit",
        "launch_at_login": "Launch at Login",
        "status_idle": "Idle",
        "status_monitoring": "Monitoring...",
        "log_title": "Activity Log",
        "current_network": "Current Network",
        "next_check_in": "Next check in %.0fs",
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
        Your Wi-Fi passwords are stored locally on your device and are NEVER uploaded to any server.
        """,
        "permission_hint": "⚠️ No networks found. Check System Settings > Privacy & Security > Location Services.",
        "scan_success": "✅ Scan Complete",
        "ssid_placeholder": "Enter SSID or Scan",
        "help_tooltip": "View Help",
        "language_tooltip": "Switch Language",
        "quit_tooltip": "Quit Application",
        "launch_at_login_tooltip": "Launch automatically at login",
        "minimum_interval_hint": "Minimum interval is %d seconds. Smaller values are corrected automatically.",
        "status_card_title": "Runtime Status",
        "latest_log": "Latest Log"
    ]
}

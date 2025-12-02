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
        "priority_network": "优先网络 (A)",
        "backup_network": "备用网络 (B)",
        "select_network": "选择网络...",
        "password": "密码",
        "check_interval": "检查间隔 (秒):",
        "start_monitoring": "开始监控",
        "stop_monitoring": "停止监控",
        "help": "使用说明",
        "quit": "退出应用",
        "status_idle": "就绪",
        "status_monitoring": "监控中...",
        "log_title": "运行日志",
        "help_content": """
        使用说明：
        
        1. 点击 "扫描网络" 获取当前可用 Wi-Fi。
        2. 设置 "优先网络 (A)"：这是您最想连接的网络。
        3. 设置 "备用网络 (B)"：当 A 不可用时连接的网络。
        4. 输入对应的 Wi-Fi 密码。
        5. 点击 "开始监控"。
        
        ❓ 为什么需要定位权限？
        macOS 系统出于隐私保护，将 Wi-Fi 名称 (SSID) 视为位置信息。
        如果不授予此权限，应用将无法获取当前连接的 Wi-Fi 名称，也无法扫描周围的网络。
        本应用仅在本地使用此权限，不会上传您的位置信息。
        
        工作原理：
        - 程序会优先保持连接网络 A。
        - 如果 A 丢失，会自动连接 B。
        - 连接 B 时，会定期检查 A 是否恢复，恢复后自动切回 A。
        """,
        "permission_hint": "⚠️ 未找到网络。请检查系统设置 > 隐私与安全性 > 定位服务权限。",
        "scan_success": "✅ 扫描完成",
        "ssid_placeholder": "输入 SSID 或扫描选择"
    ]
    
    private let englishStrings: [String: String] = [
        "app_title": "Auto-Wifi Helper",
        "scan_networks": "Scan Networks",
        "scanning": "Scanning...",
        "networks_found": "networks found",
        "priority_network": "Priority Network (A)",
        "backup_network": "Backup Network (B)",
        "select_network": "Select Network...",
        "password": "Password",
        "check_interval": "Check Interval (sec):",
        "start_monitoring": "Start Monitoring",
        "stop_monitoring": "Stop Monitoring",
        "help": "Help",
        "quit": "Quit App",
        "status_idle": "Idle",
        "status_monitoring": "Monitoring...",
        "log_title": "Activity Log",
        "help_content": """
        How to use:
        
        1. Click "Scan Networks" to find available Wi-Fi.
        2. Set "Priority Network (A)": Your preferred network.
        3. Set "Backup Network (B)": Network to use when A is lost.
        4. Enter passwords for both networks.
        5. Click "Start Monitoring".
        
        ❓ Why Location Permission?
        macOS treats Wi-Fi SSID as location data.
        Without this permission, the app cannot see your current network name or scan for nearby networks.
        This data is processed locally and never uploaded.
        
        How it works:
        - App prioritizes connection to Network A.
        - If A is lost, it connects to B.
        - While on B, it periodically checks for A and switches back if found.
        """,
        "permission_hint": "⚠️ No networks found. Check System Settings > Privacy & Security > Location Services.",
        "scan_success": "✅ Scan Complete",
        "ssid_placeholder": "Enter SSID or Scan"
    ]
}

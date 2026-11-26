# 跨平台能力与差异说明

所有平台共享相同的 Go 策略引擎（`internal/policy`）、配置与凭据模型（`internal/store`）、双语词典（`internal/i18n`）与 Scheme A UI 布局（`internal/uiapp`），硬件能力按系统权限边界实现如下：

| 平台 | Wi-Fi 读写与切换能力 | 凭据存储 (`mygo.Secrets`) | 托盘 / 系统入口 | 权限与系统限制 |
| --- | --- | --- | --- | --- |
| **macOS** | 原生 `CoreWLAN` 扫描与强制关联（支持 App Sandbox） | macOS 钥匙串（单条目合并存储 + 会话缓存） | 菜单栏原生 SF Symbol (`P`/`B`/纯Wi-Fi/红点) + 380px 自适应 Popover 浮窗 | 需要「定位服务」权限（`NSLocation*`）以读取 SSID 与扫描周边网络；未授权定位服务前锁定网络配置与自动守护开关 |
| **Windows** | 纯 Go 调用 `wlanapi.dll`（用户级配置 + 断开/完成事件监听） | Windows 凭据管理器 | 任务栏 `gdiplus.dll` 原生系统图标字体 + 380px 浮窗 | 桌面应用无需定位弹窗 |
| **Linux** | NetworkManager (`nmcli`) 扫描/连接/事件轮询 | FreeDesktop Secret Service | 系统主题 Wi-Fi 图标（找不到 PNG 时自动高清兜底） + 380px 浮窗 | 依赖已运行的 NetworkManager |
| **Android** | `WifiNetworkSuggestion` 优先级建议 + `ConnectivityManager` 实时监听 | Android 加密凭据存储 / 私有应用数据 | 全屏底部双导航 UI + 低打扰常驻通知 | Android 10+ 不允许普通应用强制切网，Via 通过动态调整首选/备用建议优先级引导系统切换；需定位与通知权限 |
| **iOS (占位)** | `errors.ErrUnsupported`（选项 A 架构预留） | 同构 UI 预留 | 同构全屏界面与清晰系统限制提示 | iOS 禁止普通应用在后台自动扫描与切换公共/家庭 Wi-Fi，当前仅作为界面占位保留 |

# Via

**自动在「首选网络」与「备用网络」之间无缝切换的多端 Wi-Fi 守护工具。**

Via v2.0 采用 **Go + MyGo Native UI** 单一代码库架构，覆盖 **macOS、Windows、Linux 与 Android**（并保留 iOS 架构占位）。所有网络策略、凭据保管、双语界面与命令行诊断均由同一套 Go 代码驱动。

---

## 核心特性

- **确定性主备切换状态机（`internal/policy`）**：
  - 首选网络（`P`）可用时自动保持/回切；
  - `P` 不可用时自动切换至备用网络（`B`）；
  - 通过稳定窗口多次复扫区分“断网/失效”与“用户手动切网”，避免因系统扫描缓存误判，并在误停后自动复核恢复；
  - 针对失败/超时的目标独立冷却（不影响切往另一槽位）。
- **多端原生 Wi-Fi 适配与系统级托盘图标**：
  - **macOS**：App Sandbox 沙盒适配（`CoreWLAN` + `CoreLocation`），菜单栏直接调用系统原生 SF Symbol，并在右下角标示 `P` / `B` 或暂停红点；
  - **Windows**：纯 Go 调用系统 `wlanapi.dll` 与 `gdiplus.dll`（使用 `Segoe Fluent Icons` / `Segoe MDL2 Assets` 系统 Wi-Fi 图标）；
  - **Linux**：基于 NetworkManager (`nmcli`) 与桌面主题系统托盘图标；
  - **Android**：通过 Kotlin 原生模块（`WifiManager`、`ConnectivityManager`、`WifiNetworkSuggestion`）提供低打扰前台守护通知与系统网络建议优先级切换；
  - **iOS**：受系统后台限制，预留同构 UI 占位与提示，待具备特定授权扩展条件时启用。
- **方案 A「晴空路径仪表盘」原生 UI（`internal/uiapp`）**：
  - 极简双视图（「主控台」+「设置」），桌面端为 380px 无边框浮出面板（高度随当前内容自适应贴合，180–720px，无底部多余留白），手机端为底部双导航全屏布局；
  - 管理网络提供下拉选择列表（首项为一键「使用当前网络」），未授予系统定位权限前严格锁定配置编辑与守护开关；
  - 点击卡片原地编辑单槽位 SSID 与密码；macOS 钥匙串将主备密码合并存储于单一凭据条目并结合进程内会话缓存，避免重复弹窗授权。
- **内置命令行工具（`internal/cli`）**：
  - `via doctor`：检查当前 Wi-Fi 适配器、定位/网络权限、配置文件、凭据库状态（绝不打印明文密码）与附近扫描情况；
  - `via status`：输出当前 SSID、角色与配置摘要；
  - `via monitor`：在终端无界面持续守护（支持无回显交互式密码输入）。

---

## 快速构建与测试

> 环境要求：Go 1.27+；macOS 需要 Xcode Command Line Tools；Android 构建需要 Android SDK 与 NDK（可通过 `go tool mygo doctor` 自检）。

```sh
# 运行全套 Go 检查与单元测试
go vet ./...
go test -v ./...

# 启动桌面端实时开发调试
go tool mygo dev

# 打包当前平台桌面应用（macOS 生成 build/darwin-arm64/Via.app）
go tool mygo build -skip-dmg

# 打包 Android APK / AAB（需已配置 Android SDK & NDK）
go tool mygo build -platform android

# 运行命令行诊断与终端守护
go run . version
go run . doctor
```

---

## 目录结构

```text
.
├── main.go                     # CLI 与 GUI 统一入口
├── mygo.json                   # MyGo 多端构建、权限与包信息配置
├── entitlements.plist          # macOS App Store 沙盒权限声明
├── resources/                  # 应用图标与隐私清单 (PrivacyInfo.xcprivacy)
└── internal/
    ├── policy/                 # 确定性 Wi-Fi 主备切换策略状态机
    ├── store/                  # 原子 JSON 配置与系统安全凭据存储 (mygo.Secrets)
    ├── i18n/                   # 中/英双语词典
    ├── cli/                    # doctor / status / monitor / version 子命令
    ├── nativewifi/             # MyGo 原生模块 (macOS Swift + Android Kotlin)
    ├── wifi/                   # 跨平台适配器 (macOS/Windows/Linux/Android/iOS) 与协调器
    ├── tray/                   # 各端系统原生托盘图标渲染 (Option 1: P/B/纯Wi-Fi/红点)
    └── uiapp/                  # Scheme A MyGo Native UI（桌面浮窗 + 手机全屏）
```

---

## 相关文档

- [UI 设计规范](docs/UI_DESIGN.md)
- [跨平台能力说明](docs/CROSS_PLATFORM.md)
- [开发指南](docs/DEVELOPMENT_GUIDE.md)
- [安全政策](SECURITY.md)
- [GitHub Releases 下载](https://github.com/ilinmu/Via/releases)

---

## 致谢（Acknowledgements）

Via v2.0 的跨平台实现与原生交互体验得益于以下优秀开源项目与基础设施：

- **[MyGo](https://github.com/egoist/mygo)**（`github.com/egoist/mygo`）：跨平台原生应用框架，提供 Native UI 渲染引擎、托盘/浮窗（Flyout / Popover）、系统安全凭据存储（`mygo.Secrets`）以及 Swift/Kotlin 原生模块桥接（`//mygo:native`）
- **[Go](https://go.dev/)**：核心编程语言、标准库与跨平台交叉编译工具链
- **[purego](https://github.com/ebitengine/purego)**：纯 Go 动态库绑定基础库，支持无 CGo 直接调用各操作系统原生 API
- **[go-text/typesetting](https://github.com/go-text/typesetting)**：跨平台文字整形与排版引擎，支撑 MyGo Native UI 的高清晰原生文本渲染
- **[Go 官方扩展库（`golang.org/x/*`）](https://pkg.go.dev/golang.org/x)**：`x/sys`、`x/image`、`x/text`、`x/net`、`x/crypto` 等系统调用、图像处理与文本国际化底层支持
- **[NetworkManager](https://networkmanager.dev/)**：Linux 平台 Wi-Fi 扫描与连接管理基础设施

---

## 许可

[MIT License](LICENSE)

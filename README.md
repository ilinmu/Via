# AutoWifi

AutoWifi 是一个面向 macOS 的菜单栏 Wi-Fi 自动切换工具。它允许用户配置一个优先网络 `P` 和一个备用网络 `B`，在优先网络不可用时自动连接备用网络，并在优先网络恢复后切回去。

## 项目用途

这个项目主要解决以下场景：

- 家中或办公室有两个常用 Wi-Fi，希望始终优先连接信号更稳定或速度更快的那个。
- 主 Wi-Fi 临时不可用时，希望自动切到备用热点，不想手动反复切换。
- 使用菜单栏常驻工具，而不是完整 Dock 应用。

## 核心功能

- 菜单栏常驻应用，使用自定义状态图标展示当前状态。
- 扫描周围可用 Wi-Fi，并选择优先网络 `P` 与备用网络 `B`。
- 自动监控连接状态：
  - 已连接 `P` 时保持不动。
  - `P` 不可用时尝试连接 `B`。
  - 当前在 `B` 上时，定期扫描并尝试切回 `P`。
- 识别用户手动切网：
  - 如果用户主动切到不受管网络，自动停止监控。
  - 如果用户切到 `B` 且 `P` 仍然可见，认为是手动覆盖，也会停止监控。
- 支持中英文切换。
- 支持登录时启动。
- 提供独立 CLI 脚本，便于命令行下验证同类逻辑。

## 工作原理

1. 应用读取当前 SSID 和可见网络列表。
2. 如果当前已经连接 `P`，则只更新状态，不做切换。
3. 如果 `P` 不可用且当前未连接 `B`，则尝试连接 `B`。
4. 如果已经在 `B` 上，会按照配置间隔继续扫描；一旦发现 `P` 恢复，则切回 `P`。
5. 如果检测到用户主动切换到其它网络，则停止自动监控，避免“和用户抢网络”。

## 权限与安全

- 应用依赖 macOS 定位权限来读取 SSID 和扫描 Wi-Fi。
- 登录启动通过 `ServiceManagement` 管理。
- Wi-Fi 密码现已存储在 macOS Keychain 中，而不是明文 `UserDefaults`。

## 主要代码结构

- `Sources/AutoWifi/main.swift`
  菜单栏应用入口、状态栏图标和弹出面板。
- `Sources/AutoWifiCore/AppState.swift`
  应用状态、配置持久化、启动项开关。
- `Sources/AutoWifiCore/WifiManager.swift`
  Wi-Fi 扫描、连接、监控和自动切换核心逻辑。
- `Sources/AutoWifiCore/SettingsView.swift`
  SwiftUI 配置界面。
- `Sources/AutoWifiCore/SecureStore.swift`
  Keychain 安全存储抽象与实现。
- `auto-wifi-cli.swift`
  命令行版本。
- `Tests/AutoWifiTests/AutoWifiTests.swift`
  核心行为测试。

## 开发与验证

运行测试：

```bash
swift test
```

检查 CLI 脚本类型：

```bash
swiftc -typecheck auto-wifi-cli.swift
```

## 本轮整理与优化

本轮已完成的关键改进：

- 修复了失效测试与当前实现不一致的问题。
- 修复了 CLI 脚本中的变量命名错误和定时器死代码问题。
- 将密码存储迁移到 Keychain，提升本地凭据安全性。
- 让 Wi-Fi 扫描逻辑走统一依赖注入路径，提升可测试性。
- 连接同名网络时优先选择更强信号的 AP。
- 为检查间隔增加最小值保护，避免异常输入导致不稳定行为。
- 保留“为什么停止监控”的状态原因，并在 UI 中展示最新运行状态和日志。

更详细的分析请见 [docs/PROJECT_REVIEW.md](docs/PROJECT_REVIEW.md)。

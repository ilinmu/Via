# Via

Via 是一个跨平台的 Wi-Fi 自动切换工具，目前提供 macOS、Windows、iOS 和 Android 客户端。它允许用户配置一个优先网络 `P` 和一个备用网络 `B`，在优先网络不可用时自动连接备用网络，并在优先网络恢复后切回去。

代码中的 SwiftPM 目标、iOS 工程 target/scheme 和 Windows 项目文件名仍沿用 `AutoWifi`；发布产物与应用标识已统一为 `Via` / `io.github.ilinmu.via`。

四个平台共用 `core/` 中的 Rust 策略状态机；平台层只负责扫描、关联、授权和界面。各平台受系统 API 限制的能力差异见 [docs/CROSS_PLATFORM.md](docs/CROSS_PLATFORM.md)。

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
  - `P` 丢失时立即尝试连接 `B`；只有 `B` 也不可用时才交由系统自行选择网络。
  - 当前在 `B` 上时，定期扫描并尝试切回 `P`。
- 识别用户手动切网：
  - 如果用户主动切到备用网络 `B` 或其它不受管网络、且此时 `P` 仍可见，视为手动覆盖，自动停止监控并在菜单栏图标显示红色圆点。
  - 如果 `P` 已不可见，切到 `B` 属于自动回退，应用保持监控，并在 `P` 恢复后切回。
- 支持中英文切换。
- 支持登录时启动。
- 跟随系统浅色/深色外观的简约面板，按“状态 / 网络 / 设置”三个 Tab 分区。
- 首次使用提供三步向导：授权定位 → 选择 P/B → 开启自动切换，也可跳过并稍后继续。
- 当前连接、自动切换、下次检查和扫描结果使用本地化语义状态展示，不暴露底层接口诊断文案。
- 提供独立 CLI 脚本，便于命令行下验证同类逻辑。

## 工作原理

1. 应用读取当前 SSID 和可见网络列表。
2. 如果当前已经连接 `P`，则只更新状态，不做切换。
3. 如果 `P` 不可用且当前未连接 `B`，则尝试连接 `B`。
4. 如果已经在 `B` 上，会按照配置间隔继续扫描；一旦发现 `P` 恢复，则切回 `P`。
5. 如果检测到用户主动切换到其它网络，则停止自动监控，避免“和用户抢网络”。

## 共享策略核心

自动切换的决策逻辑已经抽到 `core/` 下的 Rust 状态机中，与界面和平台 API 解耦：

- `core/crates/autowifi-domain`：纯策略状态机，不读时钟、不做 I/O、不接触密码。
- `core/crates/autowifi-ffi`：稳定的 C ABI，供 Swift、C#、Kotlin/JNI 等调用。
- `core/include/autowifi_core.h`：权威头文件。
- `Sources/AutoWifiCore/WifiPolicy.swift`：macOS 的 Swift 封装，通过 `dlopen`
  加载动态库；找不到核心时退回原有 Swift 逻辑。

四个客户端都通过这套核心执行同一套切换策略；平台差异只体现在“如何扫描、如何关联、如何授权”。
详见 [core/README.md](core/README.md) 和 [docs/CROSS_PLATFORM.md](docs/CROSS_PLATFORM.md)。

## 平台客户端

| 平台 | 目录 | 说明 |
| --- | --- | --- |
| macOS | `Sources/` | 菜单栏应用，CoreWLAN，完整扫描与主动切换 |
| Windows | `platforms/windows/` | WPF 托盘应用，WlanAPI，Windows Credential Manager |
| iOS | `platforms/ios/` | SwiftUI，Hotspot Configuration；无公开扫描 API，仅前台监控 |
| Android | `platforms/android/` | Kotlin + Compose，前台服务；通过系统 Wi-Fi 建议切换 |

构建命令：

```bash
# macOS
cargo build --manifest-path core/Cargo.toml -p autowifi-ffi --release
scripts/package-app.sh

# iOS
scripts/build-ios-core.sh
cd platforms/ios && xcodegen generate && cd ../..

# Android
scripts/build-android-core.sh
cd platforms/android && gradle assembleRelease && cd ../..

# Windows（在 Windows 上）
./scripts/build-windows-core.ps1
dotnet publish platforms/windows/AutoWifi.Windows.csproj -c Release -p:Platform=x64 -o dist/windows-portable
```

GitHub Actions 工作流 `.github/workflows/cross-platform.yml` 会在 push 到 `master`
和 pull request 时运行 Rust、macOS Swift、iOS XCTest、Windows xUnit 与 Android
JUnit 测试，并同时构建四个平台的产物。只改文档的 PR 会跳过平台 job；连续推送时
只保留最新一次运行。`master` 每次构建都会在 Releases 中生成
`v1.0.<运行号>` 版本，包含四个平台的产物。

## 权限与安全

- 应用依赖 macOS 定位权限来读取 SSID 和扫描 Wi-Fi。
- 登录启动通过 `ServiceManagement` 管理。
- Wi-Fi 密码保存在 macOS 钥匙串（Keychain）中，仅本机使用，绝不上传；旧版本留在本机偏好中的明文密码会在首次启动时迁移到钥匙串，只有写入并回读校验成功后才会删除旧副本。

## 主要代码结构

- `Sources/AutoWifi/main.swift`
  菜单栏应用入口、状态栏图标和弹出面板。
- `Sources/AutoWifiCore/AppState.swift`
  应用状态、配置持久化、启动项开关。
- `Sources/AutoWifiCore/CredentialStore.swift`
  Wi-Fi 密码的 Keychain 读写与旧数据迁移。
- `Sources/AutoWifiCore/WifiManager.swift`
  Wi-Fi 扫描、连接、监控和自动切换核心逻辑。
- `Sources/AutoWifiCore/WifiPolicy.swift`
  共享策略核心的 Swift 封装。
- `core/crates/autowifi-domain/`
  跨平台自动切换状态机。
- `core/crates/autowifi-ffi/`
  C ABI 导出层。
- `core/crates/autowifi-jni/`
  Android JNI 桥接层。
- `platforms/windows/`、`platforms/ios/`、`platforms/android/`
  Windows、iOS、Android 客户端。
- `.github/workflows/cross-platform.yml`
  测试与四平台构建工作流。
- `Sources/AutoWifi/SettingsView.swift`
  SwiftUI 配置界面。
- `docs/UI_DESIGN.md`
  当前界面模块、固定色彩、术语、本地化边界和交互规范。
- `auto-wifi-cli.swift`
  本地诊断脚本，不参与 SwiftPM 构建、应用打包或发布流程。
- `Tests/AutoWifiTests/AutoWifiTests.swift`
  核心行为测试。

## 开发与验证

运行测试：

```bash
swift test
```

构建并测试共享策略核心：

```bash
cargo test --manifest-path core/Cargo.toml
scripts/build-core.sh
swift run PolicySmoke
```

`swift run PolicySmoke` 会通过 C ABI 驱动核心跑一遍启动、扫描、关联和手动覆盖
流程，输出 `policy smoke ok`。

重新生成四个平台的应用图标：

```bash
swift scripts/generate-app-icons.swift
```

检查 CLI 脚本类型：

```bash
swiftc -typecheck auto-wifi-cli.swift
```

CLI 只接受 `SSID-P`、`SSID-B` 和可选间隔作为参数；密码通过隐藏回显的交互输入读取，不接受命令行密码参数。

更完整的开发入口、联调方式和打包说明见 [docs/DEVELOPMENT_GUIDE.md](docs/DEVELOPMENT_GUIDE.md)。
如果只是想在本地打成 `.app`，直接运行 `scripts/package-app.sh`，产物会出现在 `dist/Via.app`。

## 本轮整理与优化

本轮已完成的关键改进：

- 修复了失效测试与当前实现不一致的问题。
- 修复了 CLI 脚本中的变量命名错误和定时器死代码问题。
- 密码改为存入 macOS Keychain，并自动迁移旧版本遗留的本地明文密码。
- 统一网络状态模型（`NetworkStatus`），定位权限被拒绝时暂停检查并引导用户打开系统设置。
- 修复 SSID 事件与定时检查并发时可能重复发起关联的问题，关联增加超时与代次校验。
- 将密码输入框改成原生 AppKit 文本控件，支持直接粘贴。
- 让 Wi-Fi 扫描逻辑走统一依赖注入路径，提升可测试性。
- 连接同名网络时优先选择更强信号的 AP。
- 为检查间隔增加最小值保护，避免异常输入导致不稳定行为。
- 将设置面板重构为跟随系统的简约风格，并把功能拆成“状态 / 网络 / 设置”三个 Tab。
- 增加首次设置向导：定位授权、选择 P/B、完成并开启自动切换；支持跳过、稍后继续和重新运行。
- 网络配置改为草稿 + 显式保存，避免编辑到一半的空 SSID 影响自动切换。
- 原始运行日志和 Wi-Fi 接口名保留用于内部诊断，状态 Tab 只展示本地化语义状态。
- 面板高度按内容测量并以屏幕可用高度为上限，内容超出时可滚动；扫描状态在切换 Tab 后保留。

更详细的分析请见 [docs/PROJECT_REVIEW.md](docs/PROJECT_REVIEW.md)。
界面布局、模块色彩、术语和交互规范见 [docs/UI_DESIGN.md](docs/UI_DESIGN.md)。

Mac App Store 签名、隐私、元数据和提交流程见 [docs/app-store/APP_STORE_SUBMISSION.md](docs/app-store/APP_STORE_SUBMISSION.md)。

## 许可证

本项目采用 [MIT 许可证](LICENSE)。Copyright © 2025-2026 Linmu。

## 安全

如果你发现安全问题（凭证泄露、权限绕过、Wi-Fi 密码处理等），请不要在公开 issue 中披露细节，
请按 [SECURITY.md](SECURITY.md) 中的方式私密报告。

仓库不包含 token、API key、证书或签名私钥；CI 只使用 GitHub 自动生成的 `GITHUB_TOKEN`，
默认权限为只读。各平台的 Wi-Fi 密码分别存放在系统安全存储中，不会上传。

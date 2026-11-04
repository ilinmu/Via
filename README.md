# Via

<p align="center">
  <strong>Find the right way.</strong>
</p>

Via 是一款跨平台的 Wi-Fi 自动切换工具，帮助你在多个 Wi-Fi 网络之间智能切换。支持 macOS、Windows、iOS 和 Android。

你可以设置一个优先网络 `P` 和一个备用网络 `B`。当优先网络不可用时，Via 会自动切换到备用网络；当优先网络恢复后，再自动切回。

连接可以变化，体验不必改变。

## Why Via?

Via 源自拉丁语 via，意为「道路」「路径」或「通道」。

每一次网络连接，都是一次路径选择。当优先连接的 Wi-Fi 不可用时，Via 会自动寻找备用路径，保持网络连接；当优先网络恢复时，Via 又会带你回到熟悉的连接。

这个名字承载着一个简单的理念：始终找到更合适的连接方式。

Via 不需要你时刻关注网络切换，它会在后台默默寻找合适的路径，让连接保持顺畅，让你专注于真正重要的事情。

## Features

- 自动切换：优先网络不可用时，自动连接备用网络；优先网络恢复后，自动切回。
- 优先级管理：自定义优先网络 `P`和备用网络 `B`，让网络选择更符合自己的使用习惯。
- 手动切换识别：识别用户主动切换网络的行为，避免自动策略与用户操作相互干扰。
- 状态栏常驻：macOS 提供菜单栏常驻应用，通过状态图标直观展示当前状态。
- 网络扫描：扫描周围可用 Wi-Fi，帮助用户选择需要管理的网络。
- 首次设置向导：通过简单的三步流程完成权限授权、网络选择和自动切换设置。
- 中英文支持：支持中文与英文界面。
- 登录启动：支持随系统启动，无需每次手动打开。
- 简洁界面：跟随系统浅色或深色外观，按状态、网络和设置组织功能。
- 跨平台策略核心：使用 Rust 实现共享策略状态机，确保不同平台遵循一致的切换逻辑。

## How It Works

Via 使用两个网络配置实现自动切换：

| 网络  | 作用   | 行为             |
| --- | ---- | -------------- |
| `P` | 优先网络 | 始终优先连接，恢复后自动切回 |
| `B` | 备用网络 | `P` 不可用时自动连接   |

基本工作流程：

1. 应用读取当前连接的 SSID，并扫描周围可用的 Wi-Fi 网络。
2. 如果当前已经连接 `P`，则保持连接，不做额外切换。
3. 如果 `P` 不可用且当前未连接 `B`，则尝试连接 `B`。
4. 如果当前连接的是 `B`，Via 会按照设定的间隔继续扫描。
5. 一旦发现 `P` 恢复可用，Via 会自动切回 `P`。
6. 如果检测到用户主动切换网络，则暂停自动监控，避免与用户争夺网络控制权。

### Manual Override

Via 会区分自动切换和用户主动切换：

- 自动回退：当 `P` 不可见时，Via 自动切换到 `B`，继续监控，并在 `P` 恢复后自动切回。
- 手动覆盖：当 `P` 仍然可见时，如果用户主动切换到 `B` 或其他非受管网络，Via 会认为这是用户的主动选择，并暂停自动监控。

在 macOS 菜单栏图标上，手动覆盖状态会通过红色圆点提示。

这样既能保留自动切换的便利，也不会让自动化逻辑干扰用户自己的网络选择。

## Platforms

| 平台      | 项目目录                 | 技术方案                          | 主要能力                            |
| ------- | -------------------- | ----------------------------- | ------------------------------- |
| macOS   | `Sources/`           | SwiftUI、CoreWLAN              | 菜单栏应用、完整网络扫描与主动切换               |
| Windows | `platforms/windows/` | C#、WPF、WlanAPI                | 托盘应用、Windows Credential Manager |
| iOS     | `platforms/ios/`     | SwiftUI、Hotspot Configuration | 网络配置与前台监控                       |
| Android | `platforms/android/` | Kotlin、Compose                | 前台服务、通过系统 Wi-Fi 建议切换            |

> 各平台受操作系统公开 API 和权限机制限制，网络扫描、后台监控和主动切换能力可能有所不同。详细说明见 [跨平台能力说明](docs/CROSS_PLATFORM.md)。

## Getting Started

### Requirements

开发环境需要根据目标平台安装相应工具：

- macOS：Xcode、Swift、Rust。
- iOS：Xcode、Swift、Rust，以及 XcodeGen。
- Android：Android SDK、JDK、Gradle、Rust。
- Windows：Windows 开发环境、.NET SDK、Rust。

### Build

#### macOS

```
cargo build --manifest-path core/Cargo.toml -p via-ffi --release
scripts/package-app.sh
```

打包完成后，应用位于：

```
dist/Via.app
```

#### iOS

```
scripts/build-ios-core.sh
cd platforms/ios && xcodegen generate && cd ../..
```

#### Android

```
scripts/build-android-core.sh
cd platforms/android && gradle assembleRelease && cd ../..
```

#### Windows

请在 Windows 环境中执行：

```
./scripts/build-windows-core.ps1
dotnet publish platforms/windows/Via.Windows.csproj -c Release -p:Platform=x64 -o dist/windows-portable
```

### Run Tests

运行 Swift 测试：

```
swift test
```

运行 Rust Core 测试：

```
cargo test --manifest-path core/Cargo.toml
```

## CI / CD

项目使用 GitHub Actions 进行持续集成与构建，工作流配置位于：

```
.github/workflows/cross-platform.yml
```

目前工作流支持：

- Push 到 `master` 分支时触发。
- Pull Request 时触发。
- 执行 Rust、macOS Swift、iOS XCTest、Windows xUnit 和 Android JUnit 测试。
- 构建 macOS、Windows、iOS 和 Android 四个平台的产物。
- 仅修改文档的 Pull Request 会跳过平台构建任务。
- 连续推送时只保留最新一次工作流运行。

每次 `master`分支构建都会在 GitHub Releases 中生成对应版本，版本号格式为：

```
v1.0.<运行号>
```

Release 包含四个平台的构建产物。

## License

本项目采用 MIT License。

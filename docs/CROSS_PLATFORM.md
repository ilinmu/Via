# 跨平台说明

AutoWifi 目前在四个平台上提供客户端：

| 平台 | 目录 | 技术栈 | 产物 |
| --- | --- | --- | --- |
| macOS | 仓库根目录 `Sources/` | SwiftUI + AppKit + CoreWLAN | `dist/AutoWifi-macos.zip` |
| Windows | `platforms/windows/` | WPF (.NET Framework 4.8) + WlanAPI | `AutoWifi-windows-portable.exe`、`AutoWifi-windows-setup.exe` |
| iOS | `platforms/ios/` | SwiftUI + NetworkExtension | `AutoWifi-ios.xcarchive`（未签名） |
| Android | `platforms/android/` | Kotlin + Jetpack Compose | `AutoWifi-android.apk`（release，R8） |

四个客户端共用 `core/crates/autowifi-domain` 中的策略状态机。平台层只负责
“读取当前网络、扫描、发起关联、保存密码和展示状态”，不做切换决策。

## 共享核心与桥接

- `autowifi-domain`：纯逻辑状态机，不读时钟、不做 I/O、不接触密码。
- `autowifi-ffi`：C ABI，供 macOS、Windows、iOS 使用。
- `autowifi-jni`：JNI 桥，供 Android 使用；输入输出使用 JSON 字符串。
- `core/include/autowifi_core.h`：C ABI 的权威定义。

策略引擎的动作只有几类：扫描、关联、立即重新检查、停止、等待权限、写日志、
刷新状态。各平台按照自己的能力实现这些动作；无法实现的能力会在界面上说明。

## 平台能力与限制

| 能力 | macOS | Windows | iOS | Android |
| --- | --- | --- | --- | --- |
| 读取当前 SSID | CoreWLAN | WlanAPI | `NEHotspotNetwork.fetchCurrent`（需定位） | `WifiManager.connectionInfo`（需定位） |
| 扫描附近网络 | CoreWLAN | WlanAPI | 无公开 API | `startScan`（受系统限频） |
| 主动连接 | CoreWLAN | WLAN 配置文件 + `WlanConnect` | `NEHotspotConfiguration`（系统确认） | `WifiNetworkSuggestion`（系统决定） |
| 切换策略 | 完全由应用执行 | 完全由应用执行 | 只能请求加入，系统可拒绝 | 只能注册建议，系统决定时机 |
| 后台运行 | 菜单栏常驻 | 托盘常驻 | 仅前台 | 前台服务 |
| 密码存储 | Keychain | Windows Credential Manager | Keychain | EncryptedSharedPreferences |
| 权限 | 定位 | 无需额外授权 | 定位、热点配置、Wi-Fi 信息 | 定位 / 附近设备、通知 |

### iOS

iOS 没有公开的 Wi-Fi 扫描 API，也不能静默强制切换网络。应用使用
`NEHotspotConfigurationManager` 请求加入 P 或 B，系统会显示确认；自动切换只在
应用处于前台时运行。配置向导会明确说明这些限制。

### Android

Android 10 之后应用不能通过 `WifiManager` 直接连接网络。应用把 P/B 注册为
`WifiNetworkSuggestion`，由系统根据信号和策略选择；扫描在后台受频率限制，
应用会缓存最近一次结果。监控通过 `connectedDevice` 类型的前台服务运行，并在
通知栏持续显示。

### Windows

Windows 使用 WlanAPI：先写入 P/B 的 WLAN 配置文件，再调用 `WlanConnect`，
轮询当前 SSID 判断结果。密码存放在 Windows Credential Manager，开机启动通过
当前用户的 `Run` 注册表项实现。

### macOS

macOS 版本保留原有 CoreWLAN 实现和菜单栏体验；共享核心通过 `dlopen` 加载
`libautowifi_core.dylib`。

## 本地构建

### 前置条件

- Rust stable（四个平台共用）。
- macOS / iOS：Xcode 15 或更新版本；iOS 另需 XcodeGen。
- Windows：.NET Framework 4.8（Windows 10 1903+ / Windows 11 自带），构建机需要
  .NET SDK；`Microsoft.NETFramework.ReferenceAssemblies` 会补齐引用程序集。
- Android：JDK 17、Android SDK 35、NDK 27、Gradle 8.10+、`cargo-ndk`。

### macOS

```bash
cargo build --manifest-path core/Cargo.toml -p autowifi-ffi --release
scripts/package-app.sh
```

### Windows

```powershell
./scripts/build-windows-core.ps1

# 免安装单文件（约 1 MB；.NET Framework 4.8 是 Windows 自带组件）
dotnet publish platforms/windows/AutoWifi.Windows.csproj `
  -c Release -p:Platform=x64 -o dist/windows-portable

# 安装程序：发布同一应用的目录，再用 Inno Setup 打包
dotnet publish platforms/windows/AutoWifi.Windows.csproj `
  -c Release -p:Platform=x64 -o dist/windows-app
ISCC.exe /DAppVersion=1.0.0 platforms/windows/installer.iss
```

### iOS

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
scripts/build-ios-core.sh
cd platforms/ios
xcodegen generate
xcodebuild -project AutoWifi.xcodeproj -scheme AutoWifi \
  -sdk iphonesimulator -configuration Release build
```

在真机上运行需要在 Xcode 中配置开发团队和
`com.apple.developer.networking.HotspotConfiguration` 能力。

### Android

```bash
cargo install cargo-ndk
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
scripts/build-android-core.sh
cd platforms/android
gradle assembleRelease
```

APK 输出在 `platforms/android/app/build/outputs/apk/release/`。release 构建启用 R8
代码压缩和资源裁剪，并用调试密钥签名（仅用于测试）；需要发布到商店时替换签名配置。

## 应用图标

四个平台共用一套图标：蓝色渐变背景、缩小的 Wi-Fi 标记和“Auto”字样。图标由
`scripts/generate-app-icons.swift` 统一渲染，输出 macOS 的
`icon_1024x1024.png`、iOS 的 Asset Catalog、Windows 的 `Assets/app.ico`（多尺寸
ICO）以及 Android 的自适应图标前景（`mipmap-*/ic_launcher_foreground.png`）。
修改图标时重新运行该脚本，不要手工编辑各平台副本：

```bash
swift scripts/generate-app-icons.swift
```

## 状态图标

四个平台使用同一套状态规则：

| 状态 | 图标 |
| --- | --- |
| 监控运行中，已连接优先网络 | Wi-Fi 标记 + `P` |
| 监控运行中，已连接备用网络 | Wi-Fi 标记 + `B` |
| 监控运行中，未连接 P/B | 仅 Wi-Fi 标记 |
| 监控已关闭 | Wi-Fi 标记 + 红点 |

- macOS：菜单栏图标，图标与文字随菜单栏明暗切换黑/白。
- Windows：通知区域（托盘）图标，随任务栏明暗切换黑/白，悬停显示当前网络与角色。
- Android：通知栏只使用应用自己的普通通知小图标，不再叠加 P/B 或红点；当前网络
  和角色由通知文字表达，不显示检查倒计时。
- iOS：系统不允许第三方应用在状态栏放图标，因此在应用内“当前连接”卡片使用同一套
  状态图标；状态栏仍由系统显示原生 Wi-Fi 图标。

Android 的系统 Wi-Fi 图标由 SystemUI 绘制，第三方应用没有隐藏它的接口；ColorOS
也没有提供单独隐藏 Wi-Fi 图标的开关。应用只能在自身界面内隐藏状态栏，无法只隐藏
系统 Wi-Fi 图标。

## 首次运行

macOS、iOS、Android 和 Windows 在配置不完整时都会引导用户完成设置。macOS 和
iOS 使用面板内的三步向导，Android 使用全屏向导（授权定位 → 选择 P/B → 开启
监控），Windows 使用独立的设置窗口（欢迎 → 选择网络 → 完成）。配置完整且完成后
向导不再自动出现；标记丢失或配置为空时仍会进入向导。各平台都可以在设置里重新运行。

## GitHub Actions

`.github/workflows/cross-platform.yml` 在 push 到 `master`、pull request 和手动触发时
运行。PR 分支只通过 `pull_request` 触发，避免同一个提交跑两遍；连续推送时新的运行会
取消旧的运行，而 `master` 上的每次提交都会完整运行。

测试和构建互不依赖，因此同时开始，整条流水线的耗时由最慢的 job 决定。只修改
Markdown 或 `docs/` 的 PR 会跳过所有平台 job（`Detect changes` 仍会报告结果），
`master` 和手动触发不受影响。

1. `core-tests`：Rust 格式检查和 workspace 测试（Ubuntu）。
2. `macos-tests`：构建策略核心并运行 `swift test`（macOS）。
3. 平台测试：
   - `windows-tests`：编译 Rust DLL 并运行 `platforms/windows.tests` 的 xUnit 测试（Windows）。
   - `ios-tests`：构建 XCFramework，在 iOS 模拟器上运行 XCTest（macOS）。
   - `android-tests`：运行 `gradle testDebugUnitTest`（Ubuntu）。
4. 同时构建四个平台的产物：
   - `build-macos`：打包未签名 `.app` 并压缩为 `AutoWifi-macos.zip`。
   - `build-ios`：构建 XCFramework、生成 Xcode 工程、模拟器编译并归档未签名设备包。
   - `build-windows`：编译 Rust DLL，`dotnet publish` .NET Framework 4.8 产物，再生成免安装单文件和 Inno Setup 安装包。
   - `build-android`：用 `cargo-ndk` 生成三种 ABI 的 `.so`，Gradle 构建 R8 压缩的 release APK（debug 签名）。

Rust 构建用 `Swatinem/rust-cache` 缓存，.NET 用 `actions/cache` 缓存 NuGet 包，
Gradle 由 `gradle/actions/setup-gradle` 缓存依赖和构建结果。Android SDK、NDK 和
`cargo-ndk` 直接使用 runner 镜像自带的版本，缺省时再下载预编译二进制。

`master` 上的每次完整构建还会运行 `release` job：它汇总四个平台的产物，创建
标签为 `v<版本>.<运行号>` 的 GitHub Release，例如 `v1.0.42`。标签随运行号递增，
不同构建不会互相覆盖；版本号来自工作流的 `APP_VERSION`。PR 构建只上传
artifacts，不会创建 Release。

所有构建产物通过 `actions/upload-artifact` 保留 14 天。可以手动触发
`workflow_dispatch` 重新运行。

## 发布说明

`master` 每次构建都会在 GitHub Releases 中生成一个版本，包含四个平台的压缩包
或安装包。这些是未签名的自动构建，适合内部测试；正式发布仍需要下面的签名流程。

- Windows 产物未签名，首次运行可能出现 SmartScreen 提示；正式发布需要代码签名证书。
- iOS 归档未签名，仅用于验证编译；上架或真机安装需要 Apple Developer 团队和描述文件。
- Android release APK 经 R8 压缩，使用调试签名；发布到应用商店需要配置 release keystore 并替换签名配置。
- macOS 默认使用 ad-hoc 签名；正式分发需要 Developer ID 或 Mac App Store 流程，
  参见 [app-store/APP_STORE_SUBMISSION.md](app-store/APP_STORE_SUBMISSION.md)。

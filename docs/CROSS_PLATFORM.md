# 跨平台说明

AutoWifi 目前在四个平台上提供客户端：

| 平台 | 目录 | 技术栈 | 产物 |
| --- | --- | --- | --- |
| macOS | 仓库根目录 `Sources/` | SwiftUI + AppKit + CoreWLAN | `dist/AutoWifi-macos.zip` |
| Windows | `platforms/windows/` | WPF (.NET 8) + WlanAPI | `dist/windows/AutoWifi.exe` |
| iOS | `platforms/ios/` | SwiftUI + NetworkExtension | `AutoWifi-ios.xcarchive`（未签名） |
| Android | `platforms/android/` | Kotlin + Jetpack Compose | `app-debug.apk` |

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
- Windows：.NET 8 SDK。
- Android：JDK 17、Android SDK 35、NDK 27、Gradle 8.10+、`cargo-ndk`。

### macOS

```bash
cargo build --manifest-path core/Cargo.toml -p autowifi-ffi --release
scripts/package-app.sh
```

### Windows

```powershell
./scripts/build-windows-core.ps1
dotnet publish platforms/windows/AutoWifi.Windows.csproj `
  -c Release -r win-x64 --self-contained false -o dist/windows
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
gradle assembleDebug
```

APK 输出在 `platforms/android/app/build/outputs/apk/debug/`。

## GitHub Actions

`.github/workflows/cross-platform.yml` 在每次 push 和 pull request 时运行：

1. `core-tests`：Rust 格式检查和 workspace 测试（Ubuntu）。
2. `macos-tests`：构建策略核心并运行 `swift test`（macOS）。
3. 测试通过后并行构建四个平台：
   - `build-macos`：打包未签名 `.app` 并压缩为 `AutoWifi-macos.zip`。
   - `build-ios`：构建 XCFramework、生成 Xcode 工程、模拟器编译并归档未签名设备包。
   - `build-windows`：编译 Rust DLL，`dotnet publish` 自包含关闭的 `win-x64` 产物。
   - `build-android`：用 `cargo-ndk` 生成三种 ABI 的 `.so`，Gradle 构建 debug APK。

所有构建产物通过 `actions/upload-artifact` 保留 14 天。可以手动触发
`workflow_dispatch` 重新运行。

## 发布说明

- Windows 产物未签名，首次运行可能出现 SmartScreen 提示；正式发布需要代码签名证书。
- iOS 归档未签名，仅用于验证编译；上架或真机安装需要 Apple Developer 团队和描述文件。
- Android debug APK 使用调试签名；发布到应用商店需要配置 release keystore。
- macOS 默认使用 ad-hoc 签名；正式分发需要 Developer ID 或 Mac App Store 流程，
  参见 [app-store/APP_STORE_SUBMISSION.md](app-store/APP_STORE_SUBMISSION.md)。

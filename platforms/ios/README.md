# iOS 客户端

SwiftUI 客户端，使用共享 Rust 策略核心和 `NEHotspotConfigurationManager`。

## 结构

- `project.yml`：XcodeGen 工程定义（iOS 16+）。
- `Via/PolicyCore.swift`：C ABI 的 Swift 封装。
- `Via/WifiController.swift`：状态、定时检查、加入网络。
- `Via/ContentView.swift`：状态 / 网络 / 设置三个 Tab 和三步向导。
- `Via/KeychainStore.swift`：钥匙串密码存储。
- `Via/Via.entitlements`：Hotspot Configuration 与 Wi-Fi Info 能力。
- `Via/Assets.xcassets/AppIcon.appiconset`：应用图标，由
  `scripts/generate-app-icons.swift` 生成。

## 测试

```bash
scripts/build-ios-core.sh
cd platforms/ios && xcodegen generate && cd ../..
xcodebuild test -project platforms/ios/Via.xcodeproj -scheme Via \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

`ViaTests` 是宿主应用测试 target，覆盖 `L10n` 与共享策略核心的 C ABI 封装。

## 构建

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
scripts/build-ios-core.sh
cd platforms/ios
xcodegen generate
xcodebuild -project Via.xcodeproj -scheme Via \
  -sdk iphonesimulator -configuration Release build
```

`scripts/build-ios-core.sh` 会把 `libvia_core.a` 和头文件打包到
`platforms/ios/Frameworks/ViaCore.xcframework`。

## 真机运行

1. 在 `project.yml` 中填入 `DEVELOPMENT_TEAM`，或直接在 Xcode 里选择团队。
2. 为 `io.github.ilinmu.via` 创建 App ID，并启用 Hotspot Configuration 与
   Access Wi-Fi Information 能力。
3. 使用描述文件签名后安装。

## iOS 限制

- 没有公开的 Wi-Fi 扫描 API，界面不提供扫描列表，需要手动输入 SSID 或使用当前网络。
- 加入网络会弹出系统确认；用户拒绝时按连接失败处理。
- 应用进入后台后定时器停止，自动切换只在应用打开时运行。
- iOS 不允许应用在状态栏放置图标；与 macOS 菜单栏图标相同的状态图标（Wi-Fi +
  P/B/红点）显示在应用内“当前连接”卡片上。
- `NEHotspotNetwork.fetchCurrent` 需要定位权限；未授权时无法读取当前 SSID。

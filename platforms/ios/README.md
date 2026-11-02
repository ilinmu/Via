# iOS 客户端

SwiftUI 客户端，使用共享 Rust 策略核心和 `NEHotspotConfigurationManager`。

## 结构

- `project.yml`：XcodeGen 工程定义（iOS 16+）。
- `AutoWifi/PolicyCore.swift`：C ABI 的 Swift 封装。
- `AutoWifi/WifiController.swift`：状态、定时检查、加入网络。
- `AutoWifi/ContentView.swift`：状态 / 网络 / 设置三个 Tab 和三步向导。
- `AutoWifi/KeychainStore.swift`：钥匙串密码存储。
- `AutoWifi/AutoWifi.entitlements`：Hotspot Configuration 与 Wi-Fi Info 能力。

## 构建

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
scripts/build-ios-core.sh
cd platforms/ios
xcodegen generate
xcodebuild -project AutoWifi.xcodeproj -scheme AutoWifi \
  -sdk iphonesimulator -configuration Release build
```

`scripts/build-ios-core.sh` 会把 `libautowifi_core.a` 和头文件打包到
`platforms/ios/Frameworks/AutoWifiCore.xcframework`。

## 真机运行

1. 在 `project.yml` 中填入 `DEVELOPMENT_TEAM`，或直接在 Xcode 里选择团队。
2. 为 `com.autowifi.ios` 创建 App ID，并启用 Hotspot Configuration 与
   Access Wi-Fi Information 能力。
3. 使用描述文件签名后安装。

## iOS 限制

- 没有公开的 Wi-Fi 扫描 API，界面不提供扫描列表，需要手动输入 SSID 或使用当前网络。
- 加入网络会弹出系统确认；用户拒绝时按连接失败处理。
- 应用进入后台后定时器停止，自动切换只在应用打开时运行。
- `NEHotspotNetwork.fetchCurrent` 需要定位权限；未授权时无法读取当前 SSID。

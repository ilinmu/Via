# AutoWifi 开发与打包指南

## 1. 先理解这个项目是什么

AutoWifi 是一个 macOS 菜单栏应用，用来在两个 Wi-Fi 之间做自动切换：

- `P`：优先网络
- `B`：备用网络

它的目标不是通用网络管理，而是解决“优先连主 Wi-Fi，主 Wi-Fi 不可用时自动切到备用，恢复后再切回”的场景。

## 2. 开发前需要的环境

建议本地环境：

- macOS 13 或更高
- Xcode 15+/Command Line Tools
- Swift 6 工具链

先确认命令可用：

```bash
swift --version
xcodebuild -version
```

## 3. 仓库结构与开发入口

这个仓库当前是一个 **Swift Package**，不是 Xcode 工程。最重要的入口如下：

- [Package.swift](/Users/linmu/git/auto-wifi/Package.swift)
  项目的构建入口，定义了可执行目标 `AutoWifi`、核心库 `AutoWifiCore` 和测试目标。
- [Sources/AutoWifi/main.swift](/Users/linmu/git/auto-wifi/Sources/AutoWifi/main.swift)
  菜单栏应用入口，负责状态栏图标、弹出面板和 App 生命周期。
- [Sources/AutoWifiCore/AppState.swift](/Users/linmu/git/auto-wifi/Sources/AutoWifiCore/AppState.swift)
  应用状态中心，负责配置持久化、密码本地存储、开机启动状态等。
- [Sources/AutoWifiCore/WifiManager.swift](/Users/linmu/git/auto-wifi/Sources/AutoWifiCore/WifiManager.swift)
  核心业务逻辑入口，负责 Wi-Fi 扫描、自动切换、定时检测和权限相关逻辑。
- [Sources/AutoWifiCore/SettingsView.swift](/Users/linmu/git/auto-wifi/Sources/AutoWifiCore/SettingsView.swift)
  配置面板 UI。
- [Sources/AutoWifiCore/LaunchAtLoginManager.swift](/Users/linmu/git/auto-wifi/Sources/AutoWifiCore/LaunchAtLoginManager.swift)
  登录启动逻辑封装。
- [Tests/AutoWifiTests/AutoWifiTests.swift](/Users/linmu/git/auto-wifi/Tests/AutoWifiTests/AutoWifiTests.swift)
  回归测试入口。

如果你是第一次接手，推荐按下面顺序读代码：

1. 先看 [README.md](/Users/linmu/git/auto-wifi/README.md) 理解项目目标。
2. 再看 [Package.swift](/Users/linmu/git/auto-wifi/Package.swift) 确认目标结构。
3. 读 [Sources/AutoWifi/main.swift](/Users/linmu/git/auto-wifi/Sources/AutoWifi/main.swift) 了解应用怎么启动。
4. 读 [Sources/AutoWifiCore/AppState.swift](/Users/linmu/git/auto-wifi/Sources/AutoWifiCore/AppState.swift) 和 [Sources/AutoWifiCore/WifiManager.swift](/Users/linmu/git/auto-wifi/Sources/AutoWifiCore/WifiManager.swift) 了解状态与核心逻辑。
5. 最后看 [Sources/AutoWifiCore/SettingsView.swift](/Users/linmu/git/auto-wifi/Sources/AutoWifiCore/SettingsView.swift) 了解 UI 绑定方式。

## 4. 本地开发从哪里开始

### 4.1 先跑测试

推荐每次接手先跑一遍测试：

```bash
swift test
```

这一步主要用来确认：

- Swift 工具链可用
- 当前代码能编译
- 核心自动切换逻辑没有明显回归

### 4.2 本地构建可执行文件

```bash
swift build
```

调试构建产物一般会在 `.build/.../debug/AutoWifi`。

### 4.3 启动应用做联调

可以直接运行可执行文件：

```bash
swift run AutoWifi
```

或者先构建再运行生成的二进制。

注意：

- 这是菜单栏应用，启动后主要在菜单栏显示，不会像普通 App 一样出现在 Dock。
- 首次运行如果没有定位权限，SSID 读取和 Wi-Fi 扫描会失败。

### 4.4 快速验证 CLI 版本

项目里还保留了一个命令行版本，适合做快速逻辑验证：

```bash
swiftc -typecheck auto-wifi-cli.swift
swift auto-wifi-cli.swift
```

## 5. 常见开发任务从哪里改

### 5.1 改 Wi-Fi 自动切换策略

优先看：

- [Sources/AutoWifiCore/WifiManager.swift](/Users/linmu/git/auto-wifi/Sources/AutoWifiCore/WifiManager.swift)

这里包含：

- 扫描当前网络
- 定时检测
- 在 `P/B` 间切换
- 用户手动切网时停止监控

### 5.2 改设置项持久化或默认值

优先看：

- [Sources/AutoWifiCore/AppState.swift](/Users/linmu/git/auto-wifi/Sources/AutoWifiCore/AppState.swift)

这里包含：

- `UserDefaults` 配置项
- 本地密码存储
- 检查间隔规范化
- 登录启动开关

### 5.3 改 UI 或交互

优先看：

- [Sources/AutoWifiCore/SettingsView.swift](/Users/linmu/git/auto-wifi/Sources/AutoWifiCore/SettingsView.swift)
- [Sources/AutoWifi/main.swift](/Users/linmu/git/auto-wifi/Sources/AutoWifi/main.swift)

前者是弹出面板内容，后者是菜单栏图标、窗口和 App 生命周期。

### 5.4 改文案与多语言

优先看：

- [Sources/AutoWifiCore/LocalizationManager.swift](/Users/linmu/git/auto-wifi/Sources/AutoWifiCore/LocalizationManager.swift)

## 6. 开发时需要注意的系统特性

### 6.1 定位权限

macOS 会把 SSID 和 Wi-Fi 扫描结果视作定位相关信息，所以项目必须依赖：

- `NSLocationWhenInUseUsageDescription`
- 定位权限授权

相关配置在：

- [AutoWifi/Info.plist](/Users/linmu/git/auto-wifi/AutoWifi/Info.plist)

### 6.2 登录启动

项目使用 `ServiceManagement` 的 `SMAppService.mainApp` 管理开机启动。

这意味着：

- 需要以 `.app` 形式运行时才更接近真实行为
- 最终交付版本最好放到 `/Applications`

### 6.3 本地密码存储与签名

项目当前把 Wi-Fi 密码保存在应用本地存储中，不访问 macOS Keychain，因此不会触发钥匙串访问提示。

需要注意：

- 这种方式的体验更直接，但安全性弱于 Keychain。
- 如果后续要重新提高密码保护等级，可以再评估加密存储或重新接入 Keychain。
- 打包签名依然只和发布体验、系统信任链有关，不影响本地密码存储机制。

## 7. 当前项目怎么打包

### 7.1 当前项目的打包思路

这个仓库没有现成的 Xcode 工程或 CI 打包流程，因此当前打包方式是：

1. 用 SwiftPM 构建 release 可执行文件
2. 组装 `.app` bundle 目录
3. 写入 `Info.plist`
4. 生成 `.icns` 图标
5. 可选地进行 codesign
6. 输出 zip 包

我已经把这套流程整理成脚本：

- [scripts/package-app.sh](/Users/linmu/git/auto-wifi/scripts/package-app.sh)

### 7.2 一键打包

最简单的本地打包方式：

```bash
scripts/package-app.sh
```

如果你的目标只是“本地生成一个可以双击的 `.app`”，这条命令就够了。执行完成后，主要关注这个输出：

- `dist/AutoWifi.app`

默认行为：

- 构建 `release`
- 输出到 `dist/AutoWifi.app`
- 生成 `dist/AutoWifi-macos.zip`
- 使用 ad-hoc 签名（`SIGN_IDENTITY=-`）

可以直接本地打开：

```bash
open dist/AutoWifi.app
```

如果想放到应用程序目录再测试：

```bash
cp -R dist/AutoWifi.app /Applications/
```

然后从“应用程序”里启动，或者执行：

```bash
open /Applications/AutoWifi.app
```

### 7.3 跳过签名

如果只是本地验证结构，不想签名：

```bash
SIGN_IDENTITY="" scripts/package-app.sh
```

### 7.4 使用正式证书签名

如果你已经有 Developer ID 证书：

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/package-app.sh
```

### 7.5 自定义版本号

```bash
VERSION="1.0.1" BUILD_NUMBER="12" scripts/package-app.sh
```

### 7.6 打包输出

脚本默认会输出：

- `dist/AutoWifi.app`
- `dist/AutoWifi-macos.zip`

其中：

- `.app` 是本地运行和手工安装时最直接使用的产物
- `.zip` 适合发给别人下载测试

### 7.7 如果只关心本地 `.app`

本地最短路径可以记成这三步：

1. 在仓库根目录执行 `scripts/package-app.sh`
2. 产物在 `dist/AutoWifi.app`
3. 用 `open dist/AutoWifi.app` 启动，或者拖到 `/Applications`

## 8. 打包脚本内部做了什么

脚本会使用这些仓库内文件作为输入：

- [AutoWifi/Info.plist](/Users/linmu/git/auto-wifi/AutoWifi/Info.plist)
- [AutoWifi/AutoWifi.entitlements](/Users/linmu/git/auto-wifi/AutoWifi/AutoWifi.entitlements)
- [AutoWifi/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png](/Users/linmu/git/auto-wifi/AutoWifi/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png)

它会自动处理几件事：

- 把模板里的 `CFBundleExecutable`、`CFBundleName` 等字段替换成真实值
- 删除不适用于当前代码启动方式的 `NSMainStoryboardFile`
- 从 1024 PNG 生成 `.icns`
- 用 `codesign` 为 `.app` 进行签名
- 生成 zip

## 9. 发布前建议再做的事情

如果要把它发给别的用户，而不是只在自己机器上用，建议再补这些步骤：

- 使用正式 Developer ID 证书签名
- 做 notarization
- 在干净机器上验证首次启动、定位授权、登录启动
- 把 App 拷到 `/Applications` 后再验证一次

当前仓库里还没有自动化 notarization 脚本，这一步目前需要单独加。

## 10. 推荐的日常开发流程

一个比较稳妥的日常节奏是：

1. `git pull` 或切到工作分支
2. `swift test`
3. 修改核心逻辑或 UI
4. 再跑一次 `swift test`
5. 需要体验真实行为时运行 `swift run AutoWifi`
6. 需要交付测试包时执行 `scripts/package-app.sh`

## 11. 常见排查思路

### 11.1 扫描不到网络

先检查：

- 定位权限是否允许
- `Info.plist` 是否保留了定位说明
- 当前是否真的有 Wi-Fi 接口

### 11.2 登录启动不生效

先检查：

- 是否是以 `.app` 形式运行
- 是否放在稳定路径，如 `/Applications`
- 是否做过签名

### 11.3 打包后图标不对

先检查：

- `AutoWifi/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png` 是否存在
- 本机是否有 `sips` 和 `iconutil`

## 12. 补充说明

这份指南是基于当前仓库实际结构整理的，重点是帮助新接手的人快速回答三个问题：

- 代码应该先看哪里
- 本地怎么跑起来
- 当前仓库如何打包交付

如果后面项目切换到 Xcode 工程或加入 CI/CD，建议同步更新这份文档。

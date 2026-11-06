# Via 开发与打包指南

## 1. 先理解这个项目是什么

Via 是一个 macOS 菜单栏应用，用来在两个 Wi-Fi 之间做自动切换：

- `P`：优先网络
- `B`：备用网络

它的目标不是通用网络管理，而是解决“优先连主 Wi-Fi，主 Wi-Fi 不可用时自动切到备用，恢复后再切回”的场景。

## 2. 开发前需要的环境

建议本地环境：

- macOS 13 或更高
- Xcode 15+/Command Line Tools
- Swift 6 工具链
- Rust 工具链（建议 1.75+，用于构建共享策略核心）

先确认命令可用：

```bash
swift --version
xcodebuild -version
cargo --version
```

## 3. 仓库结构与开发入口

这个仓库当前是一个 **Swift Package**，不是 Xcode 工程。最重要的入口如下：

- [Package.swift](../Package.swift)
  项目的构建入口，定义了可执行目标 `Via`、核心库 `ViaCore` 和测试目标。
- [Sources/Via/main.swift](../Sources/Via/main.swift)
  菜单栏应用入口，负责状态栏图标、弹出面板和 App 生命周期。
- [Sources/ViaCore/AppState.swift](../Sources/ViaCore/AppState.swift)
  应用状态中心，负责配置持久化、开机启动状态和网络状态发布。
- [Sources/ViaCore/CredentialStore.swift](../Sources/ViaCore/CredentialStore.swift)
  Wi-Fi 密码的 Keychain 读写与旧数据迁移。
- [Sources/ViaCore/WifiManager.swift](../Sources/ViaCore/WifiManager.swift)
  核心业务逻辑入口，负责 Wi-Fi 扫描、自动切换、定时检测和权限相关逻辑。
- [Sources/ViaCore/WifiPolicy.swift](../Sources/ViaCore/WifiPolicy.swift)
  共享策略核心的 Swift 封装，通过 `dlopen` 加载 Rust 动态库。
- [core/README.md](../core/README.md)
  跨平台策略核心的目录结构、C ABI 约定与接入方式。
- [Sources/Via/SettingsView.swift](../Sources/Via/SettingsView.swift)
  配置面板 UI。
- [Sources/ViaCore/LaunchAtLoginManager.swift](../Sources/ViaCore/LaunchAtLoginManager.swift)
  登录启动逻辑封装。
- [Tests/ViaTests/ViaTests.swift](../Tests/ViaTests/ViaTests.swift)
  回归测试入口。

如果你是第一次接手，推荐按下面顺序读代码：

1. 先看 [README.md](../README.md) 理解项目目标。
2. 再看 [Package.swift](../Package.swift) 确认目标结构。
3. 读 [Sources/Via/main.swift](../Sources/Via/main.swift) 了解应用怎么启动。
4. 读 [Sources/ViaCore/AppState.swift](../Sources/ViaCore/AppState.swift) 和 [Sources/ViaCore/WifiManager.swift](../Sources/ViaCore/WifiManager.swift) 了解状态与核心逻辑。
5. 读 [core/README.md](../core/README.md) 了解共享策略核心的边界和接入方式。
6. 最后看 [Sources/Via/SettingsView.swift](../Sources/Via/SettingsView.swift) 了解 UI 绑定方式。
7. 涉及界面时读 [docs/UI_DESIGN.md](UI_DESIGN.md) 了解视觉与术语约束。

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

策略核心有独立的 Rust 测试：

```bash
cargo test --manifest-path core/Cargo.toml
```

再构建动态库并跑 C ABI 冒烟：

```bash
scripts/build-core.sh
swift run PolicySmoke
```

`PolicySmoke` 成功时输出 `policy smoke ok`。如果只想验证 C ABI，也可以直接
编译 `core/tests/ffi_smoke.c`，具体命令见 [core/README.md](../core/README.md)。

### 4.2 本地构建可执行文件

```bash
swift build
```

调试构建产物一般会在 `.build/.../debug/Via`。

如果当前 Command Line Tools 的 SDK 缺少 `libSwiftUIMacros.dylib`，SwiftUI 宏会在编译时报错。可以手动指定较旧的 SDK：

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift build
```

`scripts/package-app.sh` 会自动检测并回退到可用 SDK，本地打包时不需要手动设置。

### 4.3 启动应用做联调

可以直接运行可执行文件：

```bash
swift run Via
```

或者先构建再运行生成的二进制。

注意：

- 这是菜单栏应用，启动后主要在菜单栏显示，不会像普通 App 一样出现在 Dock。
- 首次运行如果没有定位权限，SSID 读取和 Wi-Fi 扫描会失败。

### 4.4 快速验证 CLI 版本

项目里还保留了一个命令行版本，适合做快速逻辑验证：

```bash
swiftc -typecheck via-cli.swift
swift via-cli.swift <SSID-P> <SSID-B> [interval-seconds]
```

密码会在终端中以隐藏回显方式提示输入，不再接受命令行密码参数，避免出现在 `ps` 或 Shell 历史中。

## 5. 常见开发任务从哪里改

### 5.1 改 Wi-Fi 自动切换策略

策略决定优先改共享核心：

- [core/crates/via-domain/src/engine.rs](../core/crates/via-domain/src/engine.rs)

这里包含：

- 扫描时机
- 在 `P/B` 间切换的条件
- 关联超时、冷却与代次
- 用户手动切网的识别
- 权限与配置变化的处理

改完必须同步：

- [core/crates/via-domain/src/model.rs](../core/crates/via-domain/src/model.rs)
  中的动作、事件与状态类型
- [core/crates/via-ffi/src/lib.rs](../core/crates/via-ffi/src/lib.rs)
  和 [core/include/via_core.h](../core/include/via_core.h)
  的 C ABI 映射；扫描结果是 `1/0/-1` 三态，关联结果 `3` 表示建议结束
- [core/crates/via-jni/src/lib.rs](../core/crates/via-jni/src/lib.rs)
  的 Android JNI 映射，以及各平台调用点
- [Sources/ViaCore/WifiPolicy.swift](../Sources/ViaCore/WifiPolicy.swift)
  的 Swift 枚举与结构

平台 API 的调用仍看：

- [Sources/ViaCore/WifiManager.swift](../Sources/ViaCore/WifiManager.swift)

当前主检查流程尚未完全迁移到核心；修改策略时要注意 Swift 分支与 Rust 测试
保持一致，避免两边行为分叉。

### 5.2 改设置项持久化或默认值

优先看：

- [Sources/ViaCore/AppState.swift](../Sources/ViaCore/AppState.swift)

这里包含：

- `UserDefaults` 配置项
- Keychain 密码存储（`CredentialStore`）
- 检查间隔规范化
- 登录启动开关

### 5.3 改 UI 或交互

优先看：

- [Sources/Via/SettingsView.swift](../Sources/Via/SettingsView.swift)：面板外壳、Tab 栏、横幅、路由和高度测量
- [Sources/Via/main.swift](../Sources/Via/main.swift)：菜单栏图标、窗口、面板高度上限和 App 生命周期
- [Sources/Via/Models/](../Sources/Via/Models)：`PanelModel`、`NetworkDraft`、`PanelMetrics`
- [Sources/Via/Tabs/](../Sources/Via/Tabs) 与 [Sources/Via/Onboarding/](../Sources/Via/Onboarding)

当前 UI 跟随系统外观，按三个 Tab 组织，并在配置不完整时显示三步向导。修改前先阅读：

- [docs/UI_DESIGN.md](UI_DESIGN.md)

需要保持的约束包括：

- 面板宽度为 400 点，高度动态测量，最低 360 点，最高取屏幕可用高度且不超过 680 点。
- 只使用系统语义颜色和 `DesignSystem/PanelLayout.swift` 中的令牌；系统蓝是唯一强调色。
- 功能属于“状态 / 网络 / 设置”三个 Tab 之一，不新增固定模块或深色主题。
- 网络编辑走 `NetworkDraft` + 显式保存；不要改回每个按键直接写 `AppState`。
- 自动切换的开始操作以“配置完整 + 定位权限始终”为前提；`isStarting` 用于防重入。
- 底层接口名和原始运行日志不应直接作为状态 Tab 的文案。
- 新增或修改文案时同步补齐中英文 Key；缺失 Key 会直接显示 Key。

### 5.4 改文案与多语言

优先看：

- [Sources/ViaCore/LocalizationManager.swift](../Sources/ViaCore/LocalizationManager.swift)

## 6. 开发时需要注意的系统特性

### 6.1 定位权限

macOS 会把 SSID 和 Wi-Fi 扫描结果视作定位相关信息，所以项目必须依赖：

- `NSLocationWhenInUseUsageDescription`
- 定位权限授权

相关配置在：

- [Via/Info.plist](../Via/Info.plist)

### 6.2 登录启动

项目使用 `ServiceManagement` 的 `SMAppService.mainApp` 管理开机启动。

这意味着：

- 需要以 `.app` 形式运行时才更接近真实行为
- 最终交付版本最好放到 `/Applications`

### 6.3 本地密码存储与签名

Wi-Fi 密码通过 `Security` 框架写入当前用户登录钥匙串的通用密码项（generic password），服务名为 `io.github.ilinmu.via`，账户名为 `passwordP` / `passwordB`。应用不会把密码上传到网络服务。

需要注意：

- 沙盒应用使用自身默认的钥匙串访问组即可读写自己创建的密码项，不需要额外的 keychain access group；如需跨应用共享才需要声明 `keychain-access-groups`。
- 旧版本把密码明文写在 `UserDefaults` 的 `passwordP` / `passwordB` 键中。首次启动时 `AppState` 会读取这些旧值写入钥匙串，并在回读校验成功后删除旧键；如果钥匙串写入或读取失败，会保留旧明文并在设置面板显示警告，下次启动自动重试。
- 密码输入采用 400ms 防抖，应用退出前调用 `flushPendingPasswordSaves()` 立即落盘；写入失败同样会显示可见警告。
- 未签名的本地调试构建也能使用默认钥匙串；正式发布仍应使用签名后的 `.app`，避免每次构建被系统视为不同应用。

## 7. 当前项目怎么打包

### 7.1 当前项目的打包思路

这个仓库没有现成的 Xcode 工程或 CI 打包流程，因此当前打包方式是：

1. 用 Cargo 构建共享策略核心 `libvia_core.dylib`
2. 用 SwiftPM 构建 release 可执行文件
3. 组装 `.app` bundle 目录，把动态库放进 `Contents/Frameworks/`
4. 写入 `Info.plist`
5. 生成 `.icns` 图标
6. 先签名动态库，再签名 App
7. 输出 zip 包

我已经把这套流程整理成脚本：

- [scripts/package-app.sh](../scripts/package-app.sh)

### 7.2 一键打包

最简单的本地打包方式：

```bash
scripts/package-app.sh
```

如果你的目标只是“本地生成一个可以双击的 `.app`”，这条命令就够了。执行完成后，主要关注这个输出：

- `dist/Via.app`

默认行为：

- 先构建 release 策略核心，并复制到 `dist/libvia_core.dylib`
- 构建 `release`
- 输出到 `dist/Via.app`
- 动态库嵌入 `Contents/Frameworks/libvia_core.dylib`
- 生成 `dist/Via-macos.zip`
- 使用 ad-hoc 签名（`SIGN_IDENTITY=-`）

可以直接本地打开：

```bash
open dist/Via.app
```

如果想放到应用程序目录再测试：

```bash
cp -R dist/Via.app /Applications/
```

然后从“应用程序”里启动，或者执行：

```bash
open /Applications/Via.app
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

- `dist/Via.app`
- `dist/Via-macos.zip`

其中：

- `.app` 是本地运行和手工安装时最直接使用的产物
- `.zip` 适合发给别人下载测试

### 7.7 如果只关心本地 `.app`

本地最短路径可以记成这三步：

1. 在仓库根目录执行 `scripts/package-app.sh`
2. 产物在 `dist/Via.app`
3. 用 `open dist/Via.app` 启动，或者拖到 `/Applications`

## 8. 打包脚本内部做了什么

脚本会使用这些仓库内文件作为输入：

- [Via/Info.plist](../Via/Info.plist)
- [Via/Via.entitlements](../Via/Via.entitlements)
- [Via/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png](../Via/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png)

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
5. 需要体验真实行为时运行 `swift run Via`
6. 需要交付测试包时执行 `scripts/package-app.sh`

UI 调整还应检查：

- 首次启动（配置不完整）是否出现三步向导；授权、选择 P/B、开启、仅保存、跳过都能走通。
- 跳过后的“设置未完成”横幅能否回到向导；设置页的“重新运行设置向导”是否可用。
- 三个 Tab 切换是否正常；扫描结果和未保存草稿在切换后是否保留。
- 保存前不写入 `AppState`；保存后状态 Tab 和菜单栏图标是否更新。
- 中文和英文文案是否完整；是否出现原始本地化 Key。
- 浅色和深色外观下是否都保持可读对比，是否混入硬编码颜色。
- 面板在各个 Tab 和向导下是否被裁切；小屏上是否可滚动且不超过可用高度。
- 定位权限被拒绝时，状态 Tab、网络 Tab 和向导是否都有可理解的提示和系统设置入口。
- 密码显示/隐藏、粘贴/复制、登录启动、检查间隔、帮助展开和退出是否正常。

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

- `Via/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png` 是否存在
- 本机是否有 `sips` 和 `iconutil`

## 12. 补充说明

这份指南是基于当前仓库实际结构整理的，重点是帮助新接手的人快速回答三个问题：

- 代码应该先看哪里
- 本地怎么跑起来
- 当前仓库如何打包交付

如果后面项目切换到 Xcode 工程或加入 CI/CD，建议同步更新这份文档。

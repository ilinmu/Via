# Via 功能、分支与异常处理实现说明

## 1. 文档范围

本文档以当前仓库中的实际代码为准，完整描述 Via 的功能、状态、主要执行流程、条件分支、异常处理、持久化方式、系统权限、CLI、打包流程和测试覆盖。

阅读范围包括：

- `Package.swift`
- `Sources/AutoWifi/main.swift`
- `Sources/AutoWifiCore/AppState.swift`
- `Sources/AutoWifiCore/WifiManager.swift`
- `Sources/AutoWifi/SettingsView.swift`
- `Sources/AutoWifi/Models/`（`PanelModel`、`NetworkDraft`、`PanelMetrics`、`PanelTab`）
- `Sources/AutoWifi/DesignSystem/`、`Components/`、`Tabs/`、`Onboarding/`
- `Sources/AutoWifiCore/LocalizationManager.swift`
- `Sources/AutoWifiCore/LaunchAtLoginManager.swift`
- `Tests/AutoWifiTests/AutoWifiTests.swift`
- `auto-wifi-cli.swift`
- `AutoWifi/Info.plist`
- `AutoWifi/AutoWifi.entitlements`
- `scripts/package-app.sh`
- `docs/UI_DESIGN.md`
- README 和 `docs` 下已有文档

界面视觉和交互规范另见 `docs/UI_DESIGN.md`。本文档与 README、项目评审记录已按当前实现同步；源码仍是最终依据。

## 2. 应用定位与核心规则

Via 是一个 macOS 13 及以上版本的菜单栏应用。用户配置两个受管 Wi-Fi：

- `P`：Priority，优先网络。
- `B`：Backup，备用网络。

核心规则是：

1. 只要扫描结果中存在 P，就优先连接 P。
2. P 不存在时，如果当前不在 B，并且扫描结果中存在 B，则连接 B。
3. 当前在 B 时继续定时扫描；P 恢复后切回 P。
4. P 断开时立即扫描 B：B 可见则主动连接 B；B 也不可见时才交由 macOS 自行选择网络。
5. 切到配置的 B 时，按上下文判断是自动回退还是手动切换：
   - 扫描中 P 不可见，属于系统回退（P 丢失后落到 B），保持自动切换。
   - 扫描中 P 仍可见，视为手动切换，停止自动切换（图标显示红点）。
6. 用户切到 P/B 之外的网络时，代码通过启发式规则判断这是手动覆盖还是系统回退：
   - 判断为手动覆盖时停止自动切换。
   - 判断为系统回退时保持自动切换，并尝试恢复到当前配置的 B。

## 3. 工程结构与职责

### 3.1 Swift Package 目标

`Package.swift` 定义以下目标：

| 目标 | 类型 | 职责 |
| --- | --- | --- |
| `AutoWifi` | executable | 应用入口、菜单栏图标、浮动面板、设置界面和应用生命周期 |
| `AutoWifiCore` | library | 状态、Wi-Fi、本地化和登录启动逻辑（不依赖 SwiftUI） |
| `AutoWifiTests` | test | 核心状态和 Wi-Fi 分支的单元/回归测试 |
| `CAutoWifiCore` | system library | Rust 策略核心的 C 模块声明（`core/include`） |
| `PolicySmoke` | executable | 通过 C ABI 验证策略核心的冒烟程序 |

最低平台声明为 macOS 13，Swift tools version 为 6.0。

策略核心本身是 `core/` 下的 Rust workspace：

| crate | 职责 |
| --- | --- |
| `autowifi-domain` | 平台无关的状态机，无第三方依赖、无 I/O |
| `autowifi-ffi` | C ABI 导出层，产物为 `libautowifi_core.dylib` / `.a` |

### 3.2 主要对象关系

```text
NSApplication / AppDelegate
├── AppState
│   ├── 配置与运行状态
│   ├── UserDefaults 配置持久化
│   ├── CredentialStore（Keychain）
│   └── LaunchServiceProtocol
├── WifiManager
│   ├── CWWiFiClient / CWInterface
│   ├── CLLocationManager
│   ├── SSID 变化事件
│   └── 定时检查
├── PanelMetrics（面板最大高度）
├── PanelModel（路由、Tab、草稿、扫描、启动中）
│   ├── NetworkDraft
│   └── PanelRoute / PanelTab / SetupStep / ScanOutcome
└── SettingsView
    ├── PanelTabBar 与权限/设置横幅
    ├── StatusTabView / NetworksTabView / SettingsTabView
    ├── OnboardingView（授权 → 网络 → 完成）
    └── DesignSystem / Components
```

`AppState` 和 `WifiManager` 都标记为 `@MainActor`。CoreWLAN 和 CoreLocation 的回调通过 `Task { @MainActor in ... }` 回到主 Actor 后更新状态。

### 3.3 共享策略核心接入

`WifiManager` 持有一个可选的 `WifiPolicyEngine`：

```text
WifiManager
└── WifiPolicyEngine（可选）
    └── dlopen("libautowifi_core.dylib")
        └── AwEngine（Rust 状态机）
```

- `WifiPolicy.swift` 用 `dlopen`/`dlsym` 查找动态库，路径顺序为
  `AUTOWIFI_CORE_PATH`、`Contents/Frameworks/`、bundle 根目录、当前目录向上的
  `core/target/{release,debug}/`。
- 动态库不存在时 `policy` 为 `nil`，`WifiManager` 使用原有 Swift 逻辑，应用不会
  崩溃。
- 当前已接入：配置同步、启动/停止、关联开始与结果、迟到结果、程序化切换意图
  与冷却判断、关联代次校验。
- 尚未接入：`check_begin`、`scan_result`、`classification_result`、
  `backup_scan_result`、`observed_change` 等主检查分支。

核心的输入输出约定、所有权和线程要求见 [core/README.md](../core/README.md)。

## 4. 应用启动与菜单栏生命周期

### 4.1 启动顺序

应用直接创建 `NSApplication.shared`，设置 `AppDelegate` 后调用 `app.run()`，不依赖 Storyboard。

`applicationDidFinishLaunching` 的处理顺序是：

1. 创建 `AppState`。
2. 创建 `WifiManager`，注入 `AppState`。
3. 计算 `PanelMetrics.maxHeight`，创建持有 UI 状态的 `PanelModel`。
4. 创建 `SettingsView`，注入 `AppState`、`WifiManager`、`PanelMetrics` 和 `PanelModel`。
5. 创建透明、无边框、可获得键盘焦点的 `FocusablePanel`。
6. 创建菜单栏 `NSStatusItem`。
7. 订阅当前网络名，用于更新菜单栏提示文字。
8. 订阅网络类型、监控开关、语言和应用外观，用于更新菜单栏图标和提示。
9. 监听屏幕参数变化，重新计算面板最大高度。
10. 注册全局鼠标点击监听；面板显示时，应用外部的全局左/右键点击会关闭面板。

### 4.2 启动时恢复自动切换意图

`AppState.isRunning` 保存到 `UserDefaults`。`AppDelegate` 创建 `WifiManager` 后，如果上次保存的值为 `true`，会调用 `startMonitoring()`。

因此：

- 上次退出前自动切换开启时，再次启动会尝试恢复监控。
- 配合“登录时启动应用”，登录后可以继续自动切换。
- 如果 P/B 配置已失效或为空，`startMonitoring()` 会停止并把持久化状态改回关闭。

### 4.3 浮动面板

面板宽度固定为 400 点，高度按 SwiftUI 内容测量结果动态调整，最低 360 点。`PanelMetrics.maxHeight` 取状态栏所在屏幕 `visibleFrame.height - 24`，上限 680 点；`SettingsView` 的根滚动区域和 `AppDelegate` 的窗口高度更新都按该上限钳制。

打开面板时：

- 根据菜单栏按钮的屏幕坐标，将面板水平居中放在按钮下方。
- 按屏幕可见区域修正 x/y，避免多显示器或靠近屏幕边缘时超出边界。
- 调用 `makeKeyAndOrderFront`，并激活应用。

关闭面板时只执行 `orderOut`，应用继续在菜单栏运行。

### 4.4 文本快捷键

`FocusablePanel` 处理 Command-X/C/V/A，并把剪切、复制、粘贴、全选动作发送给当前第一响应者。

密码输入框还分别继承 `NSTextField` 和 `NSSecureTextField`，再次处理同样的快捷键，并提供右键编辑菜单。这是为了确保无边框浮动面板中的密码字段可以正常粘贴和编辑。

## 5. 应用状态与持久化

### 5.1 持久化字段

`AppState` 使用 `UserDefaults` 保存非敏感配置，密码单独保存在 macOS 钥匙串：

| 字段 | 存储位置 / Key | 默认值 | 写入时机 |
| --- | --- | --- | --- |
| 优先 SSID | Defaults `ssidP` | 空字符串 | 属性变化时立即写入 |
| 优先密码 | Keychain `passwordP` | 空字符串 | 属性变化后防抖 400ms 写入；空值时删除该项 |
| 备用 SSID | Defaults `ssidB` | 空字符串 | 属性变化时立即写入 |
| 备用密码 | Keychain `passwordB` | 空字符串 | 属性变化后防抖 400ms 写入；空值时删除该项 |
| 检查间隔 | Defaults `checkInterval` | 60 秒 | 属性变化并规范化后写入 |
| 自动切换意图 | Defaults `isRunning` | false | 开启、停止或异常停止时写入 |

语言由 `LocalizationManager` 使用独立 Key `AppLanguage` 保存，默认是简体中文 `zh-Hans`。

旧版本留在 Defaults `passwordP` / `passwordB` 中的明文密码，会在初始化时迁移到钥匙串：写入后回读确认值一致，才删除对应 Defaults Key。写入或回读失败时保留旧明文，并设置 `credentialStorageWarning` 供界面显示。

### 5.2 不持久化的运行字段

以下字段只存在于当前进程内：

- `currentStatus`：最后一条业务状态消息，不含时间戳（非 `@Published`）。
- `lastLog`：最后一条带时间戳的日志（非 `@Published`）。
- `networkStatus`：唯一的网络状态来源，取值为 `.connected(ssid:role:)`、`.notConnected`、`.permissionPending`、`.permissionDenied`、`.noInterface`。
- `currentNetworkName` / `connectedNetworkType`：由 `networkStatus` 派生的兼容访问器，不再单独赋值。
- `nextCheckTime`：下次定时检查时间。

应用退出后这些值不会恢复。

### 5.3 检查间隔规范化

默认间隔为 60 秒，最小间隔为 5 秒，最大间隔为 3600 秒。

规范化分支如下：

| 输入 | 内存中的规范化值 |
| --- | --- |
| 未保存过 | 60 |
| `NaN`、正/负无穷等非有限数 | 60 |
| 小于 5，包括负数和 0 | 5 |
| 大于 3600 | 3600 |
| 5 到 3600 之间的有限数 | 原值 |

当属性被设置为越界值时，`didSet` 会再次把属性改成规范化值；第二次 `didSet` 才真正写入 `UserDefaults`。

初始化时如果读到的是无效已存值，只会把规范化结果放入当前 `AppState`，不会立刻回写修复磁盘上的旧值；不过每次启动都会重新规范化，所以运行时仍使用安全值。用户后续修改间隔时才会保存规范化后的新值。

`WifiManager` 订阅 `appState.$checkInterval`。用户在界面中提交新间隔后，如果监控正在运行，会立即重建定时器，不再等待当前计时结束。

### 5.4 密码存储

当前实现通过 `CredentialStore` 抽象把两个 Wi-Fi 密码保存到 macOS 钥匙串；生产实现为 `KeychainCredentialStore`（`Security` 框架，service `io.github.ilinmu.via`），测试使用内存实现。

密码只供本机 Wi-Fi 关联使用，应用没有上传逻辑。写入空字符串会删除对应钥匙串项。输入采用 400ms 防抖，`flushPendingPasswordSaves()` 会在退出前同步写入。旧版本位于 Defaults `passwordP` / `passwordB` 的明文密码会在首次启动时迁移到钥匙串；只有写入后回读校验一致才删除旧键，迁移失败会保留旧值并显示警告。`CredentialStore` 的读写方法会抛出错误，便于迁移和界面区分“不存在”和“读取失败”。

### 5.5 日志行为

`AppState.log` 会：

1. 用系统短时间格式生成时间戳。
2. 组装 `[时间] 消息`。
3. 输出到标准输出。
4. 把带时间戳内容写入 `lastLog`。
5. 把原始消息写入 `currentStatus`。

只保留最后一条日志，没有日志列表、磁盘日志或历史持久化。

当前设置面板不直接展示 `currentStatus` 和 `lastLog`。这是有意的产品取舍：原始业务日志和 CoreWLAN 接口诊断继续保留在状态对象、标准输出和 OSLog 中，状态 Tab 改为展示结构化且已本地化的连接角色、自动切换状态、下次检查和扫描结果，避免把英文内部日志直接暴露给用户。

## 6. 当前网络状态分类

`ConnectedNetworkType` 有四种值：

| 类型 | 条件 |
| --- | --- |
| `.none` | 无 SSID、无接口或定位权限被拒绝/限制 |
| `.priority` | 当前 SSID 等于配置的 P |
| `.backup` | 当前 SSID 等于配置的 B |
| `.other` | 有 SSID，但既不是 P 也不是 B |

菜单栏图标由网络类型和 `isRunning` 共同决定：

| 自动切换 | 网络类型 | 图标附加标记 |
| --- | --- | --- |
| 关闭 | 任意 | Wi-Fi 图标右下角红点 |
| 开启 | `.priority` | `P` |
| 开启 | `.backup` | `B` |
| 开启 | `.none` / `.other` | 无附加文字 |

当前网络名会同步到菜单栏 Tooltip，格式为 `Via: <当前网络名>`。

## 7. Wi-Fi 和定位抽象

核心代码为系统类型定义了协议包装：

- `WiFiClientProtocol`
- `WiFiInterfaceProtocol`
- `WiFiNetworkProtocol`
- `LocationManagerProtocol`

生产环境分别由 `CWWiFiClient`、`CWInterface`、`CWNetwork`、`CLLocationManager` 实现；测试环境使用 Mock。这使扫描结果、当前 SSID、连接行为、连接错误和定位授权状态可以被注入。

`CWInterface.associateNetwork` 的协议适配只接受真实 `CWNetwork`。如果传入其它协议实现，会抛出 `AutoWifi` domain、code 1、描述为 `Invalid network type` 的错误。测试 Mock 不经过这一层。

## 8. WifiManager 初始化

初始化时会：

1. 保存 `AppState`、Wi-Fi Client、Location Manager。
2. 记录初始化时配置的 B 到 `trackedBackupSSID`。
3. 读取当前 Wi-Fi 接口。
4. 创建 `WifiPolicyEngine`（动态库加载失败时为 `nil`）。
5. 把自己设置为定位和 Wi-Fi Client 的 delegate。
6. 注册 `.ssidDidChange` 事件监听。
7. 异步执行一次 `refreshStatus()`。

注册 SSID 事件失败时只通过 `print` 输出：

```text
Failed to start monitoring SSID changes: <error>
```

该失败不会写入 `AppState`，不会阻止应用启动，也不会禁用定时检查。结果是事件驱动响应可能失效，但用户手动开启自动切换后，定时扫描仍可能继续工作。

## 9. 定位权限与状态刷新

### 9.1 权限请求

`requestPermissions()` 直接调用 `requestWhenInUseAuthorization()`。

以下操作会请求权限：

- 点击“扫描网络”。
- 点击“开启自动切换”。
- `refreshStatus()` 发现授权状态为 `.notDetermined` 且当前 SSID 为 `nil`。

定位授权发生变化后，delegate 回调会重新执行 `refreshStatus()`。

### 9.2 refreshStatus 分支

`refreshStatus()` 首先同步备用网络配置变化，然后检查权限。

| 条件 | `currentNetworkName` | 网络类型 | 其它动作 |
| --- | --- | --- | --- |
| 权限 `.denied` / `.restricted` | `Location Permission Denied` | `.none` | 写警告日志并返回 |
| 有接口且能读到 SSID=P | P 名称 | `.priority` | 无额外动作 |
| 有接口且能读到 SSID=B | B 名称 | `.backup` | 无额外动作 |
| 有接口且能读到其它 SSID | 该 SSID | `.other` | 无额外动作 |
| 有接口、SSID=nil、权限未决定 | 本地化的“等待权限” | `.none` | 再次请求权限 |
| 有接口、SSID=nil、权限已决定且非拒绝 | `Not Connected` | `.none` | 无额外动作 |
| 没有接口 | `No Interface` | `.none` | 不写错误日志 |

注意：权限拒绝只会改变显示状态，不会自动调用 `stopMonitoring()`。如果自动切换原本开启，`isRunning` 仍可能保持 `true`，定时器也仍可能继续触发扫描并记录扫描失败。

## 10. 开启、停止与定时检查

### 10.1 开启自动切换

`startMonitoring()` 的执行顺序：

1. 请求定位权限。
2. 检查 P 和 B 是否都非空。
3. 清理旧定时器和旧监控上下文。
4. 设置 `isRunning = true`。
5. 记录 `Started monitoring...`。
6. 立即执行一次 `checkConnection()`。
7. 如果执行后仍为运行状态，则安排下一次定时器。

配置分支：

- P 或 B 任一为空：记录 `Error: SSIDs not configured.` 并返回，监控不会开启。
- UI 层也会在 P/B 任一为空时禁用按钮，因此该分支主要用于防御直接调用。
- 代码不验证密码是否为空。
- 代码不验证 P 和 B 是否相同。

### 10.2 定时器

定时器是一次性 `Timer`，不是重复 Timer：

1. 取消上一只 Timer。
2. 从 `appState.checkInterval` 读取间隔。
3. 更新 `nextCheckTime`。
4. Timer 到期后执行 `checkConnection()`。
5. 如果仍在运行，则再次调用 `scheduleTimer()` 创建下一只 Timer。

这种设计保证每次检查完成后再开始下一周期，不会使用固定重复 Timer 直接重叠调度。Wi-Fi 扫描和关联通过后台 Task 执行，主 Actor 只负责状态决策和 UI 更新；同时 `isCheckingConnection` 阻止多次检查重叠。

除并发互斥外，关联还受到两层保护：

- 同一时间最多只有一个 `associate` 在途；关联期间到达的 SSID 事件只刷新状态并等待结果，不会再次发起连接。
- 关联失败或超时后进入 90 秒冷却窗口，冷却状态写入 `UserDefaults` 并跨重启保留。冷却按目标网络记忆：冷却期内只有对同一目标网络的重连会被跳过，切换到其他网络（例如定时检查发现 P 可见）不受影响。
- 关联成功、已连回 P、或用户手动停止后再次开启自动切换时，冷却会被清除，确保新一轮检查立即按优先级网络执行。

用户手动连回 P、或关联成功时，冷却窗口会被清除。

### 10.3 停止自动切换

用户点击停止时：

- 取消 Timer。
- 清空 Timer 引用和 `nextCheckTime`。
- 设置 `isRunning = false`。
- 如果之前确实在运行或仍有 Timer，则记录 `Stopped monitoring.`。

内部也可以传入具体停止原因。例如判断用户切到未管理网络时，会保留包含网络名和判断原因的日志，而不是再被通用停止日志覆盖。

如果本来已经停止且没有 Timer，再调用停止不会新增日志。

### 10.4 运行中修改配置

P、B、密码和间隔在界面上始终可以修改，没有“运行时锁定配置”的机制。

- 修改 P：下一次 SSID 事件、状态刷新或定时检查会使用新 P。旧 P 不会像旧 B 一样被特殊跟踪；当前仍连着旧 P 时，它会被视为未管理网络或普通当前网络，并按新配置重新决策。
- 修改 B：`syncConfiguredNetworks()` 会把上一版 B 保存到 `previousBackupSSID`，以便识别系统随后连接旧 B 的情况。
- 修改密码：下一次连接尝试直接使用新密码。
- 修改间隔：当前已安排的 Timer 不变，下一轮调度才使用新间隔。
- 把 P 或 B 清空：后续周期检查记录配置错误并停止监控。

控制按钮只在“尚未运行且 P/B 任一为空”时禁用。监控运行期间即使清空配置，用户仍可以点击停止；自动检查也会主动结束监控。

如果 P 和 B 被配置成相同 SSID，代码会优先把它分类为 P；扫描和连接也优先使用 `passwordP`，B 分支实际不会发挥备用作用。

## 11. 周期检查与连接优先级

`checkConnection()` 是启动立即检查、定时检查和部分事件分支共用的核心函数。

### 11.1 前置分支

| 条件 | 处理 |
| --- | --- |
| 无 Wi-Fi 接口 | 类型设为 `.none`，名称设为 `No Interface`，记录错误并返回 |
| P 或 B 为空 | 记录配置错误并返回 |
| 当前已经连接 P | 更新状态后直接返回，不扫描 |

接口会在每次检查时重新从 Client 获取，以适应接口引用变化。

### 11.2 扫描来源

函数支持两种扫描来源：

- 无参数：自己调用 CoreWLAN 扫描，并先记录 `Scanning...`。
- 传入 `scannedNetworks`：复用事件处理阶段已经得到的扫描结果，不重复扫描，也不再记录 `Scanning...`。

### 11.3 连接决策矩阵

| 扫描/当前状态 | 动作 |
| --- | --- |
| 找到 P | 连接信号最强的同名 P，结束本次检查 |
| 找不到 P，当前不在 B，找到 B | 连接信号最强的同名 B |
| 找不到 P，当前不在 B，也找不到 B | 记录 `Neither network P nor B found.` |
| 找不到 P，当前已经在 B | 不重连 B；记录仍在 B，等待下次检查 |

同名 SSID 选择规则是按 `rssiValue` 取最大值，即 RSSI 数值更高、信号更强的 AP。例如 `-38` 优于 `-72`。

该算法只判断 SSID 是否出现在扫描结果中，不设置最低 RSSI 门槛，也没有连接冷却时间、失败退避或连续多次确认机制。

### 11.4 扫描异常

周期检查扫描抛错时记录：

```text
Scan failed: <系统错误描述>
```

异常不会停止自动切换。定时器回调返回后，只要 `isRunning` 仍为 `true`，就会继续安排下一次检查。

## 12. SSID 变化事件状态机

应用在初始化时监听 CoreWLAN 的 `.ssidDidChange`。事件回调先切回主 Actor，再按以下优先级处理。

### 12.1 程序正在主动切网

条件：`isSwitchingNetwork == true`。

处理：调用 `checkConnection()` 后返回。

虽然代码注释写的是“忽略通知”，实际行为不是只忽略，而是重新执行优先级检查。通常：

- 主动连到 P 后，检查发现已经在 P，直接返回。
- 主动连到 B 后，检查会再次扫描 P；若 P 已出现，可能立即回 P。

### 12.2 自动切换已关闭

条件：`appState.isRunning == false`。

处理：只执行 `refreshStatus()`，更新网络名和网络类型，不扫描、不连接，也不会自动重新开启。

### 12.3 新 SSID 是 P

处理：

- 记录已连接 P、自动切换仍有效。
- 刷新状态。
- 保持 `isRunning = true`。

### 12.4 新 SSID 为 nil

如果断开前是 P，则区分两种情况：

1. 等待无线网卡稳定后重扫 P，若 P 仍可见，说明这是手动切网的瞬态，等待后续 SSID 事件，不提前连接。
2. 若 P 已不可见，说明 P 丢失，立即扫描并主动连接 B，避免 macOS 自行漫游到其它已保存网络 X；只有 B 也不可见时才交由系统选择网络。

如果断开前不是 P，则记录 `Network disconnected. Waiting...`，刷新状态并等待后续 SSID 事件。

是否重连由后续 SSID 事件或定时检查驱动。

### 12.5 新 SSID 是当前配置的 B

切到配置的 B 时按两步判断：

1. 如果应用刚刚主动发起过连接 B（`lastProgrammaticBackupAt` 在 15 秒窗口内），直接视为自动回退并保持监控。
2. 否则等待无线网卡稳定（`observedChangeSettleDelay`，默认 1 秒）后重扫 P，再按“P 是否可见”判断。

事件处理会先扫描一次，然后按上下文记录不同日志：

| 条件 | 解释/日志语义 |
| --- | --- |
| 应用刚主动连过 B | 自动回退，保持监控 |
| 稳定后扫描中 P 可见 | 手动切换，停止自动切换并记录原因，菜单栏图标显示红色圆点 |
| 稳定后扫描中 P 不可见 | 系统回退到 B（P 已丢失），保持监控 |

系统回退（P 不可见）时，把本次扫描结果传给 `checkConnection()`：

- 扫描中有 P：立即连接 P。
- 扫描中无 P：保持在 B。

手动切到 B（P 仍可见）会停止自动切换，不再由 B 事件驱动回 P；之后若用户重新开启自动切换，定时检查发现 P 可见时会正常切回 P。

### 12.6 新 SSID 是上一版备用网络

应用会跟踪一次 B 配置变更：

- `trackedBackupSSID`：最近同步过的当前 B。
- `previousBackupSSID`：变更前的 B。

如果用户把 B 从 `BackupA` 改成 `BackupB`，随后系统连到旧的 `BackupA`，该网络会被识别为“旧备用网络”。处理为：

1. 不停止监控。
2. 在已扫描网络中寻找当前配置的 `BackupB`。
3. 找到则使用当前 B 的密码连接 `BackupB`。
4. 找不到则保持当前连接，等待下次检查。

只跟踪上一版 B，不维护更长的历史列表。

### 12.7 新 SSID 是其它未管理网络

当新网络既不是 P、当前 B，也不是上一版 B 时，按以下顺序判断：

| 顺序 | 条件 | 判断 | 动作 |
| --- | --- | --- | --- |
| 1 | 稳定后扫描中 P 可见 | 用户手动覆盖 | 停止监控，保留具体原因日志 |
| 2 | 稳定后扫描中 P 不可见 | 系统回退 | 保持监控，尝试连接当前 B |

这里的“手动切网”不是由系统提供的明确用户操作标志，而是启发式判断：切到未管理网络时，先等待无线网卡稳定再重扫，如果 P 仍可见，就假设用户主动选择了别的网络。

### 12.8 判断切网原因时扫描失败

如果 `handleObservedNetworkChange` 为判断原因而扫描失败：

- 记录无法验证切网原因及错误描述。
- 不停止监控。
- 不尝试恢复 B。
- 外层事件处理随后仍会调用 `refreshStatus()`。
- 后续依赖定时检查再次处理。

## 13. 恢复到当前备用网络

`recoverToConfiguredBackupIfNeeded` 用于旧 B、系统回退到未管理网络等分支。

| 条件 | 动作 |
| --- | --- |
| 当前 B 配置为空 | 记录未配置并返回 |
| 当前已经在 B | 记录自动切换继续 |
| 当前不在 B，扫描中找到 B | 使用 B 密码连接信号最强的 B |
| 当前不在 B，扫描中找不到 B | 记录等待下次检查 |

该函数本身不优先寻找 P，因为调用它之前的事件分支已经完成了原因判断。下一次通用 `checkConnection()` 仍会重新按 P 优先处理。

## 15. 主动连接处理

连接前设置 `isSwitchingNetwork = true`，并在关联真正结束后恢复为 false，用于覆盖程序连接和权限等待期间产生的 SSID 通知。

成功分支：

1. 调用 CoreWLAN `associate`。
2. 更新 `lastObservedSSID`。
3. 如果目标是 P 或当前 B，清除最近断开上下文。
4. 记录成功日志。
5. 调用 `refreshStatus()` 更新 UI 状态。

失败分支：

- 记录目标 SSID 和错误描述。
- 不停止监控。
- 不立即重试，并启动 90 秒关联冷却（按失败目标网络记忆）。
- 冷却期内只跳过对同一目标网络的关联；定时检查发现 P 可见时不受冷却影响，可立即回切。
- 关联成功、已连回 P，或用户停止后重新开启自动切换时清除冷却。

关联在途期间 `isSwitchingNetwork` 保持为真，SSID 事件不会把权限弹窗阶段的变化误判为“手动切网”。

如果连接函数执行时接口引用为 nil，函数直接返回，不写日志。不过正常入口通常已经在扫描或检查阶段验证过接口。

## 16. 手动扫描功能

点击“扫描网络”时，`PanelModel.scan()` 按定位权限分支：

1. `.notDetermined`：标记 `.permissionPending` 并请求权限，不开始扫描。
2. 其它非 `.authorizedAlways` 状态：标记 `.permissionDenied`，不开始扫描。
3. `.authorizedAlways`：设置 `isScanning = true`、状态 `.scanning`，写入本地化的“扫描中”日志，然后调用 `WifiManager.getAvailableNetworks()`。
4. 完成后停止旋转；有结果时替换建议列表并标记 `.success(count)`，空结果标记 `.empty` 并保留上一次的建议列表。

用户授权后，`PanelModel.handleAuthorizationChange(_:)` 会在条件满足时自动补一次扫描；权限被拒绝时把待定状态改成 `.permissionDenied`。

扫描结果处理：

- 丢弃 `ssid == nil`。
- 丢弃空字符串 SSID。
- 用 `Set` 去重。
- 按字符串升序排序。

UI 分支（`PanelModel.scan()`）：

- 权限为 `.notDetermined` 时先请求权限，并把结果标为 `.permissionPending`。
- 权限不是 `.authorizedAlways` 时标为 `.permissionDenied`，不发起扫描。
- 有权限时异步扫描，状态从 `.scanning` 进入 `.success(count)` 或 `.empty`。
- P/B 编辑器始终是可自由输入的 `TextField`；有扫描结果时右侧提供展开按钮，展开后以可滚动列表展示全部扫描结果，选中即回填。
- 扫描中禁用扫描按钮并显示进度指示。

异常处理：

- Wi-Fi 扫描错误会记录 `❌ Scan error: ...` 并返回空数组。
- 如果错误描述包含小写字符串 `location`，再记录一次定位权限建议。该判断依赖错误文本和大小写，不是结构化错误判断。
- `getAvailableNetworks()` 对“周围确实没有网络、无权限、无接口、扫描失败”都返回空数组；UI 只在有权限时显示中性的“未发现网络”，权限状态单独由横幅和提示表达。
- 扫描失败时保留上一次的成功建议列表。
- 具体扫描错误仍只留在标准输出和日志中。

## 17. 设置界面功能

UI 由 `SettingsView` 外壳、三个 Tab 和首次向导组成。`PanelModel` 持有跨视图的 UI 状态（当前路由、Tab、向导步骤、网络草稿、扫描结果、间隔草稿和启动中标记），`AppDelegate` 创建并持有它，再以 `@ObservedObject` 传入 `SettingsView`。

### 17.1 面板外壳与路由

`SettingsView` 只负责：

- 顶部标题栏：`wifi` 图标、应用标题；Tab 模式不额外放置设置入口，向导模式在右侧显示 `1 / 3` 和“跳过”。
- Tab 模式下的 `PanelTabBar`（分段 `Picker`），不使用 SwiftUI `TabView`，避免 macOS 自带 chrome 影响 400 点无边框面板。
- 条件横幅：定位权限未就绪、网络设置未完成。
- 按 `PanelRoute` 和 `PanelTab` 切换内容。
- 固定顶部区域与滚动内容的测高、`PanelMetrics.maxHeight` 钳制和 `onHeightChange` 回调。

`PanelRoute` 只有 `.onboarding` 和 `.tabs`。`PanelModel.init` 根据 `ssidP`、`ssidB` 去空白后是否都非空决定初始路由，之后只由“完成/跳过/重新运行向导”改变。这样编辑过程中清空字段不会突然切回向导并丢失焦点。

菜单栏图标左键打开或关闭面板；右键或 Control-点击弹出系统菜单，当前只包含本地化的“退出应用”，不会打开面板。

`applicationDidBecomeActive` 会刷新登录启动状态和 Wi-Fi 状态；屏幕参数变化时重新计算 `PanelMetrics.maxHeight`。

### 17.2 状态 Tab

`StatusTabView` 包含：

- `ConnectionSummary`：当前 SSID、本地化网络角色、运行状态徽标。状态徽标高度与 40 点 Wi-Fi 图标一致，文字使用 `.body`，始终带文字：运行中（绿色）、等待定位权限（橙色）、正在开启（蓝色 + 进度）、已暂停（次级灰）。
- 自动切换 `Toggle`：未运行时要求配置完整且权限为 `.authorizedAlways`；运行中始终允许停止。`isStarting` 期间禁用并显示进度。
- 下次检查：运行且有 `nextCheckTime` 时用 `TimelineView` 每秒更新倒计时；启动检查期间显示“正在检查”；权限未就绪时显示“等待定位权限”。
- 未保存草稿提示：点击切到网络 Tab。
- P/B 摘要：显示 SSID 或“未设置”，点击切到网络 Tab。
- `扫描网络`、`刷新状态`，以及扫描结果反馈。

状态页不展示 `currentStatus`、`lastLog` 或 CoreWLAN 接口诊断；这些信息仍保留在状态对象、标准输出和 OSLog 中。

### 17.3 网络 Tab 与草稿

`NetworksTabView` 使用 `NetworkSetupForm` 编辑 P/B，并复用同一组件于向导第 2 步。

编辑不直接写 `AppState`：

- `NetworkDraft` 保存 P/B 的 SSID 和密码，并记录原始快照用于 `hasChanges`。
- 点击“保存更改”才调用 `commit(to:)`，SSID 去首尾空白后一次性写入 `AppState`。
- 校验：两个 SSID 非空且不区分大小写不相同；密码可为空，适用于开放网络。
- 保存按钮只在没有改动时禁用；无效输入点击后显示具体错误，不静默禁用。
- 切换 Tab 不会丢失草稿或扫描结果。

这样可以避免用户编辑到一半清空 SSID 时，`checkConnection` 因空配置停止监控。

扫描由 `PanelModel.scan()` 统一管理，状态为 `ScanOutcome`：`.idle`、`.scanning`、`.success(count)`、`.empty`、`.permissionPending`、`.permissionDenied`。P/B 输入框始终可手动输入，有建议列表时在输入框右侧提供菜单。

### 17.4 设置 Tab

`SettingsTabView` 分为三个无卡片背景的分区：

1. 通用：登录时启动开关、语言下拉选择器、内联使用说明 `DisclosureGroup`、重新运行设置向导。
2. 自动切换：检查间隔输入框和“秒”；回车或失焦提交，经 `AppState` 归一化到 5–3600；下方显示范围提示。
3. 关于：版本号和构建号、本地隐私说明、红色“退出应用”。

登录启动处于 `.requiresApproval` 时开关禁用，显示警告横幅和“打开登录项设置”，避免开关回弹。

### 17.5 首次向导

`SetupStep` 为 `.permission`、`.networks`、`.finish`，`OnboardingView` 负责进度指示和底部导航。

1. 授权定位：`.authorizedAlways` 显示已授权；`.notDetermined` 提供“授权定位”；其它状态提供“打开系统设置”和“需要允许‘始终’访问”的提示，并说明可以跳过、手动输入 SSID。
2. 选择网络：复用 `NetworkSetupForm`；只有草稿有效时才能进入下一步。
3. 完成：展示 P/B/权限摘要。`开启自动切换` 要求配置有效且权限为 `.authorizedAlways`，`仅保存` 在配置有效时可用。完成后提交草稿、切换到 Tab 模式并停在状态 Tab。

跳过会把路由切到 `.tabs` 并选中网络 Tab，保留草稿；顶部“设置未完成 / 继续设置”横幅可重新进入向导。设置页的“重新运行设置向导”使用同一入口。

### 17.6 设计系统与视觉

面板跟随系统浅色/深色外观：

- 背景 `windowBackgroundColor`，输入框 `textBackgroundColor`，分隔线 `separatorColor`。
- 系统蓝是唯一强调色；橙色/红色只表达警告和错误。
- 单色 SF Symbols，无渐变、网格、发光和卡片阴影。
- 输入框、按钮和面板使用 8/12 点圆角；间距取 4/8/12/16/20。

设计令牌位于 `DesignSystem/PanelLayout.swift`；共享组件包括 `PanelTabBar`、`SettingsSection`、`SettingsRow`、`FieldContainer`、`StatusBadge`、`WarningBanner`、`ScanButton`、`NetworkSetupForm` 和 `ConnectionSummary`。

### 17.7 本地化范围

界面支持简体中文和英文，语言切换会持久化。Tab 名称、状态、网络配置、权限提示、向导、设置项、帮助正文、密码右键菜单和菜单栏右键退出项都通过 `LocalizationManager` 取文案；找不到 Key 时直接显示 Key 本身。

仍未本地化的内容：

- 多数 `WifiManager` 运行日志是英文，仅用于标准输出和 OSLog 排障。
- 菜单栏 Tooltip 前缀固定为 `Via`（品牌名）。
- 语言选项使用“中文”和“English”的自称，便于在任何界面语言下识别。

### 17.8 状态模型

- `PanelModel`：`@MainActor ObservableObject`，持有 `route`、`tab`、`step`、`draft`、`intervalDraft`、`availableNetworks`、`isScanning`、`scanOutcome`、`isStarting`；提供 `scan()`、`startMonitoring()`、`stopMonitoring()`、`commitDraft()`、`commitInterval()`、`refreshAll()`、`handleAuthorizationChange(_:)` 和向导导航方法。
- `NetworkDraft`：`@MainActor struct`，保存草稿、校验、提交和重新加载。
- `PanelMetrics`：`@MainActor ObservableObject`，保存面板最大高度。
- `PanelTab.swift`：定义 `PanelRoute`、`PanelTab`、`SetupStep`、`ScanOutcome`。

`isStarting` 是唯一可靠的“开启中”信号：`startMonitoring()` 可能等待关联最多 15 秒，而 `isAssociating` 没有发布。开始操作以 `canAutomate` 为前提；`startMonitoring()` 在权限不足时仍可能把 `isRunning` 置 true 且没有定时器，因此 UI 还要单独展示“等待定位权限”。

## 18. 登录启动

macOS 13 及以上使用 `SMAppService.mainApp`：

- `LaunchAtLoginStatus` 区分 `.notRegistered`、`.enabled`、`.requiresApproval` 和 `.notFound`。
- `launchAtLogin` 只在 `.enabled` 时为 true；`.requiresApproval` 会保留在 `launchAtLoginStatus` 中。
- 开启调用 `register()`。
- 关闭调用 `unregister()`。
- 点击处于待批准状态的图标会打开系统“登录项”设置；应用重新激活时会刷新真实状态。

`AppState` 初始化时会读取服务真实状态并同步 UI。同步期间通过 `isSynchronizingLaunchAtLogin` 防止 `didSet` 再次触发注册/注销。

用户切换开关时的分支：

| 条件 | 处理 |
| --- | --- |
| 正在同步系统状态 | 不调用服务 |
| 没有服务对象 | 直接返回 |
| 服务状态已经等于目标状态 | 直接返回 |
| 注册成功且状态 `.enabled` | 记录成功日志 |
| 注册成功但状态 `.requiresApproval` | 记录待批准日志，界面显示橙色警示条 |
| 注册/注销失败 | 记录失败日志，并把 UI 回滚到服务当前真实状态 |

`LaunchAtLoginManager` 自身还会把失败打印到标准输出，然后继续向上抛出。

## 19. 系统配置、权限和沙箱

`Info.plist` 的关键配置：

- `LSUIElement = true`：作为菜单栏 Agent 运行，不显示普通 Dock 图标。
- `NSLocationWhenInUseUsageDescription`：解释读取 SSID 和扫描 Wi-Fi 需要定位权限。
- 最低系统版本由打包时写入。

Entitlements：

- 开启 App Sandbox。
- 允许网络 Client，保证沙箱内 CoreWLAN 可以枚举、扫描和关联 Wi-Fi。
- 允许访问定位信息。

源码以代码方式启动，不需要 Storyboard。模板 `Info.plist` 中仍有 `NSMainStoryboardFile=Main`，但打包脚本会删除该 Key。若绕过脚本手工组装 App，需要同样处理。

## 20. CLI 版本

`auto-wifi-cli.swift` 是独立实现，不复用 `AutoWifiCore`；它只用于本地诊断，不参与 SwiftPM 构建、应用打包或发布流程。

支持两种配置方式：

1. 命令行参数：`SSID-P`、`SSID-B`、可选间隔。
2. 参数不足时进入交互输入。

密码始终通过隐藏回显的终端输入读取，不接受命令行密码参数。传入旧式“密码作为参数”的调用会被拒绝，避免密码出现在 `ps` 或 Shell 历史中。

CLI 核心规则与通用周期检查相似：

- 已在 P：不扫描。
- 否则扫描并优先连接最强 P。
- 无 P 且当前不在 B：尝试最强 B。
- 已在 B 且无 P：保持 B。
- 最小间隔 5 秒。
- 启动时立即检查，之后用重复 Timer 检查。
- SIGINT/Ctrl-C 时打印停止信息并退出。

CLI 与 GUI 的重要差异：

- 没有 SSID 事件监听。
- 没有手动切网识别和自动停止逻辑。
- 没有旧 B 迁移逻辑。
- 没有配置持久化、登录启动、菜单栏 UI 和本地化。
- 扫描和连接错误统一记录为 `Error: ...`。
- 初始化时只获取一次 `CWInterface`，后续不会重新获取接口引用。
- 密码不接受命令行参数，交互输入会关闭终端回显。

## 21. 构建和打包

打包脚本默认行为：

1. 使用 `swift build -c release` 构建。
2. 在 `dist/Via.app` 组装 App Bundle。
3. 复制并改写 `Info.plist` 的可执行文件名、Bundle ID、版本、构建号、最低系统版本和图标名。
4. 删除 `NSMainStoryboardFile`。
5. 用 `sips` 从 1024 PNG 生成多尺寸 iconset。
6. 用 `iconutil` 生成 `AppIcon.icns`。
7. 默认使用 `-` 做 ad-hoc codesign；也可指定 Developer ID 或传空字符串跳过签名。
8. 用 `ditto` 生成 `dist/Via-macos.zip`。

脚本使用 `set -euo pipefail`，多数命令失败会立即结束。特殊分支包括：

- 构建后找不到可执行文件：打印错误并退出 1。
- 源图标不存在：跳过图标生成，但仍继续打包。
- 删除模板中的 Storyboard Key 失败：显式忽略，因为该 Key 可能不存在。
- 临时 iconset 目录通过 `trap` 在退出时清理。

当前脚本不包含公证 notarization、DMG、自动上传或 CI 发布流程。

## 22. 测试覆盖

测试使用 Mock Wi-Fi 网络、接口、Client、Location Manager、凭据存储和登录启动服务。测试文件当前共有 37 个测试，覆盖：

1. 从 `UserDefaults` / Keychain 加载 SSID、密码、间隔和自动切换意图，以及旧明文密码迁移。
2. 配置持久化和检查间隔上下限规范化。
3. 登录启动失败后的 UI 状态回滚。
4. WifiManager 初始化时注册 SSID 变化监听。
5. 定位权限拒绝时清除网络类型。
6. 同名 P 中选择最强信号。
7. P 不存在时连接 B。
8. 手动扫描结果去重、过滤 nil 并排序。
9. 监控关闭时 SSID 变化仍更新显示状态。
10. 切到 B 且 P 可见时视为手动切换，停止监控并显示红点。
11. 切到 B 且 P 缺失时留在 B，并保持监控。
12. 发生断网事件后切到 B、P 可见时视为手动切换，停止监控。
13. 完整验证“P 丢失 → B（系统回退）→ P 恢复可见时定时检查回 P”，全程不关闭开关。
14. B 配置变化后连到旧 B 时，恢复到当前 B。
15. 旧 B 和 P 同时可见时仍恢复到当前 B。
16. 切到未管理网络且 P 可见时停止监控。
17. 恢复监控时配置缺失会停止并清除持久化运行状态。
18. 默认 Wi-Fi 接口为空时，从系统接口列表识别当前连接。
19. 默认接口为空时，仍能使用系统接口列表扫描并切回 P。
20. 默认接口未连接时，优先选择接口列表中已连接的接口。
21. Wi-Fi 扫描和关联操作不在主线程执行。
22. 使用仅能按接口名解析的 CoreWLAN Client 时仍可扫描并自动关联 P。
23. 冷却窗口内不会对同一目标网络再次发起关联；其他网络的关联（例如 P 恢复回切）不受冷却限制。
24. 关联在途时多个 SSID 事件不会产生重复关联。
25. 手动切 B（P → nil → B，P 可见）停止监控并显示红点。
26. 自动回退到 B（P 不可见）保持监控，P 恢复可见后定时检查切回 P。
27. 旧明文密码迁移失败时保留旧值并显示警告。
28. 密码写入失败显示警告，后续成功写入后清除警告。
29. 登录启动进入系统“需要批准”状态时，UI 读取到 `.requiresApproval`。
30. 关联超时后底层调用迟到成功，仍按程序发起处理并保持监控。
31. 扫描期间 P 配置被修改时，不按旧 SSID 发起关联，而是重新检查。

尚未被单元测试直接覆盖的关键分支包括：

- SSID 事件注册失败。
- 无 Wi-Fi 接口时的启动/检查。
- 扫描抛错及定位错误文本二次提示。
- 连接抛错后的状态和后续重试。
- 程序主动连接产生的两秒通知窗口。
- 未管理网络且 P 不可见时恢复 B。
- 当前 B 也不可见时的等待分支。
- P/B 配置为空或相同的业务行为。
- 定时器实际调度、间隔运行中修改和 UI 倒计时。
- 登录启动成功路径。
- 菜单栏面板定位、屏幕边界和全局点击监听。
- CLI 行为和打包脚本。

## 23. 异常处理汇总

| 异常/边界 | 用户可见结果 | 是否停止自动切换 | 后续行为 |
| --- | --- | --- | --- |
| P/B 未配置 | 记录配置错误；UI 通常提前禁用按钮 | 不会成功开启 | 等待配置 |
| 定位权限拒绝/限制 | 当前网络显示权限拒绝，类型 `.none` | 否 | Timer 可能继续，扫描可能继续失败 |
| 没有 Wi-Fi 接口 | 显示 `No Interface` 并记录错误 | 否 | 下个周期重新获取接口 |
| SSID 事件注册失败 | 只打印到控制台 | 否 | 定时检查仍可用 |
| 扫描失败 | 记录扫描错误 | 否 | 下个周期重试 |
| 连接失败/超时 | 记录目标网络和错误，进入 90 秒冷却（按目标网络） | 否 | 冷却结束后重试；其他网络不受影响 |
| 手动扫描为空/失败 | UI 显示权限提示 | 不影响当前开关 | 用户可再次扫描 |
| 登录启动注册/注销失败 | 记录错误并回滚按钮 | 不影响 Wi-Fi 开关 | 保持系统真实启动项状态 |
| 用户切到未管理网络且 P 可见 | 记录手动覆盖判断 | 是 | 需用户重新开启 |
| 系统切到未管理网络且 P 不可见 | 尝试恢复 B | 否 | 找不到 B 时等待下次检查 |
| 连接到旧 B | 尝试恢复当前 B | 否 | 找不到当前 B 时等待 |
| 检查间隔小于 5 | 自动改为 5 | 否 | 新调度周期使用规范化值 |
| 检查间隔非有限数 | 自动改为 60 | 否 | 新调度周期使用默认值 |

## 24. 当前实现限制与注意事项

以下内容不是代码注释中的设想，而是从当前实现可以确认的限制：

1. 自动切换开关会持久化；应用重启和登录启动时会尝试恢复。
2. 密码保存在 macOS 钥匙串；旧版本的 Defaults 明文密码只用于一次性迁移。
3. 只支持一个 P 和一个 B，不支持多级优先列表。
4. 只用 SSID 和 RSSI 选择网络，不判断 BSSID、安全类型、频段或网络可用性。
5. “P 可见”只代表扫描结果中有同名 SSID，不代表互联网连通、信号足够好或认证一定成功。
6. 没有 RSSI 阈值或迟滞策略；连接失败有 90 秒冷却（按目标网络）和单关联互斥，但弱 P 只要可见仍优先于强 B。
7. 手动切网判断是启发式，存在误判可能。
8. 切到配置 B 永远保持托管，用户若确实手动选择 B，只要自动切换开启，P 可见时仍会被切回 P。
9. Wi-Fi 扫描和关联已移出主线程，并增加单关联互斥和按目标网络的失败冷却；CoreWLAN 本身的系统行为和权限响应时间仍不可控。
10. 运行日志没有完全本地化，且只保留最后一条。
11. `currentStatus/lastLog` 不直接显示在设置面板；状态 Tab 只呈现结构化语义状态，排障仍需查看日志。
12. 手动扫描失败和真实空列表在 UI 上不可区分。
13. 当前只跟踪上一版 B；连续多次修改 B 后，更早的旧 B 会被当成普通未管理网络。
14. 没有显式处理睡眠/唤醒、Wi-Fi 开关开闭、网络服务重建等生命周期事件，只依赖接口重取、SSID 事件和 Timer；解锁带来的事件风暴由单关联互斥和失败冷却吸收。
15. 没有网络连通性检测；连接到 SSID 成功即视为成功。
16. 普通分发脚本默认只做 ad-hoc 签名；Mac App Store 需要单独使用 Store 构建脚本和开发者账号证书。
17. P/B 可以配置成相同值，代码没有校验；此时 P 分支和 P 密码优先。

## 25. 文档维护约定

- 业务状态机和异常分支以本文档及源码为准。
- 三 Tab 结构、设计令牌、状态文案、无障碍和首次向导以 `docs/UI_DESIGN.md` 为准。
- `P` 始终称为 Priority/优先网络，`B` 始终称为 Backup/备用网络；不要把备用网络配置模块命名为 `Failover`。
- 修改用户可见文案时同步更新 `LocalizationManager.swift`、README、帮助正文和 App Store 元数据。
- 修改布局或交互后同步更新本文档第 17 节和 `docs/UI_DESIGN.md`。

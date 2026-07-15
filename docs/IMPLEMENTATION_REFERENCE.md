# AutoWifi 功能、分支与异常处理实现说明

## 1. 文档范围

本文档以当前仓库中的实际代码为准，完整描述 AutoWifi 的功能、状态、主要执行流程、条件分支、异常处理、持久化方式、系统权限、CLI、打包流程和测试覆盖。

阅读范围包括：

- `Package.swift`
- `Sources/AutoWifi/main.swift`
- `Sources/AutoWifiCore/AppState.swift`
- `Sources/AutoWifiCore/WifiManager.swift`
- `Sources/AutoWifiCore/SettingsView.swift`
- `Sources/AutoWifiCore/LocalizationManager.swift`
- `Sources/AutoWifiCore/LaunchAtLoginManager.swift`
- `Tests/AutoWifiTests/AutoWifiTests.swift`
- `auto-wifi-cli.swift`
- `AutoWifi/Info.plist`
- `AutoWifi/AutoWifi.entitlements`
- `scripts/package-app.sh`
- README 和 `docs` 下已有文档

说明：仓库中的 README 和旧评审文档有少量内容已经落后于当前实现。本文档在相关章节中会明确指出差异，并以源码行为作为最终依据。

## 2. 应用定位与核心规则

AutoWifi 是一个 macOS 13 及以上版本的菜单栏应用。用户配置两个受管 Wi-Fi：

- `P`：Priority，优先网络。
- `B`：Backup，备用网络。

核心规则是：

1. 只要扫描结果中存在 P，就优先连接 P。
2. P 不存在时，如果当前不在 B，并且扫描结果中存在 B，则连接 B。
3. 当前在 B 时继续定时扫描；P 恢复后切回 P。
4. 切到配置的 B 属于正常托管流程，不会关闭自动切换。
5. 用户切到 P/B 之外的网络时，代码通过启发式规则判断这是手动覆盖还是系统回退：
   - 判断为手动覆盖时停止自动切换。
   - 判断为系统回退时保持自动切换，并尝试恢复到当前配置的 B。

## 3. 工程结构与职责

### 3.1 Swift Package 目标

`Package.swift` 定义三个目标：

| 目标 | 类型 | 职责 |
| --- | --- | --- |
| `AutoWifi` | executable | 应用入口、菜单栏图标、浮动面板和应用生命周期 |
| `AutoWifiCore` | library | 状态、Wi-Fi、设置界面、本地化和登录启动逻辑 |
| `AutoWifiTests` | test | 核心状态和 Wi-Fi 分支的单元/回归测试 |

最低平台声明为 macOS 13，Swift tools version 为 6.0。

### 3.2 主要对象关系

```text
NSApplication / AppDelegate
├── AppState
│   ├── 配置与运行状态
│   ├── UserDefaults 持久化
│   └── LaunchServiceProtocol
├── WifiManager
│   ├── CWWiFiClient / CWInterface
│   ├── CLLocationManager
│   ├── SSID 变化事件
│   └── 定时检查
└── SettingsView
    ├── 配置输入
    ├── 扫描入口
    ├── 自动切换开关
    └── 登录启动、语言、帮助、退出
```

`AppState` 和 `WifiManager` 都标记为 `@MainActor`。CoreWLAN 和 CoreLocation 的回调通过 `Task { @MainActor in ... }` 回到主 Actor 后更新状态。

## 4. 应用启动与菜单栏生命周期

### 4.1 启动顺序

应用直接创建 `NSApplication.shared`，设置 `AppDelegate` 后调用 `app.run()`，不依赖 Storyboard。

`applicationDidFinishLaunching` 的处理顺序是：

1. 创建 `AppState`。
2. 创建 `WifiManager`，注入 `AppState`。
3. 创建 `SettingsView`。
4. 创建透明、无边框、可获得键盘焦点的 `FocusablePanel`。
5. 创建菜单栏 `NSStatusItem`。
6. 订阅当前网络名，用于更新菜单栏提示文字。
7. 订阅网络类型和监控开关，用于更新菜单栏图标。
8. 注册全局鼠标点击监听；面板显示时，应用外部的全局左/右键点击会关闭面板。

### 4.2 启动时不会自动开启 Wi-Fi 自动切换

`AppState.isRunning` 的默认值固定为 `false`，且没有保存到 `UserDefaults`。`AppDelegate` 启动时只创建 `WifiManager`，没有调用 `startMonitoring()`。

因此：

- 即使上次退出前自动切换处于开启状态，再次启动也会恢复为关闭。
- “登录时启动应用”只负责启动应用本身，不等于自动开启 Wi-Fi 切换。
- 用户需要在每次应用启动后手动点击“开启自动切换”。

### 4.3 浮动面板

面板宽度固定为 360 点，高度按 SwiftUI 内容测量结果动态调整，最低高度为 360 点。

打开面板时：

- 根据菜单栏按钮的屏幕坐标，将面板水平居中放在按钮下方。
- 调用 `makeKeyAndOrderFront`，并激活应用。

关闭面板时只执行 `orderOut`，应用继续在菜单栏运行。

代码当前没有做屏幕可见区域边界修正。因此在多显示器或菜单栏按钮靠近屏幕边缘时，面板理论上可能部分超出屏幕。

### 4.4 文本快捷键

`FocusablePanel` 处理 Command-X/C/V/A，并把剪切、复制、粘贴、全选动作发送给当前第一响应者。

密码输入框还分别继承 `NSTextField` 和 `NSSecureTextField`，再次处理同样的快捷键，并提供右键编辑菜单。这是为了确保无边框浮动面板中的密码字段可以正常粘贴和编辑。

## 5. 应用状态与持久化

### 5.1 持久化字段

`AppState` 使用 `UserDefaults` 保存以下字段：

| 字段 | Key | 默认值 | 写入时机 |
| --- | --- | --- | --- |
| 优先 SSID | `ssidP` | 空字符串 | 属性变化时立即写入 |
| 优先密码 | `passwordP` | 空字符串 | 属性变化时立即写入；空值时删除 Key |
| 备用 SSID | `ssidB` | 空字符串 | 属性变化时立即写入 |
| 备用密码 | `passwordB` | 空字符串 | 属性变化时立即写入；空值时删除 Key |
| 检查间隔 | `checkInterval` | 60 秒 | 属性变化并规范化后写入 |

语言由 `LocalizationManager` 使用独立 Key `AppLanguage` 保存，默认是简体中文 `zh-Hans`。

### 5.2 不持久化的运行字段

以下字段只存在于当前进程内：

- `isRunning`：自动切换是否开启。
- `currentStatus`：最后一条业务状态消息，不含时间戳。
- `lastLog`：最后一条带时间戳的日志。
- `currentNetworkName`：当前显示的网络名或状态文本。
- `connectedNetworkType`：当前网络分类。
- `nextCheckTime`：下次定时检查时间。
- `currentCheckInterval`：当前定时器采用的间隔。

应用退出后这些值不会恢复。

### 5.3 检查间隔规范化

默认间隔为 60 秒，最小间隔为 5 秒。

规范化分支如下：

| 输入 | 内存中的规范化值 |
| --- | --- |
| 未保存过 | 60 |
| `NaN`、正/负无穷等非有限数 | 60 |
| 小于 5，包括负数和 0 | 5 |
| 大于等于 5 的有限数 | 原值 |

当属性被设置为过小值时，`didSet` 会再次把属性改成规范化值；第二次 `didSet` 才真正写入 `UserDefaults`。

初始化时如果读到的是无效已存值，只会把规范化结果放入当前 `AppState`，不会立刻回写修复磁盘上的旧值；不过每次启动都会重新规范化，所以运行时仍使用安全值。用户后续修改间隔时才会保存规范化后的新值。

已经启动的当前一次定时器不会因为用户修改间隔而立刻重建。新间隔会在下一次 `scheduleTimer()` 时生效，通常是当前计时结束并完成一次检查之后，或者用户停止再重新开启监控之后。

### 5.4 密码存储

当前实现把两个 Wi-Fi 密码直接保存在应用的 `UserDefaults` 中，没有使用 Keychain，也没有应用层加密。

因此它的准确安全语义是“只在本机应用偏好中保存，不上传”，而不是“安全加密存储”。删除输入内容时会删除对应的 Defaults Key。

### 5.5 日志行为

`AppState.log` 会：

1. 用系统短时间格式生成时间戳。
2. 组装 `[时间] 消息`。
3. 输出到标准输出。
4. 把带时间戳内容写入 `lastLog`。
5. 把原始消息写入 `currentStatus`。

只保留最后一条日志，没有日志列表、磁盘日志或历史持久化。

当前设置面板没有展示 `currentStatus` 和 `lastLog`。虽然本地化表中存在“运行状态”和“最近日志”文案，测试也会检查这些属性，但 UI 代码没有对应状态卡。这与旧评审文档中“已新增状态卡”的描述不一致。

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

当前网络名会同步到菜单栏 Tooltip，格式为 `Auto-Wifi: <当前网络名>`。

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
4. 把自己设置为定位和 Wi-Fi Client 的 delegate。
5. 注册 `.ssidDidChange` 事件监听。
6. 异步执行一次 `refreshStatus()`。

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
| 有接口且能读到 SSID=P | P 名称 | `.priority` | 清除最近受管断开上下文 |
| 有接口且能读到 SSID=B | B 名称 | `.backup` | 清除最近受管断开上下文 |
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
3. 更新 `currentCheckInterval` 和 `nextCheckTime`。
4. Timer 到期后执行 `checkConnection()`。
5. 如果仍在运行，则再次调用 `scheduleTimer()` 创建下一只 Timer。

这种设计保证每次检查完成后再开始下一周期，不会使用固定重复 Timer 直接重叠调度。但 Wi-Fi 扫描本身在主 Actor 路径上同步调用，扫描耗时时可能影响 UI 响应。

### 10.3 停止自动切换

用户点击停止时：

- 取消 Timer。
- 清空 Timer 引用和 `nextCheckTime`。
- 设置 `isRunning = false`。
- 清除最近受管网络断开上下文。
- 如果之前确实在运行或仍有 Timer，则记录 `Stopped monitoring.`。

内部也可以传入具体停止原因。例如判断用户切到未管理网络时，会保留包含网络名和判断原因的日志，而不是再被通用停止日志覆盖。

如果本来已经停止且没有 Timer，再调用停止不会新增日志。

### 10.4 运行中修改配置

P、B、密码和间隔在界面上始终可以修改，没有“运行时锁定配置”的机制。

- 修改 P：下一次 SSID 事件、状态刷新或定时检查会使用新 P。旧 P 不会像旧 B 一样被特殊跟踪；当前仍连着旧 P 时，它会被视为未管理网络或普通当前网络，并按新配置重新决策。
- 修改 B：`syncConfiguredNetworks()` 会把上一版 B 保存到 `previousBackupSSID`，以便识别系统随后连接旧 B 的情况。
- 修改密码：下一次连接尝试直接使用新密码。
- 修改间隔：当前已安排的 Timer 不变，下一轮调度才使用新间隔。
- 把 P 或 B 清空：后续周期检查只记录“SSID 未配置”，但不会自动把 `isRunning` 设为 false，Timer 仍会继续安排下一轮。

最后一个分支还有一个 UI 细节：控制按钮在 P/B 任一为空时整体禁用。如果用户在监控运行中把某个 SSID 清空，界面上的“停止自动切换”按钮也会被禁用，无法通过该按钮停止；需要先恢复非空配置或通过其它生命周期方式结束运行。这是当前实现的边界缺陷。

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

- 清除最近受管断开记录。
- 记录已连接 P、自动切换仍有效。
- 刷新状态。
- 保持 `isRunning = true`。

### 12.4 新 SSID 为 nil

这通常代表断网或切网过程中的瞬态。

处理：

1. 如果事件前的 SSID 是 P、当前 B 或上一版 B，则记录本次受管网络断开时间。
2. 记录 `Network disconnected. Waiting...`。
3. 刷新状态。
4. 保持监控，不立即在这个事件分支中扫描或连接。

是否重连由后续 SSID 事件或定时检查驱动。

### 12.5 新 SSID 是当前配置的 B

切到配置的 B 永远被视为受管自动切换流程，不会停止监控。

事件处理会先扫描一次，然后按上下文记录不同日志：

| 条件 | 解释/日志语义 |
| --- | --- |
| 12 秒内刚从受管网络断开 | 视为网络丢失后的系统切换，保持监控 |
| 没有最近断开，但扫描到 P | P 已恢复，准备立即回切，同时保持监控 |
| 没有最近断开且扫描不到 P | 视为系统回退到 B，保持监控 |

随后把本次扫描结果传给 `checkConnection()`：

- 扫描中有 P：立即连接 P。
- 扫描中无 P：保持在 B。

因此当前代码与 README 中“切到 B 且 P 可见时会停止监控”的旧描述不一致。当前实际行为是立即回到 P，并保持自动切换开启。

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
| 1 | 12 秒内刚从受管网络断开 | 系统回退 | 保持监控，尝试连接当前 B |
| 2 | 无最近受管断开，且扫描中 P 可见 | 用户手动覆盖 | 停止监控，保留具体原因日志 |
| 3 | 无最近受管断开，且扫描中 P 不可见 | 系统回退 | 保持监控，尝试连接当前 B |

这里的“手动切网”不是由系统提供的明确用户操作标志，而是启发式判断：切到未管理网络时，如果 P 仍可见且没有刚刚发生受管断开，就假设用户主动选择了别的网络。

### 12.8 判断切网原因时扫描失败

如果 `handleObservedNetworkChange` 为判断原因而扫描失败：

- 记录无法验证切网原因及错误描述。
- 不停止监控。
- 不尝试恢复 B。
- 外层事件处理随后仍会调用 `refreshStatus()`。
- 后续依赖定时检查再次处理。

## 13. 最近受管断开窗口

`managedDisconnectWindow` 固定为 12 秒。

当从以下网络收到 `SSID=nil` 事件时，会保存断开时间：

- 当前 P。
- 当前 B。
- 上一版 B。

后续 12 秒内切到其它网络，会优先被判断为系统断网后的回退，而不是用户手动切网。

断开上下文在以下情况清除：

- 状态刷新确认当前连接 P 或当前 B。
- 成功主动连接 P 或当前 B。
- 停止/重置监控。
- 恢复函数确认已经在当前 B。

超过 12 秒后 `hasRecentManagedDisconnect` 返回 false，但旧时间值不会主动设为 nil；它只是不再影响判断，直到后续清理。

## 14. 恢复到当前备用网络

`recoverToConfiguredBackupIfNeeded` 用于旧 B、系统回退到未管理网络等分支。

| 条件 | 动作 |
| --- | --- |
| 当前 B 配置为空 | 记录未配置并返回 |
| 当前已经在 B | 记录自动切换继续，清除断开上下文 |
| 当前不在 B，扫描中找到 B | 使用 B 密码连接信号最强的 B |
| 当前不在 B，扫描中找不到 B | 记录等待下次检查 |

该函数本身不优先寻找 P，因为调用它之前的事件分支已经完成了原因判断。下一次通用 `checkConnection()` 仍会重新按 P 优先处理。

## 15. 主动连接处理

连接前设置 `isSwitchingNetwork = true`，2 秒后通过主队列异步恢复为 false，用于覆盖程序连接引发的 SSID 通知窗口。

成功分支：

1. 调用 CoreWLAN `associate`。
2. 更新 `lastObservedSSID`。
3. 如果目标是 P 或当前 B，清除最近断开上下文。
4. 记录成功日志。
5. 调用 `refreshStatus()` 更新 UI 状态。

失败分支：

- 记录目标 SSID 和错误描述。
- 不停止监控。
- 不立即重试。
- `isSwitchingNetwork` 仍会在原定 2 秒后恢复。
- 后续由 Timer 再次尝试。

如果连接函数执行时接口引用为 nil，函数直接返回，不写日志。不过正常入口通常已经在扫描或检查阶段验证过接口。

## 16. 手动扫描功能

点击“扫描网络”时：

1. 请求定位权限。
2. 设置 `isScanning = true`。
3. 清空上次网络列表。
4. 写入本地化的“扫描中”日志。
5. 调用 `WifiManager.getAvailableNetworks()`。
6. 完成后更新网络列表并停止旋转动画。

扫描结果处理：

- 丢弃 `ssid == nil`。
- 丢弃空字符串 SSID。
- 用 `Set` 去重。
- 按字符串升序排序。

UI 分支：

- 未扫描到列表时，P/B 都使用可自由输入的 `TextField`。
- 有扫描列表时，P/B 都切换为 Picker；包含一个空值“选择网络”选项。
- 扫描中禁用扫描按钮并旋转图标。

异常处理：

- Wi-Fi 扫描错误会记录 `❌ Scan error: ...` 并返回空数组。
- 如果错误描述包含小写字符串 `location`，再记录一次定位权限建议。该判断依赖错误文本和大小写，不是结构化错误判断。
- UI 无法区分“周围确实没有网络”和“扫描失败”，两者最终都会显示定位权限提示。
- 第二条 UI 提示日志会覆盖 `lastLog/currentStatus` 中前一条具体扫描错误；具体错误仍只留在标准输出中。

## 17. 设置界面功能

### 17.1 顶部操作

- 登录启动：电脑图标；开启时蓝色，关闭时灰色。
- 语言切换：中文状态显示 `EN`，英文状态显示 `中`，表示点击后的目标语言。
- 帮助：弹出 300×250 的可滚动说明。
- 退出：直接调用 `NSApplication.shared.terminate(nil)`。

四个按钮都使用系统 `.help` 和自定义悬浮胶囊提示。自定义提示位于面板右上区域，同一时间只显示一个。

### 17.2 当前网络与扫描卡片

显示 `currentNetworkName`。只有扫描得到非空列表时才显示“找到 N 个网络”。

### 17.3 P/B 配置卡片

每张卡包括：

- SSID 手动输入或扫描结果 Picker。
- 密码输入框。
- 明文/密文切换按钮。
- 原生编辑快捷键和右键菜单。

明文和密文切换会在 `NSTextField` 与 `NSSecureTextField` 两种原生控件之间重建视图，但都绑定同一个密码字符串。

### 17.4 自动切换控制

- P/B 任一为空时按钮禁用。
- 关闭状态：蓝色按钮，播放图标，文案“开启自动切换”。
- 开启状态：红色按钮，停止图标，文案“停止自动切换”。
- 运行且存在 `nextCheckTime` 时，用 `TimelineView` 显示向下取到 0 的剩余秒数。

### 17.5 本地化范围

界面支持简体中文和英文，语言切换会持久化。

未完全本地化的内容包括：

- 多数 `WifiManager` 运行日志是英文。
- `Ready`、`Not Connected`、`No Interface`、`Location Permission Denied` 等部分状态文本是英文常量。
- 密码字段右键菜单固定为英文 Cut/Copy/Paste/Select All。
- 菜单栏 Tooltip 前缀固定为 `Auto-Wifi`。

找不到本地化 Key 时，会直接显示 Key 本身。

## 18. 登录启动

macOS 13 及以上使用 `SMAppService.mainApp`：

- `isEnabled` 只在状态为 `.enabled` 时返回 true。
- 开启调用 `register()`。
- 关闭调用 `unregister()`。

`AppState` 初始化时会读取服务真实状态并同步 UI。同步期间通过 `isSynchronizingLaunchAtLogin` 防止 `didSet` 再次触发注册/注销。

用户切换开关时的分支：

| 条件 | 处理 |
| --- | --- |
| 正在同步系统状态 | 不调用服务 |
| 没有服务对象 | 直接返回 |
| 服务状态已经等于目标状态 | 直接返回 |
| 注册/注销成功 | 记录成功日志 |
| 注册/注销失败 | 记录失败日志，并把 UI 回滚到服务当前真实状态 |

`LaunchAtLoginManager` 自身还会把失败打印到标准输出，然后继续向上抛出。

虽然代码保留了旧系统使用 `MockLaunchService` 的分支，但 Package 最低平台就是 macOS 13，该分支在正式支持范围内不会使用。

## 19. 系统配置、权限和沙箱

`Info.plist` 的关键配置：

- `LSUIElement = true`：作为菜单栏 Agent 运行，不显示普通 Dock 图标。
- `NSLocationWhenInUseUsageDescription`：解释读取 SSID 和扫描 Wi-Fi 需要定位权限。
- 最低系统版本由打包时写入。

Entitlements：

- 开启 App Sandbox。
- 允许网络 Client。
- 允许访问定位信息。

源码以代码方式启动，不需要 Storyboard。模板 `Info.plist` 中仍有 `NSMainStoryboardFile=Main`，但打包脚本会删除该 Key。若绕过脚本手工组装 App，需要同样处理。

## 20. CLI 版本

`auto-wifi-cli.swift` 是独立实现，不复用 `AutoWifiCore`。

支持两种配置方式：

1. 命令行参数：`P SSID`、`P 密码`、`B SSID`、`B 密码`、可选间隔。
2. 参数不足时进入交互输入。

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
- 没有 12 秒断开窗口或旧 B 迁移逻辑。
- 没有配置持久化、登录启动、菜单栏 UI 和本地化。
- 扫描和连接错误统一记录为 `Error: ...`。
- 初始化时只获取一次 `CWInterface`，后续不会重新获取接口引用。
- 命令行直接传密码时，密码可能出现在 Shell 历史或进程参数中。
- 交互密码使用普通 `readLine()`，输入不会隐藏。

## 21. 构建和打包

打包脚本默认行为：

1. 使用 `swift build -c release` 构建。
2. 在 `dist/AutoWifi.app` 组装 App Bundle。
3. 复制并改写 `Info.plist` 的可执行文件名、Bundle ID、版本、构建号、最低系统版本和图标名。
4. 删除 `NSMainStoryboardFile`。
5. 用 `sips` 从 1024 PNG 生成多尺寸 iconset。
6. 用 `iconutil` 生成 `AppIcon.icns`。
7. 默认使用 `-` 做 ad-hoc codesign；也可指定 Developer ID 或传空字符串跳过签名。
8. 用 `ditto` 生成 `dist/AutoWifi-macos.zip`。

脚本使用 `set -euo pipefail`，多数命令失败会立即结束。特殊分支包括：

- 构建后找不到可执行文件：打印错误并退出 1。
- 源图标不存在：跳过图标生成，但仍继续打包。
- 删除模板中的 Storyboard Key 失败：显式忽略，因为该 Key 可能不存在。
- 临时 iconset 目录通过 `trap` 在退出时清理。

当前脚本不包含公证 notarization、DMG、自动上传或 CI 发布流程。

## 22. 测试覆盖

测试使用 Mock Wi-Fi 网络、接口、Client、Location Manager 和登录启动服务。当前共有 16 个测试，覆盖：

1. 从 `UserDefaults` 加载 SSID、密码、间隔。
2. 配置持久化和最小间隔规范化。
3. 登录启动失败后的 UI 状态回滚。
4. WifiManager 初始化时注册 SSID 变化监听。
5. 定位权限拒绝时清除网络类型。
6. 同名 P 中选择最强信号。
7. P 不存在时连接 B。
8. 手动扫描结果去重、过滤 nil 并排序。
9. 监控关闭时 SSID 变化仍更新显示状态。
10. 切到 B 且 P 可见时立即回 P，并保持监控。
11. 切到 B 且 P 缺失时留在 B，并保持监控。
12. 发生断网事件后切到 B、P 可见时回 P。
13. 完整验证“P 丢失 → B → P 恢复 → P”，全程不关闭开关。
14. B 配置变化后连到旧 B 时，恢复到当前 B。
15. 旧 B 和 P 同时可见时仍恢复到当前 B。
16. 切到未管理网络且 P 可见时停止监控。

尚未被单元测试直接覆盖的关键分支包括：

- SSID 事件注册失败。
- 无 Wi-Fi 接口时的启动/检查。
- 扫描抛错及定位错误文本二次提示。
- 连接抛错后的状态和后续重试。
- 程序主动连接产生的两秒通知窗口。
- 12 秒窗口过期前后的边界值。
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
| 连接失败 | 记录目标网络和错误 | 否 | 下个周期重试 |
| 手动扫描为空/失败 | UI 显示权限提示 | 不影响当前开关 | 用户可再次扫描 |
| 登录启动注册/注销失败 | 记录错误并回滚按钮 | 不影响 Wi-Fi 开关 | 保持系统真实启动项状态 |
| 用户切到未管理网络且 P 可见 | 记录手动覆盖判断 | 是 | 需用户重新开启 |
| 系统切到未管理网络且 P 不可见 | 尝试恢复 B | 否 | 找不到 B 时等待下次检查 |
| 连接到旧 B | 尝试恢复当前 B | 否 | 找不到当前 B 时等待 |
| 检查间隔小于 5 | 自动改为 5 | 否 | 新调度周期使用规范化值 |
| 检查间隔非有限数 | 自动改为 60 | 否 | 新调度周期使用默认值 |

## 24. 当前实现限制与注意事项

以下内容不是代码注释中的设想，而是从当前实现可以确认的限制：

1. 自动切换开关不持久化，应用重启后默认关闭。
2. 登录启动不会顺带开启自动切换。
3. 密码存储在 `UserDefaults`，不是 Keychain 或加密存储。
4. 只支持一个 P 和一个 B，不支持多级优先列表。
5. 只用 SSID 和 RSSI 选择网络，不判断 BSSID、安全类型、频段或网络可用性。
6. “P 可见”只代表扫描结果中有同名 SSID，不代表互联网连通、信号足够好或认证一定成功。
7. 没有 RSSI 阈值、迟滞策略、连接失败退避，弱 P 只要可见也优先于强 B。
8. 手动切网判断是启发式，存在误判可能。
9. 切到配置 B 永远保持托管，用户若确实手动选择 B，只要自动切换开启，P 可见时仍会被切回 P。
10. Wi-Fi 扫描和关联调用位于主 Actor 流程，耗时操作可能影响界面响应。
11. 运行日志没有完全本地化，且只保留最后一条。
12. `currentStatus/lastLog` 当前未显示在设置面板。
13. 手动扫描失败和真实空列表在 UI 上不可区分。
14. 当前只跟踪上一版 B；连续多次修改 B 后，更早的旧 B 会被当成普通未管理网络。
15. 没有显式处理睡眠/唤醒、Wi-Fi 开关开闭、网络服务重建等生命周期事件，只依赖接口重取、SSID 事件和 Timer。
16. 没有网络连通性检测；连接到 SSID 成功即视为成功。
17. 没有公证发布流程，默认产物只是 ad-hoc 签名。
18. 运行中清空 P/B 不会自动停止 Timer，却会让 UI 的启停按钮禁用。
19. P/B 可以配置成相同值，代码没有校验；此时 P 分支和 P 密码优先。

## 25. 现有文档与当前代码的已知差异

维护时应以本文档和源码为准，以下旧描述已经不准确：

- README 仍写着“切到 B 且 P 可见时认为是手动覆盖并停止监控”。当前代码会保持监控并立即回 P。
- `docs/PROJECT_REVIEW.md` 写着 UI 已新增运行状态卡。当前 `SettingsView` 没有渲染 `currentStatus` 或 `lastLog`。
- 帮助文案写着“手动切换网络会停止监控”，实际只在启发式判断为手动切到未管理网络时停止；切到配置 B 不停止。

如果后续继续维护项目，建议同步修正 README、帮助文案和旧评审文档，避免产品说明与实际状态机再次分叉。

# Via 共享策略核心

`core/` 是与平台无关的自动切换策略实现，用 Rust 编写，通过稳定的 C ABI 供
macOS、Windows、Android 和 iOS 复用。它的目标是让四个平台对“什么时候扫描、
什么时候切换、什么时候停止”给出完全一致的决定，而把“怎么扫描、怎么连接、
怎么申请权限”留给各平台原生适配层。

当前 macOS 应用已经接入该核心的**关联生命周期与程序化切换意图**；完整的
检查流程仍由 `WifiManager` 的 Swift 实现驱动，两者行为一致，后续可以逐段替换。

## 目录结构

```text
core/
├── Cargo.toml                  Rust workspace
├── crates/
│   ├── via-domain/            纯策略状态机（无依赖、无 I/O）
│   ├── via-ffi/               C ABI 导出层（staticlib / cdylib）
│   └── via-jni/               Android JNI/JSON 桥（cdylib）
├── include/
│   ├── via_core.h             权威 C 头文件
│   └── module.modulemap        SwiftPM systemLibrary 模块
└── tests/
    └── ffi_smoke.c             C ABI 快速验证
```

`via-domain` 不依赖任何第三方 crate，也不读取时钟、文件、钥匙串或系统
网络状态。它只接收调用方传入的 `now_ms` 和观察结果，返回一组 `Action`。

## 设计约束

- **纯决策**：核心不执行扫描、关联或权限请求，只告诉调用方下一步做什么。
- **时间由调用方提供**：所有超时、冷却和宽限判断都基于传入的 `now_ms`。
- **不碰密码**：核心只处理 SSID，凭据由各平台的凭据存储负责。
- **单线程使用**：一个引擎实例同一时间只应被一个线程调用；跨线程调用方需自行加锁。
- **确定性**：相同的输入序列产生相同的 `Action` 序列，便于单元测试和跨端对齐。

## 状态与动作

核心维护：

- 优先网络 `P`、备用网络 `B` 与运行开关
- 当前 SSID、权限状态、关联代次（generation）
- 程序化切换意图及其时间窗
- 备用网络冷却目标与截止时间
- 上一个观察到的备用网络 SSID

返回的动作包括：

| 动作 | 含义 |
| --- | --- |
| `Scan(purpose)` | 扫描，并说明这次扫描的用途 |
| `Associate { ssid, role }` | 关联到目标网络 |
| `CheckNow` | 立即重新检查（扫描期间配置发生变化） |
| `Stop(reason)` | 停止自动监控（未配置、手动覆盖） |
| `WaitForPermission` | 暂停并等待用户授权 |
| `Log(event)` | 语义日志事件 |
| `RefreshStatus` | 刷新界面状态 |

让调用方处理这些动作，而不是在核心里回调平台 API，是为了让同一套策略能在
不同语言、不同线程模型和不同测试环境中复用。

## 构建与测试

需要 Rust 工具链（建议 1.75+）。所有命令都可以在仓库根目录执行：

```bash
cargo test --manifest-path core/Cargo.toml
cargo build --manifest-path core/Cargo.toml -p via-ffi --release
```

构建产物：

- `core/target/release/libvia_core.dylib`（macOS）
- `core/target/release/libvia_core.a`（静态库）
- 其它平台对应 `libvia_core.so` / `via_core.dll` 等

仓库脚本会构建并复制动态库到 `dist/`：

```bash
scripts/build-core.sh          # release
scripts/build-core.sh debug    # debug
```

### C ABI 冒烟测试

```bash
cc -I core/include core/tests/ffi_smoke.c \
  core/target/release/libvia_core.a \
  -o /tmp/via-ffi-smoke
/tmp/via-ffi-smoke
```

看到 `ffi smoke ok` 即表示 C ABI 的创建、扫描、关联、超时和手动覆盖路径正常。

## C ABI 约定

头文件：[`include/via_core.h`](include/via_core.h)

- 枚举值以稳定的整数编码导出，新增值只追加、不复用。
- `ViaResult` 中的 `actions`、`ssid` 以及 `ViaSnapshot` 中的 SSID 指针由引擎
  持有，**只在下一次调用同一引擎前有效**。调用方需要保留时应立即复制。
- 字符串为 NUL 结尾的 UTF-8；输入中的非法 UTF-8 按空值处理，包含内部 NUL
  的 SSID 不会渲染成关联动作。
- 每个 `ViaEngine` 必须用 `via_engine_new` 创建、`via_engine_free` 释放。
- 引擎不是线程安全的；不要并发调用同一个实例。
- 扫描结果与分类结果使用三态整数：`1` = 可见，`0` = 确认不可见，
  `-1` = 未知/扫描失败。未知结果只记录 `VIA_LOG_PRIORITY_VISIBLE_UNKNOWN`
  并刷新状态，绝不解释为 P 已丢失；JNI 桥的对应参数也使用同样的整数。
- 关联结果 `3` = `VIA_ASSOCIATION_ADVISORY_ENDED`：用于系统建议或用户取消，
  只结束在途关联，不应用失败冷却。
- `via_engine_snapshot` 接收只读 `const ViaEngine *`；其返回的两个 SSID 指针
  保存在线程局部缓存中，同样只在下一次快照调用前有效。

Swift 侧通过 `Sources/ViaCore/WifiPolicy.swift` 使用 `dlopen`/`dlsym`
加载动态库，因此 SwiftPM 构建不依赖 XCFramework。加载顺序：

1. 环境变量 `VIA_CORE_PATH`
2. `Contents/Frameworks/libvia_core.dylib`
3. bundle 根目录及其它常见位置
4. 从当前目录向上查找 `core/target/{release,debug}/libvia_core.dylib`

找不到核心时，macOS 应用会退回原有的 Swift 逻辑，不会崩溃。

## 接入新平台

1. 用目标平台的语言声明 C ABI（C# `DllImport`、Kotlin/JNI、Swift module map）。
2. 实现一个适配层，把平台事件翻译成核心调用：
   - 启动/停止、配置变化
   - 权限状态
   - 三态扫描结果：`P` / `B` 是否发现、或扫描是否无法确认
   - 关联开始、成功、超时、失败、建议结束（无冷却）
   - 观察到的 SSID 变化
3. 执行核心返回的 `Action`：
   - `Scan` → 平台扫描 API
   - `Associate` → 平台连接 API
   - `WaitForPermission` → 引导授权
   - `Log` → 平台日志
4. 每 15 秒左右调用一次 `check_begin`，或由平台事件驱动；`now_ms` 使用单调时钟。

平台能力差异只影响 `Associate` 的实现方式，不改变策略决定：

- **macOS / Windows**：可以直接关联并切换。
- **Android**：通过 `WifiNetworkSuggestion` 提交建议，由系统决定是否切换。
- **iOS**：没有公开扫描 API，`NEHotspotConfiguration` 加入网络需要用户确认，
  因此只能做“建议 + 用户确认”的交互。

## 当前 macOS 接入范围

已接入（`Sources/ViaCore/WifiManager.swift`）：

- 配置同步：`set_config`
- 启动/停止：`start` / `stop`
- 程序化切换意图与冷却：`association_started` / `association_result` /
  `late_association_result` / `is_recent_programmatic_backup`
- 关联代次校验：`is_current_generation`

尚未接入：

- 主检查流程的 `check_begin` / `scan_result` / `classification_result` /
  `backup_scan_result` / `observed_change`
- 这些分支仍由 Swift 实现，行为与核心测试一致；替换时应逐个分支切换并补充
  对应平台测试。

# Android 客户端

Kotlin + Jetpack Compose 客户端，使用共享 Rust 策略核心（JNI）和系统
`WifiNetworkSuggestion` API。

## 结构

- `app/src/main/java/com/autowifi/policy/PolicyEngine.kt`：JNI 封装，JSON 结果解析。
- `app/src/main/java/com/autowifi/data/`：设置、加密密码存储、Wi-Fi 读取。
- `app/src/main/java/com/autowifi/service/`：前台监控服务、开机广播、状态总线。
- `app/src/main/java/com/autowifi/ui/`：Compose 界面、主题和 ViewModel。
- `app/src/main/java/com/autowifi/L10n.kt`：中英文文案。

## 界面

首次安装会进入三步设置向导（授权定位 → 选择 P/B → 完成并开启监控），完成后
不再自动出现，可在“设置”里重新运行。主界面是状态 / 网络 / 设置三个 Tab，支持
点击或左右滑动切换。网络页扫描后，P、B 的 SSID 输入框会变成下拉列表，可直接
从扫描结果中选择，也可以手动输入。

前台服务的通知使用应用自己的普通通知小图标，不显示 P/B 或红点；当前网络和角色
由通知文字表达。监控运行时，通知显示到下次检查的倒计时，倒计时由系统
`Chronometer` 渲染，应用只在重新排期时更新一次通知，不会每秒唤醒。

编辑密码并保存后，服务通过 `ACTION_RESTART` 原地重启循环：重新读取设置并用新密码
重新注册 `WifiNetworkSuggestion`，无需重启应用。Android 不会把关联失败的原因
（例如密码错误）告诉应用，因此失败在界面上表现为“连接超时，请检查密码和信号”。

应用图标由 `scripts/generate-app-icons.swift` 生成：蓝色渐变背景、缩小的 Wi-Fi
标记和“Auto”字样。自适应图标的前景图位于 `res/mipmap-*/ic_launcher_foreground.png`。

## 构建

需要 JDK 17、Android SDK 35、NDK 27、Gradle 8.10+ 和 `cargo-ndk`。

```bash
cargo install cargo-ndk
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
scripts/build-android-core.sh
cd platforms/android
gradle assembleRelease
```

release 构建启用 R8 代码压缩和资源裁剪，并用调试密钥签名（仅用于测试），产物在
`app/build/outputs/apk/release/`。CI 会传入 `-PbuildNumber=<运行号>`，让 APK 的
`versionName`（`1.0.<运行号>`）与 Release 标签一致。

`scripts/build-android-core.sh` 生成 `libautowifi_jni.so` 到
`app/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}/`。

运行 JVM 单元测试（不需要 NDK）：

```bash
cd platforms/android
gradle testDebugUnitTest
```

本地没有安装 Gradle 时，可以用 Android Studio 打开 `platforms/android`；命令行构建
则需要在 `platforms/android/local.properties` 写入 `sdk.dir=<Android SDK 路径>`，
或设置 `ANDROID_HOME`。

## 权限

- `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION`：读取 SSID 和扫描。
- `NEARBY_WIFI_DEVICES`（Android 13+）：Wi-Fi 建议和附近网络。
- `POST_NOTIFICATIONS`（Android 13+）：前台服务通知。
- `FOREGROUND_SERVICE_CONNECTED_DEVICE`：持续监控。
- `RECEIVE_BOOT_COMPLETED`：开机自动监控（需在设置中开启）。

## Android 限制

- 应用不能静默强制连接。P/B 会注册为 `WifiNetworkSuggestion`，由系统决定何时切换。
- 后台扫描受系统限频；策略循环会复用最近一次扫描结果。
- 读取 SSID 需要定位权限，且系统定位服务需要开启。
- 前台服务会显示常驻通知；这是持续监控的必要条件。

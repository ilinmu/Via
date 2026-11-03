# Android 客户端

Kotlin + Jetpack Compose 客户端，使用共享 Rust 策略核心（JNI）和系统
`WifiNetworkSuggestion` API。

## 结构

- `app/src/main/java/com/autowifi/policy/PolicyEngine.kt`：JNI 封装，JSON 结果解析。
- `app/src/main/java/com/autowifi/data/`：设置、加密密码存储、Wi-Fi 读取。
- `app/src/main/java/com/autowifi/service/`：前台监控服务、开机广播、状态总线。
- `app/src/main/java/com/autowifi/ui/`：Compose 界面、主题和 ViewModel。
- `app/src/main/java/com/autowifi/L10n.kt`：中英文文案。

## 构建

需要 JDK 17、Android SDK 35、NDK 27、Gradle 8.10+ 和 `cargo-ndk`。

```bash
cargo install cargo-ndk
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
scripts/build-android-core.sh
cd platforms/android
gradle assembleDebug
```

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

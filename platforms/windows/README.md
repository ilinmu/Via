# Windows 客户端

基于 .NET Framework 4.8 + WPF 的托盘 AutoWifi 客户端。窗口关闭后继续驻留托盘，
右键菜单提供“打开”和“退出”。

## 结构

- `App.xaml.cs`：单实例、托盘和窗口生命周期。
- `MainWindow.xaml(.cs)`：状态 / 网络 / 设置三个 Tab。
- `SetupWindow.xaml(.cs)`：首次运行的设置向导（欢迎 → 选择网络 → 完成）。
- `MonitorService.cs`：策略循环，执行扫描和关联动作。
- `PolicyEngine.cs`：`autowifi_core.dll` 的 P/Invoke 封装。
- `NativeCore.cs`：便携版把核心 DLL 嵌入 exe，启动时释放到
  `%LocalAppData%\AutoWifi\bin` 并按绝对路径加载。
- `WlanApi.cs`：WlanAPI（扫描、当前 SSID、WLAN 配置文件、连接）。
- `CredentialStore.cs`：Windows Credential Manager。
- `SettingsStore.cs`：`%LocalAppData%\AutoWifi\settings.json` 与开机启动注册表项。

## 测试

先运行 `scripts/build-windows-core.ps1` 生成 `autowifi_core.dll`，然后：

```powershell
dotnet test platforms/windows.tests/AutoWifi.Windows.Tests.csproj
```

xUnit 测试覆盖设置归一化、本地化文案，以及通过 C ABI 驱动的策略引擎行为。

## 构建

需要 .NET SDK 和 Rust stable；运行目标为 .NET Framework 4.8（Windows 10 1903+
和 Windows 11 自带，无需安装运行时）。

```powershell
./scripts/build-windows-core.ps1

# 免安装单文件：核心 DLL 已嵌入 exe，双击即可运行，约 1 MB
dotnet publish platforms/windows/AutoWifi.Windows.csproj `
  -c Release -p:Platform=x64 -o dist/windows-portable

# 安装程序：发布同一应用的目录，再用 Inno Setup 打包
dotnet publish platforms/windows/AutoWifi.Windows.csproj `
  -c Release -p:Platform=x64 -o dist/windows-app
ISCC.exe /DAppVersion=1.0.0 platforms/windows/installer.iss
```

`installer.iss` 生成 `dist/AutoWifi-windows-setup.exe`（可选桌面快捷方式、自带
卸载程序）。`.NET Framework 4.8` 是系统组件，所以两个产物都不需要用户预装
运行时，体积也只有 1–2 MB。

`AutoWifi.Windows.csproj` 会自动复制 `core/target/.../autowifi_core.dll` 到输出目录。

## 界面

首次启动会打开三步设置向导；配置完整并完成后写入 `SetupCompleted`，之后可在
“设置”里重新运行。若标记丢失或 P/B 为空，仍会进入向导。网络页的 P、B 输入框是可编辑下拉框，扫描后可从结果中选择或直接输入。
语言使用下拉框选择，与 macOS 一致。

## 行为说明

- 应用图标为 `Assets/app.ico`，由 `scripts/generate-app-icons.swift` 生成，同时用于
  窗口和任务栏。
- 托盘图标与 macOS 菜单栏图标一致：运行中显示 Wi-Fi + 当前角色（P/B），停止时显示
  红点；颜色随任务栏明暗自动切换，悬停显示当前网络与角色。
- 密码只写入 Windows Credential Manager（目标名 `AutoWifi/passwordP`、
  `AutoWifi/passwordB`），不写入 JSON 设置。
- 连接使用 `WlanSetProfile` + `WlanConnect`，随后轮询当前 SSID，超时视为失败。
- 扫描会等待约 2.5 秒让 WlanAPI 完成异步扫描。
- 登录启动写入当前用户的 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`。

## 限制

- 需要系统允许应用修改 WLAN 配置；受组策略管理的设备可能拒绝。
- 部分企业网络使用 802.1X，当前只生成开放或 WPA2-PSK 配置文件。

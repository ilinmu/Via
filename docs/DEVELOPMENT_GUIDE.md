# Via 开发指南

## 1. 技术栈总览

Via v2.0 使用单一 Go 模块管理所有业务逻辑、UI 与多端打包：

- **策略核心（`internal/policy`）**：纯 Go 状态机，所有时钟与外部事件由调用方注入，可在任意平台执行全覆盖单元测试。
- **监控协调器（`internal/wifi`）**：管理扫描稳定窗口（`2s` + 3 次复扫）、手动切换误判复核（`25s`）、关联超时与定时巡检。
- **平台原生桥接（`internal/nativewifi`）**：使用 `//mygo:native` 自动生成 Swift 与 Kotlin 绑定代码：
  - `swift/`：macOS `CoreWLAN`、`CoreLocation`、`AppKit` 菜单栏 SF Symbol 渲染；
  - `kotlin/`：Android `WifiManager`、`ConnectivityManager`、`WifiNetworkSuggestion` 与低打扰前台通知。
- **原生 UI（`internal/uiapp`）**：基于 MyGo `ui` 原生绘制引擎，不内嵌浏览器或 WebView。

## 2. 常用开发命令

```sh
# 1. 环境体检
go tool mygo doctor

# 2. 更新 nativewifi 绑定并编译检查 Swift 模块
go tool mygo native check internal/nativewifi

# 3. 运行静态检查与单元测试
go vet ./...
GOOS=windows GOARCH=amd64 go vet ./...
GOOS=linux GOARCH=amd64 go vet ./...
go test -race -v ./...

# 4. 启动本地桌面调试
go tool mygo dev

# 5. 打包 macOS 沙盒应用
go tool mygo build -skip-dmg

# 6. 测试包内 CLI 诊断
"./build/darwin-arm64/Via.app/Contents/MacOS/Via" doctor
```

## 3. 修改 `nativewifi` 接口约定

1. 只修改 [`internal/nativewifi/nativewifi.go`](../internal/nativewifi/nativewifi.go) 中的接口与数据结构。
2. 切勿手动编辑 `nativewifi_native.go`、`Nativewifi.mygo.swift` 或 `Nativewifi.mygo.kt`。
3. 修改接口后立即运行 `go tool mygo native check internal/nativewifi` 重新生成绑定，然后补齐 Swift 与 Kotlin 实现。

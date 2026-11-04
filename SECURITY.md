# 安全政策

## 报告漏洞

请**不要**在公开 issue 中披露安全问题。请通过 GitHub 的私密漏洞报告功能提交：

1. 打开仓库的 **Security** 标签页。
2. 选择 **Advisories** → **Report a vulnerability**。
3. 说明受影响的平台（macOS / Windows / iOS / Android）、版本、复现步骤和影响范围。

我们会在确认后尽快回复，并在修复发布后公开致谢（如果你愿意）。

## 支持范围

安全修复只针对 `master` 分支和最新一次 Release。旧版本不单独维护。

## 凭证与密钥约定

本仓库遵循以下约定，提交 PR 前请确认：

- **不提交任何** token、API key、密码、证书、签名私钥、provisioning profile、keystore 或 `.env` 文件。
- 签名身份、Team ID 等敏感信息通过环境变量或本机配置传入，不写入仓库。
- CI 只使用 GitHub 自动生成的 `GITHUB_TOKEN`，工作流默认权限为只读；发布 job 才临时申请 `contents: write`。
- 各平台的 Wi-Fi 密码只存放在系统提供的安全存储中：
  - macOS：Keychain
  - iOS：Keychain
  - Windows：Credential Manager
  - Android：`EncryptedSharedPreferences`（`allowBackup=false`）
- 日志和状态界面不输出密码；诊断日志只包含 SSID 和连接结果。

## 依赖与供应链

- 第三方 GitHub Actions 建议固定到 commit SHA，并由 Dependabot 定期更新。
- 仓库启用了 Dependabot 版本更新（见 `.github/dependabot.yml`）。
- 公开仓库后请在 GitHub 设置中启用 **Secret scanning**、**Push protection** 和 **Dependabot alerts**。

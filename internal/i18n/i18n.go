// Package i18n provides Via's unified Simplified Chinese and English strings.
package i18n

import (
	"os"
	"strings"
)

type Lang string

const (
	LangZH Lang = "zh"
	LangEN Lang = "en"
)

// DetectSystemLang inspects environment locale variables and defaults to English unless zh.
func DetectSystemLang() Lang {
	for _, key := range []string{"LC_ALL", "LC_MESSAGES", "LANG"} {
		v := strings.ToLower(os.Getenv(key))
		if strings.HasPrefix(v, "zh") {
			return LangZH
		}
		if v != "" && v != "c" && v != "posix" {
			return LangEN
		}
	}
	return LangEN
}

// Strings holds every user-facing UI, tray, and notification string.
type Strings struct {
	NavDashboard string
	NavSettings  string

	BadgeGuardPriority string
	BadgeGuardBackup   string
	BadgeGuardOther    string
	BadgePaused        string
	BadgeNoPermission  string
	BadgeNotConfigured string

	PrimarySlotLabel string
	BackupSlotLabel  string

	AutoSwitchTitle    string
	SubCheckingInFmt   string
	SubBackupInFmt     string
	SubGuardWaiting    string
	SubPausedManual    string
	SubPausedStopped   string
	SubNeedPermission  string
	SubNotConfigured   string
	SubIOSUnsupported  string
	SubAndroidAdvisory string

	BtnResumeNow    string
	BtnGrantPerm    string
	BtnOpenSysSet   string
	BtnRecheckPerm  string
	BtnSetupNet     string
	BtnScanNearby   string
	BtnScanning     string
	BtnSwitchNow    string
	BtnUseCurrent   string
	BtnCancel       string
	BtnSave         string
	BtnQuit         string
	BtnRerunWizard  string

	PickerTriggerFmt  string
	PickerEmpty       string
	PickerEmptyList   string
	PickerCurrentFmt  string
	PickerNoCurrent   string
	PermMacSettingsHint string
	LockedCardHint    string
	SwitchFailedFmt   string

	ManagedNetworksTitle string
	RoleBadgeP           string
	RoleBadgeB           string
	PrimaryLabel         string
	BackupLabel          string
	ConnectedTag         string
	NotSetTag            string
	SSIDPlaceholder      string
	PwdPlaceholder       string
	ErrEmptySSID         string
	ErrDuplicateSSID     string
	SavedNotice          string
	SwitchedNotice       string

	SettingsGeneralTitle  string
	LaunchAtLoginTitle    string
	LaunchAtLoginDesc     string
	BootRestoreTitle      string
	BootRestoreDesc       string
	LaunchApprovalHint    string
	LanguageLabel         string
	IntervalTitle         string
	IntervalPresets       [4]string
	IntervalCustom        string
	IntervalSecondsSuffix string
	IntervalClampedHint   string
	AboutTitle            string
	HelpTitle             string
	HelpLines             [3]string
	PrivacyNote           string

	WizardTitle           string
	WizardSkip            string
	WizardSteps           [3]string
	WizardStep1Title      string
	WizardStep1Desc       string
	WizardStep1Grant      string
	WizardStep1Manual     string
	WizardStep2Title      string
	WizardStep2SetP       string
	WizardStep2SetB       string
	WizardStep2Manual     string
	WizardPrev            string
	WizardNext            string
	WizardStep3Title      string
	WizardPermStatus      string
	WizardPermGranted     string
	WizardPermPending     string
	WizardFinishAndStart  string
	WizardFinishSaveOnly  string

	TrayTooltipPaused   string
	TrayTooltipPrimary  string
	TrayTooltipBackup   string
	TrayTooltipOther    string
	MenuOpenPanel       string
	MenuTogglePause     string
	MenuQuit            string
}

var zhStrings = Strings{
	NavDashboard: "主控台",
	NavSettings:  "设置",

	BadgeGuardPriority: "自动守护中-首选",
	BadgeGuardBackup:   "自动守护中-备用",
	BadgeGuardOther:    "自动守护中",
	BadgePaused:        "已暂停",
	BadgeNoPermission:  "缺少权限",
	BadgeNotConfigured: "未配置",

	PrimarySlotLabel: "主路径 · 首选",
	BackupSlotLabel:  "备路径 · 备用",

	AutoSwitchTitle:    "智能自动切换",
	SubCheckingInFmt:   "下次检查：约 %d 秒",
	SubBackupInFmt:     "重检首选网络：约 %d 秒",
	SubGuardWaiting:    "守护运行中 · 靠近首选或备用将自动切换",
	SubPausedManual:    "检测到手动切换，已暂停避免干扰",
	SubPausedStopped:   "自动切换已关闭",
	SubNeedPermission:  "需要定位权限才能读取 Wi-Fi 名称与扫描网络",
	SubNotConfigured:   "请先设置首选与备用网络后再开启",
	SubIOSUnsupported:  "iOS 系统限制后台自动切换 Wi-Fi，当前仅支持查看配置状态",
	SubAndroidAdvisory: "Android 模式下将通过系统网络建议优先级引导自动切换",

	BtnResumeNow:   "立即恢复",
	BtnGrantPerm:   "去授权",
	BtnOpenSysSet:  "打开系统设置",
	BtnRecheckPerm: "重新检测",
	BtnSetupNet:    "点击设置网络",
	BtnScanNearby:  "扫描附近",
	BtnScanning:    "扫描中…",
	BtnSwitchNow:   "切换",
	BtnUseCurrent:  "使用当前网络",
	BtnCancel:      "取消",
	BtnSave:        "保存",
	BtnQuit:        "退出 Via",
	BtnRerunWizard: "重新运行首次设置向导",

	PickerTriggerFmt:    "选择网络（附近 %d 个）",
	PickerEmpty:         "点击选择当前或附近网络",
	PickerEmptyList:     "暂无扫描结果，请点右上角「扫描附近」或下方手动输入",
	PickerCurrentFmt:    "使用当前网络：%s",
	PickerNoCurrent:     "使用当前网络（当前未连接）",
	PermMacSettingsHint: "点击「去授权」将打开系统「定位服务」，勾选 Via 后点「重新检测」",
	LockedCardHint:      "授予系统定位权限后解锁配置",
	SwitchFailedFmt:     "切换失败：%s",

	ManagedNetworksTitle: "管理的网络（点击展开原地编辑）",
	RoleBadgeP:           "主",
	RoleBadgeB:           "备",
	PrimaryLabel:         "首选网络",
	BackupLabel:          "备用网络",
	ConnectedTag:         "已连接",
	NotSetTag:            "点击设置网络",
	SSIDPlaceholder:      "输入或从上方点选 Wi-Fi 名称",
	PwdPlaceholder:       "密码（开放网络可留空）",
	ErrEmptySSID:         "网络名称不能为空",
	ErrDuplicateSSID:     "首选与备用网络不能相同",
	SavedNotice:          "网络配置已保存",
	SwitchedNotice:       "已发起切换请求",

	SettingsGeneralTitle:  "通用",
	LaunchAtLoginTitle:    "登录时自动启动",
	LaunchAtLoginDesc:     "开机静默驻留托盘",
	BootRestoreTitle:      "开机自动恢复监控",
	BootRestoreDesc:       "手机重启后自动恢复后台护航",
	LaunchApprovalHint:    "请在「系统设置 → 通用 → 登录项」中允许后台运行",
	LanguageLabel:         "界面语言",
	IntervalTitle:         "自动检查频率",
	IntervalPresets:       [4]string{"15 秒", "30 秒", "1 分钟", "5 分钟"},
	IntervalCustom:        "自定义",
	IntervalSecondsSuffix: "秒",
	IntervalClampedHint:   "已自动调整到允许范围（5–3600 秒）",
	AboutTitle:            "说明与关于",
	HelpTitle:             "使用说明",
	HelpLines: [3]string{
		"1. 首选网络可用时始终保持连接；不可用时自动切到备用网络并持续检测，恢复后立即切回。",
		"2. 系统将 Wi-Fi 名称视为位置信息，因此需要定位权限，所有数据仅保存在本机。",
		"3. 当首选网络仍可用而你主动切到其他网络时，Via 会自动暂停以尊重你的选择。",
	},
	PrivacyNote: "Via v2.0 · 密码仅保存在本机安全凭据库",

	WizardTitle:          "Via 首次设置",
	WizardSkip:           "跳过",
	WizardSteps:          [3]string{"定位授权", "选择网络", "准备就绪"},
	WizardStep1Title:     "允许读取 Wi-Fi 名称",
	WizardStep1Desc:      "操作系统把读取 Wi-Fi 名称归类为位置相关信息。Via 只在本地识别网络以完成自动切换，绝不上传任何位置或密码。",
	WizardStep1Grant:     "允许访问并继续",
	WizardStep1Manual:    "暂不授权，先手动填写",
	WizardStep2Title:     "选择你的首选与备用网络",
	WizardStep2SetP:      "设为首选",
	WizardStep2SetB:      "设为备用",
	WizardStep2Manual:    "手动输入网络名称与密码",
	WizardPrev:           "上一步",
	WizardNext:           "下一步",
	WizardStep3Title:     "一切准备就绪",
	WizardPermStatus:     "定位权限",
	WizardPermGranted:    "已授权",
	WizardPermPending:    "待授权（可在主控台开启）",
	WizardFinishAndStart: "保存并开启自动切换",
	WizardFinishSaveOnly: "仅保存配置",

	TrayTooltipPaused:  "Via: 已暂停",
	TrayTooltipPrimary: "Via: %s — 自动守护中-首选",
	TrayTooltipBackup:  "Via: %s — 自动守护中-备用",
	TrayTooltipOther:   "Via: %s — 自动守护中",
	MenuOpenPanel:      "打开 Via 面板",
	MenuTogglePause:    "切换运行 / 暂停",
	MenuQuit:           "退出 Via",
}

var enStrings = Strings{
	NavDashboard: "Dashboard",
	NavSettings:  "Settings",

	BadgeGuardPriority: "Auto-Guard · Primary",
	BadgeGuardBackup:   "Auto-Guard · Backup",
	BadgeGuardOther:    "Auto-Guard",
	BadgePaused:        "Paused",
	BadgeNoPermission:  "No Permission",
	BadgeNotConfigured: "Not Set",

	PrimarySlotLabel: "Primary Path",
	BackupSlotLabel:  "Backup Path",

	AutoSwitchTitle:    "Auto-Switch Guard",
	SubCheckingInFmt:   "Next check in %ds",
	SubBackupInFmt:     "Rechecking primary in %ds",
	SubGuardWaiting:    "Guard active · waiting for Primary or Backup",
	SubPausedManual:    "Manual Wi-Fi switch detected · paused to avoid interference",
	SubPausedStopped:   "Auto-switch is off",
	SubNeedPermission:  "Location permission is required to read Wi-Fi names and scan",
	SubNotConfigured:   "Configure both Primary and Backup networks first",
	SubIOSUnsupported:  "iOS restricts automatic background Wi-Fi switching; view-only mode",
	SubAndroidAdvisory: "On Android, Via guides switching via prioritized system Wi-Fi suggestions",

	BtnResumeNow:   "Resume Now",
	BtnGrantPerm:   "Grant Access",
	BtnOpenSysSet:  "Open System Settings",
	BtnRecheckPerm: "Recheck",
	BtnSetupNet:    "Set Up Networks",
	BtnScanNearby:  "Scan Nearby",
	BtnScanning:    "Scanning…",
	BtnSwitchNow:   "Switch",
	BtnUseCurrent:  "Use Current Wi-Fi",
	BtnCancel:      "Cancel",
	BtnSave:        "Save",
	BtnQuit:        "Quit Via",
	BtnRerunWizard: "Re-run Setup Wizard",

	PickerTriggerFmt:    "Choose Network (%d nearby)",
	PickerEmpty:         "Choose current or nearby Wi-Fi",
	PickerEmptyList:     "No scan results yet — tap Scan Nearby or type below",
	PickerCurrentFmt:    "Use Current Network: %s",
	PickerNoCurrent:     "Use Current Network (Not Connected)",
	PermMacSettingsHint: "Click Grant Access to open Location Services, enable Via, then click Recheck",
	LockedCardHint:      "Grant location permission to edit",
	SwitchFailedFmt:     "Switch failed: %s",

	ManagedNetworksTitle: "Managed Networks (click card to edit inline)",
	RoleBadgeP:           "P",
	RoleBadgeB:           "B",
	PrimaryLabel:         "Primary Network",
	BackupLabel:          "Backup Network",
	ConnectedTag:         "Connected",
	NotSetTag:            "Tap to configure",
	SSIDPlaceholder:      "Enter or pick a Wi-Fi name above",
	PwdPlaceholder:       "Password (leave empty for open network)",
	ErrEmptySSID:         "Network SSID cannot be empty",
	ErrDuplicateSSID:     "Primary and Backup networks cannot be the same",
	SavedNotice:          "Network saved",
	SwitchedNotice:       "Switch requested",

	SettingsGeneralTitle:  "General",
	LaunchAtLoginTitle:    "Launch at Login",
	LaunchAtLoginDesc:     "Start quietly in the menu bar / tray",
	BootRestoreTitle:      "Restore Guard on Boot",
	BootRestoreDesc:       "Resume monitoring automatically after reboot",
	LaunchApprovalHint:    "Allow Via in System Settings → General → Login Items",
	LanguageLabel:         "Language",
	IntervalTitle:         "Check Interval",
	IntervalPresets:       [4]string{"15s", "30s", "1m", "5m"},
	IntervalCustom:        "Custom",
	IntervalSecondsSuffix: "sec",
	IntervalClampedHint:   "Adjusted to valid range (5–3600s)",
	AboutTitle:            "Help & About",
	HelpTitle:             "How Via Works",
	HelpLines: [3]string{
		"1. Keeps Primary connected when available; falls back to Backup automatically and switches back once Primary returns.",
		"2. OS treats Wi-Fi names as location info, so location permission is required; credentials stay local.",
		"3. Switching away manually while Primary is still available pauses Via automatically.",
	},
	PrivacyNote: "Via v2.0 · Passwords stay in local OS keychain/credential store",

	WizardTitle:          "Via Setup",
	WizardSkip:           "Skip",
	WizardSteps:          [3]string{"Permission", "Networks", "Ready"},
	WizardStep1Title:     "Allow Reading Wi-Fi Names",
	WizardStep1Desc:      "Your OS classifies Wi-Fi names under location privacy. Via only inspects networks locally to switch automatically.",
	WizardStep1Grant:     "Allow & Continue",
	WizardStep1Manual:    "Skip & Enter Manually",
	WizardStep2Title:     "Pick Primary & Backup Wi-Fi",
	WizardStep2SetP:      "Set Primary",
	WizardStep2SetB:      "Set Backup",
	WizardStep2Manual:    "Enter SSID & password manually",
	WizardPrev:           "Back",
	WizardNext:           "Next",
	WizardStep3Title:     "Ready to Go",
	WizardPermStatus:     "Location Permission",
	WizardPermGranted:    "Granted",
	WizardPermPending:    "Pending (grant later)",
	WizardFinishAndStart: "Save & Start Guard",
	WizardFinishSaveOnly: "Save Only",

	TrayTooltipPaused:  "Via: Paused",
	TrayTooltipPrimary: "Via: %s — Auto-Guard · Primary",
	TrayTooltipBackup:  "Via: %s — Auto-Guard · Backup",
	TrayTooltipOther:   "Via: %s — Auto-Guard",
	MenuOpenPanel:      "Open Via",
	MenuTogglePause:    "Pause / Resume Guard",
	MenuQuit:           "Quit Via",
}

// T returns the Strings catalog for lang (falling back to English if unknown).
func T(lang Lang) Strings {
	if lang == LangZH {
		return zhStrings
	}
	return enStrings
}

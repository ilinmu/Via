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

	NotConnectedTitle  string
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

	BtnResumeNow   string
	BtnGrantPerm   string
	BtnRecheckPerm string
	BtnSetupNet    string
	BtnScanNearby  string
	BtnScanning    string
	BtnSwitchNow   string
	BtnCancel      string
	BtnSave        string
	BtnQuit        string
	BtnRerunWizard string

	PickerTriggerFmt      string
	PickerEmpty           string
	PickerEmptyList       string
	PickerCurrentFmt      string
	PickerNoCurrent       string
	PermNecessityDesc     string
	PermMacSettingsHint   string
	LockedCardHint        string
	SwitchFailedFmt       string
	ErrPermissionRequired string
	ErrNetworkNotFoundFmt string
	ErrNoWifiInterface    string
	ErrConnectStayFmt     string
	ErrConnectStayPrefix  string

	ManagedNetworksTitle  string
	RoleBadgeP            string
	RoleBadgeB            string
	PrimaryLabel          string
	BackupLabel           string
	ConnectedTag          string
	NotSetTag             string
	SSIDPlaceholder       string
	PwdPlaceholder        string
	ShowPasswordLabel     string
	HidePasswordLabel     string
	ErrEmptySSID          string
	ErrDuplicateSSID      string
	SavedNotice           string
	SavedAndStartedNotice string
	SwitchedNotice        string

	LaunchAtLoginTitle    string
	LaunchAtLoginDesc     string
	BootRestoreTitle      string
	BootRestoreDesc       string
	LanguageLabel         string
	LangOptionZH          string
	LangOptionEN          string
	ThemeLabel            string
	ThemeSystem           string
	ThemeLight            string
	ThemeDark             string
	IntervalTitle         string
	IntervalPresets       [4]string
	IntervalCustom        string
	IntervalSecondsSuffix string
	ErrInvalidInterval    string
	HelpTitle             string
	HelpLines             [4]string
	PrivacyNote           string
	VersionLabel          string

	WizardSkip           string
	WizardStep1Title     string
	WizardStep1Desc      string
	WizardStep1Grant     string
	WizardStep2Title     string
	WizardPrev           string
	WizardNext           string
	WizardStep3Title     string
	WizardPermStatus     string
	WizardPermGranted    string
	WizardPermPending    string
	WizardFinishAndStart string
	WizardFinishSaveOnly string

	TrayTooltipPaused  string
	TrayTooltipPrimary string
	TrayTooltipBackup  string
	TrayTooltipOther   string
	MenuOpenPanel      string
	MenuTogglePause    string
	MenuQuit           string
}

var zhStrings = Strings{
	NavDashboard: "主控台",
	NavSettings:  "设置",

	NotConnectedTitle:  "未连接 Wi-Fi",
	BadgeGuardPriority: "自动守护中-首选",
	BadgeGuardBackup:   "自动守护中-备用",
	BadgeGuardOther:    "自动守护中",
	BadgePaused:        "已暂停",
	BadgeNoPermission:  "需要权限",
	BadgeNotConfigured: "未设置",

	PrimarySlotLabel: "首选",
	BackupSlotLabel:  "备用",

	AutoSwitchTitle:    "自动切换",
	SubCheckingInFmt:   "下次检查：%s",
	SubBackupInFmt:     "重检首选网络：%s",
	SubGuardWaiting:    "等待首选或备用网络出现",
	SubPausedManual:    "你已手动切换网络，自动切换已暂停",
	SubPausedStopped:   "已关闭",
	SubNeedPermission:  "需要定位权限才能识别 Wi-Fi",
	SubNotConfigured:   "设置首选和备用网络后即可自动切换",
	SubIOSUnsupported:  "iOS 不允许应用在后台自动切换 Wi-Fi，当前仅可查看状态",
	SubAndroidAdvisory: "Android 会根据首选和备用优先级由系统自动连接",

	BtnResumeNow:   "恢复",
	BtnGrantPerm:   "开启定位",
	BtnRecheckPerm: "重新检测",
	BtnSetupNet:    "设置网络",
	BtnScanNearby:  "扫描",
	BtnScanning:    "扫描中…",
	BtnSwitchNow:   "连接",
	BtnCancel:      "取消",
	BtnSave:        "保存",
	BtnQuit:        "退出 Via",
	BtnRerunWizard: "设置向导",

	PickerTriggerFmt:      "选择网络（附近 %d 个）",
	PickerEmpty:           "选择网络",
	PickerEmptyList:       "未发现附近网络，可扫描或在下方输入",
	PickerCurrentFmt:      "使用当前网络：%s",
	PickerNoCurrent:       "当前未连接 Wi-Fi",
	PermNecessityDesc:     "系统将 Wi-Fi 名称和附近网络归类为位置隐私，未授权时无法识别当前网络及自动切换。所有数据仅在本机使用，绝不上传。",
	PermMacSettingsHint:   "在系统「定位服务」中开启 Via，再点「重新检测」",
	LockedCardHint:        "开启定位权限后可编辑",
	SwitchFailedFmt:       "连接失败：%s",
	ErrPermissionRequired: "需要先开启定位权限",
	ErrNetworkNotFoundFmt: "未找到网络「%s」，请确认路由器已开启或在信号范围内",
	ErrNoWifiInterface:    "未检测到可用的 Wi-Fi 网卡",
	ErrConnectStayFmt:     "未能切换到「%s」，当前仍连接着原网络",
	ErrConnectStayPrefix:  "未能连接到目标网络",

	ManagedNetworksTitle:  "网络配置",
	RoleBadgeP:            "主",
	RoleBadgeB:            "备",
	PrimaryLabel:          "首选网络",
	BackupLabel:           "备用网络",
	ConnectedTag:          "已连接",
	NotSetTag:             "未设置",
	SSIDPlaceholder:       "输入网络名称",
	PwdPlaceholder:        "输入密码（无密码可留空）",
	ShowPasswordLabel:     "显示密码",
	HidePasswordLabel:     "隐藏密码",
	ErrEmptySSID:          "请输入网络名称",
	ErrDuplicateSSID:      "首选和备用网络不能相同",
	SavedNotice:           "已保存",
	SavedAndStartedNotice: "已保存并开启自动切换",
	SwitchedNotice:        "正在连接",

	LaunchAtLoginTitle:    "登录时打开",
	LaunchAtLoginDesc:     "开机后在菜单栏后台运行",
	BootRestoreTitle:      "重启后自动恢复",
	BootRestoreDesc:       "设备重启后继续自动切换",
	LanguageLabel:         "语言",
	LangOptionZH:          "中文",
	LangOptionEN:          "English",
	ThemeLabel:            "外观",
	ThemeSystem:           "跟随系统",
	ThemeLight:            "浅色",
	ThemeDark:             "深色",
	IntervalTitle:         "检查间隔",
	IntervalPresets:       [4]string{"15 秒", "30 秒", "1 分钟", "5 分钟"},
	IntervalCustom:        "自定义",
	IntervalSecondsSuffix: "秒",
	ErrInvalidInterval:    "请输入 5 到 3600 之间的整数（秒）",
	HelpTitle:             "使用说明",
	HelpLines: [4]string{
		"自动切换：首选网络可用时保持连接；不可用时自动切到备用网络，首选恢复后再自动切回。",
		"为何需要定位权限：系统将 Wi-Fi 名称和附近网络列表归类为位置隐私信息。如果不授权，Via 无法识别当前网络，也无法扫描并判断首选网络是否恢复；所有数据仅在本机使用，绝不上传。",
		"为何需要钥匙串与密码本：自动切换网络时系统可能需要验证 Wi-Fi 密码。Via 将密码加密保存在本机系统钥匙串（Windows 为凭据管理器）中，不以明文存储，也不会上传到任何服务器。",
		"尊重手动选择：首选网络仍可用时，如果你手动切换到了其他网络，Via 会自动暂停，不与你的操作冲突。",
	},
	PrivacyNote:  "密码仅保存在本机",
	VersionLabel: "Via 2.0",

	WizardSkip:           "稍后",
	WizardStep1Title:     "开启定位权限",
	WizardStep1Desc:      "系统将 Wi-Fi 名称归类为位置信息。Via 仅在本机识别网络，不会上传任何数据。",
	WizardStep1Grant:     "开启定位",
	WizardStep2Title:     "选择首选和备用网络",
	WizardPrev:           "上一步",
	WizardNext:           "下一步",
	WizardStep3Title:     "准备就绪",
	WizardPermStatus:     "定位权限",
	WizardPermGranted:    "已开启",
	WizardPermPending:    "尚未开启",
	WizardFinishAndStart: "完成并开启",
	WizardFinishSaveOnly: "保存配置",

	TrayTooltipPaused:  "Via：已暂停",
	TrayTooltipPrimary: "Via：%s（自动守护中-首选）",
	TrayTooltipBackup:  "Via：%s（自动守护中-备用）",
	TrayTooltipOther:   "Via：%s（自动守护中）",
	MenuOpenPanel:      "打开 Via",
	MenuTogglePause:    "暂停或恢复自动切换",
	MenuQuit:           "退出 Via",
}

var enStrings = Strings{
	NavDashboard: "Status",
	NavSettings:  "Settings",

	NotConnectedTitle:  "Not connected",
	BadgeGuardPriority: "Active: Primary",
	BadgeGuardBackup:   "Active: Backup",
	BadgeGuardOther:    "Active",
	BadgePaused:        "Paused",
	BadgeNoPermission:  "Permission needed",
	BadgeNotConfigured: "Not set",

	PrimarySlotLabel: "Primary",
	BackupSlotLabel:  "Backup",

	AutoSwitchTitle:    "Auto-switch",
	SubCheckingInFmt:   "Next check in %s",
	SubBackupInFmt:     "Rechecking primary in %s",
	SubGuardWaiting:    "Waiting for primary or backup network",
	SubPausedManual:    "Paused after you switched networks manually",
	SubPausedStopped:   "Off",
	SubNeedPermission:  "Location access is needed to read Wi-Fi names",
	SubNotConfigured:   "Add primary and backup networks to enable auto-switch",
	SubIOSUnsupported:  "iOS does not allow background Wi-Fi switching; view-only mode",
	SubAndroidAdvisory: "Android switches using your prioritized network suggestions",

	BtnResumeNow:   "Resume",
	BtnGrantPerm:   "Enable Location",
	BtnRecheckPerm: "Check again",
	BtnSetupNet:    "Set up",
	BtnScanNearby:  "Scan",
	BtnScanning:    "Scanning…",
	BtnSwitchNow:   "Connect",
	BtnCancel:      "Cancel",
	BtnSave:        "Save",
	BtnQuit:        "Quit Via",
	BtnRerunWizard: "Run setup",

	PickerTriggerFmt:      "Choose network (%d nearby)",
	PickerEmpty:           "Choose network",
	PickerEmptyList:       "No nearby networks yet. Scan or enter one below.",
	PickerCurrentFmt:      "Use current: %s",
	PickerNoCurrent:       "Not connected to Wi-Fi",
	PermNecessityDesc:     "Your OS treats Wi-Fi names and nearby scans as location data. Without it, Via cannot detect networks or switch automatically. Everything stays on this device.",
	PermMacSettingsHint:   "Turn on Via in Location Services, then select Check again.",
	LockedCardHint:        "Enable location permission to edit",
	SwitchFailedFmt:       "Failed: %s",
	ErrPermissionRequired: "Enable location permission first",
	ErrNetworkNotFoundFmt: "Network \"%s\" not found. Make sure it is powered on and in range.",
	ErrNoWifiInterface:    "No Wi-Fi interface available",
	ErrConnectStayFmt:     "Could not switch to \"%s\"; staying on current network",
	ErrConnectStayPrefix:  "Could not switch to target network",

	ManagedNetworksTitle:  "Networks",
	RoleBadgeP:            "1",
	RoleBadgeB:            "2",
	PrimaryLabel:          "Primary network",
	BackupLabel:           "Backup network",
	ConnectedTag:          "Connected",
	NotSetTag:             "Not set",
	SSIDPlaceholder:       "Network name",
	PwdPlaceholder:        "Password (optional if open)",
	ShowPasswordLabel:     "Show password",
	HidePasswordLabel:     "Hide password",
	ErrEmptySSID:          "Enter a network name",
	ErrDuplicateSSID:      "Primary and backup networks must be different",
	SavedNotice:           "Saved",
	SavedAndStartedNotice: "Saved and auto-switch started",
	SwitchedNotice:        "Connecting",

	LaunchAtLoginTitle:    "Open at login",
	LaunchAtLoginDesc:     "Run quietly in the background",
	BootRestoreTitle:      "Resume after restart",
	BootRestoreDesc:       "Keep auto-switch active after restart",
	LanguageLabel:         "Language",
	LangOptionZH:          "中文",
	LangOptionEN:          "English",
	ThemeLabel:            "Appearance",
	ThemeSystem:           "Auto",
	ThemeLight:            "Light",
	ThemeDark:             "Dark",
	IntervalTitle:         "Check interval",
	IntervalPresets:       [4]string{"15s", "30s", "1m", "5m"},
	IntervalCustom:        "Custom",
	IntervalSecondsSuffix: "sec",
	ErrInvalidInterval:    "Enter a whole number from 5 to 3,600 seconds",
	HelpTitle:             "How it works",
	HelpLines: [4]string{
		"Auto-switch: Keeps you on your primary network when available, switches to backup if it drops, and returns automatically once primary is back.",
		"Why location access is needed: Your OS classifies Wi-Fi names and nearby scans as location privacy data. Without it, Via cannot tell which network you are on or detect when your primary network returns. Everything stays on this device.",
		"Why Keychain / credential storage is needed: Switching networks automatically may require your Wi-Fi password. Via stores passwords encrypted in your system Keychain or Credential Manager, never in plain text and never uploaded.",
		"Manual choice respected: If you switch networks manually while your primary network is still available, Via pauses automatically.",
	},
	PrivacyNote:  "Passwords stay on this device",
	VersionLabel: "Via 2.0",

	WizardSkip:           "Later",
	WizardStep1Title:     "Enable location access",
	WizardStep1Desc:      "Your system treats Wi-Fi names as location data. Via checks networks locally and never uploads anything.",
	WizardStep1Grant:     "Enable Location",
	WizardStep2Title:     "Choose primary and backup Wi-Fi",
	WizardPrev:           "Back",
	WizardNext:           "Next",
	WizardStep3Title:     "Ready to start",
	WizardPermStatus:     "Location access",
	WizardPermGranted:    "Enabled",
	WizardPermPending:    "Not enabled",
	WizardFinishAndStart: "Save and start",
	WizardFinishSaveOnly: "Save",

	TrayTooltipPaused:  "Via: Paused",
	TrayTooltipPrimary: "Via: %s (Active: Primary)",
	TrayTooltipBackup:  "Via: %s (Active: Backup)",
	TrayTooltipOther:   "Via: %s (Active)",
	MenuOpenPanel:      "Open Via",
	MenuTogglePause:    "Pause or resume",
	MenuQuit:           "Quit Via",
}

// T returns the Strings catalog for lang (falling back to English if unknown).
func T(lang Lang) Strings {
	if lang == LangZH {
		return zhStrings
	}
	return enStrings
}

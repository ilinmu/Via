package uiapp

import (
	"context"
	"fmt"
	"io"
	"testing"
	"time"

	"github.com/egoist/mygo/ui"

	"via/internal/i18n"
	"via/internal/policy"
	"via/internal/store"
	"via/internal/wifi"
)

type stubAdapter struct{}

func (stubAdapter) Name() string                                        { return "stub" }
func (stubAdapter) CurrentSSID(context.Context) (string, error)         { return "Home_WiFi", nil }
func (stubAdapter) Permission(context.Context) policy.Permission        { return policy.PermissionAuthorized }
func (stubAdapter) RequestPermission() error                            { return nil }
func (stubAdapter) OpenPermissionSettings() error                       { return nil }
func (stubAdapter) Scan(context.Context) ([]wifi.Network, error)        { return nil, nil }
func (stubAdapter) Connect(context.Context, string, string) error       { return nil }
func (stubAdapter) SubscribeChanges(func(string)) (io.Closer, error)    { return nil, nil }
func (stubAdapter) SubscribePermissionChanges(func(policy.Permission)) (io.Closer, error) {
	return nil, nil
}
func (stubAdapter) IsAdvisory() bool                                  { return false }
func (stubAdapter) ApplyAdvisory(string, string, string, string, string) error { return nil }
func (stubAdapter) UpdateNotification(bool, string, string)           {}

func newTestApp(lang i18n.Lang, st wifi.State) *App {
	settings := store.Settings{
		SSIDP:            st.SSIDP,
		SSIDB:            st.SSIDB,
		CheckIntervalSec: st.CheckInterval,
		Language:         string(lang),
		OnboardingDone:   true,
	}.Normalize()
	mon := wifi.NewMonitor(stubAdapter{}, store.NewMemSecretStore(), settings, "", wifi.DefaultTimingOptions())
	return &App{
		monitor:            mon,
		state:              st,
		settings:           settings,
		lang:               lang,
		activeTab:          tabDashboard,
		iconCache:          make(map[trayIconKey][]byte),
		testMode:           true,
		customIntervalText: fmt.Sprintf("%d", settings.CheckIntervalSec),
		wizardStep:         1,
	}
}

func TestFormatDurationAndCountdown(t *testing.T) {
	cases := []struct {
		sec    int
		lang   i18n.Lang
		want   string
	}{
		{-3, i18n.LangZH, "0 秒"},
		{15, i18n.LangZH, "15 秒"},
		{60, i18n.LangZH, "1 分钟"},
		{90, i18n.LangZH, "1 分 30 秒"},
		{300, i18n.LangZH, "5 分钟"},
		{3600, i18n.LangZH, "1 小时"},
		{15, i18n.LangEN, "15s"},
		{60, i18n.LangEN, "1m"},
		{90, i18n.LangEN, "1m 30s"},
		{3600, i18n.LangEN, "1h"},
	}
	for _, tc := range cases {
		if got := formatDuration(tc.sec, tc.lang); got != tc.want {
			t.Fatalf("formatDuration(%d, %s) = %q, want %q", tc.sec, tc.lang, got, tc.want)
		}
	}

	if got := formatCountdown("Next check in %s", time.Time{}, 90, i18n.LangEN); got != "Next check in 1m 30s" {
		t.Fatalf("unexpected fallback countdown: %q", got)
	}
	if got := formatCountdown("下次检查：%s", time.Now().Add(-2*time.Second), 60, i18n.LangZH); got != "下次检查：0 秒" {
		t.Fatalf("unexpected clamped countdown: %q", got)
	}
}

func TestValidateCustomInterval(t *testing.T) {
	invalid := []string{"", "   ", "abc", "30s", "4", "0", "-5", "3601"}
	for _, in := range invalid {
		if n, ok := validateCustomInterval(in); ok {
			t.Fatalf("expected invalid for %q, got %d", in, n)
		}
	}
	valid := map[string]int{"5": 5, " 60 ": 60, "3600": 3600}
	for in, want := range valid {
		if n, ok := validateCustomInterval(in); !ok || n != want {
			t.Fatalf("validateCustomInterval(%q) = (%d, %v), want (%d, true)", in, n, ok, want)
		}
	}
}

func TestLocalizeMonitorError(t *testing.T) {
	zh := i18n.T(i18n.LangZH)
	en := i18n.T(i18n.LangEN)

	if got := localizeMonitorError("Network Office_5G not found", zh); got != "未找到网络「Office_5G」，请确认路由器已开启或在信号范围内" {
		t.Fatalf("unexpected zh not found: %q", got)
	}
	if got := localizeMonitorError("Network Office_5G not found", en); got != `Network "Office_5G" not found. Make sure it is powered on and in range.` {
		t.Fatalf("unexpected en not found: %q", got)
	}
	if got := localizeMonitorError("Location permission is required to scan Wi-Fi networks", zh); got != zh.ErrPermissionRequired {
		t.Fatalf("unexpected permission error: %q", got)
	}
	if got := localizeMonitorError("No Wi-Fi interface available", zh); got != zh.ErrNoWifiInterface {
		t.Fatalf("unexpected interface error: %q", got)
	}
	if got := localizeMonitorError("macOS did not switch Wi-Fi to Office_5G (current: Backup)", zh); got != "未能切换到「Office_5G」，当前仍连接着原网络" {
		t.Fatalf("unexpected connect error: %q", got)
	}
}

func assertTextsWithinWidth(t *testing.T, tt *ui.Tester, maxWidth int, labels []string) {
	t.Helper()
	limit := float32(maxWidth) + 0.5
	for _, label := range labels {
		if label == "" {
			continue
		}
		r, ok := tt.Find(label)
		if !ok {
			t.Fatalf("expected element with text %q to be rendered at width %d", label, maxWidth)
		}
		if r.W <= 0 || r.H <= 0 {
			t.Fatalf("element %q has non-positive bounds %+v at width %d", label, r, maxWidth)
		}
		if r.X < -0.5 || r.X+r.W > limit {
			t.Fatalf("element %q overflows viewport width %d: rect=%+v", label, maxWidth, r)
		}
	}
}

func TestResponsiveLayoutsAcrossDevicesAndLanguages(t *testing.T) {
	widths := []struct {
		w      int
		mobile bool
	}{
		{320, true},  // Compact mobile
		{375, true},  // Standard mobile
		{380, false}, // Desktop popover
		{430, true},  // Large mobile
	}
	langs := []i18n.Lang{i18n.LangZH, i18n.LangEN}
	themes := []bool{false, true}

	for _, lang := range langs {
		s := i18n.T(lang)
		for _, dark := range themes {
			for _, dev := range widths {
				// 1. Dashboard: active primary with long SSID + inline editor open
				t.Run(fmt.Sprintf("dashboard_%s_w%d_dark%v", lang, dev.w, dark), func(t *testing.T) {
					st := wifi.State{
						Running:       true,
						Configured:    true,
						Role:          policy.RolePriority,
						Permission:    policy.PermissionAuthorized,
						CurrentSSID:   "VeryLongOfficeWirelessNetworkName_5GHz",
						HasCurrentSSID: true,
						SSIDP:         "VeryLongOfficeWirelessNetworkName_5GHz",
						SSIDB:         "BackupHotspot_Mobile",
						CheckInterval: 90,
						NextCheckAt:   time.Now().Add(45 * time.Second),
						Nearby: []wifi.Network{
							{SSID: "Office_5G", RSSI: -52, Secured: true},
							{SSID: "Cafe_Guest", RSSI: -78, Secured: false},
						},
					}
					app := newTestApp(lang, st)
					app.editingSlot = store.SlotPrimary
					app.draftSSID = st.SSIDP

					tt := ui.NewTester(func(c *ui.Context) {
						app.renderCommonRoot(c, dev.mobile)
					}, dev.w, 700)
					tt.SetDark(dark)
					tt.Frame()

					assertTextsWithinWidth(t, tt, dev.w, []string{
						"Via",
						s.NavDashboard,
						s.NavSettings,
						s.BadgeGuardPriority,
						s.PrimarySlotLabel,
						s.BackupSlotLabel,
						s.AutoSwitchTitle,
						s.ManagedNetworksTitle,
						s.BtnScanNearby,
						s.PrimaryLabel,
						s.BackupLabel,
						s.BtnCancel,
						s.BtnSave,
					})
				})

				// 2. Dashboard: unauthorized + manual-pause prompt localization
				t.Run(fmt.Sprintf("dashboard_perm_%s_w%d_dark%v", lang, dev.w, dark), func(t *testing.T) {
					st := wifi.State{
						Permission:    policy.PermissionDenied,
						CheckInterval: 60,
					}
					app := newTestApp(lang, st)
					tt := ui.NewTester(func(c *ui.Context) {
						app.renderCommonRoot(c, dev.mobile)
					}, dev.w, 640)
					tt.SetDark(dark)
					tt.Frame()

					assertTextsWithinWidth(t, tt, dev.w, []string{
						s.BadgeNoPermission,
						s.SubNeedPermission,
						s.BtnGrantPerm,
						s.BtnRecheckPerm,
					})
				})

				// 3. Settings: custom interval validation + expanded help
				t.Run(fmt.Sprintf("settings_%s_w%d_dark%v", lang, dev.w, dark), func(t *testing.T) {
					st := wifi.State{
						Configured:    true,
						Permission:    policy.PermissionAuthorized,
						SSIDP:         "Office_5G",
						SSIDB:         "Phone_AP",
						CheckInterval: 60,
					}
					app := newTestApp(lang, st)
					app.activeTab = tabSettings
					app.customIntervalMode = true
					app.intervalError = s.ErrInvalidInterval
					app.showHelp = true

					tt := ui.NewTester(func(c *ui.Context) {
						app.renderCommonRoot(c, dev.mobile)
					}, dev.w, 1080)
					tt.SetDark(dark)
					tt.Frame()

					checks := []string{
						s.LanguageLabel,
						s.LangOptionZH,
						s.LangOptionEN,
						s.ThemeLabel,
						s.ThemeSystem,
						s.ThemeLight,
						s.ThemeDark,
						s.IntervalTitle,
						s.IntervalCustom,
						s.BtnSave,
						s.ErrInvalidInterval,
						s.HelpTitle,
						s.BtnRerunWizard,
						s.PrivacyNote,
						s.VersionLabel,
					}
					if dev.mobile {
						checks = append(checks, s.BootRestoreTitle)
					} else {
						checks = append(checks, s.LaunchAtLoginTitle, s.BtnQuit)
					}
					assertTextsWithinWidth(t, tt, dev.w, checks)
				})

				// 4. Onboarding Step 2 (networks selection)
				t.Run(fmt.Sprintf("onboarding_step2_%s_w%d_dark%v", lang, dev.w, dark), func(t *testing.T) {
					st := wifi.State{
						Permission:    policy.PermissionAuthorized,
						CurrentSSID:   "Studio_5G",
						CheckInterval: 60,
					}
					app := newTestApp(lang, st)
					app.activeTab = tabOnboarding
					app.wizardStep = 2

					tt := ui.NewTester(func(c *ui.Context) {
						app.renderCommonRoot(c, dev.mobile)
					}, dev.w, 700)
					tt.SetDark(dark)
					tt.Frame()

					assertTextsWithinWidth(t, tt, dev.w, []string{
						s.WizardSkip,
						s.WizardStep2Title,
						s.BtnScanNearby,
						s.PrimaryLabel,
						s.BackupLabel,
						s.WizardNext,
					})
				})
			}
		}
	}
}

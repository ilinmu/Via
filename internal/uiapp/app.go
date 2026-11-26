// Package uiapp implements Via's cross-platform Scheme A Native UI.
package uiapp

import (
	"fmt"
	"runtime"
	"strconv"
	"sync"
	"time"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"

	"via/internal/i18n"
	"via/internal/nativewifi"
	"via/internal/policy"
	"via/internal/store"
	"via/internal/tray"
	"via/internal/wifi"
)

type viewTab int

const (
	tabDashboard viewTab = iota
	tabSettings
	tabOnboarding
)

type trayIconKey struct {
	running bool
	role    policy.Role
	darkBar bool
}

type App struct {
	mu sync.Mutex

	monitor    *wifi.Monitor
	nativeCtrl nativewifi.Controller
	tray       *mygo.Tray
	win        *mygo.Window

	state    wifi.State
	settings store.Settings
	lang     i18n.Lang

	activeTab viewTab
	iconCache map[trayIconKey][]byte

	// Inline editor draft state (Dashboard)
	editingSlot string
	draftSSID   string
	draftPwd    string
	showPwd     bool
	editError   string

	// Settings UI state
	launchAtLogin      bool
	bootRestore        bool
	customIntervalMode bool
	customIntervalText string
	intervalClamped    bool
	showHelp           bool

	// Onboarding wizard state
	wizardStep        int // 1, 2, 3
	wizardManualInput bool
	wizardPrimarySSID string
	wizardPrimaryPwd  string
	wizardBackupSSID  string
	wizardBackupPwd   string
	wizardError       string

	// Ephemeral toast notice
	toastText  string
	toastUntil time.Time
}

func newApp() *App {
	dir, err := mygo.App.Path(mygo.PathUserData)
	if err != nil {
		dir = "."
	}
	settings, _ := store.LoadSettings(dir)
	secrets := store.NewMyGoSecretStore()

	adapter, _ := wifi.NewAdapter()
	var nctrl nativewifi.Controller
	if d, ok := adapter.(interface{ NativeController() nativewifi.Controller }); ok {
		nctrl = d.NativeController()
	}

	mon := wifi.NewMonitor(adapter, secrets, settings, dir, wifi.DefaultTimingOptions())

	lang := i18n.DetectSystemLang()
	if settings.Language == string(i18n.LangZH) {
		lang = i18n.LangZH
	} else if settings.Language == string(i18n.LangEN) {
		lang = i18n.LangEN
	}

	startTab := tabDashboard
	if !settings.OnboardingDone && !settings.IsConfigured() {
		startTab = tabOnboarding
	}

	app := &App{
		monitor:            mon,
		nativeCtrl:         nctrl,
		state:              mon.State(),
		settings:           settings,
		lang:               lang,
		activeTab:          startTab,
		iconCache:          make(map[trayIconKey][]byte),
		bootRestore:        settings.BootRestore,
		customIntervalText: strconv.Itoa(settings.CheckIntervalSec),
		wizardStep:         1,
		wizardPrimarySSID:  settings.SSIDP,
		wizardBackupSSID:   settings.SSIDB,
	}

	mon.Subscribe(func(st wifi.State) {
		app.mu.Lock()
		app.state = st
		app.settings = mon.Settings()
		app.bootRestore = app.settings.BootRestore
		app.mu.Unlock()
		app.onStateUpdated()
	})
	return app
}

func (a *App) strings() i18n.Strings {
	a.mu.Lock()
	lang := a.lang
	a.mu.Unlock()
	return i18n.T(lang)
}

func (a *App) setLang(lang i18n.Lang) {
	a.mu.Lock()
	a.lang = lang
	a.mu.Unlock()
	a.monitor.SetLanguage(string(lang))
	a.onStateUpdated()
}

func (a *App) invalidate() {
	a.mu.Lock()
	w := a.win
	a.mu.Unlock()
	if w != nil {
		w.Invalidate()
	}
}

func (a *App) setToast(msg string) {
	a.mu.Lock()
	a.toastText = msg
	a.toastUntil = time.Now().Add(2500 * time.Millisecond)
	a.mu.Unlock()
	go func() {
		time.Sleep(2600 * time.Millisecond)
		a.invalidate()
	}()
	a.invalidate()
}

func (a *App) currentTrayIcon(running bool, role policy.Role, darkBar bool) []byte {
	key := trayIconKey{running: running, role: role, darkBar: darkBar}
	a.mu.Lock()
	if b, ok := a.iconCache[key]; ok {
		a.mu.Unlock()
		return b
	}
	ctrl := a.nativeCtrl
	a.mu.Unlock()

	pngBytes := tray.Render(ctrl, running, role, darkBar)
	a.mu.Lock()
	a.iconCache[key] = pngBytes
	a.mu.Unlock()
	return pngBytes
}

func (a *App) syncTray() {
	a.mu.Lock()
	tr := a.tray
	st := a.state
	s := i18n.T(a.lang)
	a.mu.Unlock()
	if tr == nil {
		return
	}
	darkBar := tr.Dark()
	pngBytes := a.currentTrayIcon(st.Running, st.Role, darkBar)
	_ = tr.SetIcon(pngBytes, st.Running)

	var tip string
	if !st.Running {
		tip = s.TrayTooltipPaused
	} else {
		ssid := st.CurrentSSID
		if ssid == "" {
			ssid = "-"
		}
		switch st.Role {
		case policy.RolePriority:
			tip = fmt.Sprintf(s.TrayTooltipPrimary, ssid)
		case policy.RoleBackup:
			tip = fmt.Sprintf(s.TrayTooltipBackup, ssid)
		default:
			tip = fmt.Sprintf(s.TrayTooltipOther, ssid)
		}
	}
	tr.SetToolTip(tip)
}

func (a *App) onStateUpdated() {
	a.syncTray()
	a.invalidate()
}

func (a *App) renderCommonRoot(c *ui.Context, isMobile bool) {
	p := schemeAPalette(mygo.Theme.IsDark())
	applyTheme(c, p)
	c.Root().Background(p.bg)

	s := a.strings()
	a.mu.Lock()
	st := a.state
	tab := a.activeTab
	toast := ""
	if time.Now().Before(a.toastUntil) {
		toast = a.toastText
	}
	a.mu.Unlock()

	var topInset, bottomInset float32
	if isMobile {
		topInset, _, bottomInset, _ = c.SafeArea()
	}

	ui.Column(c).Fill().Background(p.bg).Children(func() {
		if topInset > 0 {
			ui.Box(c).Height(topInset).Background(p.surface)
		}

		// Top bar (on onboarding or desktop; mobile keeps clean brand bar on top + tabs at bottom)
		if tab == tabOnboarding {
			a.renderHeaderBar(c, p, s, tab, false)
		} else {
			a.renderHeaderBar(c, p, s, tab, !isMobile)
		}

		ui.Scroll(c).Grow(1).Children(func() {
			pad := float32(14)
			if isMobile {
				pad = 16
			}
			ui.Column(c).Padding(pad).Gap(12).Children(func() {
				switch tab {
				case tabOnboarding:
					a.renderOnboarding(c, p, s, st, isMobile)
				case tabSettings:
					a.renderSettings(c, p, s, st, isMobile)
				default:
					a.renderDashboard(c, p, s, st, isMobile)
				}
			})
		})

		if toast != "" {
			ui.Row(c).Padding(6, 14).Justify(ui.Center).Children(func() {
				ui.Box(c).Padding(6, 12).Radius(999).Background(p.accentSoft).Children(func() {
					ui.Text(c, toast).FontSize(11).FontWeight(600).TextColor(p.accentText)
				})
			})
		}

		if isMobile && tab != tabOnboarding {
			a.renderMobileBottomBar(c, p, s, tab, bottomInset)
		} else if bottomInset > 0 {
			ui.Box(c).Height(bottomInset).Background(p.bg)
		}
	})
}

func (a *App) renderHeaderBar(c *ui.Context, p palette, s i18n.Strings, tab viewTab, showNavPills bool) {
	ui.Row(c).Padding(11, 16).Gap(8).AlignItems(ui.Center).
		Background(p.surface).BorderWidth(0, 0, 1, 0).BorderColor(p.border).
		Children(func() {
			ui.Box(c).Size(24, 24).Radius(7).Background(p.accent).Center().Children(func() {
				ui.Text(c, "V").FontSize(12).Bold().TextColor(ui.Hex("#FFFFFF"))
			})
			ui.Text(c, "Via").FontSize(15).Bold().TextColor(p.text)
			ui.Spacer(c)
			if tab == tabOnboarding {
				btn := ui.Box(c.Key("wizard_skip")).Padding(5, 10).Radius(8).Background(p.surfaceMuted).
					Focusable().Cursor(ui.CursorPointer).
					Children(func() {
						ui.Text(c, s.WizardSkip).FontSize(12).FontWeight(600).TextColor(p.muted)
					})
				if btn.Clicked() {
					a.monitor.SetOnboardingDone(true)
					a.mu.Lock()
					a.activeTab = tabDashboard
					a.mu.Unlock()
				}
				return
			}
			if showNavPills {
				a.navPill(c, p, "dash", s.NavDashboard, tab == tabDashboard, func() {
					a.mu.Lock()
					a.activeTab = tabDashboard
					a.mu.Unlock()
				})
				a.navPill(c, p, "settings", s.NavSettings, tab == tabSettings, func() {
					a.mu.Lock()
					a.activeTab = tabSettings
					a.mu.Unlock()
				})
			}
		})
}

func (a *App) navPill(c *ui.Context, p palette, key, title string, active bool, onClick func()) {
	bg, fg := ui.Transparent, p.muted
	if active {
		bg, fg = p.accentSoft, p.accentText
	}
	btn := ui.Box(c.Key("nav:" + key)).Padding(5, 10).Radius(8).Background(bg).
		Focusable().Cursor(ui.CursorPointer).
		Children(func() {
			ui.Text(c, title).FontSize(12).FontWeight(600).TextColor(fg)
		})
	if btn.Clicked() {
		onClick()
	}
}

func (a *App) renderMobileBottomBar(c *ui.Context, p palette, s i18n.Strings, tab viewTab, bottomInset float32) {
	ui.Column(c).Background(p.surface).BorderWidth(1, 0, 0, 0).BorderColor(p.border).Children(func() {
		ui.Row(c).Padding(8, 16).Gap(10).Children(func() {
			for _, item := range []struct {
				key   string
				title string
				target viewTab
			}{
				{"m_dash", s.NavDashboard, tabDashboard},
				{"m_set", s.NavSettings, tabSettings},
			} {
				active := tab == item.target
				bg, fg := ui.Transparent, p.muted
				if active {
					bg, fg = p.accentSoft, p.accentText
				}
				btn := ui.Box(c.Key(item.key)).Grow(1).Padding(9, 0).Radius(10).Background(bg).Center().
					Focusable().Cursor(ui.CursorPointer).
					Children(func() {
						ui.Text(c, item.title).FontSize(13).FontWeight(600).TextColor(fg)
					})
				if btn.Clicked() {
					target := item.target
					a.mu.Lock()
					a.activeTab = target
					a.mu.Unlock()
				}
			}
		})
		if bottomInset > 0 {
			ui.Box(c).Height(bottomInset)
		}
	})
}

func isIOS() bool {
	return runtime.GOOS == "ios"
}

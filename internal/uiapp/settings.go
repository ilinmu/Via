package uiapp

import (
	"context"
	"fmt"
	"runtime"
	"strconv"
	"strings"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"

	"via/internal/i18n"
	"via/internal/policy"
	"via/internal/store"
	"via/internal/wifi"
)

func validateCustomInterval(raw string) (int, bool) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return 0, false
	}
	n, err := strconv.Atoi(trimmed)
	if err != nil || n < store.MinCheckIntervalSec || n > store.MaxCheckIntervalSec {
		return 0, false
	}
	return n, true
}

func (a *App) renderSettings(c *ui.Context, p palette, s i18n.Strings, lang i18n.Lang, st wifi.State, isMobile bool) {
	// Card 1: General (Auto-launch + Language)
	ui.Column(c).Radius(radiusCard).Background(p.surface).Border(1, p.border).Clip().Children(func() {
		if isMobile {
			ui.Row(c).Padding(12, spaceCard).Gap(10).AlignItems(ui.Center).Children(func() {
				ui.Column(c).Grow(1).Shrink(1).MinWidth(0).Gap(3).Children(func() {
					ui.Text(c, s.BootRestoreTitle).FontSize(fontBody).FontWeight(600).TextColor(p.text)
					ui.Text(c, s.BootRestoreDesc).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.muted)
				})
				if ui.Switch(c.Key("boot_restore"), &a.bootRestore).Label(s.BootRestoreTitle).Changed() {
					a.monitor.SetBootRestore(a.bootRestore)
				}
			})
		} else {
			ui.Row(c).Padding(12, spaceCard).Gap(10).AlignItems(ui.Center).Children(func() {
				ui.Column(c).Grow(1).Shrink(1).MinWidth(0).Gap(3).Children(func() {
					ui.Text(c, s.LaunchAtLoginTitle).FontSize(fontBody).FontWeight(600).TextColor(p.text)
					ui.Text(c, s.LaunchAtLoginDesc).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.muted)
				})
				if ui.Switch(c.Key("autostart"), &a.launchAtLogin).Label(s.LaunchAtLoginTitle).Changed() {
					_ = mygo.App.SetOpenAtLogin(a.launchAtLogin)
				}
			})
		}

		ui.Row(c).Padding(12, spaceCard).Gap(10).AlignItems(ui.Center).
			BorderWidth(1, 0, 0, 0).BorderColor(p.border).
			Children(func() {
				ui.Text(c, s.LanguageLabel).FontSize(fontBody).FontWeight(600).TextColor(p.text).Grow(1).Shrink(1).MinWidth(0)
				ui.Row(c).Padding(3).Gap(2).Radius(radiusTrack).Background(p.surfaceMuted).Shrink(0).Children(func() {
					a.segChip(c, p, "lang:zh", s.LangOptionZH, lang == i18n.LangZH, func() { a.setLang(i18n.LangZH) })
					a.segChip(c, p, "lang:en", s.LangOptionEN, lang == i18n.LangEN, func() { a.setLang(i18n.LangEN) })
				})
			})

		themeMode := a.currentTheme()
		ui.Row(c).Padding(12, spaceCard).Gap(10).AlignItems(ui.Center).
			BorderWidth(1, 0, 0, 0).BorderColor(p.border).
			Children(func() {
				ui.Text(c, s.ThemeLabel).FontSize(fontBody).FontWeight(600).TextColor(p.text).Grow(1).Shrink(1).MinWidth(0)
				ui.Row(c).Padding(3).Gap(2).Radius(radiusTrack).Background(p.surfaceMuted).Shrink(0).Children(func() {
					a.segChip(c, p, "theme:auto", s.ThemeSystem, themeMode == "", func() { a.setTheme("") })
					a.segChip(c, p, "theme:light", s.ThemeLight, themeMode == "light", func() { a.setTheme("light") })
					a.segChip(c, p, "theme:dark", s.ThemeDark, themeMode == "dark", func() { a.setTheme("dark") })
				})
			})
	})

	// Card 2: Check Interval Presets + Custom
	ui.Column(c).Padding(spaceCard).Gap(10).Radius(radiusCard).Background(p.surface).Border(1, p.border).Children(func() {
		ui.Row(c).AlignItems(ui.Center).Gap(8).Children(func() {
			ui.Text(c, s.IntervalTitle).FontSize(fontBody).FontWeight(600).TextColor(p.text).Grow(1).Shrink(1).MinWidth(0)
			ui.Text(c, formatDuration(st.CheckInterval, lang)).FontSize(fontSub).FontWeight(600).TextColor(p.accentText).Shrink(0)
		})

		presets := []int{15, 30, 60, 300}
		ui.Row(c).Padding(3).Gap(2).Radius(radiusTrack).Background(p.surfaceMuted).Children(func() {
			for idx, sec := range presets {
				active := !a.customIntervalMode && st.CheckInterval == sec
				bg, fg := ui.Transparent, p.muted
				if active {
					bg, fg = p.accent, ui.Hex("#FFFFFF")
				}
				btn := ui.Box(c.Key(fmt.Sprintf("freq:%d", sec))).Grow(1).Shrink(1).MinWidth(0).
					Padding(6, 4).Radius(radiusSegment).Background(bg).Center().
					Focusable().Cursor(ui.CursorPointer).
					Children(func() {
						ui.Text(c, s.IntervalPresets[idx]).FontSize(fontSub).FontWeight(600).TextColor(fg).SingleLine()
					})
				if btn.Clicked() {
					targetSec := sec
					a.mu.Lock()
					a.customIntervalMode = false
					a.intervalError = ""
					a.customIntervalText = strconv.Itoa(targetSec)
					a.mu.Unlock()
					_, _ = a.monitor.SetInterval(targetSec)
				}
			}

			cActive := a.customIntervalMode || (st.CheckInterval != 15 && st.CheckInterval != 30 && st.CheckInterval != 60 && st.CheckInterval != 300)
			cBg, cFg := ui.Transparent, p.muted
			if cActive {
				cBg, cFg = p.accent, ui.Hex("#FFFFFF")
			}
			cBtn := ui.Box(c.Key("freq:custom")).Grow(1).Shrink(1).MinWidth(0).
				Padding(6, 4).Radius(radiusSegment).Background(cBg).Center().
				Focusable().Cursor(ui.CursorPointer).
				Children(func() {
					ui.Text(c, s.IntervalCustom).FontSize(fontSub).FontWeight(600).TextColor(cFg).SingleLine()
				})
			if cBtn.Clicked() {
				a.mu.Lock()
				a.customIntervalMode = true
				a.intervalError = ""
				a.customIntervalText = strconv.Itoa(st.CheckInterval)
				a.mu.Unlock()
			}
		})

		if a.customIntervalMode {
			ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
				ui.TextInput(c.Key("custom_interval"), &a.customIntervalText).Grow(1).Shrink(1).MinWidth(0).Placeholder("5 - 3600")
				if ui.PrimaryButton(c.Key("apply_interval"), s.BtnSave).Clicked() {
					n, ok := validateCustomInterval(a.customIntervalText)
					if !ok {
						a.mu.Lock()
						a.intervalError = s.ErrInvalidInterval
						a.mu.Unlock()
						return
					}
					_, _ = a.monitor.SetInterval(n)
					newSec := a.monitor.Settings().CheckIntervalSec
					a.mu.Lock()
					a.customIntervalText = strconv.Itoa(newSec)
					a.intervalError = ""
					a.mu.Unlock()
					a.setToast(s.SavedNotice)
				}
			})
		}
		if a.intervalError != "" {
			ui.Text(c, a.intervalError).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.dangerText)
		}
	})

	// Card 3: Help, Wizard & About (flat inner dividers, no nested cards, calm quit button)
	ui.Column(c).Radius(radiusCard).Background(p.surface).Border(1, p.border).Clip().Children(func() {
		helpHeader := ui.Row(c).Padding(12, spaceCard).Gap(8).AlignItems(ui.Center).Focusable().Cursor(ui.CursorPointer).Children(func() {
			ui.Text(c, s.HelpTitle).FontSize(fontBody).FontWeight(600).TextColor(p.text).Grow(1).Shrink(1).MinWidth(0)
			chevron := svgChevronDown
			if a.showHelp {
				chevron = svgChevronUp
			}
			ui.Box(c).Size(28, 28).Radius(radiusControl).Background(p.surfaceMuted).Center().Shrink(0).Children(func() {
				ui.Icon(c, chevron).Size(16, 16).TextColor(p.muted)
			})
		})
		if helpHeader.Clicked() {
			a.mu.Lock()
			a.showHelp = !a.showHelp
			a.mu.Unlock()
		}
		if a.showHelp {
			ui.Column(c).Padding(12, spaceCard).Gap(6).
				BorderWidth(1, 0, 0, 0).BorderColor(p.border).
				Children(func() {
					for i, line := range s.HelpLines {
						ui.Textf(c, "%d. %s", i+1, line).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.muted)
					}
				})
		}

		ui.Row(c).Padding(12, spaceCard).Gap(8).AlignItems(ui.Center).Wrap().
			BorderWidth(1, 0, 0, 0).BorderColor(p.border).
			Children(func() {
				if ui.Button(c.Key("rerun_wizard"), s.BtnRerunWizard).Clicked() {
					step := 1
					if st.Permission == policy.PermissionAuthorized && !isIOS() {
						step = 2
						go func() { _, _ = a.monitor.ScanNearby(context.Background()) }()
					}
					a.mu.Lock()
					a.wizardStep = step
					a.wizardPrimarySSID = st.SSIDP
					a.wizardBackupSSID = st.SSIDB
					a.wizardError = ""
					a.activeTab = tabOnboarding
					a.mu.Unlock()
				}
				ui.Spacer(c)
				if !isMobile && runtime.GOOS != "android" && runtime.GOOS != "ios" {
					if ui.Button(c.Key("quit"), s.BtnQuit).Clicked() {
						a.monitor.Close()
						mygo.App.Quit()
					}
				}
			})

		ui.Row(c).Padding(10, spaceCard).Gap(8).AlignItems(ui.Center).Wrap().
			BorderWidth(1, 0, 0, 0).BorderColor(p.border).
			Children(func() {
				ui.Text(c, s.PrivacyNote).FontSize(fontCaption).TextColor(p.muted).Grow(1).Shrink(1).MinWidth(0)
				ui.Text(c, s.VersionLabel).FontSize(fontCaption).TextColor(p.muted).Shrink(0)
			})
	})
}

func (a *App) segChip(c *ui.Context, p palette, key, label string, active bool, onClick func()) {
	bg, fg := ui.Transparent, p.muted
	if active {
		bg, fg = p.surface, p.text
	}
	btn := ui.Box(c.Key(key)).Padding(5, 8).Radius(radiusSegment).Background(bg).
		Focusable().Cursor(ui.CursorPointer).
		Children(func() {
			ui.Text(c, label).FontSize(fontSub).FontWeight(600).TextColor(fg).SingleLine()
		})
	if btn.Clicked() {
		onClick()
	}
}

package uiapp

import (
	"fmt"
	"runtime"
	"strconv"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"

	"via/internal/i18n"
	"via/internal/wifi"
)

func (a *App) renderSettings(c *ui.Context, p palette, s i18n.Strings, st wifi.State, isMobile bool) {
	// Card 1: General (Auto-launch + Language)
	ui.Column(c).Radius(14).Background(p.surface).Border(1, p.border).Clip().Children(func() {
		if isMobile {
			ui.Row(c).Padding(12, 14).Gap(10).AlignItems(ui.Center).Children(func() {
				ui.Column(c).Grow(1).Gap(2).Children(func() {
					ui.Text(c, s.BootRestoreTitle).FontSize(13).FontWeight(600).TextColor(p.text)
					ui.Text(c, s.BootRestoreDesc).FontSize(11).TextColor(p.muted)
				})
				if ui.Switch(c.Key("boot_restore"), &a.bootRestore).Label(s.BootRestoreTitle).Changed() {
					a.monitor.SetBootRestore(a.bootRestore)
				}
			})
		} else {
			ui.Row(c).Padding(12, 14).Gap(10).AlignItems(ui.Center).Children(func() {
				ui.Column(c).Grow(1).Gap(2).Children(func() {
					ui.Text(c, s.LaunchAtLoginTitle).FontSize(13).FontWeight(600).TextColor(p.text)
					ui.Text(c, s.LaunchAtLoginDesc).FontSize(11).TextColor(p.muted)
				})
				if ui.Switch(c.Key("autostart"), &a.launchAtLogin).Label(s.LaunchAtLoginTitle).Changed() {
					_ = mygo.App.SetOpenAtLogin(a.launchAtLogin)
				}
			})
		}

		ui.Row(c).Padding(12, 14).Gap(10).AlignItems(ui.Center).BorderWidth(1, 0, 0, 0).BorderColor(p.border).Children(func() {
			ui.Text(c, s.LanguageLabel).FontSize(13).FontWeight(600).TextColor(p.text).Grow(1)
			a.langChip(c, p, "中文", a.lang == i18n.LangZH, func() { a.setLang(i18n.LangZH) })
			a.langChip(c, p, "EN", a.lang == i18n.LangEN, func() { a.setLang(i18n.LangEN) })
		})
	})

	// Card 2: Check Interval Presets + Custom
	ui.Column(c).Padding(14).Gap(10).Radius(14).Background(p.surface).Border(1, p.border).Children(func() {
		ui.Row(c).AlignItems(ui.Center).Children(func() {
			ui.Text(c, s.IntervalTitle).FontSize(13).FontWeight(600).TextColor(p.text).Grow(1)
			ui.Textf(c, "%d %s", st.CheckInterval, s.IntervalSecondsSuffix).FontSize(12).FontWeight(600).TextColor(p.accentText)
		})

		presets := []int{15, 30, 60, 300}
		ui.Row(c).Gap(6).Children(func() {
			for idx, sec := range presets {
				active := !a.customIntervalMode && st.CheckInterval == sec
				bg, fg := p.surfaceMuted, p.muted
				if active {
					bg, fg = p.accent, ui.Hex("#FFFFFF")
				}
				btn := ui.Box(c.Key(fmt.Sprintf("freq:%d", sec))).Grow(1).Padding(6, 0).Radius(8).Background(bg).Center().
					Focusable().Cursor(ui.CursorPointer).
					Children(func() {
						ui.Text(c, s.IntervalPresets[idx]).FontSize(11).FontWeight(600).TextColor(fg)
					})
				if btn.Clicked() {
					targetSec := sec
					a.mu.Lock()
					a.customIntervalMode = false
					a.intervalClamped = false
					a.customIntervalText = strconv.Itoa(targetSec)
					a.mu.Unlock()
					_, _ = a.monitor.SetInterval(targetSec)
				}
			}

			cActive := a.customIntervalMode || (st.CheckInterval != 15 && st.CheckInterval != 30 && st.CheckInterval != 60 && st.CheckInterval != 300)
			cBg, cFg := p.surfaceMuted, p.muted
			if cActive {
				cBg, cFg = p.accent, ui.Hex("#FFFFFF")
			}
			cBtn := ui.Box(c.Key("freq:custom")).Grow(1).Padding(6, 0).Radius(8).Background(cBg).Center().
				Focusable().Cursor(ui.CursorPointer).
				Children(func() {
					ui.Text(c, s.IntervalCustom).FontSize(11).FontWeight(600).TextColor(cFg)
				})
			if cBtn.Clicked() {
				a.mu.Lock()
				a.customIntervalMode = true
				a.customIntervalText = strconv.Itoa(st.CheckInterval)
				a.mu.Unlock()
			}
		})

		if a.customIntervalMode {
			ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
				ui.TextInput(c.Key("custom_interval"), &a.customIntervalText).Grow(1).Placeholder("5 - 3600")
				if ui.PrimaryButton(c.Key("apply_interval"), s.BtnSave).Clicked() {
					n, err := strconv.Atoi(a.customIntervalText)
					if err != nil {
						n = 5
					}
					adjusted, _ := a.monitor.SetInterval(n)
					newSec := a.monitor.Settings().CheckIntervalSec
					a.mu.Lock()
					a.customIntervalText = strconv.Itoa(newSec)
					a.intervalClamped = adjusted
					a.mu.Unlock()
				}
			})
		}
		if a.intervalClamped {
			ui.Text(c, s.IntervalClampedHint).FontSize(11).TextColor(p.warningText)
		}
	})

	// Card 3: Help, Wizard & About
	ui.Column(c).Padding(14).Gap(10).Radius(14).Background(p.surface).Border(1, p.border).Children(func() {
		helpHeader := ui.Row(c).AlignItems(ui.Center).Focusable().Cursor(ui.CursorPointer).Children(func() {
			ui.Text(c, s.HelpTitle).FontSize(13).FontWeight(600).TextColor(p.text).Grow(1)
			chevron := svgChevronDown
			if a.showHelp {
				chevron = svgChevronUp
			}
			ui.Box(c).Size(28, 28).Radius(8).Background(p.surfaceMuted).Center().Children(func() {
				ui.Icon(c, chevron).Size(16, 16).TextColor(p.muted)
			})
		})
		if helpHeader.Clicked() {
			a.mu.Lock()
			a.showHelp = !a.showHelp
			a.mu.Unlock()
		}
		if a.showHelp {
			ui.Column(c).Padding(10).Gap(6).Radius(10).Background(p.bg).Children(func() {
				for _, line := range s.HelpLines {
					ui.Text(c, line).FontSize(11).TextColor(p.muted)
				}
			})
		}

		ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
			if ui.Button(c.Key("rerun_wizard"), s.BtnRerunWizard).Clicked() {
				a.mu.Lock()
				a.wizardStep = 1
				a.wizardPrimarySSID = st.SSIDP
				a.wizardBackupSSID = st.SSIDB
				a.wizardError = ""
				a.activeTab = tabOnboarding
				a.mu.Unlock()
			}
			ui.Spacer(c)
			if !isMobile && runtime.GOOS != "android" && runtime.GOOS != "ios" {
				quitBtn := ui.Box(c.Key("quit")).Padding(6, 12).Radius(8).Background(p.dangerSoft).
					Focusable().Cursor(ui.CursorPointer).
					Children(func() {
						ui.Text(c, s.BtnQuit).FontSize(12).FontWeight(600).TextColor(p.dangerText)
					})
				if quitBtn.Clicked() {
					a.monitor.Close()
					mygo.App.Quit()
				}
			}
		})

		ui.Text(c, s.PrivacyNote).FontSize(11).TextColor(p.muted)
	})
}

func (a *App) langChip(c *ui.Context, p palette, label string, active bool, onClick func()) {
	bg, fg := p.surfaceMuted, p.muted
	if active {
		bg, fg = p.accentSoft, p.accentText
	}
	btn := ui.Box(c.Key("lang:" + label)).Padding(4, 10).Radius(8).Background(bg).
		Focusable().Cursor(ui.CursorPointer).
		Children(func() {
			ui.Text(c, label).FontSize(11).FontWeight(600).TextColor(fg)
		})
	if btn.Clicked() {
		onClick()
	}
}

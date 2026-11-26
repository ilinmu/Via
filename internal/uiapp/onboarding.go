package uiapp

import (
	"context"

	"github.com/egoist/mygo/ui"

	"via/internal/i18n"
	"via/internal/policy"
	"via/internal/store"
	"via/internal/wifi"
)

func (a *App) renderOnboarding(c *ui.Context, p palette, s i18n.Strings, st wifi.State, _ bool) {
	permOK := st.Permission == policy.PermissionAuthorized || isIOS()

	// Never remain on step 2/3 if OS permission is missing.
	if !permOK && a.wizardStep > 1 {
		a.mu.Lock()
		a.wizardStep = 1
		a.mu.Unlock()
	}

	// 3-step progress bar
	ui.Row(c).Gap(6).Children(func() {
		for step := 1; step <= 3; step++ {
			col := p.surfaceMuted
			if step <= a.wizardStep {
				col = p.accent
			}
			ui.Box(c).Grow(1).Height(4).Radius(2).Background(col)
		}
	})

	switch a.wizardStep {
	case 1:
		ui.Column(c).Padding(16).Gap(12).Radius(14).Background(p.surface).Border(1, p.border).Children(func() {
			ui.Text(c, s.WizardStep1Title).FontSize(15).Bold().TextColor(p.text)
			ui.Text(c, s.WizardStep1Desc).FontSize(12).TextColor(p.muted)
			if !permOK {
				ui.Box(c).Padding(10).Radius(10).Background(p.warningSoft).Children(func() {
					ui.Text(c, s.PermMacSettingsHint).FontSize(11).TextColor(p.warningText)
				})
			}

			ui.Column(c).Gap(8).Children(func() {
				if !isIOS() {
					if permOK {
						if ui.PrimaryButton(c.Key("wiz_continue"), s.WizardNext).Clicked() {
							go func() { _, _ = a.monitor.ScanNearby(context.Background()) }()
							a.mu.Lock()
							a.wizardStep = 2
							a.mu.Unlock()
						}
					} else {
						if ui.PrimaryButton(c.Key("wiz_grant"), s.WizardStep1Grant).Clicked() {
							a.triggerPermissionRequest()
						}
						if ui.Button(c.Key("wiz_recheck"), s.BtnRecheckPerm).Clicked() {
							go a.monitor.RefreshStatus(context.Background())
						}
					}
				} else {
					if ui.PrimaryButton(c.Key("wiz_ios_next"), s.WizardNext).Clicked() {
						a.mu.Lock()
						a.wizardStep = 2
						a.mu.Unlock()
					}
				}
			})
		})

	case 2:
		ui.Column(c).Padding(16).Gap(10).Radius(14).Background(p.surface).Border(1, p.border).Children(func() {
			ui.Row(c).AlignItems(ui.Center).Children(func() {
				ui.Text(c, s.WizardStep2Title).FontSize(14).Bold().TextColor(p.text).Grow(1)
				if !isIOS() {
					scanText := s.BtnScanNearby
					if st.Scanning {
						scanText = s.BtnScanning
					}
					if ui.Button(c.Key("wiz_scan"), scanText).Clicked() && !st.Scanning {
						go func() { _, _ = a.monitor.ScanNearby(context.Background()) }()
					}
				}
			})

			ui.Text(c, s.PrimaryLabel).FontSize(11).FontWeight(600).TextColor(p.accentText)
			a.renderNetworkPicker(c, p, s, st, "wiz_picker_p", &a.wizardPrimarySSID)
			ui.TextInput(c.Key("wiz_p_ssid"), &a.wizardPrimarySSID).Placeholder(s.SSIDPlaceholder)
			ui.TextInput(c.Key("wiz_p_pwd"), &a.wizardPrimaryPwd).Password().Placeholder(s.PwdPlaceholder)

			ui.Text(c, s.BackupLabel).FontSize(11).FontWeight(600).TextColor(p.warningText)
			a.renderNetworkPicker(c, p, s, st, "wiz_picker_b", &a.wizardBackupSSID)
			ui.TextInput(c.Key("wiz_b_ssid"), &a.wizardBackupSSID).Placeholder(s.SSIDPlaceholder)
			ui.TextInput(c.Key("wiz_b_pwd"), &a.wizardBackupPwd).Password().Placeholder(s.PwdPlaceholder)

			if a.wizardError != "" {
				ui.Text(c, a.wizardError).FontSize(11).TextColor(p.dangerText)
			}

			ui.Row(c).Gap(8).Justify(ui.End).Children(func() {
				if ui.Button(c.Key("wiz_prev2"), s.WizardPrev).Clicked() {
					a.mu.Lock()
					a.wizardStep = 1
					a.mu.Unlock()
				}
				if ui.PrimaryButton(c.Key("wiz_next2"), s.WizardNext).Clicked() {
					if err := store.ValidateSlot(store.SlotPrimary, a.wizardPrimarySSID, a.wizardBackupSSID); err != nil {
						a.mu.Lock()
						a.wizardError = s.ErrEmptySSID
						if err == store.ErrDuplicateSSID {
							a.wizardError = s.ErrDuplicateSSID
						}
						a.mu.Unlock()
						return
					}
					if err := store.ValidateSlot(store.SlotBackup, a.wizardBackupSSID, a.wizardPrimarySSID); err != nil {
						a.mu.Lock()
						a.wizardError = s.ErrEmptySSID
						if err == store.ErrDuplicateSSID {
							a.wizardError = s.ErrDuplicateSSID
						}
						a.mu.Unlock()
						return
					}
					a.mu.Lock()
					a.wizardError = ""
					a.wizardStep = 3
					a.mu.Unlock()
				}
			})
		})

	default:
		ui.Column(c).Padding(16).Gap(12).Radius(14).Background(p.surface).Border(1, p.border).Children(func() {
			ui.Text(c, s.WizardStep3Title).FontSize(15).Bold().TextColor(p.text)
			ui.Column(c).Padding(10).Gap(6).Radius(10).Background(p.bg).Children(func() {
				ui.Textf(c, "%s: %s", s.PrimaryLabel, a.wizardPrimarySSID).FontSize(12).FontWeight(600).TextColor(p.text)
				ui.Textf(c, "%s: %s", s.BackupLabel, a.wizardBackupSSID).FontSize(12).FontWeight(600).TextColor(p.text)
				permStr := s.WizardPermPending
				if st.Permission == policy.PermissionAuthorized {
					permStr = s.WizardPermGranted
				}
				ui.Textf(c, "%s: %s", s.WizardPermStatus, permStr).FontSize(12).TextColor(p.muted)
			})

			if a.wizardError != "" {
				ui.Text(c, a.wizardError).FontSize(11).TextColor(p.dangerText)
			}

			ui.Row(c).Gap(8).Justify(ui.End).Children(func() {
				if ui.Button(c.Key("wiz_prev3"), s.WizardPrev).Clicked() {
					a.mu.Lock()
					a.wizardStep = 2
					a.mu.Unlock()
				}
				finishLabel := s.WizardFinishAndStart
				startAfter := !isIOS() && st.Permission == policy.PermissionAuthorized
				if !startAfter {
					finishLabel = s.WizardFinishSaveOnly
				}
				if ui.PrimaryButton(c.Key("wiz_finish"), finishLabel).Clicked() {
					pSSID, pPwd := a.wizardPrimarySSID, a.wizardPrimaryPwd
					bSSID, bPwd := a.wizardBackupSSID, a.wizardBackupPwd
					if err := a.monitor.SaveSlot(store.SlotPrimary, pSSID, pPwd); err != nil {
						a.mu.Lock()
						a.wizardError = err.Error()
						a.mu.Unlock()
						return
					}
					if err := a.monitor.SaveSlot(store.SlotBackup, bSSID, bPwd); err != nil {
						a.mu.Lock()
						a.wizardError = err.Error()
						a.mu.Unlock()
						return
					}
					a.monitor.SetOnboardingDone(true)
					a.mu.Lock()
					a.wizardError = ""
					a.activeTab = tabDashboard
					a.mu.Unlock()
					if startAfter {
						go a.monitor.Start()
					}
				}
			})
		})
	}
}

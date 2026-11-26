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

	// Automatically skip permission step when already authorized.
	if permOK && a.wizardStep == 1 && !isIOS() {
		a.mu.Lock()
		a.wizardStep = 2
		a.mu.Unlock()
		go func() { _, _ = a.monitor.ScanNearby(context.Background()) }()
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
		ui.Column(c).Radius(radiusCard).Background(p.surface).Border(1, p.border).Clip().Children(func() {
			ui.Column(c).Padding(16).Gap(8).Children(func() {
				ui.Text(c, s.WizardStep1Title).FontSize(fontTitle).Bold().TextColor(p.text)
				ui.Text(c, s.WizardStep1Desc).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.muted)
			})
			if st.Permission == policy.PermissionDenied {
				ui.Row(c).Padding(12, 16).Background(p.warningSoft).
					BorderWidth(1, 0, 0, 0).BorderColor(p.border).
					Children(func() {
						ui.Text(c, s.PermMacSettingsHint).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.warningText).Grow(1).Shrink(1).MinWidth(0)
					})
			}

			ui.Row(c).Padding(12, 16).Gap(8).Wrap().
				BorderWidth(1, 0, 0, 0).BorderColor(p.border).
				Children(func() {
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
		ui.Column(c).Padding(16).Gap(10).Radius(radiusCard).Background(p.surface).Border(1, p.border).Children(func() {
			ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
				ui.Text(c, s.WizardStep2Title).FontSize(fontTitle).Bold().TextColor(p.text).Grow(1).Shrink(1).MinWidth(0)
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

			ui.Text(c, s.PrimaryLabel).FontSize(fontBody).FontWeight(600).TextColor(p.accentText)
			a.renderNetworkPicker(c, p, s, st, "wiz_picker_p", &a.wizardPrimarySSID)
			ui.TextInput(c.Key("wiz_p_ssid"), &a.wizardPrimarySSID).Placeholder(s.SSIDPlaceholder)
			ui.Row(c).Gap(6).AlignItems(ui.Center).Children(func() {
				pwdIn := ui.TextInput(c.Key("wiz_p_pwd"), &a.wizardPrimaryPwd).Grow(1).Shrink(1).MinWidth(0).Placeholder(s.PwdPlaceholder)
				if !a.wizardPrimaryShowPwd {
					pwdIn.Password()
				}
				eyeIcon, eyeLabel := svgEye, s.ShowPasswordLabel
				if a.wizardPrimaryShowPwd {
					eyeIcon, eyeLabel = svgEyeOff, s.HidePasswordLabel
				}
				eyeBtn := ui.ButtonBase(c.Key("wiz_p_eye")).Size(32, 32).Radius(radiusControl).
					Background(p.surfaceMuted).Center().Shrink(0).Label(eyeLabel).
					Children(func() {
						ui.Icon(c, eyeIcon).Size(15, 15).TextColor(p.muted)
					})
				if eyeBtn.Clicked() {
					a.mu.Lock()
					a.wizardPrimaryShowPwd = !a.wizardPrimaryShowPwd
					a.mu.Unlock()
				}
			})

			ui.Text(c, s.BackupLabel).FontSize(fontBody).FontWeight(600).TextColor(p.warningText)
			a.renderNetworkPicker(c, p, s, st, "wiz_picker_b", &a.wizardBackupSSID)
			ui.TextInput(c.Key("wiz_b_ssid"), &a.wizardBackupSSID).Placeholder(s.SSIDPlaceholder)
			ui.Row(c).Gap(6).AlignItems(ui.Center).Children(func() {
				pwdIn := ui.TextInput(c.Key("wiz_b_pwd"), &a.wizardBackupPwd).Grow(1).Shrink(1).MinWidth(0).Placeholder(s.PwdPlaceholder)
				if !a.wizardBackupShowPwd {
					pwdIn.Password()
				}
				eyeIcon, eyeLabel := svgEye, s.ShowPasswordLabel
				if a.wizardBackupShowPwd {
					eyeIcon, eyeLabel = svgEyeOff, s.HidePasswordLabel
				}
				eyeBtn := ui.ButtonBase(c.Key("wiz_b_eye")).Size(32, 32).Radius(radiusControl).
					Background(p.surfaceMuted).Center().Shrink(0).Label(eyeLabel).
					Children(func() {
						ui.Icon(c, eyeIcon).Size(15, 15).TextColor(p.muted)
					})
				if eyeBtn.Clicked() {
					a.mu.Lock()
					a.wizardBackupShowPwd = !a.wizardBackupShowPwd
					a.mu.Unlock()
				}
			})

			if a.wizardError != "" {
				ui.Text(c, a.wizardError).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.dangerText)
			}

			ui.Row(c).Gap(8).Justify(ui.End).Wrap().Children(func() {
				if isIOS() {
					if ui.Button(c.Key("wiz_prev2"), s.WizardPrev).Clicked() {
						a.mu.Lock()
						a.wizardStep = 1
						a.mu.Unlock()
					}
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
		ui.Column(c).Radius(radiusCard).Background(p.surface).Border(1, p.border).Clip().Children(func() {
			ui.Box(c).Padding(16).Children(func() {
				ui.Text(c, s.WizardStep3Title).FontSize(fontTitle).Bold().TextColor(p.text)
			})
			ui.Column(c).Padding(12, 16).Gap(8).BorderWidth(1, 0, 0, 0).BorderColor(p.border).Children(func() {
				ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
					ui.Text(c, s.PrimaryLabel).FontSize(fontSub).TextColor(p.muted).Grow(1).Shrink(1).MinWidth(0)
					ui.Text(c, a.wizardPrimarySSID).FontSize(fontBody).FontWeight(600).TextColor(p.text).SingleLine()
				})
				ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
					ui.Text(c, s.BackupLabel).FontSize(fontSub).TextColor(p.muted).Grow(1).Shrink(1).MinWidth(0)
					ui.Text(c, a.wizardBackupSSID).FontSize(fontBody).FontWeight(600).TextColor(p.text).SingleLine()
				})
				permStr := s.WizardPermPending
				if st.Permission == policy.PermissionAuthorized {
					permStr = s.WizardPermGranted
				}
				ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
					ui.Text(c, s.WizardPermStatus).FontSize(fontSub).TextColor(p.muted).Grow(1).Shrink(1).MinWidth(0)
					ui.Text(c, permStr).FontSize(fontSub).FontWeight(600).TextColor(p.text).SingleLine()
				})
			})

			if a.wizardError != "" {
				ui.Box(c).Padding(10, 16).BorderWidth(1, 0, 0, 0).BorderColor(p.border).Children(func() {
					ui.Text(c, a.wizardError).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.dangerText)
				})
			}

			ui.Row(c).Padding(12, 16).Gap(8).Justify(ui.End).Wrap().
				BorderWidth(1, 0, 0, 0).BorderColor(p.border).
				Children(func() {
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

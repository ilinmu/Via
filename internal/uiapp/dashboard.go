package uiapp

import (
	"context"
	"fmt"
	"time"

	"github.com/egoist/mygo/ui"

	"via/internal/i18n"
	"via/internal/policy"
	"via/internal/store"
	"via/internal/wifi"
)

const pickerCurrentToken = "\x00__via_current__"

func (a *App) renderDashboard(c *ui.Context, p palette, s i18n.Strings, st wifi.State, _ bool) {
	permOK := st.Permission == policy.PermissionAuthorized && !isIOS()

	// Lock out open inline editor if permission is missing.
	if !permOK {
		a.mu.Lock()
		a.editingSlot = ""
		a.editError = ""
		a.mu.Unlock()
	}

	// Contextual permission / configuration notices
	if isIOS() {
		a.infoBanner(c, p, s.SubIOSUnsupported, "", nil)
	} else if st.Permission != policy.PermissionAuthorized {
		a.permissionBanner(c, p, s, st)
	} else if !st.Configured {
		a.warningBanner(c, p, "cfg_banner", s.SubNotConfigured, s.BtnSetupNet, func() {
			a.openSlotEditor(store.SlotPrimary)
		})
	}
	if st.AdvisoryMode {
		a.infoBanner(c, p, s.SubAndroidAdvisory, "", nil)
	}

	connectedTitle := st.CurrentSSID
	if connectedTitle == "" {
		connectedTitle = "Wi-Fi"
	}

	badgeText := s.BadgePaused
	badgeBg, badgeFg, dotColor := p.dangerSoft, p.dangerText, p.danger
	subText := s.SubPausedStopped

	switch {
	case st.Permission != policy.PermissionAuthorized && !isIOS():
		badgeText = s.BadgeNoPermission
		badgeBg, badgeFg, dotColor = p.warningSoft, p.warningText, p.warning
		subText = s.SubNeedPermission
	case !st.Configured:
		badgeText = s.BadgeNotConfigured
		badgeBg, badgeFg, dotColor = p.surfaceMuted, p.muted, p.muted
		subText = s.SubNotConfigured
	case !st.Running:
		badgeText = s.BadgePaused
		badgeBg, badgeFg, dotColor = p.dangerSoft, p.dangerText, p.danger
		if st.HasStopReason && (st.StopReason == policy.StopManualOverrideBackup || st.StopReason == policy.StopManualOverrideUnmanaged) {
			subText = s.SubPausedManual
		} else {
			subText = s.SubPausedStopped
		}
	case st.Role == policy.RolePriority:
		badgeText = s.BadgeGuardPriority
		badgeBg, badgeFg, dotColor = p.successSoft, p.successText, p.success
		subText = formatCountdown(s.SubCheckingInFmt, st.NextCheckAt, st.CheckInterval)
	case st.Role == policy.RoleBackup:
		badgeText = s.BadgeGuardBackup
		badgeBg, badgeFg, dotColor = p.warningSoft, p.warningText, p.warning
		subText = formatCountdown(s.SubBackupInFmt, st.NextCheckAt, st.CheckInterval)
	default:
		badgeText = s.BadgeGuardOther
		badgeBg, badgeFg, dotColor = p.accentSoft, p.accentText, p.accent
		subText = s.SubGuardWaiting
	}

	// Hero Route Card
	ui.Column(c).Padding(14).Gap(12).Radius(14).Background(p.surface).Border(1, p.border).Children(func() {
		ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
			ui.Box(c).Size(9, 9).Radius(5).Background(dotColor)
			ui.Text(c, connectedTitle).FontSize(15).Bold().TextColor(p.text).SingleLine().Grow(1)
			ui.Box(c).Padding(3, 9).Radius(999).Background(badgeBg).Children(func() {
				ui.Text(c, badgeText).FontSize(11).FontWeight(600).TextColor(badgeFg)
			})
		})

		// Route Diagram: Primary <-> Backup
		pActive := st.Configured && st.CurrentSSID == st.SSIDP
		bActive := st.Configured && st.CurrentSSID == st.SSIDB

		ui.Row(c).Padding(8).Gap(6).Radius(10).Background(p.bg).AlignItems(ui.Center).Children(func() {
			pName := st.SSIDP
			if pName == "" {
				pName = s.NotSetTag
			}
			bName := st.SSIDB
			if bName == "" {
				bName = s.NotSetTag
			}
			a.routeNode(c, p, s.PrimarySlotLabel, pName, pActive, p.accent, p.accentText)

			swapBtn := ui.Box(c.Key("swap_btn")).Size(28, 28).Radius(14).Background(p.surface).Border(1, p.border).
				Center()
			if permOK && st.Configured {
				swapBtn.Focusable().Cursor(ui.CursorPointer)
			} else {
				swapBtn.Opacity(0.45)
			}
			swapBtn.Children(func() {
				ui.Text(c, "⇄").FontSize(12).Bold().TextColor(p.muted)
			})
			if permOK && st.Configured && swapBtn.Clicked() {
				go func() { _ = a.monitor.SwapSlots() }()
			}

			a.routeNode(c, p, s.BackupSlotLabel, bName, bActive, p.warning, p.warningText)
		})

		// Master Guard Switch Row
		running := st.Running
		ui.Row(c).Gap(10).AlignItems(ui.Center).Children(func() {
			ui.Column(c).Grow(1).Gap(2).Children(func() {
				ui.Text(c, s.AutoSwitchTitle).FontSize(13).FontWeight(600).TextColor(p.text)
				ui.Text(c, subText).FontSize(11).TextColor(p.muted).SingleLine()
			})
			sw := ui.Switch(c.Key("guard_switch"), &running).Label(s.AutoSwitchTitle)
			if !permOK || !st.Configured {
				sw.Disabled(true)
			}
			if sw.Changed() && permOK && st.Configured {
				go a.monitor.ToggleRunning()
			}
		})

		if !st.Running && permOK && st.HasStopReason && (st.StopReason == policy.StopManualOverrideBackup || st.StopReason == policy.StopManualOverrideUnmanaged) {
			ui.Row(c).Padding(8, 10).Radius(10).Background(p.warningSoft).AlignItems(ui.Center).Children(func() {
				ui.Text(c, s.SubPausedManual).FontSize(11).TextColor(p.warningText).Grow(1)
				if ui.Button(c.Key("resume_now"), s.BtnResumeNow).Clicked() {
					go a.monitor.Start()
				}
			})
		}

		if permOK && st.LastError != "" {
			ui.Row(c).Padding(8, 10).Radius(10).Background(p.dangerSoft).AlignItems(ui.Center).Children(func() {
				ui.Text(c, st.LastError).FontSize(11).TextColor(p.dangerText).Grow(1)
			})
		}
	})

	// Managed Networks Section
	ui.Column(c).Gap(8).Children(func() {
		ui.Row(c).AlignItems(ui.Center).Children(func() {
			ui.Text(c, s.ManagedNetworksTitle).FontSize(11).FontWeight(600).TextColor(p.muted).Grow(1)
			scanLabel := s.BtnScanNearby
			if st.Scanning {
				scanLabel = s.BtnScanning
			}
			scanBtn := ui.Button(c.Key("scan_nearby"), scanLabel)
			if st.Scanning || !permOK {
				scanBtn.Disabled(true)
			}
			if scanBtn.Clicked() && !st.Scanning && permOK {
				go func() {
					_, _ = a.monitor.ScanNearby(context.Background())
				}()
			}
		})

		a.networkCard(c, p, s, st, permOK, store.SlotPrimary, s.RoleBadgeP, s.PrimaryLabel, st.SSIDP, st.Configured && st.CurrentSSID == st.SSIDP)
		a.networkCard(c, p, s, st, permOK, store.SlotBackup, s.RoleBadgeB, s.BackupLabel, st.SSIDB, st.Configured && st.CurrentSSID == st.SSIDB)
	})
}

func (a *App) triggerPermissionRequest() {
	_ = a.monitor.RequestPermission()
	go func() {
		for _, delay := range []time.Duration{400 * time.Millisecond, 1500 * time.Millisecond, 3500 * time.Millisecond} {
			time.Sleep(delay)
			a.monitor.RefreshStatus(context.Background())
			if a.monitor.State().Permission == policy.PermissionAuthorized {
				_, _ = a.monitor.ScanNearby(context.Background())
				return
			}
		}
	}()
}

func (a *App) permissionBanner(c *ui.Context, p palette, s i18n.Strings, st wifi.State) {
	ui.Column(c).Padding(12).Gap(8).Radius(12).Background(p.warningSoft).Children(func() {
		ui.Text(c, s.SubNeedPermission).FontSize(12).FontWeight(600).TextColor(p.warningText)
		ui.Text(c, s.PermMacSettingsHint).FontSize(11).TextColor(p.warningText)
		ui.Row(c).Gap(6).Wrap().Children(func() {
			if ui.PrimaryButton(c.Key("perm_grant"), s.BtnGrantPerm).Clicked() {
				a.triggerPermissionRequest()
			}
			if ui.Button(c.Key("perm_recheck"), s.BtnRecheckPerm).Clicked() {
				go a.monitor.RefreshStatus(context.Background())
			}
		})
	})
}

func formatCountdown(fmtStr string, nextAt time.Time, fallbackSec int) string {
	rem := fallbackSec
	if !nextAt.IsZero() {
		d := int(time.Until(nextAt).Round(time.Second).Seconds())
		if d < 0 {
			d = 0
		}
		rem = d
	}
	return fmt.Sprintf(fmtStr, rem)
}

func (a *App) warningBanner(c *ui.Context, p palette, key, msg, btnLabel string, onClick func()) {
	ui.Row(c).Padding(10, 12).Gap(8).Radius(12).Background(p.warningSoft).AlignItems(ui.Center).Children(func() {
		ui.Text(c, msg).FontSize(11).TextColor(p.warningText).Grow(1)
		if btnLabel != "" && onClick != nil {
			if ui.Button(c.Key(key), btnLabel).Clicked() {
				onClick()
			}
		}
	})
}

func (a *App) infoBanner(c *ui.Context, p palette, msg, btnLabel string, onClick func()) {
	ui.Row(c).Padding(10, 12).Gap(8).Radius(12).Background(p.accentSoft).AlignItems(ui.Center).Children(func() {
		ui.Text(c, msg).FontSize(11).TextColor(p.accentText).Grow(1)
		if btnLabel != "" && onClick != nil {
			if ui.Button(c.Key("info_btn"), btnLabel).Clicked() {
				onClick()
			}
		}
	})
}

func (a *App) routeNode(c *ui.Context, p palette, label, ssid string, active bool, borderColor, labelColor ui.Color) {
	bg, bc, lc := ui.Transparent, ui.Transparent, p.muted
	if active {
		bg, bc, lc = p.surface, borderColor, labelColor
	}
	ui.Column(c).Grow(1).Padding(6, 8).Radius(8).Background(bg).Border(1, bc).AlignItems(ui.Center).Children(func() {
		ui.Text(c, label).FontSize(10).FontWeight(600).TextColor(lc).SingleLine()
		ui.Text(c, ssid).FontSize(12).FontWeight(600).TextColor(p.text).SingleLine()
	})
}

func (a *App) openSlotEditor(slot string) {
	pwd, _ := a.monitor.LoadPassword(slot)
	a.mu.Lock()
	defer a.mu.Unlock()
	a.editingSlot = slot
	a.showPwd = false
	a.editError = ""
	if slot == store.SlotPrimary {
		a.draftSSID = a.state.SSIDP
	} else {
		a.draftSSID = a.state.SSIDB
	}
	a.draftPwd = pwd
}

func (a *App) renderNetworkPicker(c *ui.Context, p palette, s i18n.Strings, st wifi.State, key string, targetSSID *string) {
	a.mu.Lock()
	selected := *targetSSID
	a.mu.Unlock()

	sel := ui.SelectBase(c.Key(key), &selected)
	triggerLabel := s.PickerEmpty
	if selected != "" {
		triggerLabel = selected
	} else if len(st.Nearby) > 0 {
		triggerLabel = fmt.Sprintf(s.PickerTriggerFmt, len(st.Nearby))
	}

	triggerBorder := p.border
	if sel.Open() {
		triggerBorder = p.accent
	}
	sel.Trigger.Padding(8, 10).Radius(8).Background(p.surface).Border(1, triggerBorder).
		AlignItems(ui.Center).Cursor(ui.CursorPointer).
		Children(func() {
			labelColor := p.muted
			if selected != "" {
				labelColor = p.text
			}
			ui.Text(c, triggerLabel).FontSize(12).TextColor(labelColor).SingleLine().Grow(1)
			chevron := svgChevronDown
			if sel.Open() {
				chevron = svgChevronUp
			}
			ui.Icon(c, chevron).Size(16, 16).TextColor(p.muted)
		})

	sel.Popup(func(panel ui.Element) {
		w := sel.Trigger.Bounds().W
		if w < 280 {
			w = 324
		}
		panel.Margin(6, 0, 6, 0).Padding(4).Radius(10).Width(w).MaxHeight(210).
			Background(p.surface).Border(1, p.border).Clip().
			Shadow(0, 6, 16, 0, ui.RGBA(15, 23, 42, 0.14))

		ui.Scroll(c).Shrink(1).Children(func() {
			// First item: Use Current Network
			curItem := sel.Item(pickerCurrentToken).Padding(8, 10).Radius(6).Cursor(ui.CursorPointer)
			curText := s.PickerNoCurrent
			if st.CurrentSSID != "" {
				curText = fmt.Sprintf(s.PickerCurrentFmt, st.CurrentSSID)
			} else {
				curItem.Disabled(true)
			}
			if curItem.Highlighted() {
				curItem.Background(p.accentSoft)
			}
			curItem.Children(func() {
				fg := p.accentText
				if st.CurrentSSID == "" {
					fg = p.muted
				}
				ui.Text(c, curText).FontSize(12).FontWeight(600).TextColor(fg).SingleLine()
			})

			if len(st.Nearby) == 0 {
				ui.Box(c).Padding(8, 10).Children(func() {
					ui.Text(c, s.PickerEmptyList).FontSize(11).TextColor(p.muted)
				})
				return
			}

			for _, net := range st.Nearby {
				n := net
				item := sel.Item(n.SSID).Padding(8, 10).Radius(6).Cursor(ui.CursorPointer)
				if item.Highlighted() {
					item.Background(p.accentSoft)
				} else if n.SSID == selected {
					item.Background(p.bg)
				}
				item.Children(func() {
					ui.Row(c).Gap(6).AlignItems(ui.Center).Children(func() {
						ui.Text(c, n.SSID).FontSize(12).TextColor(p.text).SingleLine().Grow(1)
						if n.Secured {
							ui.Icon(c, svgLock).Size(12, 12).TextColor(p.muted)
						}
						ui.Textf(c, "%ddBm", n.RSSI).FontSize(10).TextColor(p.muted)
					})
				})
			}
		})
	})

	if sel.Trigger.Changed() {
		a.mu.Lock()
		if selected == pickerCurrentToken {
			if st.CurrentSSID != "" {
				*targetSSID = st.CurrentSSID
			}
		} else {
			*targetSSID = selected
		}
		a.mu.Unlock()
	}
}

func (a *App) networkCard(c *ui.Context, p palette, s i18n.Strings, st wifi.State, permOK bool, slot, badge, desc, ssid string, connected bool) {
	a.mu.Lock()
	isOpen := permOK && a.editingSlot == slot
	editErr := a.editError
	showPwd := a.showPwd
	a.mu.Unlock()

	border := p.border
	if isOpen {
		border = p.accent
	}
	badgeBg, badgeFg := p.surfaceMuted, p.muted
	if slot == store.SlotPrimary {
		badgeBg, badgeFg = p.accentSoft, p.accentText
	}

	displaySSID := ssid
	if displaySSID == "" {
		displaySSID = s.NotSetTag
	}
	subtitle := desc
	if !permOK {
		subtitle = s.LockedCardHint
	}

	card := ui.Column(c).Radius(12).Background(p.surface).Border(1, border).Clip()
	if !permOK {
		card.Opacity(0.7)
	}
	card.Children(func() {
		header := ui.Row(c).Padding(10, 12).Gap(10).AlignItems(ui.Center)
		if permOK {
			header.Focusable().Cursor(ui.CursorPointer)
		}
		header.Children(func() {
			ui.Box(c).Size(30, 30).Radius(8).Background(badgeBg).Center().Children(func() {
				ui.Text(c, badge).FontSize(12).Bold().TextColor(badgeFg)
			})
			ui.Column(c).Grow(1).Gap(2).Children(func() {
				ui.Row(c).Gap(6).AlignItems(ui.Center).Children(func() {
					ui.Text(c, displaySSID).FontSize(13).FontWeight(600).TextColor(p.text).SingleLine()
					if connected {
						ui.Box(c).Padding(2, 6).Radius(6).Background(p.successSoft).Children(func() {
							ui.Text(c, s.ConnectedTag).FontSize(10).FontWeight(600).TextColor(p.successText)
						})
					}
				})
				ui.Text(c, subtitle).FontSize(11).TextColor(p.muted).SingleLine()
			})
			if permOK && ssid != "" && !connected {
				if ui.Button(c.Key("switch:"+slot), s.BtnSwitchNow).Clicked() {
					targetSlot := slot
					go func() {
						if err := a.monitor.ConnectNow(context.Background(), targetSlot); err != nil {
							a.setToast(fmt.Sprintf(s.SwitchFailedFmt, err.Error()))
							return
						}
						a.setToast(s.SwitchedNotice)
					}()
				}
			}
			ui.Box(c).Size(28, 28).Radius(8).Background(p.surfaceMuted).Center().Children(func() {
				if !permOK {
					ui.Icon(c, svgLock).Size(14, 14).TextColor(p.muted)
					return
				}
				chevron := svgChevronDown
				if isOpen {
					chevron = svgChevronUp
				}
				ui.Icon(c, chevron).Size(16, 16).TextColor(p.muted)
			})
		})
		if permOK && header.Clicked() {
			if isOpen {
				a.mu.Lock()
				a.editingSlot = ""
				a.editError = ""
				a.mu.Unlock()
			} else {
				a.openSlotEditor(slot)
			}
		}

		if isOpen {
			ui.Column(c).Padding(12).Gap(8).Background(p.bg).BorderWidth(1, 0, 0, 0).BorderColor(p.border).Children(func() {
				a.renderNetworkPicker(c, p, s, st, "net_picker:"+slot, &a.draftSSID)

				ui.TextInput(c.Key("ssid:"+slot), &a.draftSSID).Placeholder(s.SSIDPlaceholder)

				ui.Row(c).Gap(6).AlignItems(ui.Center).Children(func() {
					pwdIn := ui.TextInput(c.Key("pwd:"+slot), &a.draftPwd).Grow(1).Placeholder(s.PwdPlaceholder)
					if !showPwd {
						pwdIn.Password()
					}
					eyeLabel := "👁"
					if showPwd {
						eyeLabel = "🙈"
					}
					if ui.Button(c.Key("eye:"+slot), eyeLabel).Clicked() {
						a.mu.Lock()
						a.showPwd = !a.showPwd
						a.mu.Unlock()
					}
				})

				if editErr != "" {
					ui.Text(c, editErr).FontSize(11).TextColor(p.dangerText)
				}

				ui.Row(c).Gap(8).Justify(ui.End).Children(func() {
					if ui.Button(c.Key("cancel:"+slot), s.BtnCancel).Clicked() {
						a.mu.Lock()
						a.editingSlot = ""
						a.editError = ""
						a.mu.Unlock()
					}
					if ui.PrimaryButton(c.Key("save:"+slot), s.BtnSave).Clicked() {
						a.mu.Lock()
						dSSID, dPwd := a.draftSSID, a.draftPwd
						a.mu.Unlock()
						err := a.monitor.SaveSlot(slot, dSSID, dPwd)
						if err != nil {
							msg := err.Error()
							if err == store.ErrEmptySSID {
								msg = s.ErrEmptySSID
							} else if err == store.ErrDuplicateSSID {
								msg = s.ErrDuplicateSSID
							}
							a.mu.Lock()
							a.editError = msg
							a.mu.Unlock()
						} else {
							a.mu.Lock()
							a.editingSlot = ""
							a.editError = ""
							a.mu.Unlock()
							a.setToast(s.SavedNotice)
						}
					}
				})
			})
		}
	})
}

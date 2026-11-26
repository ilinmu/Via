package uiapp

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/egoist/mygo/ui"

	"via/internal/i18n"
	"via/internal/policy"
	"via/internal/store"
	"via/internal/wifi"
)

const pickerCurrentToken = "\x00__via_current__"

func (a *App) renderDashboard(c *ui.Context, p palette, s i18n.Strings, lang i18n.Lang, st wifi.State, _ bool) {
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
		a.infoBanner(c, p, s.SubIOSUnsupported)
	} else if st.Permission != policy.PermissionAuthorized {
		a.permissionBanner(c, p, s, st)
	} else if !st.Configured {
		missingSlot := store.SlotPrimary
		if st.SSIDP != "" {
			missingSlot = store.SlotBackup
		}
		a.noticeBanner(c, p, "cfg_banner", s.SubNotConfigured, s.BtnSetupNet, func() {
			a.openSlotEditor(missingSlot)
		})
	}
	if st.AdvisoryMode {
		a.infoBanner(c, p, s.SubAndroidAdvisory)
	}

	connectedTitle := st.CurrentSSID
	if connectedTitle == "" {
		connectedTitle = s.NotConnectedTitle
	}

	badgeText := s.BadgePaused
	badgeBg, badgeFg, dotColor := p.surfaceMuted, p.muted, p.muted
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
		badgeBg, badgeFg, dotColor = p.surfaceMuted, p.muted, p.muted
		if st.HasStopReason && (st.StopReason == policy.StopManualOverrideBackup || st.StopReason == policy.StopManualOverrideUnmanaged) {
			subText = s.SubPausedManual
		} else {
			subText = s.SubPausedStopped
		}
	case st.Role == policy.RolePriority:
		badgeText = s.BadgeGuardPriority
		badgeBg, badgeFg, dotColor = p.successSoft, p.successText, p.success
		subText = formatCountdown(s.SubCheckingInFmt, st.NextCheckAt, st.CheckInterval, lang)
	case st.Role == policy.RoleBackup:
		badgeText = s.BadgeGuardBackup
		badgeBg, badgeFg, dotColor = p.warningSoft, p.warningText, p.warning
		subText = formatCountdown(s.SubBackupInFmt, st.NextCheckAt, st.CheckInterval, lang)
	default:
		badgeText = s.BadgeGuardOther
		badgeBg, badgeFg, dotColor = p.accentSoft, p.accentText, p.accent
		subText = s.SubGuardWaiting
	}

	// Flat Hero Card separated by crisp 1px horizontal hairlines (zero nested cards).
	ui.Column(c).Radius(radiusCard).Background(p.surface).Border(1, p.border).Clip().Children(func() {
		// Row 1: Current Connection + Status Pill
		ui.Row(c).Padding(12, spaceCard).Gap(8).AlignItems(ui.Center).Children(func() {
			ui.Box(c).Size(8, 8).Radius(4).Background(dotColor).Shrink(0)
			ui.Text(c, connectedTitle).FontSize(fontTitle).Bold().TextColor(p.text).SingleLine().Grow(1).Shrink(1).MinWidth(0)
			ui.Box(c).Padding(3, 9).Radius(999).Background(badgeBg).Shrink(0).Children(func() {
				ui.Text(c, badgeText).FontSize(fontCaption).FontWeight(600).TextColor(badgeFg).SingleLine()
			})
		})

		// Row 2: Stacked Primary / Backup Path Rows (Option C: clear primary & accent color distinction, no swap button)
		pActive := st.Configured && st.CurrentSSID == st.SSIDP
		bActive := st.Configured && st.CurrentSSID == st.SSIDB

		ui.Column(c).Padding(8, spaceCard).Gap(4).
			BorderWidth(1, 0, 0, 0).BorderColor(p.border).
			Children(func() {
				pName := st.SSIDP
				if pName == "" {
					pName = s.NotSetTag
				}
				bName := st.SSIDB
				if bName == "" {
					bName = s.NotSetTag
				}

				a.routeRow(c, p, "route_p", s.PrimarySlotLabel, pName, s.ConnectedTag, pActive,
					p.accent, p.accentSoft, p.accentText, p.accentSoft,
					permOK && st.SSIDP == "", func() {
						a.openSlotEditor(store.SlotPrimary)
					})

				a.routeRow(c, p, "route_b", s.BackupSlotLabel, bName, s.ConnectedTag, bActive,
					p.warning, p.warningSoft, p.warningText, p.warningSoft,
					permOK && st.SSIDB == "", func() {
						a.openSlotEditor(store.SlotBackup)
					})
			})

		// Row 3: Auto-Switch Guard Master Switch
		running := st.Running
		ui.Row(c).Padding(12, spaceCard).Gap(10).AlignItems(ui.Center).
			BorderWidth(1, 0, 0, 0).BorderColor(p.border).
			Children(func() {
				ui.Column(c).Grow(1).Shrink(1).MinWidth(0).Gap(3).Children(func() {
					ui.Text(c, s.AutoSwitchTitle).FontSize(fontBody).FontWeight(600).TextColor(p.text)
					ui.Text(c, subText).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.muted)
				})
				sw := ui.Switch(c.Key("guard_switch"), &running).Label(s.AutoSwitchTitle)
				if !permOK || !st.Configured {
					sw.Disabled(true)
				}
				if sw.Changed() && permOK && st.Configured {
					go a.monitor.ToggleRunning()
				}
			})

		// Optional Row 4: Manual override resume strip
		if !st.Running && permOK && st.HasStopReason && (st.StopReason == policy.StopManualOverrideBackup || st.StopReason == policy.StopManualOverrideUnmanaged) {
			ui.Row(c).Padding(10, spaceCard).Gap(8).AlignItems(ui.Center).
				Background(p.warningSoft).BorderWidth(1, 0, 0, 0).BorderColor(p.border).
				Children(func() {
					ui.Text(c, s.SubPausedManual).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.warningText).Grow(1).Shrink(1).MinWidth(0)
					if ui.Button(c.Key("resume_now"), s.BtnResumeNow).Clicked() {
						go a.monitor.Start()
					}
				})
		}

		// Optional Row 5: Friendly Error Strip
		if permOK && st.LastError != "" {
			errText := localizeMonitorError(st.LastError, s)
			ui.Row(c).Padding(10, spaceCard).AlignItems(ui.Center).
				Background(p.dangerSoft).BorderWidth(1, 0, 0, 0).BorderColor(p.border).
				Children(func() {
					ui.Text(c, errText).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.dangerText).Grow(1).Shrink(1).MinWidth(0)
				})
		}
	})

	// Managed Networks Section
	ui.Column(c).Gap(8).Children(func() {
		ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
			ui.Text(c, s.ManagedNetworksTitle).FontSize(fontSub).FontWeight(600).TextColor(p.muted).Grow(1).Shrink(1).MinWidth(0)
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
	ui.Column(c).Padding(12, spaceCard).Gap(8).Radius(radiusCard).Background(p.warningSoft).Children(func() {
		ui.Text(c, s.SubNeedPermission).FontSize(fontBody).FontWeight(600).TextColor(p.warningText).LineHeight(lineHeightTight)
		ui.Text(c, s.PermNecessityDesc).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.warningText)
		if st.Permission == policy.PermissionDenied {
			ui.Text(c, s.PermMacSettingsHint).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.warningText)
		}
		ui.Row(c).Gap(8).Wrap().Children(func() {
			if ui.PrimaryButton(c.Key("perm_grant"), s.BtnGrantPerm).Clicked() {
				a.triggerPermissionRequest()
			}
			if ui.Button(c.Key("perm_recheck"), s.BtnRecheckPerm).Clicked() {
				go a.monitor.RefreshStatus(context.Background())
			}
		})
	})
}

// formatDuration formats seconds into natural, easy-to-read durations without technical abbreviations in Chinese.
func formatDuration(sec int, lang i18n.Lang) string {
	if sec < 0 {
		sec = 0
	}
	if lang == i18n.LangZH {
		switch {
		case sec < 60:
			return fmt.Sprintf("%d 秒", sec)
		case sec == 3600:
			return "1 小时"
		case sec%60 == 0:
			return fmt.Sprintf("%d 分钟", sec/60)
		default:
			return fmt.Sprintf("%d 分 %d 秒", sec/60, sec%60)
		}
	}
	switch {
	case sec < 60:
		return fmt.Sprintf("%ds", sec)
	case sec == 3600:
		return "1h"
	case sec%60 == 0:
		return fmt.Sprintf("%dm", sec/60)
	default:
		return fmt.Sprintf("%dm %ds", sec/60, sec%60)
	}
}

func formatCountdown(fmtStr string, nextAt time.Time, fallbackSec int, lang i18n.Lang) string {
	rem := fallbackSec
	if !nextAt.IsZero() {
		d := int(time.Until(nextAt).Round(time.Second).Seconds())
		if d < 0 {
			d = 0
		}
		rem = d
	}
	return fmt.Sprintf(fmtStr, formatDuration(rem, lang))
}

func localizeMonitorError(raw string, s i18n.Strings) string {
	lower := strings.ToLower(raw)
	if strings.Contains(lower, "location permission") {
		return s.ErrPermissionRequired
	}
	if strings.Contains(lower, "no wi-fi interface") {
		return s.ErrNoWifiInterface
	}
	if strings.HasPrefix(raw, "Network ") && strings.HasSuffix(raw, " not found") {
		name := strings.TrimSuffix(strings.TrimPrefix(raw, "Network "), " not found")
		if name != "" {
			return fmt.Sprintf(s.ErrNetworkNotFoundFmt, name)
		}
	}
	if strings.HasPrefix(raw, "macOS did not switch Wi-Fi to ") {
		rest := strings.TrimPrefix(raw, "macOS did not switch Wi-Fi to ")
		if idx := strings.Index(rest, " (current:"); idx > 0 {
			return fmt.Sprintf(s.ErrConnectStayFmt, rest[:idx])
		}
	}
	if strings.Contains(lower, "stayed on") {
		return s.ErrConnectStayPrefix
	}
	return raw
}

func (a *App) noticeBanner(c *ui.Context, p palette, key, msg, btnLabel string, onClick func()) {
	ui.Row(c).Padding(10, spaceCard).Gap(8).Radius(radiusCard).Background(p.accentSoft).AlignItems(ui.Center).Wrap().Children(func() {
		ui.Text(c, msg).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.accentText).Grow(1).Shrink(1).MinWidth(0)
		if btnLabel != "" && onClick != nil {
			if ui.PrimaryButton(c.Key(key), btnLabel).Clicked() {
				onClick()
			}
		}
	})
}

func (a *App) infoBanner(c *ui.Context, p palette, msg string) {
	ui.Row(c).Padding(10, spaceCard).Gap(8).Radius(radiusCard).Background(p.accentSoft).AlignItems(ui.Center).Children(func() {
		ui.Text(c, msg).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.accentText).Grow(1).Shrink(1).MinWidth(0)
	})
}

func (a *App) routeRow(c *ui.Context, p palette, key, label, ssid, connectedLabel string, active bool, barColor, tagBg, tagFg, activeBg ui.Color, clickable bool, onClick func()) {
	bg := ui.Transparent
	if active {
		bg = activeBg
	}
	row := ui.Row(c.Key(key)).Padding(7, 8).Gap(8).Radius(radiusControl).Background(bg).AlignItems(ui.Center)
	if clickable && onClick != nil {
		row.Focusable().Cursor(ui.CursorPointer)
	}
	row.Children(func() {
		ui.Box(c).Size(3, 18).Radius(2).Background(barColor).Shrink(0)
		ui.Box(c).Padding(2, 7).Radius(6).Background(tagBg).Shrink(0).Children(func() {
			ui.Text(c, label).FontSize(fontCaption).FontWeight(600).TextColor(tagFg).SingleLine()
		})
		nameColor := p.text
		if !active {
			nameColor = p.muted
		}
		ui.Text(c, ssid).FontSize(fontBody).FontWeight(600).TextColor(nameColor).SingleLine().Grow(1).Shrink(1).MinWidth(0)
		if active {
			ui.Row(c).Gap(5).AlignItems(ui.Center).Shrink(0).Children(func() {
				ui.Box(c).Size(6, 6).Radius(3).Background(barColor)
				ui.Text(c, connectedLabel).FontSize(fontCaption).FontWeight(600).TextColor(tagFg).SingleLine()
			})
		}
	})
	if clickable && onClick != nil && row.Clicked() {
		onClick()
	}
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

func signalIcon(rssi int) *ui.SVG {
	switch {
	case rssi >= -60:
		return svgSignalStrong
	case rssi >= -75:
		return svgSignalMedium
	default:
		return svgSignalWeak
	}
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
	sel.Trigger.Padding(8, 10).Radius(radiusControl).Background(p.surface).Border(1, triggerBorder).
		AlignItems(ui.Center).Cursor(ui.CursorPointer).
		Children(func() {
			labelColor := p.muted
			if selected != "" {
				labelColor = p.text
			}
			ui.Text(c, triggerLabel).FontSize(fontBody).TextColor(labelColor).SingleLine().Grow(1).Shrink(1).MinWidth(0)
			chevron := svgChevronDown
			if sel.Open() {
				chevron = svgChevronUp
			}
			ui.Icon(c, chevron).Size(16, 16).TextColor(p.muted)
		})

	sel.Popup(func(panel ui.Element) {
		w := sel.Trigger.Bounds().W
		if w < 260 {
			w = 324
		}
		panel.Margin(6, 0, 6, 0).Padding(4).Radius(radiusPopup).Width(w).MaxHeight(210).
			Background(p.surface).Border(1, p.border).Clip().
			Shadow(0, 6, 16, 0, ui.RGBA(15, 23, 42, 0.14))

		ui.Scroll(c).Shrink(1).Children(func() {
			// First item: Use Current Network
			curItem := sel.Item(pickerCurrentToken).Padding(8, 10).Radius(radiusPopupItem).Cursor(ui.CursorPointer)
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
				ui.Text(c, curText).FontSize(fontBody).FontWeight(600).TextColor(fg).SingleLine()
			})

			if len(st.Nearby) == 0 {
				ui.Box(c).Padding(8, 10).Children(func() {
					ui.Text(c, s.PickerEmptyList).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.muted)
				})
				return
			}

			for _, net := range st.Nearby {
				n := net
				item := sel.Item(n.SSID).Padding(8, 10).Radius(radiusPopupItem).Cursor(ui.CursorPointer)
				if item.Highlighted() {
					item.Background(p.accentSoft)
				} else if n.SSID == selected {
					item.Background(p.surfaceMuted)
				}
				item.Children(func() {
					ui.Row(c).Gap(8).AlignItems(ui.Center).Children(func() {
						ui.Text(c, n.SSID).FontSize(fontBody).TextColor(p.text).SingleLine().Grow(1).Shrink(1).MinWidth(0)
						if n.Secured {
							ui.Icon(c, svgLock).Size(12, 12).TextColor(p.muted).Shrink(0)
						}
						ui.Icon(c, signalIcon(n.RSSI)).Size(14, 14).TextColor(p.muted).Shrink(0)
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

	card := ui.Column(c).Radius(radiusCard).Background(p.surface).Border(1, border).Clip()
	if !permOK {
		card.Opacity(0.7)
	}
	card.Children(func() {
		header := ui.Row(c).Padding(12, spaceCard).Gap(10).AlignItems(ui.Center)
		if permOK {
			header.Focusable().Cursor(ui.CursorPointer)
		}
		header.Children(func() {
			ui.Box(c).Size(30, 30).Radius(radiusControl).Background(badgeBg).Center().Shrink(0).Children(func() {
				ui.Text(c, badge).FontSize(fontSub).Bold().TextColor(badgeFg)
			})
			ui.Column(c).Grow(1).Shrink(1).MinWidth(0).Gap(2).Children(func() {
				ui.Row(c).Gap(6).AlignItems(ui.Center).Wrap().Children(func() {
					ui.Text(c, displaySSID).FontSize(fontBody).FontWeight(600).TextColor(p.text).SingleLine()
					if connected {
						ui.Box(c).Padding(2, 6).Radius(6).Background(p.successSoft).Shrink(0).Children(func() {
							ui.Text(c, s.ConnectedTag).FontSize(fontCaption).FontWeight(600).TextColor(p.successText).SingleLine()
						})
					}
				})
				ui.Text(c, subtitle).FontSize(fontSub).LineHeight(lineHeightTight).TextColor(p.muted)
			})
			if permOK && ssid != "" && !connected {
				if ui.Button(c.Key("switch:"+slot), s.BtnSwitchNow).Clicked() {
					targetSlot := slot
					go func() {
						if err := a.monitor.ConnectNow(context.Background(), targetSlot); err != nil {
							a.setToast(fmt.Sprintf(s.SwitchFailedFmt, localizeMonitorError(err.Error(), s)))
							return
						}
						a.setToast(s.SwitchedNotice)
					}()
				}
			}
			ui.Box(c).Size(28, 28).Radius(radiusControl).Background(p.surfaceMuted).Center().Shrink(0).Children(func() {
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
			ui.Column(c).Padding(12, spaceCard).Gap(8).Background(p.surface).
				BorderWidth(1, 0, 0, 0).BorderColor(p.border).
				Children(func() {
					a.renderNetworkPicker(c, p, s, st, "net_picker:"+slot, &a.draftSSID)

					ui.TextInput(c.Key("ssid:"+slot), &a.draftSSID).Placeholder(s.SSIDPlaceholder)

					ui.Row(c).Gap(6).AlignItems(ui.Center).Children(func() {
						pwdIn := ui.TextInput(c.Key("pwd:"+slot), &a.draftPwd).Grow(1).Shrink(1).MinWidth(0).Placeholder(s.PwdPlaceholder)
						if !showPwd {
							pwdIn.Password()
						}
						eyeIcon := svgEye
						eyeLabel := s.ShowPasswordLabel
						if showPwd {
							eyeIcon = svgEyeOff
							eyeLabel = s.HidePasswordLabel
						}
						eyeBtn := ui.ButtonBase(c.Key("eye:"+slot)).Size(32, 32).Radius(radiusControl).
							Background(p.surfaceMuted).Center().Shrink(0).Label(eyeLabel).
							Children(func() {
								ui.Icon(c, eyeIcon).Size(15, 15).TextColor(p.muted)
							})
						if eyeBtn.Clicked() {
							a.mu.Lock()
							a.showPwd = !a.showPwd
							a.mu.Unlock()
						}
					})

					if editErr != "" {
						ui.Text(c, editErr).FontSize(fontSub).LineHeight(lineHeightBody).TextColor(p.dangerText)
					}

					ui.Row(c).Gap(8).Justify(ui.End).Wrap().Children(func() {
						if ui.Button(c.Key("cancel:"+slot), s.BtnCancel).Clicked() {
							a.mu.Lock()
							a.editingSlot = ""
							a.editError = ""
							a.mu.Unlock()
						}
						if ui.PrimaryButton(c.Key("save:"+slot), s.BtnSave).Clicked() {
							wasConfigured := st.Configured
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
								return
							}

							nextState := a.monitor.State()
							if slot == store.SlotPrimary && nextState.SSIDB == "" {
								a.openSlotEditor(store.SlotBackup)
								a.setToast(s.SavedNotice)
								return
							}

							a.mu.Lock()
							a.editingSlot = ""
							a.editError = ""
							a.mu.Unlock()

							if !wasConfigured && nextState.Configured && permOK && !nextState.Running {
								go a.monitor.Start()
								a.setToast(s.SavedAndStartedNotice)
								return
							}
							a.setToast(s.SavedNotice)
						}
					})
				})
		}
	})
}

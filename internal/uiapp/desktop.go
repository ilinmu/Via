//go:build !android && !ios

package uiapp

import (
	"context"
	"log"
	"runtime"
	"time"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"
)

// Run launches Via as a desktop tray / menu bar application.
func Run() {
	app := newApp()
	app.launchAtLogin = mygo.App.OpenAtLogin()

	mygo.App.SetName("Via")
	mygo.App.SetActivationPolicy(mygo.ActivationPolicyAccessory)
	mygo.App.OnWindowAllClosed(func() {})
	mygo.App.WhenReady(func() {
		app.readyDesktop()
	})
	if err := mygo.App.Run(); err != nil {
		log.Fatal(err)
	}
}

func (a *App) viewDesktop(c *ui.Context) {
	if c.Shortcut(0, ui.KeyEscape) {
		a.mu.Lock()
		w := a.win
		a.mu.Unlock()
		if w != nil {
			w.Close()
			return
		}
	}
	c.OnShortcut(ui.Cmd, ui.KeyQ, func() {
		a.monitor.Close()
		mygo.App.Quit()
	})
	a.renderCommonRoot(c, false)
}

func (a *App) toggleFlyout() {
	a.mu.Lock()
	w := a.win
	a.mu.Unlock()
	if w != nil {
		w.Close()
		return
	}

	go a.monitor.RefreshStatus(context.Background())

	panel := mygo.NewFlyout(mygo.FlyoutOptions{
		Tray:       a.tray,
		Placement:  mygo.PlacementBottom,
		Gap:        6,
		Width:      380,
		Height:     380,
		FitContent: true,
		MinWidth:   380,
		MaxWidth:   380,
		MinHeight:  180,
		MaxHeight:  720,
		Focusable:  true,
		Shadow:     true,
		Popover:    runtime.GOOS == "darwin",
		Content:    ui.View(a.viewDesktop),
	})
	tickCtx, cancelTick := context.WithCancel(context.Background())
	panel.OnClosed(func() {
		cancelTick()
		a.mu.Lock()
		a.win = nil
		a.mu.Unlock()
	})
	go func() {
		ticker := time.NewTicker(1 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-tickCtx.Done():
				return
			case <-ticker.C:
				a.mu.Lock()
				shouldTick := a.state.Running && a.activeTab == tabDashboard
				a.mu.Unlock()
				if shouldTick {
					a.invalidate()
				}
			}
		}
	}()
	a.mu.Lock()
	a.win = panel
	a.mu.Unlock()
}

func (a *App) readyDesktop() {
	go a.monitor.Init(context.Background())

	tr, err := mygo.NewTray(mygo.TrayOptions{
		ID:             "via-main-tray",
		Icon:           a.currentTrayIcon(a.state.Running, a.state.Role, false),
		IconIsTemplate: a.state.Running,
		ToolTip:        "Via",
	})
	if err != nil {
		log.Fatal("tray: ", err)
	}
	a.mu.Lock()
	a.tray = tr
	a.mu.Unlock()

	a.syncTray()
	tr.OnAppearanceChange(a.syncTray)

	s := a.strings()
	menu := mygo.NewMenu([]*mygo.MenuItem{
		{Label: s.MenuOpenPanel, Click: func(*mygo.MenuItem, *mygo.Window) { a.toggleFlyout() }},
		{Label: s.MenuTogglePause, Click: func(*mygo.MenuItem, *mygo.Window) { go a.monitor.ToggleRunning() }},
		mygo.Separator(),
		{Label: s.MenuQuit, Role: mygo.RoleQuit},
	})

	if runtime.GOOS == "linux" {
		tr.SetMenu(menu)
		tr.OnClick(a.toggleFlyout)
	} else {
		tr.OnClick(a.toggleFlyout)
		tr.OnRightClick(func() {
			a.mu.Lock()
			w := a.win
			a.mu.Unlock()
			if w != nil {
				w.Close()
			}
			cur := a.strings()
			m := mygo.NewMenu([]*mygo.MenuItem{
				{Label: cur.MenuOpenPanel, Click: func(*mygo.MenuItem, *mygo.Window) { a.toggleFlyout() }},
				{Label: cur.MenuTogglePause, Click: func(*mygo.MenuItem, *mygo.Window) { go a.monitor.ToggleRunning() }},
				mygo.Separator(),
				{Label: cur.MenuQuit, Role: mygo.RoleQuit},
			})
			tr.SetMenu(m)
			defer tr.SetMenu(nil)
			tr.PopUpMenu()
		})
	}

	mygo.App.OnWillQuit(func(*mygo.QuitEvent) {
		a.monitor.Close()
		tr.Destroy()
	})
}

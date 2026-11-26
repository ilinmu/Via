//go:build android || ios

package uiapp

import (
	"context"
	"log"
	"time"

	"github.com/egoist/mygo"
	"github.com/egoist/mygo/ui"
)

// Run launches Via as a full-screen mobile UI application on Android and iOS.
func Run() {
	app := newApp()
	mygo.KeepState(app)
	mygo.App.SetName("Via")
	mygo.App.WhenReady(func() {
		go app.monitor.Init(context.Background())
		w := mygo.NewWindow(mygo.WindowOptions{
			Title:   "Via",
			Content: ui.View(app.viewMobile),
		})
		tickCtx, cancelTick := context.WithCancel(context.Background())
		w.OnClosed(cancelTick)
		go func() {
			ticker := time.NewTicker(1 * time.Second)
			defer ticker.Stop()
			for {
				select {
				case <-tickCtx.Done():
					return
				case <-ticker.C:
					app.mu.Lock()
					shouldTick := app.state.Running && app.activeTab == tabDashboard
					app.mu.Unlock()
					if shouldTick {
						app.invalidate()
					}
				}
			}
		}()
		app.mu.Lock()
		app.win = w
		app.mu.Unlock()
	})
	if err := mygo.App.Run(); err != nil {
		log.Fatal(err)
	}
}

func (a *App) viewMobile(c *ui.Context) {
	a.renderCommonRoot(c, true)
}

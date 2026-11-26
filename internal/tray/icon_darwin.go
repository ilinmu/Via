//go:build darwin

package tray

import (
	"via/internal/nativewifi"
	"via/internal/policy"
)

func renderNative(ctrl nativewifi.Controller, running bool, role policy.Role, darkBar bool) []byte {
	if ctrl == nil {
		return nil
	}
	data, err := ctrl.RenderTrayIcon(Badge(running, role), !running, darkBar)
	if err != nil || len(data) == 0 {
		return nil
	}
	return data
}

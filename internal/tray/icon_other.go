//go:build (!darwin && !windows && !linux) || android

package tray

import (
	"via/internal/nativewifi"
	"via/internal/policy"
)

func renderNative(_ nativewifi.Controller, _ bool, _ policy.Role, _ bool) []byte {
	return nil
}

// Package wifi provides cross-platform Wi-Fi hardware adapters and Via's
// unified monitoring & auto-switching coordinator.
package wifi

import (
	"context"
	"io"

	"via/internal/policy"
)

// Network describes an available Wi-Fi network discovered during a scan.
type Network struct {
	SSID    string
	RSSI    int
	Secured bool
}

// Adapter abstracts OS-specific Wi-Fi querying, scanning, connection, and permissions.
type Adapter interface {
	Name() string
	CurrentSSID(ctx context.Context) (string, error)
	Permission(ctx context.Context) policy.Permission
	RequestPermission() error
	OpenPermissionSettings() error
	Scan(ctx context.Context) ([]Network, error)
	Connect(ctx context.Context, ssid, password string) error
	SubscribeChanges(onChange func(ssid string)) (io.Closer, error)
	SubscribePermissionChanges(onChange func(perm policy.Permission)) (io.Closer, error)
	IsAdvisory() bool
	ApplyAdvisory(ssidP, pwdP, ssidB, pwdB, preferSSID string) error
	UpdateNotification(running bool, title, subtitle string)
}

type nopCloser struct{}

func (nopCloser) Close() error { return nil }

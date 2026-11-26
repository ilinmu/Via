//go:build darwin

package wifi

import (
	"context"
	"errors"
	"io"

	"via/internal/nativewifi"
	"via/internal/policy"
)

type darwinAdapter struct {
	ctrl nativewifi.Controller
}

// NewAdapter creates the macOS CoreWLAN + CoreLocation Wi-Fi adapter.
func NewAdapter() (Adapter, error) {
	ctrl, err := nativewifi.NewController()
	if err != nil {
		return nil, err
	}
	return &darwinAdapter{ctrl: ctrl}, nil
}

// NativeController returns the underlying nativewifi.Controller for tray rendering.
func (a *darwinAdapter) NativeController() nativewifi.Controller {
	return a.ctrl
}

func (a *darwinAdapter) Name() string { return "macOS CoreWLAN" }

func (a *darwinAdapter) CurrentSSID(_ context.Context) (string, error) {
	return a.ctrl.CurrentSSID()
}

func mapLocationPermission(st string) policy.Permission {
	switch st {
	case "authorizedAlways", "authorizedWhenInUse":
		return policy.PermissionAuthorized
	case "denied", "restricted":
		return policy.PermissionDenied
	default:
		return policy.PermissionUnknown
	}
}

func (a *darwinAdapter) Permission(_ context.Context) policy.Permission {
	st, err := a.ctrl.LocationStatus()
	if err != nil {
		return policy.PermissionUnknown
	}
	return mapLocationPermission(st)
}

func (a *darwinAdapter) RequestPermission() error      { return a.ctrl.RequestLocation() }
func (a *darwinAdapter) OpenPermissionSettings() error { return a.ctrl.OpenLocationSettings() }
func (a *darwinAdapter) IsAdvisory() bool              { return false }
func (a *darwinAdapter) ApplyAdvisory(_, _, _, _, _ string) error {
	return errors.ErrUnsupported
}
func (a *darwinAdapter) UpdateNotification(_ bool, _, _ string) {}

func (a *darwinAdapter) Scan(_ context.Context) ([]Network, error) {
	nets, err := a.ctrl.Scan()
	if err != nil {
		return nil, err
	}
	out := make([]Network, 0, len(nets))
	for _, n := range nets {
		out = append(out, Network{
			SSID:    n.SSID,
			RSSI:    n.RSSI,
			Secured: n.Secured,
		})
	}
	return out, nil
}

func (a *darwinAdapter) Connect(_ context.Context, ssid, password string) error {
	return a.ctrl.Connect(ssid, password)
}

func (a *darwinAdapter) SubscribeChanges(onChange func(ssid string)) (io.Closer, error) {
	return a.ctrl.WatchSSIDChanges(onChange), nil
}

func (a *darwinAdapter) SubscribePermissionChanges(onChange func(perm policy.Permission)) (io.Closer, error) {
	return a.ctrl.WatchPermissionChanges(func(st string) {
		onChange(mapLocationPermission(st))
	}), nil
}

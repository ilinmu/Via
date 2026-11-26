//go:build android

package wifi

import (
	"context"
	"io"

	"via/internal/nativewifi"
	"via/internal/policy"
)

type androidAdapter struct {
	ctrl nativewifi.Controller
}

// NewAdapter creates the Android WifiManager + WifiNetworkSuggestion adapter.
func NewAdapter() (Adapter, error) {
	ctrl, err := nativewifi.NewController()
	if err != nil {
		return nil, err
	}
	return &androidAdapter{ctrl: ctrl}, nil
}

func (a *androidAdapter) Name() string { return "Android WifiManager" }

func (a *androidAdapter) CurrentSSID(_ context.Context) (string, error) {
	return a.ctrl.CurrentSSID()
}

func (a *androidAdapter) Permission(_ context.Context) policy.Permission {
	st, err := a.ctrl.LocationStatus()
	if err != nil {
		return policy.PermissionUnknown
	}
	switch st {
	case "authorizedAlways", "authorizedWhenInUse":
		return policy.PermissionAuthorized
	case "denied", "restricted":
		return policy.PermissionDenied
	default:
		return policy.PermissionUnknown
	}
}

func (a *androidAdapter) RequestPermission() error      { return a.ctrl.RequestLocation() }
func (a *androidAdapter) OpenPermissionSettings() error { return a.ctrl.OpenLocationSettings() }

func (a *androidAdapter) Scan(_ context.Context) ([]Network, error) {
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

func (a *androidAdapter) Connect(_ context.Context, ssid, password string) error {
	return a.ctrl.Connect(ssid, password)
}

func (a *androidAdapter) SubscribeChanges(onChange func(ssid string)) (io.Closer, error) {
	return a.ctrl.WatchSSIDChanges(onChange), nil
}

func (a *androidAdapter) SubscribePermissionChanges(onChange func(perm policy.Permission)) (io.Closer, error) {
	return a.ctrl.WatchPermissionChanges(func(st string) {
		if st == "authorizedAlways" || st == "authorizedWhenInUse" {
			onChange(policy.PermissionAuthorized)
		} else if st == "denied" || st == "restricted" {
			onChange(policy.PermissionDenied)
		} else {
			onChange(policy.PermissionUnknown)
		}
	}), nil
}

func (a *androidAdapter) IsAdvisory() bool { return true }

func (a *androidAdapter) ApplyAdvisory(ssidP, pwdP, ssidB, pwdB, preferSSID string) error {
	return a.ctrl.ApplySuggestions(ssidP, pwdP, ssidB, pwdB, preferSSID)
}

func (a *androidAdapter) UpdateNotification(running bool, title, subtitle string) {
	_ = a.ctrl.UpdateGuardNotification(running, title, subtitle)
}

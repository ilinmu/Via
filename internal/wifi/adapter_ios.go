//go:build ios

package wifi

import (
	"context"
	"errors"
	"io"

	"via/internal/policy"
)

type iosAdapter struct{}

// NewAdapter returns the Option A iOS placeholder adapter. Background automatic
// Wi-Fi switching is restricted on iOS without NEHotspotConfiguration / MDM.
func NewAdapter() (Adapter, error) {
	return &iosAdapter{}, nil
}

func (a *iosAdapter) Name() string                              { return "iOS Placeholder (Option A)" }
func (a *iosAdapter) CurrentSSID(_ context.Context) (string, error) { return "", nil }
func (a *iosAdapter) Permission(_ context.Context) policy.Permission {
	return policy.PermissionUnknown
}
func (a *iosAdapter) RequestPermission() error                  { return errors.ErrUnsupported }
func (a *iosAdapter) OpenPermissionSettings() error             { return errors.ErrUnsupported }
func (a *iosAdapter) Scan(_ context.Context) ([]Network, error) { return nil, errors.ErrUnsupported }
func (a *iosAdapter) Connect(_ context.Context, _, _ string) error {
	return errors.ErrUnsupported
}
func (a *iosAdapter) SubscribeChanges(_ func(string)) (io.Closer, error) {
	return nopCloser{}, errors.ErrUnsupported
}
func (a *iosAdapter) SubscribePermissionChanges(_ func(policy.Permission)) (io.Closer, error) {
	return nopCloser{}, nil
}
func (a *iosAdapter) IsAdvisory() bool                             { return false }
func (a *iosAdapter) ApplyAdvisory(_, _, _, _, _ string) error     { return errors.ErrUnsupported }
func (a *iosAdapter) UpdateNotification(_ bool, _, _ string)       {}

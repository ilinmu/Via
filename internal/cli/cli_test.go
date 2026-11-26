package cli

import (
	"bytes"
	"context"
	"io"
	"strings"
	"testing"

	"via/internal/policy"
	"via/internal/store"
	"via/internal/wifi"
)

type stubAdapter struct {
	ssid string
	perm policy.Permission
	nets []wifi.Network
}

func (s *stubAdapter) Name() string                              { return "stub-adapter" }
func (s *stubAdapter) CurrentSSID(_ context.Context) (string, error) { return s.ssid, nil }
func (s *stubAdapter) Permission(_ context.Context) policy.Permission {
	return s.perm
}
func (s *stubAdapter) RequestPermission() error               { return nil }
func (s *stubAdapter) OpenPermissionSettings() error          { return nil }
func (s *stubAdapter) Scan(_ context.Context) ([]wifi.Network, error) { return s.nets, nil }
func (s *stubAdapter) Connect(_ context.Context, _, _ string) error   { return nil }
func (s *stubAdapter) SubscribeChanges(_ func(string)) (io.Closer, error) {
	return nil, nil
}
func (s *stubAdapter) SubscribePermissionChanges(_ func(policy.Permission)) (io.Closer, error) {
	return nil, nil
}
func (s *stubAdapter) IsAdvisory() bool                         { return false }
func (s *stubAdapter) ApplyAdvisory(_, _, _, _, _ string) error { return nil }
func (s *stubAdapter) UpdateNotification(_ bool, _, _ string)   {}

func TestIsSubcommand(t *testing.T) {
	for _, cmd := range []string{"doctor", "status", "monitor", "version", "--help", "-h"} {
		if !IsSubcommand(cmd) {
			t.Fatalf("expected IsSubcommand(%q) == true", cmd)
		}
	}
	if IsSubcommand("foo") {
		t.Fatal("expected IsSubcommand(\"foo\") == false")
	}
}

func TestDoctorDoesNotLeakPasswordsAndReportsConfig(t *testing.T) {
	dir := t.TempDir()
	sec := store.NewMemSecretStore()
	s := store.DefaultSettings()
	if err := store.SaveSlot(dir, sec, &s, store.SlotPrimary, "Office_5G", "super-secret-P"); err != nil {
		t.Fatal(err)
	}
	if err := store.SaveSlot(dir, sec, &s, store.SlotBackup, "Mobile_AP", "super-secret-B"); err != nil {
		t.Fatal(err)
	}

	var out bytes.Buffer
	var errOut bytes.Buffer
	code := RunWithDeps([]string{"doctor", "--config-dir", dir}, Deps{
		NewAdapter: func() (wifi.Adapter, error) {
			return &stubAdapter{
				ssid: "Office_5G",
				perm: policy.PermissionAuthorized,
				nets: []wifi.Network{{SSID: "Office_5G", RSSI: -45}, {SSID: "Mobile_AP", RSSI: -62}},
			}, nil
		},
		NewSecrets: func() store.SecretStore { return sec },
		ConfigDir:  func() (string, error) { return dir, nil },
		Stdout:     &out,
		Stderr:     &errOut,
	})
	if code != 0 {
		t.Fatalf("expected exit 0, got %d (%s)", code, errOut.String())
	}
	txt := out.String()
	if strings.Contains(txt, "super-secret-P") || strings.Contains(txt, "super-secret-B") {
		t.Fatalf("password leaked in doctor output: %s", txt)
	}
	if !strings.Contains(txt, "Office_5G") || !strings.Contains(txt, "primaryVisible=true, backupVisible=true") {
		t.Fatalf("missing diagnostic details in output:\n%s", txt)
	}
}

func TestMonitorRejectsPasswordFlags(t *testing.T) {
	var out, errOut bytes.Buffer
	code := RunWithDeps([]string{"monitor", "--password", "leak"}, Deps{
		Stdout: &out,
		Stderr: &errOut,
	})
	if code != 2 {
		t.Fatalf("expected exit 2, got %d", code)
	}
}

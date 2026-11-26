// Package store manages atomic persistent settings JSON and secure credentials.
package store

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
)

const (
	DefaultCheckIntervalSec = 60
	MinCheckIntervalSec     = 5
	MaxCheckIntervalSec     = 3600

	SlotPrimary = "P"
	SlotBackup  = "B"
)

var (
	ErrEmptySSID      = errors.New("network SSID cannot be empty")
	ErrDuplicateSSID  = errors.New("primary and backup networks cannot be the same")
	ErrInvalidSlot    = errors.New("invalid network slot")
)

// Settings stores non-sensitive user preferences for Via.
// Passwords are stored separately in SecretStore, never in JSON.
type Settings struct {
	SSIDP            string `json:"ssid_p"`
	SSIDB            string `json:"ssid_b"`
	CheckIntervalSec int    `json:"check_interval_sec"`
	IsRunning        bool   `json:"is_running"`
	Language         string `json:"language,omitempty"` // "", "zh", "en"
	OnboardingDone   bool   `json:"onboarding_done"`
	BootRestore      bool   `json:"boot_restore"`
}

// DefaultSettings returns initial default preferences.
func DefaultSettings() Settings {
	return Settings{
		CheckIntervalSec: DefaultCheckIntervalSec,
	}
}

// Normalize returns a copy of s with normalized interval and trimmed SSIDs.
func (s Settings) Normalize() Settings {
	s.SSIDP = strings.TrimSpace(s.SSIDP)
	s.SSIDB = strings.TrimSpace(s.SSIDB)
	s.CheckIntervalSec, _ = NormalizeInterval(s.CheckIntervalSec)
	return s
}

// IsConfigured reports whether both primary and backup SSIDs are non-empty.
func (s Settings) IsConfigured() bool {
	return strings.TrimSpace(s.SSIDP) != "" && strings.TrimSpace(s.SSIDB) != ""
}

// NormalizeInterval clamps sec to [MinCheckIntervalSec, MaxCheckIntervalSec].
// Returns (60, false) for non-positive unset values? Positive values below 5 clamp to 5 with adjusted=true;
// values <= 0 clamp to MinCheckIntervalSec when explicitly normalized unless 0 default is wanted.
func NormalizeInterval(sec int) (int, bool) {
	if sec == 0 {
		return DefaultCheckIntervalSec, false
	}
	if sec < MinCheckIntervalSec {
		return MinCheckIntervalSec, true
	}
	if sec > MaxCheckIntervalSec {
		return MaxCheckIntervalSec, true
	}
	return sec, false
}

// ValidateSlot checks whether a candidate SSID is valid and distinct from otherSSID.
func ValidateSlot(slot, ssid, otherSSID string) error {
	if slot != SlotPrimary && slot != SlotBackup {
		return ErrInvalidSlot
	}
	trimmed := strings.TrimSpace(ssid)
	if trimmed == "" {
		return ErrEmptySSID
	}
	if strings.TrimSpace(otherSSID) != "" && trimmed == strings.TrimSpace(otherSSID) {
		return ErrDuplicateSSID
	}
	return nil
}

// ConfigPath returns the JSON path inside dir.
func ConfigPath(dir string) string {
	return filepath.Join(dir, "config.json")
}

// LoadSettings reads settings from dir/config.json, returning defaults if absent.
func LoadSettings(dir string) (Settings, error) {
	path := ConfigPath(dir)
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return DefaultSettings(), nil
	}
	if err != nil {
		return DefaultSettings(), err
	}
	var s Settings
	if err := json.Unmarshal(data, &s); err != nil {
		return DefaultSettings(), err
	}
	return s.Normalize(), nil
}

// SaveSettings atomically writes settings to dir/config.json with mode 0600.
func SaveSettings(dir string, s Settings) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	s = s.Normalize()
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')

	tmp, err := os.CreateTemp(dir, ".config-*.json")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()
	cleanup := true
	defer func() {
		if cleanup {
			_ = os.Remove(tmpName)
		}
	}()

	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Rename(tmpName, ConfigPath(dir)); err != nil {
		return err
	}
	cleanup = false
	return nil
}

// SaveSlot validates and persists only the targeted network slot (P or B) and its
// password, leaving the opposite slot's password untouched.
func SaveSlot(dir string, secrets SecretStore, s *Settings, slot, ssid, password string) error {
	other := s.SSIDB
	if slot == SlotBackup {
		other = s.SSIDP
	}
	if err := ValidateSlot(slot, ssid, other); err != nil {
		return err
	}
	trimmed := strings.TrimSpace(ssid)
	key := SecretKeyForSlot(slot)
	if password == "" {
		if err := secrets.Delete(key); err != nil {
			return err
		}
	} else {
		if err := secrets.Set(key, password); err != nil {
			return err
		}
	}

	next := *s
	if slot == SlotPrimary {
		next.SSIDP = trimmed
	} else {
		next.SSIDB = trimmed
	}
	if err := SaveSettings(dir, next); err != nil {
		return err
	}
	*s = next
	return nil
}

// SwapSlots swaps Primary and Backup SSIDs and their stored passwords atomically.
func SwapSlots(dir string, secrets SecretStore, s *Settings) (pwdP, pwdB string, err error) {
	oldP, err := secrets.Get(SecretKeyPriority)
	if err != nil {
		return "", "", err
	}
	oldB, err := secrets.Get(SecretKeyBackup)
	if err != nil {
		return "", "", err
	}

	writeKey := func(key, val string) error {
		if val == "" {
			return secrets.Delete(key)
		}
		return secrets.Set(key, val)
	}
	if err := writeKey(SecretKeyPriority, oldB); err != nil {
		return "", "", err
	}
	if err := writeKey(SecretKeyBackup, oldP); err != nil {
		return "", "", err
	}

	next := *s
	next.SSIDP, next.SSIDB = s.SSIDB, s.SSIDP
	if err := SaveSettings(dir, next); err != nil {
		return "", "", err
	}
	*s = next
	return oldB, oldP, nil
}

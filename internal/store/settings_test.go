package store

import (
	"errors"
	"testing"

	"github.com/egoist/mygo"
)

func TestNormalizeInterval(t *testing.T) {
	cases := []struct {
		in       int
		want     int
		adjusted bool
	}{
		{0, DefaultCheckIntervalSec, false},
		{-10, MinCheckIntervalSec, true},
		{3, MinCheckIntervalSec, true},
		{5, 5, false},
		{60, 60, false},
		{3600, 3600, false},
		{9999, MaxCheckIntervalSec, true},
	}
	for _, tc := range cases {
		got, adj := NormalizeInterval(tc.in)
		if got != tc.want || adj != tc.adjusted {
			t.Fatalf("NormalizeInterval(%d) = (%d, %v), want (%d, %v)", tc.in, got, adj, tc.want, tc.adjusted)
		}
	}
}

func TestSaveAndLoadSettingsAtomic(t *testing.T) {
	dir := t.TempDir()
	s := Settings{
		SSIDP:            "  Studio_5G ",
		SSIDB:            "Studio_Backup",
		CheckIntervalSec: 45,
		IsRunning:        true,
		Language:         "zh",
		OnboardingDone:   true,
	}
	if err := SaveSettings(dir, s); err != nil {
		t.Fatalf("SaveSettings: %v", err)
	}
	loaded, err := LoadSettings(dir)
	if err != nil {
		t.Fatalf("LoadSettings: %v", err)
	}
	if loaded.SSIDP != "Studio_5G" || loaded.SSIDB != "Studio_Backup" || loaded.CheckIntervalSec != 45 || !loaded.IsRunning || loaded.Language != "zh" || !loaded.OnboardingDone {
		t.Fatalf("unexpected loaded settings: %+v", loaded)
	}
}

func TestSingleSlotSaveAndSwapIsolation(t *testing.T) {
	dir := t.TempDir()
	sec := NewMemSecretStore()
	s := DefaultSettings()

	if err := SaveSlot(dir, sec, &s, SlotPrimary, "Home_5G", "pass-p"); err != nil {
		t.Fatalf("save P: %v", err)
	}
	if err := SaveSlot(dir, sec, &s, SlotBackup, "Phone_AP", "pass-b"); err != nil {
		t.Fatalf("save B: %v", err)
	}
	// Editing P again must not touch B's password.
	if err := SaveSlot(dir, sec, &s, SlotPrimary, "Home_6G", "new-pass-p"); err != nil {
		t.Fatalf("update P: %v", err)
	}
	if got, _ := sec.Get(SecretKeyBackup); got != "pass-b" {
		t.Fatalf("backup secret modified unexpectedly: %q", got)
	}
	if err := SaveSlot(dir, sec, &s, SlotPrimary, "Phone_AP", "x"); !errors.Is(err, ErrDuplicateSSID) {
		t.Fatalf("expected ErrDuplicateSSID, got %v", err)
	}

	p, b, err := SwapSlots(dir, sec, &s)
	if err != nil {
		t.Fatalf("SwapSlots: %v", err)
	}
	if s.SSIDP != "Phone_AP" || s.SSIDB != "Home_6G" || p != "pass-b" || b != "new-pass-p" {
		t.Fatalf("unexpected swapped state: settings=%+v p=%q b=%q", s, p, b)
	}
}

type fakeRawBackend struct {
	data    map[string][]byte
	gets    int
	sets    int
	deletes int
}

func newFakeRawBackend() *fakeRawBackend {
	return &fakeRawBackend{data: make(map[string][]byte)}
}

func (f *fakeRawBackend) Get(key string) ([]byte, error) {
	f.gets++
	v, ok := f.data[key]
	if !ok {
		return nil, mygo.ErrSecretNotFound
	}
	return append([]byte(nil), v...), nil
}

func (f *fakeRawBackend) Set(key string, val []byte) error {
	f.sets++
	f.data[key] = append([]byte(nil), val...)
	return nil
}

func (f *fakeRawBackend) Delete(key string) error {
	f.deletes++
	delete(f.data, key)
	return nil
}

func TestVaultSecretStoreSingleItemCachingAndMigration(t *testing.T) {
	// 1. Writing both slots stores only a single consolidated vault entry.
	backend := newFakeRawBackend()
	storeA := newVaultSecretStore(backend)
	if err := storeA.Set(SecretKeyPriority, "pass-p"); err != nil {
		t.Fatalf("Set P: %v", err)
	}
	if err := storeA.Set(SecretKeyBackup, "pass-b"); err != nil {
		t.Fatalf("Set B: %v", err)
	}
	if len(backend.data) != 1 {
		t.Fatalf("expected 1 backend key, got %d (%v)", len(backend.data), backend.data)
	}
	if _, ok := backend.data[SecretKeyVault]; !ok {
		t.Fatalf("expected consolidated key %q in backend", SecretKeyVault)
	}
	if _, ok := backend.data[SecretKeyPriority]; ok {
		t.Fatalf("unexpected legacy key %q in backend", SecretKeyPriority)
	}
	if _, ok := backend.data[SecretKeyBackup]; ok {
		t.Fatalf("unexpected legacy key %q in backend", SecretKeyBackup)
	}

	// 2. Reopening against the same backend and reading both slots performs only 1 backend Get.
	backend.gets = 0
	storeB := newVaultSecretStore(backend)
	gotP, err := storeB.Get(SecretKeyPriority)
	if err != nil || gotP != "pass-p" {
		t.Fatalf("Get P = (%q, %v), want pass-p", gotP, err)
	}
	gotB, err := storeB.Get(SecretKeyBackup)
	if err != nil || gotB != "pass-b" {
		t.Fatalf("Get B = (%q, %v), want pass-b", gotB, err)
	}
	if backend.gets != 1 {
		t.Fatalf("expected 1 backend Get for session reads, got %d", backend.gets)
	}

	// 3. Deleting both slots removes the vault entry completely.
	if err := storeB.Delete(SecretKeyPriority); err != nil {
		t.Fatalf("Delete P: %v", err)
	}
	if err := storeB.Delete(SecretKeyBackup); err != nil {
		t.Fatalf("Delete B: %v", err)
	}
	if _, ok := backend.data[SecretKeyVault]; ok {
		t.Fatalf("expected vault key %q deleted when empty", SecretKeyVault)
	}

	// 4. Legacy per-slot keys migrate into SecretKeyVault and get cleaned up.
	legacyBackend := newFakeRawBackend()
	legacyBackend.data[SecretKeyPriority] = []byte("legacy-p")
	legacyBackend.data[SecretKeyBackup] = []byte("legacy-b")
	storeC := newVaultSecretStore(legacyBackend)
	migP, err := storeC.Get(SecretKeyPriority)
	if err != nil || migP != "legacy-p" {
		t.Fatalf("migrated P = (%q, %v), want legacy-p", migP, err)
	}
	migB, err := storeC.Get(SecretKeyBackup)
	if err != nil || migB != "legacy-b" {
		t.Fatalf("migrated B = (%q, %v), want legacy-b", migB, err)
	}
	if _, ok := legacyBackend.data[SecretKeyVault]; !ok {
		t.Fatalf("expected migrated vault key %q", SecretKeyVault)
	}
	if _, ok := legacyBackend.data[SecretKeyPriority]; ok {
		t.Fatalf("expected legacy key %q deleted after migration", SecretKeyPriority)
	}
	if _, ok := legacyBackend.data[SecretKeyBackup]; ok {
		t.Fatalf("expected legacy key %q deleted after migration", SecretKeyBackup)
	}
}

package store

import (
	"encoding/json"
	"errors"
	"sync"

	"github.com/egoist/mygo"
)

const (
	SecretsService    = "io.github.ilinmu.via"
	SecretKeyPriority = "password_p"
	SecretKeyBackup   = "password_b"
	SecretKeyVault    = "credentials"
)

// SecretKeyForSlot maps SlotPrimary / SlotBackup to its SecretStore key.
func SecretKeyForSlot(slot string) string {
	if slot == SlotBackup {
		return SecretKeyBackup
	}
	return SecretKeyPriority
}

// SecretStore abstracts platform credential storage (Keychain / Windows Credential Manager / Secret Service).
type SecretStore interface {
	Get(key string) (string, error)
	Set(key string, val string) error
	Delete(key string) error
}

type rawSecretBackend interface {
	Get(key string) ([]byte, error)
	Set(key string, val []byte) error
	Delete(key string) error
}

type mygoRawBackend struct {
	svc mygo.SecretsModule
}

func (b mygoRawBackend) Get(key string) ([]byte, error) {
	return b.svc.Get(key)
}

func (b mygoRawBackend) Set(key string, val []byte) error {
	return b.svc.Set(key, val)
}

func (b mygoRawBackend) Delete(key string) error {
	return b.svc.Delete(key)
}

// MyGoSecretStore delegates credential storage to a single consolidated mygo.Secrets
// entry with in-memory session caching so macOS Keychain prompts at most once.
type MyGoSecretStore struct {
	mu      sync.Mutex
	backend rawSecretBackend
	loaded  bool
	cache   map[string]string
}

// NewMyGoSecretStore returns a credential store scoped to Via's service identifier.
func NewMyGoSecretStore() *MyGoSecretStore {
	return newVaultSecretStore(mygoRawBackend{svc: mygo.Secrets.Service(SecretsService)})
}

func newVaultSecretStore(backend rawSecretBackend) *MyGoSecretStore {
	return &MyGoSecretStore{backend: backend}
}

func (m *MyGoSecretStore) loadLocked() error {
	if m.loaded {
		return nil
	}
	if m.backend == nil {
		m.cache = make(map[string]string)
		m.loaded = true
		return nil
	}

	b, err := m.backend.Get(SecretKeyVault)
	if err == nil {
		loaded := make(map[string]string)
		if len(b) > 0 {
			if uErr := json.Unmarshal(b, &loaded); uErr != nil || loaded == nil {
				loaded = make(map[string]string)
			}
		}
		m.cache = loaded
		m.loaded = true
		return nil
	}

	if !errors.Is(err, mygo.ErrSecretNotFound) {
		return err
	}

	// Vault entry does not exist yet: perform a best-effort one-time migration
	// from legacy per-slot Keychain items (password_p / password_b).
	migrated := make(map[string]string)
	var legacyFound []string
	for _, k := range []string{SecretKeyPriority, SecretKeyBackup} {
		lb, lErr := m.backend.Get(k)
		if lErr == nil && len(lb) > 0 {
			migrated[k] = string(lb)
			legacyFound = append(legacyFound, k)
		}
	}
	if len(legacyFound) > 0 {
		if persistErr := m.persistLocked(migrated); persistErr == nil {
			for _, k := range legacyFound {
				_ = m.backend.Delete(k)
			}
		}
	}
	m.cache = migrated
	m.loaded = true
	return nil
}

func (m *MyGoSecretStore) persistLocked(next map[string]string) error {
	if m.backend == nil {
		return nil
	}
	if len(next) == 0 {
		return m.backend.Delete(SecretKeyVault)
	}
	data, err := json.Marshal(next)
	if err != nil {
		return err
	}
	return m.backend.Set(SecretKeyVault, data)
}

func cloneSecretMap(src map[string]string) map[string]string {
	dst := make(map[string]string, len(src))
	for k, v := range src {
		dst[k] = v
	}
	return dst
}

func (m *MyGoSecretStore) Get(key string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.loadLocked(); err != nil {
		return "", err
	}
	return m.cache[key], nil
}

func (m *MyGoSecretStore) Set(key, val string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if !m.loaded {
		if err := m.loadLocked(); err != nil {
			return err
		}
	}
	next := cloneSecretMap(m.cache)
	if val == "" {
		delete(next, key)
	} else {
		next[key] = val
	}
	if err := m.persistLocked(next); err != nil {
		return err
	}
	m.cache = next
	m.loaded = true
	return nil
}

func (m *MyGoSecretStore) Delete(key string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if !m.loaded {
		if err := m.loadLocked(); err != nil {
			return err
		}
	}
	if _, ok := m.cache[key]; !ok {
		return nil
	}
	next := cloneSecretMap(m.cache)
	delete(next, key)
	if err := m.persistLocked(next); err != nil {
		return err
	}
	m.cache = next
	return nil
}

// MemSecretStore is an in-memory SecretStore for unit tests and ephemeral CLI sessions.
type MemSecretStore struct {
	mu   sync.RWMutex
	data map[string]string
}

func NewMemSecretStore() *MemSecretStore {
	return &MemSecretStore{data: make(map[string]string)}
}

func (m *MemSecretStore) Get(key string) (string, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.data[key], nil
}

func (m *MemSecretStore) Set(key, val string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.data[key] = val
	return nil
}

func (m *MemSecretStore) Delete(key string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.data, key)
	return nil
}

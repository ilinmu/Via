//go:build linux && !android

package wifi

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"time"

	"via/internal/policy"
)

type linuxAdapter struct{}

// NewAdapter returns a NetworkManager (`nmcli`) Wi-Fi adapter for Linux desktops.
func NewAdapter() (Adapter, error) {
	return &linuxAdapter{}, nil
}

func (a *linuxAdapter) Name() string { return "Linux NetworkManager (nmcli)" }

func (a *linuxAdapter) Permission(_ context.Context) policy.Permission {
	if _, err := exec.LookPath("nmcli"); err != nil {
		return policy.PermissionDenied
	}
	return policy.PermissionAuthorized
}

func (a *linuxAdapter) RequestPermission() error      { return nil }
func (a *linuxAdapter) OpenPermissionSettings() error { return errors.ErrUnsupported }
func (a *linuxAdapter) IsAdvisory() bool              { return false }
func (a *linuxAdapter) ApplyAdvisory(_, _, _, _, _ string) error {
	return errors.ErrUnsupported
}
func (a *linuxAdapter) UpdateNotification(_ bool, _, _ string) {}

func (a *linuxAdapter) CurrentSSID(ctx context.Context) (string, error) {
	if _, err := exec.LookPath("nmcli"); err == nil {
		out, err := exec.CommandContext(ctx, "nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi").Output()
		if err == nil {
			for _, line := range strings.Split(string(out), "\n") {
				line = strings.TrimRight(line, "\r")
				if strings.HasPrefix(line, "yes:") {
					ssid := unescapeNmcliField(strings.TrimPrefix(line, "yes:"))
					if ssid != "" {
						return ssid, nil
					}
				}
			}
		}
	}
	if _, err := exec.LookPath("iwgetid"); err == nil {
		out, err := exec.CommandContext(ctx, "iwgetid", "-r").Output()
		if err == nil {
			return strings.TrimSpace(string(out)), nil
		}
	}
	return "", nil
}

func (a *linuxAdapter) Scan(ctx context.Context) ([]Network, error) {
	out, err := exec.CommandContext(ctx, "nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY", "dev", "wifi", "list", "--rescan", "yes").Output()
	if err != nil {
		return nil, fmt.Errorf("nmcli scan failed: %w", err)
	}
	best := make(map[string]Network)
	for _, rawLine := range strings.Split(string(out), "\n") {
		line := strings.TrimRight(rawLine, "\r")
		if line == "" {
			continue
		}
		fields := splitNmcliTerse(line)
		if len(fields) < 3 {
			continue
		}
		ssid := fields[0]
		if strings.TrimSpace(ssid) == "" {
			continue
		}
		sig, _ := strconv.Atoi(fields[1])
		rssi := sig/2 - 100
		sec := strings.TrimSpace(fields[2]) != "" && fields[2] != "--"
		net := Network{SSID: ssid, RSSI: rssi, Secured: sec}
		if prev, ok := best[ssid]; !ok || net.RSSI > prev.RSSI {
			best[ssid] = net
		}
	}
	res := make([]Network, 0, len(best))
	for _, n := range best {
		res = append(res, n)
	}
	sort.Slice(res, func(i, j int) bool {
		if res[i].RSSI != res[j].RSSI {
			return res[i].RSSI > res[j].RSSI
		}
		return res[i].SSID < res[j].SSID
	})
	return res, nil
}

func (a *linuxAdapter) Connect(ctx context.Context, ssid, password string) error {
	args := []string{"dev", "wifi", "connect", ssid}
	if password != "" {
		args = append(args, "password", password)
	}
	cmd := exec.CommandContext(ctx, "nmcli", args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		// Never echo command arguments that might contain the password.
		return fmt.Errorf("nmcli connect failed: %w (%s)", err, strings.TrimSpace(string(out)))
	}
	return nil
}

func (a *linuxAdapter) SubscribeChanges(onChange func(ssid string)) (io.Closer, error) {
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		last, _ := a.CurrentSSID(ctx)
		ticker := time.NewTicker(3 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				cur, err := a.CurrentSSID(ctx)
				if err != nil {
					continue
				}
				if cur != last {
					last = cur
					onChange(cur)
				}
			}
		}
	}()
	return closerFunc(cancel), nil
}

func (a *linuxAdapter) SubscribePermissionChanges(_ func(perm policy.Permission)) (io.Closer, error) {
	return nopCloser{}, nil
}

type closerFunc func()

func (f closerFunc) Close() error { f(); return nil }

func splitNmcliTerse(line string) []string {
	var fields []string
	var cur strings.Builder
	escaped := false
	for _, r := range line {
		if escaped {
			cur.WriteRune(r)
			escaped = false
			continue
		}
		if r == '\\' {
			escaped = true
			continue
		}
		if r == ':' {
			fields = append(fields, cur.String())
			cur.Reset()
			continue
		}
		cur.WriteRune(r)
	}
	fields = append(fields, cur.String())
	return fields
}

func unescapeNmcliField(s string) string {
	return strings.ReplaceAll(strings.ReplaceAll(s, `\:`, `:`), `\\`, `\`)
}

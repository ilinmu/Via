// Package cli implements Via's diagnostic and headless terminal subcommands:
// `via doctor`, `via status`, `via monitor`, and `via version`.
package cli

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"

	"via/internal/policy"
	"via/internal/store"
	"via/internal/wifi"
)

const AppVersion = "2.0.0"

// Deps supplies platform and I/O hooks (injectable for tests).
type Deps struct {
	NewAdapter   func() (wifi.Adapter, error)
	NewSecrets   func() store.SecretStore
	ConfigDir    func() (string, error)
	Stdout       io.Writer
	Stderr       io.Writer
	Stdin        io.Reader
	ReadPassword func(prompt string) (string, error)
}

func defaultDeps() Deps {
	return Deps{
		NewAdapter: wifi.NewAdapter,
		NewSecrets: func() store.SecretStore { return store.NewMyGoSecretStore() },
		ConfigDir:  DefaultConfigDir,
		Stdout:     os.Stdout,
		Stderr:     os.Stderr,
		Stdin:      os.Stdin,
	}
}

// DefaultConfigDir returns ~/.config/Via or ~/Library/Application Support/Via (matching mygo.PathUserData).
func DefaultConfigDir() (string, error) {
	base, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(base, "Via"), nil
}

// IsSubcommand reports whether arg invokes a CLI subcommand rather than the GUI app.
func IsSubcommand(arg string) bool {
	switch arg {
	case "doctor", "status", "monitor", "version", "help", "-h", "--help", "--version":
		return true
	default:
		return false
	}
}

// Run executes CLI arguments (excluding os.Args[0]) and returns an exit code.
func Run(args []string) int {
	return RunWithDeps(args, defaultDeps())
}

// RunWithDeps executes CLI subcommands with explicit dependencies (for tests).
func RunWithDeps(args []string, d Deps) int {
	if d.Stdout == nil {
		d.Stdout = os.Stdout
	}
	if d.Stderr == nil {
		d.Stderr = os.Stderr
	}
	if d.Stdin == nil {
		d.Stdin = os.Stdin
	}
	if d.ReadPassword == nil {
		d.ReadPassword = func(prompt string) (string, error) {
			return readPasswordPrompt(d.Stdin, d.Stdout, prompt)
		}
	}
	if len(args) == 0 {
		printUsage(d.Stdout)
		return 0
	}

	switch args[0] {
	case "version", "--version":
		fmt.Fprintf(d.Stdout, "Via %s (%s/%s)\n", AppVersion, runtime.GOOS, runtime.GOARCH)
		return 0
	case "help", "-h", "--help":
		printUsage(d.Stdout)
		return 0
	case "doctor":
		return runDoctor(args[1:], d)
	case "status":
		return runStatus(args[1:], d)
	case "monitor":
		return runMonitor(args[1:], d)
	default:
		fmt.Fprintf(d.Stderr, "Unknown command %q\n\n", args[0])
		printUsage(d.Stderr)
		return 2
	}
}

func printUsage(w io.Writer) {
	fmt.Fprintln(w, "Via — Automatic Priority/Backup Wi-Fi Switcher")
	fmt.Fprintln(w, "")
	fmt.Fprintln(w, "Usage:")
	fmt.Fprintln(w, "  via              Launch desktop tray / UI application")
	fmt.Fprintln(w, "  via doctor       Run environment, Wi-Fi adapter, permission & config diagnostics")
	fmt.Fprintln(w, "  via status       Print current Wi-Fi SSID, role and configuration summary")
	fmt.Fprintln(w, "  via monitor      Run headless automatic Wi-Fi monitor in terminal")
	fmt.Fprintln(w, "  via version      Print version information")
}

func runDoctor(args []string, d Deps) int {
	fs := flag.NewFlagSet("doctor", flag.ContinueOnError)
	fs.SetOutput(d.Stderr)
	cfgDirFlag := fs.String("config-dir", "", "Override config directory")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	fmt.Fprintf(d.Stdout, "Via Doctor v%s (%s/%s)\n", AppVersion, runtime.GOOS, runtime.GOARCH)
	fmt.Fprintln(d.Stdout, "----------------------------------------")

	dir, err := resolveDir(*cfgDirFlag, d)
	var settings store.Settings
	if err != nil {
		fmt.Fprintf(d.Stdout, "[!] Config Dir   : error (%v)\n", err)
		settings = store.DefaultSettings()
	} else {
		var loadErr error
		settings, loadErr = store.LoadSettings(dir)
		cfgPath := store.ConfigPath(dir)
		if loadErr != nil {
			fmt.Fprintf(d.Stdout, "[!] Config File  : %s (load error: %v)\n", cfgPath, loadErr)
		} else {
			status := "not configured"
			if settings.IsConfigured() {
				status = fmt.Sprintf("primary=%q backup=%q interval=%ds running=%v",
					settings.SSIDP, settings.SSIDB, settings.CheckIntervalSec, settings.IsRunning)
			}
			fmt.Fprintf(d.Stdout, "[ok] Config      : %s (%s)\n", cfgPath, status)
		}
	}

	if d.NewSecrets != nil {
		sec := d.NewSecrets()
		pState := checkSecretPresence(sec, store.SecretKeyPriority)
		bState := checkSecretPresence(sec, store.SecretKeyBackup)
		fmt.Fprintf(d.Stdout, "[ok] Credentials : primary=%s, backup=%s (passwords never printed)\n", pState, bState)
	}

	adapter, err := d.NewAdapter()
	if err != nil {
		fmt.Fprintf(d.Stdout, "[!] Wi-Fi Adapter: unavailable (%v)\n", err)
		return 1
	}
	fmt.Fprintf(d.Stdout, "[ok] Adapter     : %s\n", adapter.Name())

	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Second)
	defer cancel()

	perm := adapter.Permission(ctx)
	fmt.Fprintf(d.Stdout, "[%s] Permission  : %s\n", okMark(perm == policy.PermissionAuthorized), perm)
	if perm != policy.PermissionAuthorized {
		fmt.Fprintln(d.Stdout, "    Hint: Grant Location/Wi-Fi permission in System Settings to read SSIDs and scan nearby networks.")
	}

	ssid, ssidErr := adapter.CurrentSSID(ctx)
	if ssidErr != nil {
		fmt.Fprintf(d.Stdout, "[!] Current SSID : error (%v)\n", ssidErr)
	} else if ssid == "" {
		fmt.Fprintln(d.Stdout, "[ok] Current SSID: (none)")
	} else {
		role := policy.New(policy.Config{SSIDP: settings.SSIDP, SSIDB: settings.SSIDB}).RoleFor(&ssid)
		fmt.Fprintf(d.Stdout, "[ok] Current SSID: %q (role=%s)\n", ssid, role)
	}

	nets, scanErr := adapter.Scan(ctx)
	if scanErr != nil {
		fmt.Fprintf(d.Stdout, "[!] Nearby Scan  : failed (%v)\n", scanErr)
	} else {
		pFound, bFound := false, false
		for _, n := range nets {
			if settings.SSIDP != "" && n.SSID == settings.SSIDP {
				pFound = true
			}
			if settings.SSIDB != "" && n.SSID == settings.SSIDB {
				bFound = true
			}
		}
		fmt.Fprintf(d.Stdout, "[ok] Nearby Scan : %d networks found (primaryVisible=%v, backupVisible=%v)\n",
			len(nets), pFound, bFound)
	}
	return 0
}

func runStatus(args []string, d Deps) int {
	fs := flag.NewFlagSet("status", flag.ContinueOnError)
	fs.SetOutput(d.Stderr)
	cfgDirFlag := fs.String("config-dir", "", "Override config directory")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	dir, _ := resolveDir(*cfgDirFlag, d)
	settings, _ := store.LoadSettings(dir)

	adapter, err := d.NewAdapter()
	if err != nil {
		fmt.Fprintf(d.Stderr, "adapter unavailable: %v\n", err)
		return 1
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	perm := adapter.Permission(ctx)
	ssid, _ := adapter.CurrentSSID(ctx)
	role := policy.New(policy.Config{SSIDP: settings.SSIDP, SSIDB: settings.SSIDB}).RoleFor(optStr(ssid))

	if ssid == "" {
		ssid = "(none)"
	}
	fmt.Fprintf(d.Stdout, "SSID      : %s\n", ssid)
	fmt.Fprintf(d.Stdout, "Role      : %s\n", role)
	fmt.Fprintf(d.Stdout, "Permission: %s\n", perm)
	fmt.Fprintf(d.Stdout, "Configured: primary=%q backup=%q interval=%ds\n",
		settings.SSIDP, settings.SSIDB, settings.CheckIntervalSec)
	return 0
}

func runMonitor(args []string, d Deps) int {
	for _, a := range args {
		if a == "--password" || strings.HasPrefix(a, "--password=") || a == "-p" {
			fmt.Fprintln(d.Stderr, "Passwords are not accepted as command-line arguments. Leave flags off to enter them via secure prompt.")
			return 2
		}
	}

	fs := flag.NewFlagSet("monitor", flag.ContinueOnError)
	fs.SetOutput(d.Stderr)
	primaryFlag := fs.String("primary", "", "Primary network SSID")
	backupFlag := fs.String("backup", "", "Backup network SSID")
	intervalFlag := fs.Int("interval", 0, "Check interval in seconds (5..3600)")
	cfgDirFlag := fs.String("config-dir", "", "Override config directory")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if fs.NArg() > 0 {
		fmt.Fprintln(d.Stderr, "Passwords or extra positional arguments are not accepted. Usage: via monitor [--primary SSID] [--backup SSID] [--interval SEC]")
		return 2
	}

	dir, _ := resolveDir(*cfgDirFlag, d)
	settings, _ := store.LoadSettings(dir)
	secrets := store.SecretStore(store.NewMemSecretStore())
	if d.NewSecrets != nil && *primaryFlag == "" && *backupFlag == "" {
		secrets = d.NewSecrets()
	}

	reader := bufio.NewReader(d.Stdin)
	if *primaryFlag != "" {
		settings.SSIDP = strings.TrimSpace(*primaryFlag)
	}
	if *backupFlag != "" {
		settings.SSIDB = strings.TrimSpace(*backupFlag)
	}
	if *intervalFlag != 0 {
		settings.CheckIntervalSec, _ = store.NormalizeInterval(*intervalFlag)
	}

	if settings.SSIDP == "" {
		fmt.Fprint(d.Stdout, "Enter Primary Network (P) SSID: ")
		line, _ := reader.ReadString('\n')
		settings.SSIDP = strings.TrimSpace(line)
	}
	if settings.SSIDB == "" {
		fmt.Fprint(d.Stdout, "Enter Backup Network (B) SSID: ")
		line, _ := reader.ReadString('\n')
		settings.SSIDB = strings.TrimSpace(line)
	}
	if !settings.IsConfigured() || settings.SSIDP == settings.SSIDB {
		fmt.Fprintln(d.Stderr, "Invalid configuration: primary and backup SSIDs must be non-empty and distinct.")
		return 2
	}

	// Prompt passwords if CLI flags were used or secret store doesn't have them.
	if *primaryFlag != "" {
		p, err := d.ReadPassword("Primary Network (P) Password (empty if open): ")
		if err != nil {
			fmt.Fprintf(d.Stderr, "read password: %v\n", err)
			return 1
		}
		_ = secrets.Set(store.SecretKeyPriority, p)
	}
	if *backupFlag != "" {
		b, err := d.ReadPassword("Backup Network (B) Password (empty if open): ")
		if err != nil {
			fmt.Fprintf(d.Stderr, "read password: %v\n", err)
			return 1
		}
		_ = secrets.Set(store.SecretKeyBackup, b)
	}

	adapter, err := d.NewAdapter()
	if err != nil {
		fmt.Fprintf(d.Stderr, "Wi-Fi adapter error: %v\n", err)
		return 1
	}

	mon := wifi.NewMonitor(adapter, secrets, settings, "", wifi.DefaultTimingOptions())
	defer mon.Close()

	mon.Subscribe(func(st wifi.State) {
		if st.LastEvent != "" {
			fmt.Fprintf(d.Stdout, "[%s] %s (ssid=%q role=%s running=%v)\n",
				time.Now().Format("15:04:05"), st.LastEvent, st.CurrentSSID, st.Role, st.Running)
		}
	})

	fmt.Fprintf(d.Stdout, "Via Monitor v%s started | primary=%q backup=%q interval=%ds\n",
		AppVersion, settings.SSIDP, settings.SSIDB, settings.CheckIntervalSec)
	fmt.Fprintln(d.Stdout, "Press Ctrl+C to stop")

	mon.Init(context.Background())
	mon.Start()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	<-sigCh
	fmt.Fprintln(d.Stdout, "\nStopping Via monitor...")
	mon.Stop()
	return 0
}

func resolveDir(flagDir string, d Deps) (string, error) {
	if flagDir != "" {
		return flagDir, nil
	}
	if d.ConfigDir != nil {
		return d.ConfigDir()
	}
	return "", errors.New("no config directory")
}

func checkSecretPresence(sec store.SecretStore, key string) string {
	val, err := sec.Get(key)
	if err != nil {
		return fmt.Sprintf("unavailable (%v)", err)
	}
	if val == "" {
		return "empty"
	}
	return "stored"
}

func okMark(ok bool) string {
	if ok {
		return "ok"
	}
	return "!"
}

func optStr(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

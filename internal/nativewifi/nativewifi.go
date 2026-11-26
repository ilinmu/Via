// Package nativewifi bridges Via to OS-native Wi-Fi, permission, tray-icon,
// and Android foreground-service APIs via MyGo's native module mechanism.
package nativewifi

import "io"

// Network describes a nearby Wi-Fi network returned by an OS scan.
type Network struct {
	SSID    string
	RSSI    int
	Secured bool
}

// Controller is implemented natively on macOS (Swift/CoreWLAN/AppKit) and
// Android (Kotlin/WifiManager/ConnectivityManager). Other desktop targets get
// errors.ErrUnsupported from NewController and use pure-Go adapters instead.
//
//mygo:native
type Controller interface {
	// CurrentSSID returns the currently joined Wi-Fi SSID, or "" if disconnected/unavailable.
	CurrentSSID() (string, error)
	// LocationStatus returns the OS location/Wi-Fi permission state ("authorizedAlways", "authorizedWhenInUse", "denied", "restricted", "notDetermined", "unknown").
	LocationStatus() (string, error)
	// RequestLocation prompts the user for Wi-Fi/location permission when undetermined.
	RequestLocation() error
	// OpenLocationSettings opens the system privacy/location settings pane.
	OpenLocationSettings() error
	// Scan scans nearby Wi-Fi networks, deduplicated and sorted by RSSI descending.
	Scan() ([]Network, error)
	// Connect associates the Wi-Fi adapter with ssid using password (empty for open networks).
	Connect(ssid string, password string) error
	// WatchSSIDChanges subscribes to OS Wi-Fi SSID change events and returns a subscription closer.
	WatchSSIDChanges(onChange func(ssid string)) io.Closer
	// WatchPermissionChanges subscribes to OS location/Wi-Fi permission authorization changes.
	WatchPermissionChanges(onChange func(status string)) io.Closer
	// RenderTrayIcon renders the macOS SF Symbol "wifi" tray icon with optional "P"/"B" corner badge or paused red dot as a @2x PNG.
	//mygo:mainthread
	RenderTrayIcon(badge string, paused bool, darkBar bool) ([]byte, error)
	// ApplySuggestions updates Android Wi-Fi network suggestions (ErrUnsupported on macOS).
	ApplySuggestions(ssidP string, pwdP string, ssidB string, pwdB string, preferSSID string) error
	// UpdateGuardNotification updates the Android foreground service notification (ErrUnsupported on macOS).
	UpdateGuardNotification(running bool, title string, subtitle string) error
}

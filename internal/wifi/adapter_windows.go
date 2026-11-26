//go:build windows

package wifi

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unicode/utf16"
	"unsafe"

	"via/internal/policy"
)

const (
	wlanIntfOpcodeCurrentConnection     = 7
	wlanConnectionModeProfile           = 0
	dot11BssTypeInfrastructure          = 1
	wlanProfileUser                     = 0x2
	wlanNotificationSourceAcm           = 0x8
	wlanNotificationAcmConnectionComplete = 10
	wlanNotificationAcmDisconnected     = 21
	wlanInterfaceStateConnected         = 1
	winErrorAccessDenied                = 5
)

var (
	wlanDLL     = syscall.NewLazyDLL("wlanapi.dll")
	kernel32DLL = syscall.NewLazyDLL("kernel32.dll")

	procRtlMoveMemory = kernel32DLL.NewProc("RtlMoveMemory")

	procWlanOpenHandle               = wlanDLL.NewProc("WlanOpenHandle")
	procWlanCloseHandle              = wlanDLL.NewProc("WlanCloseHandle")
	procWlanEnumInterfaces           = wlanDLL.NewProc("WlanEnumInterfaces")
	procWlanQueryInterface           = wlanDLL.NewProc("WlanQueryInterface")
	procWlanGetAvailableNetworkList  = wlanDLL.NewProc("WlanGetAvailableNetworkList")
	procWlanScan                     = wlanDLL.NewProc("WlanScan")
	procWlanSetProfile               = wlanDLL.NewProc("WlanSetProfile")
	procWlanConnect                  = wlanDLL.NewProc("WlanConnect")
	procWlanFreeMemory               = wlanDLL.NewProc("WlanFreeMemory")
	procWlanRegisterNotification     = wlanDLL.NewProc("WlanRegisterNotification")
)

type guid struct {
	Data1 uint32
	Data2 uint16
	Data3 uint16
	Data4 [8]byte
}

type dot11Ssid struct {
	Length uint32
	SSID   [32]byte
}

type wlanAssociationAttributes struct {
	Dot11Ssid         dot11Ssid
	Dot11BssType      int32
	Dot11Bssid        [6]byte
	_                 [2]byte
	Dot11PhyType      int32
	UDot11PhyIndex    uint32
	WlanSignalQuality uint32
	UlRxRate          uint32
	UlTxRate          uint32
}

type wlanSecurityAttributes struct {
	BSecurityEnabled     int32
	BOneXEnabled         int32
	Dot11AuthAlgorithm   int32
	Dot11CipherAlgorithm int32
}

type wlanConnectionAttributes struct {
	IsState                   int32
	WlanConnectionMode        int32
	StrProfileName            [256]uint16
	WlanAssociationAttributes wlanAssociationAttributes
	WlanSecurityAttributes    wlanSecurityAttributes
}

type wlanInterfaceInfo struct {
	InterfaceGuid           guid
	StrInterfaceDescription [256]uint16
	IsState                 int32
}

type wlanAvailableNetwork struct {
	StrProfileName             [256]uint16
	Dot11Ssid                  dot11Ssid
	Dot11BssType               int32
	UNumberOfBssids            uint32
	BNetworkConnectable        int32
	WlanNotConnectableReason   uint32
	UNumberOfPhyTypes          uint32
	Dot11PhyTypes              [8]int32
	BMorePhyTypes              int32
	WlanSignalQuality          uint32
	BSecurityEnabled           int32
	Dot11DefaultAuthAlgorithm  int32
	Dot11DefaultCipherAlgorithm int32
	DwFlags                    uint32
	DwReserved                 uint32
}

type wlanConnectionParameters struct {
	WlanConnectionMode int32
	StrProfile         *uint16
	PDot11Ssid         uintptr
	PDesiredBssidList  uintptr
	Dot11BssType       int32
	DwFlags            uint32
}

type wlanNotificationData struct {
	NotificationSource int32
	NotificationCode   int32
	InterfaceGuid      guid
	DataSize           uint32
	Data               uintptr
}

type wlanConnectionNotificationData struct {
	WlanConnectionMode int32
	StrProfileName     [256]uint16
	Dot11Ssid          dot11Ssid
	Dot11BssType       int32
	BSecurityEnabled   int32
	WlanReasonCode     uint32
	DwFlags            uint32
}

type windowsAdapter struct {
	accessDenied atomic.Bool
}

// NewAdapter returns the Windows Native WLAN API adapter.
func NewAdapter() (Adapter, error) {
	return &windowsAdapter{}, nil
}

func (a *windowsAdapter) Name() string { return "Windows WLAN API" }

func (a *windowsAdapter) Permission(_ context.Context) policy.Permission {
	if err := wlanDLL.Load(); err != nil {
		return policy.PermissionDenied
	}
	if a.accessDenied.Load() {
		return policy.PermissionDenied
	}
	return policy.PermissionAuthorized
}

func (a *windowsAdapter) RequestPermission() error { return a.OpenPermissionSettings() }
func (a *windowsAdapter) OpenPermissionSettings() error {
	return exec.Command("rundll32", "url.dll,FileProtocolHandler", "ms-settings:privacy-location").Start()
}
func (a *windowsAdapter) SubscribePermissionChanges(_ func(policy.Permission)) (io.Closer, error) {
	return nopCloser{}, nil
}
func (a *windowsAdapter) IsAdvisory() bool              { return false }
func (a *windowsAdapter) ApplyAdvisory(_, _, _, _, _ string) error {
	return errors.ErrUnsupported
}
func (a *windowsAdapter) UpdateNotification(_ bool, _, _ string) {}

func openWlanHandle() (uintptr, error) {
	if err := wlanDLL.Load(); err != nil {
		return 0, err
	}
	var negVer uint32
	var handle uintptr
	r, _, _ := procWlanOpenHandle.Call(2, 0, uintptr(unsafe.Pointer(&negVer)), uintptr(unsafe.Pointer(&handle)))
	if r != 0 || handle == 0 {
		return 0, fmt.Errorf("WlanOpenHandle failed: error %d", r)
	}
	return handle, nil
}

func closeWlanHandle(h uintptr) {
	if h != 0 {
		procWlanCloseHandle.Call(h, 0)
	}
}

func findWlanInterface(h uintptr) (guid, error) {
	var listPtr uintptr
	r, _, _ := procWlanEnumInterfaces.Call(h, 0, uintptr(unsafe.Pointer(&listPtr)))
	if r != 0 || listPtr == 0 {
		return guid{}, fmt.Errorf("WlanEnumInterfaces failed: error %d", r)
	}
	defer procWlanFreeMemory.Call(listPtr)

	var count uint32
	procRtlMoveMemory.Call(uintptr(unsafe.Pointer(&count)), listPtr, unsafe.Sizeof(count))
	if count == 0 {
		return guid{}, errors.New("no Wi-Fi interface found")
	}
	// WLAN_INTERFACE_INFO_LIST header is dwNumberOfItems (4) + dwIndex (4) = 8 bytes.
	var info wlanInterfaceInfo
	procRtlMoveMemory.Call(uintptr(unsafe.Pointer(&info)), listPtr+8, unsafe.Sizeof(info))
	return info.InterfaceGuid, nil
}

func decodeDot11SSID(s dot11Ssid) string {
	n := int(s.Length)
	if n <= 0 {
		return ""
	}
	if n > len(s.SSID) {
		n = len(s.SSID)
	}
	return string(s.SSID[:n])
}

func currentSSIDWithHandle(h uintptr) (string, uint32, error) {
	iface, err := findWlanInterface(h)
	if err != nil {
		return "", 0, err
	}
	var dataSize uint32
	var dataPtr uintptr
	var opcodeType int32
	r, _, _ := procWlanQueryInterface.Call(
		h,
		uintptr(unsafe.Pointer(&iface)),
		wlanIntfOpcodeCurrentConnection,
		0,
		uintptr(unsafe.Pointer(&dataSize)),
		uintptr(unsafe.Pointer(&dataPtr)),
		uintptr(unsafe.Pointer(&opcodeType)),
	)
	if r != 0 || dataPtr == 0 {
		return "", uint32(r), nil
	}
	defer procWlanFreeMemory.Call(dataPtr)

	var attrs wlanConnectionAttributes
	procRtlMoveMemory.Call(uintptr(unsafe.Pointer(&attrs)), dataPtr, unsafe.Sizeof(attrs))
	if attrs.IsState != wlanInterfaceStateConnected {
		return "", 0, nil
	}
	return decodeDot11SSID(attrs.WlanAssociationAttributes.Dot11Ssid), 0, nil
}

func (a *windowsAdapter) CurrentSSID(_ context.Context) (string, error) {
	h, err := openWlanHandle()
	if err != nil {
		return "", err
	}
	defer closeWlanHandle(h)
	ssid, code, err := currentSSIDWithHandle(h)
	if code == winErrorAccessDenied {
		a.accessDenied.Store(true)
		return "", errors.New("Windows Location Services permission is required (ERROR_ACCESS_DENIED)")
	}
	if err == nil && code == 0 {
		a.accessDenied.Store(false)
	}
	return ssid, err
}

func (a *windowsAdapter) Scan(ctx context.Context) ([]Network, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	h, err := openWlanHandle()
	if err != nil {
		return nil, err
	}
	defer closeWlanHandle(h)

	iface, err := findWlanInterface(h)
	if err != nil {
		return nil, err
	}
	r, _, _ := procWlanScan.Call(h, uintptr(unsafe.Pointer(&iface)), 0, 0, 0)
	if r == winErrorAccessDenied {
		a.accessDenied.Store(true)
		return nil, errors.New("Windows Location Services permission is required (WlanScan ERROR_ACCESS_DENIED)")
	}
	if r != 0 {
		return nil, fmt.Errorf("WlanScan failed: error %d", r)
	}

	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-time.After(2500 * time.Millisecond):
	}

	var listPtr uintptr
	r, _, _ = procWlanGetAvailableNetworkList.Call(h, uintptr(unsafe.Pointer(&iface)), 0, 0, uintptr(unsafe.Pointer(&listPtr)))
	if r == winErrorAccessDenied {
		a.accessDenied.Store(true)
		return nil, errors.New("Windows Location Services permission is required (WlanGetAvailableNetworkList ERROR_ACCESS_DENIED)")
	}
	if r != 0 || listPtr == 0 {
		return nil, fmt.Errorf("WlanGetAvailableNetworkList failed: error %d", r)
	}
	defer procWlanFreeMemory.Call(listPtr)
	a.accessDenied.Store(false)

	var count uint32
	procRtlMoveMemory.Call(uintptr(unsafe.Pointer(&count)), listPtr, unsafe.Sizeof(count))
	itemSize := unsafe.Sizeof(wlanAvailableNetwork{})
	best := make(map[string]Network, count)
	for i := uint32(0); i < count; i++ {
		var item wlanAvailableNetwork
		procRtlMoveMemory.Call(uintptr(unsafe.Pointer(&item)), listPtr+8+uintptr(i)*itemSize, itemSize)
		ssid := decodeDot11SSID(item.Dot11Ssid)
		if strings.TrimSpace(ssid) == "" {
			continue
		}
		rssi := int(item.WlanSignalQuality)/2 - 100
		net := Network{
			SSID:    ssid,
			RSSI:    rssi,
			Secured: item.BSecurityEnabled != 0,
		}
		if prev, ok := best[ssid]; !ok || net.RSSI > prev.RSSI {
			best[ssid] = net
		}
	}

	out := make([]Network, 0, len(best))
	for _, net := range best {
		out = append(out, net)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].RSSI != out[j].RSSI {
			return out[i].RSSI > out[j].RSSI
		}
		return out[i].SSID < out[j].SSID
	})
	return out, nil
}

func (a *windowsAdapter) Connect(ctx context.Context, ssid, password string) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	h, err := openWlanHandle()
	if err != nil {
		return err
	}
	defer closeWlanHandle(h)

	iface, err := findWlanInterface(h)
	if err != nil {
		return err
	}

	sum := sha256.Sum256([]byte(ssid))
	profileName := "Via-" + hex.EncodeToString(sum[:8])
	profileXML := buildWindowsProfileXML(profileName, ssid, password)
	xmlPtr, err := syscall.UTF16PtrFromString(profileXML)
	if err != nil {
		return err
	}

	var reasonCode uint32
	r, _, _ := procWlanSetProfile.Call(
		h,
		uintptr(unsafe.Pointer(&iface)),
		wlanProfileUser,
		uintptr(unsafe.Pointer(xmlPtr)),
		0,
		1, // bOverwrite = true
		0,
		uintptr(unsafe.Pointer(&reasonCode)),
	)
	if r != 0 {
		return fmt.Errorf("WlanSetProfile failed: error %d (reason %d)", r, reasonCode)
	}

	profPtr, err := syscall.UTF16PtrFromString(profileName)
	if err != nil {
		return err
	}
	params := wlanConnectionParameters{
		WlanConnectionMode: wlanConnectionModeProfile,
		StrProfile:         profPtr,
		Dot11BssType:       dot11BssTypeInfrastructure,
	}
	r, _, _ = procWlanConnect.Call(h, uintptr(unsafe.Pointer(&iface)), uintptr(unsafe.Pointer(&params)), 0)
	if r != 0 {
		return fmt.Errorf("WlanConnect failed: error %d", r)
	}

	deadline := time.Now().Add(15 * time.Second)
	for time.Now().Before(deadline) {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(500 * time.Millisecond):
		}
		if cur, _, err := currentSSIDWithHandle(h); err == nil && cur == ssid {
			return nil
		}
	}
	return fmt.Errorf("timed out connecting to %s", ssid)
}

func xmlEscape(s string) string {
	var b bytes.Buffer
	_ = xml.EscapeText(&b, []byte(s))
	return b.String()
}

func buildWindowsProfileXML(profileName, ssid, password string) string {
	nameEsc := xmlEscape(profileName)
	ssidEsc := xmlEscape(ssid)
	if password == "" {
		return fmt.Sprintf(`<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>%s</name>
  <SSIDConfig><SSID><name>%s</name></SSID></SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>auto</connectionMode>
  <MSM><security><authEncryption><authentication>open</authentication><encryption>none</encryption><useOneX>false</useOneX></authEncryption></security></MSM>
</WLANProfile>`, nameEsc, ssidEsc)
	}
	pwdEsc := xmlEscape(password)
	return fmt.Sprintf(`<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>%s</name>
  <SSIDConfig><SSID><name>%s</name></SSID></SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>auto</connectionMode>
  <MSM><security><authEncryption><authentication>WPA2PSK</authentication><encryption>AES</encryption><useOneX>false</useOneX></authEncryption><sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>%s</keyMaterial></sharedKey></security></MSM>
</WLANProfile>`, nameEsc, ssidEsc, pwdEsc)
}

var (
	winWatchMu        sync.Mutex
	winWatchRegOnce   sync.Once
	winWatchHandle    uintptr
	winWatchCallback  uintptr
	winWatchListeners = map[uint64]func(string){}
	winWatchNextID    uint64
	winEventCh        = make(chan string, 16)
)

func wlanNotifyCallback(dataPtr uintptr, _ uintptr) uintptr {
	if dataPtr == 0 {
		return 0
	}
	var nd wlanNotificationData
	procRtlMoveMemory.Call(uintptr(unsafe.Pointer(&nd)), dataPtr, unsafe.Sizeof(nd))
	if nd.NotificationSource != wlanNotificationSourceAcm {
		return 0
	}
	var ssid string
	switch nd.NotificationCode {
	case wlanNotificationAcmDisconnected:
		ssid = ""
	case wlanNotificationAcmConnectionComplete:
		if nd.Data == 0 || uintptr(nd.DataSize) < unsafe.Sizeof(wlanConnectionNotificationData{}) {
			return 0
		}
		var cn wlanConnectionNotificationData
		procRtlMoveMemory.Call(uintptr(unsafe.Pointer(&cn)), nd.Data, unsafe.Sizeof(cn))
		ssid = decodeDot11SSID(cn.Dot11Ssid)
		if ssid == "" {
			return 0
		}
	default:
		return 0
	}
	select {
	case winEventCh <- ssid:
	default:
	}
	return 0
}

func (a *windowsAdapter) SubscribeChanges(onChange func(ssid string)) (io.Closer, error) {
	winWatchRegOnce.Do(func() {
		h, err := openWlanHandle()
		if err != nil {
			return
		}
		cb := syscall.NewCallback(wlanNotifyCallback)
		var prevSrc uint32
		r, _, _ := procWlanRegisterNotification.Call(h, wlanNotificationSourceAcm, 1, cb, 0, 0, uintptr(unsafe.Pointer(&prevSrc)))
		if r != 0 {
			closeWlanHandle(h)
			return
		}
		winWatchHandle = h
		winWatchCallback = cb
		go func() {
			for ssid := range winEventCh {
				winWatchMu.Lock()
				cbs := make([]func(string), 0, len(winWatchListeners))
				for _, fn := range winWatchListeners {
					cbs = append(cbs, fn)
				}
				winWatchMu.Unlock()
				for _, fn := range cbs {
					fn(ssid)
				}
			}
		}()
	})
	_ = utf16.Encode
	winWatchMu.Lock()
	winWatchNextID++
	id := winWatchNextID
	winWatchListeners[id] = onChange
	winWatchMu.Unlock()
	return &winWatcher{id: id}, nil
}

type winWatcher struct{ id uint64 }

func (w *winWatcher) Close() error {
	winWatchMu.Lock()
	delete(winWatchListeners, w.id)
	winWatchMu.Unlock()
	return nil
}

import Foundation
#if os(macOS)
import AppKit
import CoreWLAN
import CoreLocation
import SystemConfiguration
#endif

func makeController() throws -> any Controller {
#if os(macOS)
    return MacOSController()
#else
    throw NativeError.unsupported
#endif
}

#if os(macOS)
final class MacOSController: NSObject, Controller, CWEventDelegate, CLLocationManagerDelegate {
    private let client = CWWiFiClient.shared()
    private var location: CLLocationManager!
    private let watchLock = NSLock()
    private var watchCallbacks: [UUID: @Sendable (String) -> Void] = [:]
    private var permCallbacks: [UUID: @Sendable (String) -> Void] = [:]
    private var eventMonitoringStarted = false
    private let scanCacheLock = NSLock()
    private var cachedNetworks: [String: (network: CWNetwork, at: Date)] = [:]

    private func onMainSync<T>(_ work: () -> T) -> T {
        if Thread.isMainThread {
            return work()
        }
        return DispatchQueue.main.sync(execute: work)
    }

    override init() {
        super.init()
        client.delegate = self
        onMainSync {
            let mgr = CLLocationManager()
            mgr.delegate = self
            self.location = mgr
        }
    }

    private func resolveInterface() -> CWInterface? {
        if let iface = client.interface() {
            return iface
        }
        if let list = client.interfaces(), let first = list.first {
            return first
        }
        // CoreWLAN can return nil for interface() / interfaces() inside a sandboxed Mac App Store
        // app; fall back to IEEE 802.11 BSD names exposed by SystemConfiguration.
        var candidateNames = client.interfaceNames() ?? []
        if let sysIfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for sysIf in sysIfaces {
                guard SCNetworkInterfaceGetInterfaceType(sysIf) as String? == kSCNetworkInterfaceTypeIEEE80211 as String,
                      let bsdName = SCNetworkInterfaceGetBSDName(sysIf) as String?,
                      !candidateNames.contains(bsdName) else {
                    continue
                }
                candidateNames.append(bsdName)
            }
        }
        for name in candidateNames {
            if let iface = client.interface(withName: name) {
                return iface
            }
        }
        return nil
    }

    func currentSSID() throws -> String {
        if let ssid = resolveInterface()?.ssid(), !ssid.isEmpty {
            return ssid
        }
        for iface in client.interfaces() ?? [] {
            if let ssid = iface.ssid(), !ssid.isEmpty {
                return ssid
            }
        }
        return ""
    }

    private func statusString(for auth: CLAuthorizationStatus) -> String {
        switch auth {
        case .authorizedAlways:
            return "authorizedAlways"
        case .authorizedWhenInUse:
            return "authorizedWhenInUse"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "notDetermined"
        @unknown default:
            return "unknown"
        }
    }

    private func isLocationAuthorized() -> Bool {
        return onMainSync {
            location.authorizationStatus == .authorizedAlways
        }
    }

    func locationStatus() throws -> String {
        return onMainSync {
            statusString(for: location.authorizationStatus)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = statusString(for: manager.authorizationStatus)
        watchLock.lock()
        let callbacks = Array(permCallbacks.values)
        watchLock.unlock()
        for cb in callbacks {
            cb(status)
        }
    }

    func requestLocation() throws {
        DispatchQueue.main.async {
            let st = self.location.authorizationStatus
            NSApp.activate(ignoringOtherApps: true)
            if st == .notDetermined {
                self.location.requestAlwaysAuthorization()
                return
            }
            if st == .denied || st == .restricted {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    func openLocationSettings() throws {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else {
            return
        }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSWorkspace.shared.open(url)
        }
    }

    private func updateScanCache(from found: Set<CWNetwork>) -> [Network] {
        var bestBySSID: [String: Network] = [:]
        var bestCWBySSID: [String: CWNetwork] = [:]
        for net in found {
            guard let ssid = net.ssid, !ssid.isEmpty else { continue }
            let secured = !net.supportsSecurity(.none)
            let item = Network(ssid: ssid, rssi: net.rssiValue, secured: secured)
            if let existing = bestBySSID[ssid] {
                if item.rssi > existing.rssi {
                    bestBySSID[ssid] = item
                    bestCWBySSID[ssid] = net
                }
            } else {
                bestBySSID[ssid] = item
                bestCWBySSID[ssid] = net
            }
        }
        let now = Date()
        scanCacheLock.lock()
        for (ssid, net) in bestCWBySSID {
            cachedNetworks[ssid] = (network: net, at: now)
        }
        scanCacheLock.unlock()

        return bestBySSID.values.sorted { a, b in
            if a.rssi != b.rssi {
                return a.rssi > b.rssi
            }
            return a.ssid < b.ssid
        }
    }

    private func freshCachedNetwork(for ssid: String, maxAge: TimeInterval = 20.0) -> CWNetwork? {
        scanCacheLock.lock()
        defer { scanCacheLock.unlock() }
        guard let entry = cachedNetworks[ssid], Date().timeIntervalSince(entry.at) <= maxAge else {
            return nil
        }
        return entry.network
    }

    private func invalidateCachedNetwork(for ssid: String) {
        scanCacheLock.lock()
        cachedNetworks.removeValue(forKey: ssid)
        scanCacheLock.unlock()
    }

    private func resolveTargetNetwork(iface: CWInterface, ssid: String) throws -> CWNetwork {
        if let found = try? iface.scanForNetworks(withSSID: nil) {
            _ = updateScanCache(from: found)
            if let hit = found.filter({ $0.ssid == ssid }).max(by: { $0.rssiValue < $1.rssiValue }) {
                return hit
            }
        }
        if let directed = try? iface.scanForNetworks(withSSID: Data(ssid.utf8)),
           let hit = directed.filter({ $0.ssid == ssid }).max(by: { $0.rssiValue < $1.rssiValue }) {
            return hit
        }
        // CoreWLAN may briefly throttle scans right after an association; settle and retry once.
        Thread.sleep(forTimeInterval: 0.6)
        let retryFound = try iface.scanForNetworks(withSSID: nil)
        _ = updateScanCache(from: retryFound)
        if let hit = retryFound.filter({ $0.ssid == ssid }).max(by: { $0.rssiValue < $1.rssiValue }) {
            return hit
        }
        throw NSError(domain: "ViaNativeWiFi", code: 2, userInfo: [NSLocalizedDescriptionKey: "Network \(ssid) not found"])
    }

    func scan() throws -> [Network] {
        guard isLocationAuthorized() else {
            throw NSError(domain: "ViaNativeWiFi", code: 3, userInfo: [NSLocalizedDescriptionKey: "Location permission is required to scan Wi-Fi networks"])
        }
        guard let iface = resolveInterface() else {
            throw NSError(domain: "ViaNativeWiFi", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Wi-Fi interface available"])
        }
        let found = try iface.scanForNetworks(withSSID: nil)
        return updateScanCache(from: found)
    }

    func connect(ssid: String, password: String) throws {
        guard isLocationAuthorized() else {
            throw NSError(domain: "ViaNativeWiFi", code: 3, userInfo: [NSLocalizedDescriptionKey: "Location permission is required to switch Wi-Fi networks"])
        }
        guard let iface = resolveInterface() else {
            throw NSError(domain: "ViaNativeWiFi", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Wi-Fi interface available"])
        }
        let pwd: String? = password.isEmpty ? nil : password
        var associated = false
        if let cached = freshCachedNetwork(for: ssid) {
            do {
                try iface.associate(to: cached, password: pwd)
                associated = true
            } catch {
                invalidateCachedNetwork(for: ssid)
            }
        }
        if !associated {
            let target = try resolveTargetNetwork(iface: iface, ssid: ssid)
            try iface.associate(to: target, password: pwd)
        }

        // Confirm the OS radio actually joined the requested SSID.
        for _ in 0..<12 {
            if let cur = resolveInterface()?.ssid(), cur == ssid {
                return
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        let actual = resolveInterface()?.ssid() ?? ""
        throw NSError(
            domain: "ViaNativeWiFi",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "macOS did not switch Wi-Fi to \(ssid) (current: \(actual.isEmpty ? "none" : actual))"]
        )
    }

    func watchSSIDChanges(onChange: @escaping @Sendable (String) -> Void) -> any Closer {
        let id = UUID()
        watchLock.lock()
        watchCallbacks[id] = onChange
        if !eventMonitoringStarted {
            do {
                try client.startMonitoringEvent(with: .ssidDidChange)
                eventMonitoringStarted = true
            } catch {
                // Keep callback registered; callers still run periodic checks.
            }
        }
        watchLock.unlock()

        return NativeCloser { [weak self] in
            guard let self else { return }
            self.watchLock.lock()
            self.watchCallbacks.removeValue(forKey: id)
            let empty = self.watchCallbacks.isEmpty
            if empty && self.eventMonitoringStarted {
                try? self.client.stopMonitoringEvent(with: .ssidDidChange)
                self.eventMonitoringStarted = false
            }
            self.watchLock.unlock()
        }
    }

    func watchPermissionChanges(onChange: @escaping @Sendable (String) -> Void) -> any Closer {
        let id = UUID()
        watchLock.lock()
        permCallbacks[id] = onChange
        watchLock.unlock()

        return NativeCloser { [weak self] in
            guard let self else { return }
            self.watchLock.lock()
            self.permCallbacks.removeValue(forKey: id)
            self.watchLock.unlock()
        }
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        let ssid = (try? currentSSID()) ?? ""
        watchLock.lock()
        let callbacks = Array(watchCallbacks.values)
        watchLock.unlock()
        for cb in callbacks {
            cb(ssid)
        }
    }

    @MainActor
    func renderTrayIcon(badge: String, paused: Bool, darkBar: Bool) throws -> Data {
        guard let baseSymbol = NSImage(systemSymbolName: "wifi", accessibilityDescription: "Via")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) else {
            throw NativeError.unsupported
        }

        let iconColor: NSColor = !paused ? .black : (darkBar ? .white : .black)
        let coloredSymbol = baseSymbol.withSymbolConfiguration(.init(paletteColors: [iconColor])) ?? baseSymbol
        let symSize = coloredSymbol.size

        let heightPt: CGFloat = 18.0
        let scale: CGFloat = 2.0
        let badgeAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9.0, weight: .bold),
            .foregroundColor: iconColor,
        ]
        let showBadge = !paused && !badge.isEmpty
        let badgeSize = showBadge ? (badge as NSString).size(withAttributes: badgeAttr) : .zero
        let badgeGap: CGFloat = 0.0

        let widthPt: CGFloat
        let symX: CGFloat
        if showBadge {
            symX = 0.5
            widthPt = ceil(0.5 + symSize.width + badgeGap + badgeSize.width + 0.5)
        } else if paused {
            symX = 1.0
            widthPt = ceil(symSize.width + 3.0)
        } else {
            widthPt = ceil(symSize.width + 2.0)
            symX = (widthPt - symSize.width) / 2.0
        }
        let symY = (heightPt - symSize.height) / 2.0

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(widthPt * scale),
            pixelsHigh: Int(heightPt * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NativeError.unsupported
        }
        rep.size = NSSize(width: widthPt, height: heightPt)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            throw NativeError.unsupported
        }
        NSGraphicsContext.current = ctx

        coloredSymbol.draw(
            in: NSRect(x: symX, y: symY, width: symSize.width, height: symSize.height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )

        if showBadge {
            let badgeY: CGFloat = 0.5
            (badge as NSString).draw(at: NSPoint(x: symX + symSize.width + badgeGap, y: badgeY), withAttributes: badgeAttr)
        } else if paused {
            let dotSize: CGFloat = 4.5
            let dotRect = NSRect(x: widthPt - dotSize - 0.5, y: 1.5, width: dotSize, height: dotSize)
            ctx.compositingOperation = .clear
            NSBezierPath(ovalIn: dotRect.insetBy(dx: -0.8, dy: -0.8)).fill()
            ctx.compositingOperation = .sourceOver
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }

        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            throw NativeError.unsupported
        }
        return pngData
    }

    func applySuggestions(ssidP: String, pwdP: String, ssidB: String, pwdB: String, preferSSID: String) throws {
        throw NativeError.unsupported
    }

    func updateGuardNotification(running: Bool, title: String, subtitle: String) throws {
        throw NativeError.unsupported
    }
}
#endif

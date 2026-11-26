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
    private let wifiOpLock = NSLock()
    private let scanCacheLock = NSLock()
    private var cachedNetworks: [String: (network: CWNetwork, at: Date)] = [:]
    private var lastScanAt: Date?

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
        lastScanAt = now
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

    private func freshCachedNetwork(for ssid: String, maxAge: TimeInterval = 15.0) -> CWNetwork? {
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

    private func waitPostScanSettle(minInterval: TimeInterval = 0.35) {
        scanCacheLock.lock()
        let last = lastScanAt
        scanCacheLock.unlock()
        guard let last else { return }
        let elapsed = Date().timeIntervalSince(last)
        if elapsed < minInterval {
            Thread.sleep(forTimeInterval: minInterval - elapsed)
        }
    }

    private func isTransientAssociationError(_ error: Error) -> Bool {
        let nsErr = error as NSError
        if nsErr.localizedDescription.lowercased().contains("tmperr") {
            return true
        }
        if nsErr.domain == "com.apple.wifi.apple80211API.error" || nsErr.code == -528342014 {
            return true
        }
        if nsErr.domain == CWErrorDomain {
            let transientCodes: Set<Int> = [-3902, -3905, -3906, -3908, -3928, -3929, -3931]
            if transientCodes.contains(nsErr.code) {
                return true
            }
        }
        return false
    }

    private func findTargetNetwork(iface: CWInterface, ssid: String, allowCache: Bool) throws -> (network: CWNetwork, fromCache: Bool) {
        if allowCache, let cached = freshCachedNetwork(for: ssid) {
            return (cached, true)
        }
        if let named = try? iface.scanForNetworks(withName: ssid, includeHidden: true) {
            let now = Date()
            scanCacheLock.lock()
            lastScanAt = now
            scanCacheLock.unlock()
            if let hit = named.filter({ $0.ssid == ssid }).max(by: { $0.rssiValue < $1.rssiValue }) {
                scanCacheLock.lock()
                cachedNetworks[ssid] = (network: hit, at: now)
                scanCacheLock.unlock()
                return (hit, false)
            }
        }
        if let found = try? iface.scanForNetworks(withSSID: nil) {
            _ = updateScanCache(from: found)
            if let hit = found.filter({ $0.ssid == ssid }).max(by: { $0.rssiValue < $1.rssiValue }) {
                return (hit, false)
            }
        }
        // CoreWLAN may briefly throttle scans right after an association; settle and retry once.
        Thread.sleep(forTimeInterval: 0.6)
        let retryFound = try iface.scanForNetworks(withSSID: nil)
        _ = updateScanCache(from: retryFound)
        if let hit = retryFound.filter({ $0.ssid == ssid }).max(by: { $0.rssiValue < $1.rssiValue }) {
            return (hit, false)
        }
        throw NSError(domain: "ViaNativeWiFi", code: 2, userInfo: [NSLocalizedDescriptionKey: "Network \(ssid) not found"])
    }

    func scan() throws -> [Network] {
        guard isLocationAuthorized() else {
            throw NSError(domain: "ViaNativeWiFi", code: 3, userInfo: [NSLocalizedDescriptionKey: "Location permission is required to scan Wi-Fi networks"])
        }
        wifiOpLock.lock()
        defer { wifiOpLock.unlock() }
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
        wifiOpLock.lock()
        defer { wifiOpLock.unlock() }
        guard let iface = resolveInterface() else {
            throw NSError(domain: "ViaNativeWiFi", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Wi-Fi interface available"])
        }
        if iface.ssid() == ssid {
            return
        }

        let pwd: String? = password.isEmpty ? nil : password
        var associated = false
        var lastError: Error?
        var targetSecured = false
        var tryAttempt2 = false
        var tryAttempt3 = false

        // Attempt 1: fast path (allows recently cached CWNetwork).
        do {
            waitPostScanSettle(minInterval: 0.35)
            let resolved = try findTargetNetwork(iface: iface, ssid: ssid, allowCache: true)
            targetSecured = !resolved.network.supportsSecurity(.none)
            waitPostScanSettle(minInterval: 0.35)
            do {
                try iface.associate(to: resolved.network, password: pwd)
                associated = true
            } catch {
                if resolveInterface()?.ssid() == ssid {
                    return
                }
                invalidateCachedNetwork(for: ssid)
                lastError = error
                tryAttempt2 = resolved.fromCache || isTransientAssociationError(error)
            }
        } catch {
            if resolveInterface()?.ssid() == ssid {
                return
            }
            lastError = error
            tryAttempt2 = isTransientAssociationError(error)
        }

        // Attempt 2: settle briefly, re-acquire interface, fresh scan without disassociating first.
        if !associated && tryAttempt2 {
            Thread.sleep(forTimeInterval: 0.8)
            let freshIface = resolveInterface() ?? iface
            if freshIface.ssid() == ssid {
                return
            }
            do {
                let freshTarget = try findTargetNetwork(iface: freshIface, ssid: ssid, allowCache: false)
                targetSecured = !freshTarget.network.supportsSecurity(.none)
                waitPostScanSettle(minInterval: 0.35)
                do {
                    try freshIface.associate(to: freshTarget.network, password: pwd)
                    associated = true
                } catch {
                    if resolveInterface()?.ssid() == ssid {
                        return
                    }
                    lastError = error
                    tryAttempt3 = isTransientAssociationError(error)
                }
            } catch {
                if resolveInterface()?.ssid() == ssid {
                    return
                }
                lastError = error
                tryAttempt3 = isTransientAssociationError(error)
            }
        }

        // Attempt 3: disassociate from current network before retrying when apple80211 driver returned tmpErr.
        if !associated && tryAttempt3 {
            let curIface = resolveInterface() ?? iface
            if curIface.ssid() == ssid {
                return
            }
            if let curSSID = curIface.ssid(), !curSSID.isEmpty, curSSID != ssid {
                curIface.disassociate()
                Thread.sleep(forTimeInterval: 0.9)
            }
            let retryIface = resolveInterface() ?? curIface
            do {
                let retryTarget = try findTargetNetwork(iface: retryIface, ssid: ssid, allowCache: false)
                targetSecured = !retryTarget.network.supportsSecurity(.none)
                waitPostScanSettle(minInterval: 0.35)
                try retryIface.associate(to: retryTarget.network, password: pwd)
                associated = true
            } catch {
                if resolveInterface()?.ssid() == ssid {
                    return
                }
                lastError = error
            }
        }

        if !associated {
            Thread.sleep(forTimeInterval: 0.4)
            if resolveInterface()?.ssid() == ssid {
                return
            }
            if let err = lastError {
                if targetSecured && password.isEmpty && !isTransientAssociationError(err) {
                    throw NSError(domain: "ViaNativeWiFi", code: 5, userInfo: [NSLocalizedDescriptionKey: "Password required or invalid for \(ssid)"])
                }
                if isTransientAssociationError(err) {
                    throw NSError(domain: "ViaNativeWiFi", code: 6, userInfo: [NSLocalizedDescriptionKey: "Wi-Fi driver busy while connecting to \(ssid) (tmpErr)"])
                }
                throw err
            }
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

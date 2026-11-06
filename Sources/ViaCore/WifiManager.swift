import Foundation
import Combine
import CoreWLAN
import CoreLocation
import SystemConfiguration

// MARK: - Protocols

public protocol WiFiClientProtocol: AnyObject {
    var delegate: AnyObject? { get set }
    func interface() -> WiFiInterfaceProtocol?
    func interfacesProtocol() -> [WiFiInterfaceProtocol]
    func interfaceNamesProtocol() -> [String]
    func interfaceProtocol(withName name: String) -> WiFiInterfaceProtocol?
    func startMonitoringEvent(with type: CWEventType) throws
}

public protocol WiFiNetworkProtocol: AnyObject {
    var ssid: String? { get }
    var rssiValue: Int { get }
}

public protocol WiFiInterfaceProtocol: AnyObject {
    func ssid() -> String?
    func interfaceNameProtocol() -> String?
    func isPowerOnProtocol() -> Bool
    func scanForNetworksProtocol(withSSID ssid: Data?) throws -> [WiFiNetworkProtocol]
    func associateNetwork(_ network: WiFiNetworkProtocol, password: String) throws
}

public protocol LocationManagerProtocol: AnyObject {
    var delegate: CLLocationManagerDelegate? { get set }
    var authorizationStatus: CLAuthorizationStatus { get }
    func requestWhenInUseAuthorization()
}

// MARK: - System Implementations

extension CWNetwork: WiFiNetworkProtocol {}

extension CWWiFiClient: WiFiClientProtocol {
    public func interface() -> WiFiInterfaceProtocol? {
        return self.interface() as CWInterface?
    }

    public func interfacesProtocol() -> [WiFiInterfaceProtocol] {
        let interfaces = (self.interfaces() as [CWInterface]?) ?? []
        if !interfaces.isEmpty {
            return interfaces.map { $0 as WiFiInterfaceProtocol }
        }

        return (self.interfaceNames() ?? []).compactMap { name in
            self.interface(withName: name) as WiFiInterfaceProtocol?
        }
    }

    public func interfaceNamesProtocol() -> [String] {
        var names = self.interfaceNames() ?? []

        // CoreWLAN can return no default/listed interface to a sandboxed app
        // even though the public SystemConfiguration API still exposes the
        // machine's IEEE 802.11 BSD interface. Use those names as a final
        // lookup source, then bind them back to CoreWLAN for scan/association.
        let systemInterfaces = (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? []
        for systemInterface in systemInterfaces {
            guard SCNetworkInterfaceGetInterfaceType(systemInterface) as String? == kSCNetworkInterfaceTypeIEEE80211 as String,
                  let name = SCNetworkInterfaceGetBSDName(systemInterface) as String?
            else {
                continue
            }

            if !names.contains(name) {
                names.append(name)
            }
        }

        return names
    }

    public func interfaceProtocol(withName name: String) -> WiFiInterfaceProtocol? {
        self.interface(withName: name) as WiFiInterfaceProtocol?
    }
}

extension CWInterface: WiFiInterfaceProtocol {
    public func interfaceNameProtocol() -> String? {
        interfaceName
    }

    public func isPowerOnProtocol() -> Bool {
        powerOn()
    }

    public func scanForNetworksProtocol(withSSID ssid: Data?) throws -> [WiFiNetworkProtocol] {
        let networks = try self.scanForNetworks(withSSID: ssid)
        return networks.map { $0 as WiFiNetworkProtocol }
    }
    
    public func associateNetwork(_ network: WiFiNetworkProtocol, password: String) throws {
        guard let cwNetwork = network as? CWNetwork else {
            throw NSError(domain: "Via", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid network type"])
        }
        try self.associate(to: cwNetwork, password: password)
    }
}

extension CLLocationManager: LocationManagerProtocol {}

enum WifiManagerError: LocalizedError {
    case noInterface
    case networkNotFound(String)

    var errorDescription: String? {
        switch self {
        case .noInterface:
            return "No Wi-Fi interface found."
        case let .networkNotFound(ssid):
            return "Network \(ssid) was no longer visible when association started."
        }
    }
}

private final class WiFiOperation: @unchecked Sendable {
    private let interface: WiFiInterfaceProtocol

    init(interface: WiFiInterfaceProtocol) {
        self.interface = interface
    }

    func scan(ssid: Data? = nil) throws -> NetworkList {
        NetworkList(try interface.scanForNetworksProtocol(withSSID: ssid))
    }

    func associate(network: WiFiNetworkProtocol, password: String) throws {
        try interface.associateNetwork(network, password: password)
    }

    func scanAndAssociate(networkNamed ssid: String, password: String) throws {
        let networks = try interface.scanForNetworksProtocol(withSSID: Data(ssid.utf8))
        guard let target = networks.max(by: { $0.rssiValue < $1.rssiValue }) else {
            throw WifiManagerError.networkNotFound(ssid)
        }
        try interface.associateNetwork(target, password: password)
    }
}

private final class NetworkList: @unchecked Sendable {
    let networks: [WiFiNetworkProtocol]

    init(_ networks: [WiFiNetworkProtocol]) {
        self.networks = networks
    }
}

private enum AssociationResult: Sendable {
    case succeeded
    case timedOut
    case failed(domain: String, code: Int, description: String)
}

private final class AssociationContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AssociationResult, Never>?

    init(_ continuation: CheckedContinuation<AssociationResult, Never>) {
        self.continuation = continuation
    }

    /// Returns `true` when this call delivered the result, and `false` when the
    /// operation finished after the timeout already resumed the continuation.
    @discardableResult
    func resume(returning result: AssociationResult) -> Bool {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return false
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: result)
        return true
    }
}

// MARK: - WifiManager

@MainActor
public class WifiManager: NSObject, ObservableObject, CLLocationManagerDelegate, CWEventDelegate {
    private var client: WiFiClientProtocol
    private var interface: WiFiInterfaceProtocol?
    private var timer: Timer?
    private var appState: AppState
    private var locationManager: LocationManagerProtocol
    private var cancellables = Set<AnyCancellable>()

    /// Association lifecycle bridge to the Rust core. The macOS monitoring
    /// loop itself is Swift-owned; policy state is kept in exactly one place so
    /// the two implementations cannot diverge on P-loss classification.
    private var policy: WifiPolicyEngine?

    @Published public private(set) var locationAuthorizationStatus: CLAuthorizationStatus = .notDetermined

    private var lastObservedSSID: String?
    private var trackedBackupSSID: String
    private var previousBackupSSID: String?
    private var lastProgrammaticBackupAt: Date?
    private let programmaticBackupWindow: TimeInterval = 15
    private var isCheckingConnection = false
    private var isHandlingObservedChange = false
    private var isConfirmingPriorityVisibility = false
    private var pendingObservedChange: ObservedChange?
    private var isAssociating = false
    private var pendingAssociationRequested = false
    private var hasRequestedPermissions = false
    private var associationGeneration: UInt64 = 0
    private var activeProgrammaticAssociation: ProgrammaticAssociationIntent?
    private var needsImmediateRecheck = false
    private var manualOverrideVerificationTask: Task<Void, Never>?
    private let associationRetryDelay: TimeInterval = 20
    private let associationCooldown: TimeInterval = 90

    private struct ObservedChange {
        let previousSSID: String?
        let ssid: String?
    }

    /// A timed-out association is not cancelled at the CoreWLAN layer. Keep its
    /// intent until the underlying call really returns, but bound how long a
    /// late SSID event may still be attributed to it.
    private struct ProgrammaticAssociationIntent {
        let ssid: String
        let generation: UInt64
        let deadline: Date
    }

    /// Overridable in tests so timeout behavior can be exercised without
    /// waiting the production interval.
    var associationTimeout: TimeInterval = 15

    /// Settle/rescan timing used to distinguish a manual Wi-Fi switch from an
    /// automatic fallback. CoreWLAN may serve the system scan cache for a
    /// while after a change, and that cache can still list the network the
    /// radio just lost. One immediate scan is therefore not enough to decide
    /// that P is available: a manual switch is only confirmed when P is still
    /// reported after several scans spread over a settling window.
    /// Overridable in tests so classification happens immediately.
    var observedChangeSettleDelay: TimeInterval = 2.0
    var observedChangeRescanInterval: TimeInterval = 2.0
    var observedChangeRescanAttempts: Int = 3

    /// A stop caused by a suspected manual switch gets one delayed review. If
    /// P is really gone by then, the stop was a stale-scan false positive and
    /// monitoring resumes so P reconnects automatically when it returns.
    /// A genuine manual switch keeps P visible and stays stopped.
    var manualOverrideVerificationDelay: TimeInterval = 25
    var manualOverrideVerificationAttempts: Int = 2
    var manualOverrideVerificationInterval: TimeInterval = 3

    
    public init(appState: AppState,
                client: WiFiClientProtocol = CWWiFiClient.shared(),
                locationManager: LocationManagerProtocol = CLLocationManager()) {
        self.appState = appState
        self.client = client
        self.locationManager = locationManager
        self.trackedBackupSSID = appState.ssidB
        super.init()

        self.policy = WifiPolicyEngine(ssidP: appState.ssidP, ssidB: appState.ssidB)
        self.locationAuthorizationStatus = locationManager.authorizationStatus
        self.interface = Self.resolveInterface(from: client)
        self.locationManager.delegate = self
        self.client.delegate = self

        do {
            try self.client.startMonitoringEvent(with: .ssidDidChange)
        } catch {
            print("Failed to start monitoring SSID changes: \(error)")
        }

        // Re-schedule immediately when the user edits the check interval while
        // monitoring is active. The sink runs on the next run-loop turn so the
        // normalized value has already been persisted by AppState.
        appState.$checkInterval
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handleCheckIntervalChange()
                }
            }
            .store(in: &cancellables)

        // Initial status check
        Task { @MainActor in
            self.refreshStatus()
        }
    }
    
    // ... (refreshStatus and requestPermissions remain same)
    
    public func refreshStatus() {
        syncConfiguredNetworks()
        let authStatus = locationManager.authorizationStatus
        locationAuthorizationStatus = authStatus

        if authStatus == .denied || authStatus == .restricted {
            appState.setNetworkStatus(.permissionDenied)
            appState.log("⚠️ Location permission denied. Cannot read SSID.")
            return
        }

        // The default CoreWLAN interface can be nil even while another Wi-Fi
        // interface is active, so always fall back to the complete interface list.
        self.interface = resolvedInterface()

        guard let interface = self.interface else {
            appState.setNetworkStatus(.noInterface)
            appState.interfaceStatus = "Wi-Fi interface unavailable"
            return
        }

        updateInterfaceStatus(interface)
        let currentSSID = interface.ssid()
        // Do not mirror the current SSID into `lastObservedSSID` here: a
        // refresh may be scheduled after an SSID-change event has already been
        // delivered, which would erase the previous network the event handler
        // needs in order to classify a disconnect as P disappearing.

        if let ssid = currentSSID {
            appState.setNetworkStatus(.connected(ssid: ssid, role: networkRole(for: ssid)))
        } else if authStatus == .notDetermined {
            // Do not prompt merely because the panel was opened; monitoring
            // and the explicit scan button request authorization instead.
            appState.setNetworkStatus(.permissionPending)
        } else {
            appState.setNetworkStatus(.notConnected)
        }
    }

    public func requestPermissions() {
        guard !hasRequestedPermissions else { return }
        hasRequestedPermissions = true
        locationManager.requestWhenInUseAuthorization()
    }

    nonisolated public func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        Task { @MainActor in
            // Read from the injected manager: it is the source of truth used
            // everywhere else, and tests replace it with a mock.
            let status = self.locationManager.authorizationStatus
            self.locationAuthorizationStatus = status
            self.refreshStatus()

            guard self.appState.isRunning else { return }

            switch status {
            case .authorizedAlways:
                await self.checkConnection()
                if self.appState.isRunning {
                    self.scheduleTimer()
                }
            case .denied, .restricted:
                self.pauseMonitoringForPermission()
            default:
                break
            }
        }
    }
    
    nonisolated public func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in
            print("DEBUG: SSID Changed notification received")
            self.syncConfiguredNetworks()
            
            // 1. If we are programmatically switching, ignore this notification
            if self.isAssociating {
                self.appState.log("Wi-Fi changed during active association. Waiting for connection result.")
                self.refreshStatus()
                return
            }

            // 1b. If an association was requested while another one is in
            // flight, hold until the in-flight attempt finishes so a burst of
            // unlock/SSID events cannot open repeated permission prompts.
            if self.pendingAssociationRequested {
                self.refreshStatus()
                return
            }

            // 2. If monitoring is stopped, just update status
            if !self.appState.isRunning {
                self.refreshStatus()
                return
            }
            
            // 3. Get new SSID
            let previousSSID = self.lastObservedSSID
            self.interface = self.resolvedInterface()
            let newSSID = self.interface?.ssid()
            self.lastObservedSSID = newSSID

            // 4. Analyze the change

            // Case A: Switched to Priority Network (P)
            if newSSID == self.appState.ssidP {
                self.appState.log("Connected to Priority Network (P). Auto-switch active.")
                self.refreshStatus()
                return
            }

            // Everything else, including a disconnect, is classified while
            // serialized: a disconnect is often followed immediately by macOS
            // auto-joining B, and both events must not run competing scans.
            await self.handleObservedNetworkChange(from: previousSSID, to: newSSID)
            self.refreshStatus()
        }
    }
    
    @Published public var nextCheckTime: Date?
    
    public func startMonitoring() async {
        requestPermissions()

        guard !appState.ssidP.isEmpty, !appState.ssidB.isEmpty else {
            stopMonitoring(logMessage: "Error: SSIDs not configured. Auto-switch stopped.")
            return
        }

        resetMonitoringState()
        appState.clearAssociationCooldown()
        appState.isRunning = true
        appState.log("Started monitoring...")
        appState.diagnostic("monitor.start")

        let status = locationManager.authorizationStatus
        locationAuthorizationStatus = status

        policy?.setConfig(ssidP: appState.ssidP, ssidB: appState.ssidB)
        _ = policy?.start(
            permission: Self.policyPermission(for: status),
            currentSSID: activeInterface()?.ssid()
        )

        // Reading the current SSID requires Location Services authorization.
        // Stay in the running state but wait for the delegate callback so
        // granting access from System Settings resumes checks automatically.
        guard status == .authorizedAlways else {
            refreshStatus()
            if status == .denied || status == .restricted {
                appState.log("⚠️ Location permission denied. Grant access in System Settings to read Wi-Fi names.")
            }
            return
        }

        // Run immediately. Scan/association work leaves the main actor inside
        // checkConnection(), so callers can await completion without freezing UI.
        await checkConnection()

        if appState.isRunning {
            scheduleTimer()
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = nil

        guard appState.isRunning else {
            nextCheckTime = nil
            return
        }

        guard hasLocationAuthorization else {
            nextCheckTime = nil
            return
        }

        let interval = appState.checkInterval
        nextCheckTime = Date().addingTimeInterval(interval)

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.appState.isRunning else { return }
                await self.checkConnection()
                // Reschedule if still running
                if self.appState.isRunning {
                    self.scheduleTimer()
                }
            }
        }
    }

    private var hasLocationAuthorization: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return true
        default:
            return false
        }
    }

    /// Keeps the monitoring switch on but stops the timer while Location
    /// Services access is missing. The authorization callback reschedules.
    private func pauseMonitoringForPermission() {
        timer?.invalidate()
        timer = nil
        nextCheckTime = nil
    }

    public func stopMonitoring() {
        manualOverrideVerificationTask?.cancel()
        manualOverrideVerificationTask = nil
        stopMonitoring(logMessage: "Stopped monitoring.")
    }

    private func stopMonitoring(logMessage: String?) {
        let wasRunning = appState.isRunning || timer != nil
        resetMonitoringState()

        if wasRunning, let logMessage {
            appState.log(logMessage)
        }
    }

    /// Stops for a suspected manual switch, then reviews that decision later.
    ///
    /// The review is what keeps a stale CoreWLAN scan cache from leaving the
    /// app permanently stopped after P is lost: if P is really unavailable,
    /// auto-switch resumes on its own and will reconnect when P returns.
    private func stopForManualOverride(logMessage: String) {
        stopMonitoring(logMessage: logMessage)
        scheduleManualOverrideVerification()
    }

    private func scheduleManualOverrideVerification() {
        manualOverrideVerificationTask?.cancel()

        let delay = manualOverrideVerificationDelay
        manualOverrideVerificationTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled, let self else { return }
            guard !self.appState.isRunning else { return }
            guard !self.appState.ssidP.isEmpty, !self.appState.ssidB.isEmpty else { return }

            let priorityVisible = await self.isPriorityVisibleAfterSettling(
                settleDelay: 0,
                attempts: self.manualOverrideVerificationAttempts,
                interval: self.manualOverrideVerificationInterval,
                considerEarlierScans: true,
                confirmsObservedChange: false
            )

            guard !Task.isCancelled, !self.appState.isRunning else { return }

            switch priorityVisible {
            case .some(true):
                self.appState.log("Manual switch confirmed. Auto-switch remains off.")
                return
            case .none:
                // Inconclusive scans cannot prove a P loss either. Stay stopped
                // until the user decides; only confirmed absence auto-resumes.
                self.appState.log("Could not verify P after the manual-switch stop; auto-switch remains off.")
                return
            case .some(false):
                break
            }

            self.appState.log(
                "ℹ️ Priority network is unavailable. Resuming auto-switch after the earlier manual-switch stop."
            )
            self.appState.diagnostic("manualOverride.false_positive_resumed")
            await self.startMonitoring()
        }
    }

    func checkConnection(scannedNetworks: [WiFiNetworkProtocol]? = nil) async {
        guard !isCheckingConnection else {
            return
        }
        isCheckingConnection = true
        defer {
            isCheckingConnection = false
            if needsImmediateRecheck, appState.isRunning {
                needsImmediateRecheck = false
                Task { @MainActor in
                    await self.checkConnection()
                }
            }
        }

        syncConfiguredNetworks()

        let authStatus = locationManager.authorizationStatus
        locationAuthorizationStatus = authStatus

        guard authStatus == .authorizedAlways else {
            refreshStatus()
            if authStatus == .notDetermined {
                requestPermissions()
            } else {
                pauseMonitoringForPermission()
            }
            return
        }

        // Association owns the radio. A timer check must not scan or issue a
        // second association while one is in flight.
        guard !isAssociating else { return }

        // An observed change owns classification. A scheduled check during
        // that window could act on the same stale scan cache and issue a
        // competing association, so let the classification finish first.
        guard !isConfirmingPriorityVisibility else { return }

        guard let interface = activeInterface() else {
            appState.setNetworkStatus(.noInterface)
            appState.interfaceStatus = interfaceLookupSummary()
            appState.log("Error: No Wi-Fi interface found. \(appState.interfaceStatus)")
            appState.diagnostic("interface.missing")
            return
        }

        updateInterfaceStatus(interface)

        let ssidP = appState.ssidP
        let ssidB = appState.ssidB

        guard !ssidP.isEmpty, !ssidB.isEmpty else {
            stopMonitoring(logMessage: "Error: SSIDs not configured. Auto-switch stopped.")
            return
        }

        let currentSSID = interface.ssid()
        // A scheduled check can run just before CoreWLAN delivers `P -> nil`.
        // Do not erase the prior SSID here; only the event handler owns that
        // transition state. Observed-change processing below needs it to tell
        // a real P loss from an unrelated disconnect.
        if !isHandlingObservedChange, !isConfirmingPriorityVisibility {
            lastObservedSSID = currentSSID
        }
        if let currentSSID {
            appState.setNetworkStatus(.connected(ssid: currentSSID, role: networkRole(for: currentSSID)))
        } else {
            appState.setNetworkStatus(.notConnected)
        }

        // If already connected to P, we are good.
        if currentSSID == ssidP {
            appState.clearAssociationCooldown()
            return
        }

        do {
            let priorityNetwork: WiFiNetworkProtocol?
            let backupNetwork: WiFiNetworkProtocol?
            if let scannedNetworks {
                priorityNetwork = bestNetwork(named: ssidP, in: scannedNetworks)
                backupNetwork = bestNetwork(named: ssidB, in: scannedNetworks)
            } else {
                appState.log("Scanning for configured networks...")
                appState.diagnostic("scan.configured.start")
                priorityNetwork = try await scanNetwork(named: ssidP)

                // The user can edit either SSID while a scan is in flight.
                // Never act on a stale target: re-run the whole decision with
                // the current configuration instead.
                guard configurationMatches(ssidP, ssidB) else {
                    needsImmediateRecheck = true
                    return
                }

                backupNetwork = priorityNetwork == nil ? try await scanNetwork(named: ssidB) : nil
                appState.diagnostic(
                    "scan.configured.success priorityVisible=\(priorityNetwork != nil) backupVisible=\(backupNetwork != nil)"
                )
            }

            guard appState.isRunning else { return }
            guard configurationMatches(ssidP, ssidB) else {
                needsImmediateRecheck = true
                return
            }

            // Check for P
            if priorityNetwork != nil {
                appState.log("Found network P (\(ssidP)). Connecting...")
                appState.diagnostic("priority.visible association.start")
                await connect(networkNamed: ssidP, password: appState.passwordP)
                return
            }

            // If P not found, and not connected to B, check for B
            if currentSSID != ssidB {
                if backupNetwork != nil {
                    appState.log("Network P not found. Found network B (\(ssidB)). Connecting...")
                    await connect(networkNamed: ssidB, password: appState.passwordB)
                    return
                } else {
                    appState.log("Neither network P nor B found.")
                }
            } else {
                appState.log("Connected to backup network B (\(ssidB)). Network P not found.")
            }

        } catch {
            appState.log("Scan failed: \(Self.errorDescription(error))")
            let nsError = error as NSError
            appState.diagnostic("scan.failure domain=\(nsError.domain) code=\(nsError.code)")
        }
    }

    private func configurationMatches(_ ssidP: String, _ ssidB: String) -> Bool {
        appState.ssidP == ssidP && appState.ssidB == ssidB
    }

    private func networkRole(for ssid: String) -> AppState.ConnectedNetworkType {
        if ssid == appState.ssidP {
            return .priority
        }
        if ssid == appState.ssidB {
            return .backup
        }
        return .other
    }

    /// Diagnostics must not publish the user's SSID. A short role tag is
    /// enough to correlate an association attempt with the configured slots.
    private func associationRole(for ssid: String) -> String {
        if ssid == appState.ssidP {
            return "P"
        }
        if ssid == appState.ssidB {
            return "B"
        }
        return "other"
    }

    private func failoverToBackupIfAvailable() async {
        guard appState.isRunning else { return }

        do {
            let backupNetwork = try await scanNetwork(named: appState.ssidB)
            if backupNetwork != nil {
                appState.log("Found backup network B (\(appState.ssidB)). Connecting...")
                await connect(networkNamed: appState.ssidB, password: appState.passwordB)
            } else {
                appState.log("Backup network B not found. Letting macOS choose a network.")
            }
        } catch {
            appState.log("Backup scan failed: \(Self.errorDescription(error))")
        }
    }

    private func handleObservedNetworkChange(from previousSSID: String?, to newSSID: String?) async {
        if isHandlingObservedChange {
            // Classification scans can take seconds. Keep only the newest
            // event instead of dropping it, then process it after the current
            // classification completes.
            pendingObservedChange = ObservedChange(previousSSID: previousSSID, ssid: newSSID)
            return
        }

        isHandlingObservedChange = true
        var current = ObservedChange(previousSSID: previousSSID, ssid: newSSID)

        while true {
            await processObservedNetworkChange(from: current.previousSSID, to: current.ssid)

            guard appState.isRunning, let pending = pendingObservedChange else {
                break
            }
            pendingObservedChange = nil
            current = pending
        }

        pendingObservedChange = nil
        isHandlingObservedChange = false
    }

    private func processObservedNetworkChange(from previousSSID: String?, to newSSID: String?) async {
        // Disconnected. If P just disappeared, proactively connect to B
        // before macOS roams to some other saved network. Otherwise this is a
        // transient state during a manual switch and we should wait for the
        // follow-up SSID event instead of acting prematurely.
        if newSSID == nil {
            if previousSSID == appState.ssidP {
                switch await isPriorityVisibleAfterSettling() {
                case .some(true):
                    appState.log("Disconnected from P while it is still visible. Waiting for the manual switch to complete.")
                case .some(false):
                    appState.log("Priority network lost. Connecting to backup network B.")
                    await failoverToBackupIfAvailable()
                case .none:
                    appState.log("Could not verify whether P is still available. Keeping the current state.")
                    appState.diagnostic("classification.priority_visibility_unknown")
                }
            } else {
                appState.log("Network disconnected. Waiting...")
            }
            return
        }

        // Switched to the configured backup network. An association this app
        // itself just initiated is definitely an automatic failover. Otherwise
        // wait for the radio to settle and rescan P: if P is still visible the
        // user manually left it (stop), and if P is gone macOS auto-joined B
        // after P was lost (keep monitoring and recover to P when it returns).
        if newSSID == appState.ssidB {
            if isRecentProgrammaticBackup {
                appState.log("ℹ️ Automatic failover to B (app initiated). Auto-switch continues.")
                await checkConnection()
            } else {
                switch await isPriorityVisibleAfterSettling() {
                case .some(true):
                    appState.log("⚠️ Switched to backup network while P is still available. Assuming manual override.")
                    stopForManualOverride(
                        logMessage: "⚠️ Manual switch to backup network (\(appState.ssidB)). Auto-switch stopped."
                    )
                case .some(false):
                    appState.log("ℹ️ P was lost; system joined backup network B. Auto-switch continues.")
                    await checkConnection()
                case .none:
                    appState.log("Could not verify P after joining B; keeping monitoring active.")
                    appState.diagnostic("classification.priority_visibility_unknown")
                }
            }
            return
        }

        // Switched to the previous backup configuration after the user changed
        // the B SSID: keep monitoring and reconnect to the newly configured B.
        if newSSID == previousBackupSSID && newSSID != appState.ssidB {
            appState.log(
                "ℹ️ Switched to previous backup network (\(newSSID ?? "Unknown")). Reconnecting to current backup configuration."
            )
            do {
                let backupNetwork = try await scanNetwork(named: appState.ssidB)
                await recoverToConfiguredBackupIfNeeded(
                    from: newSSID,
                    networks: [backupNetwork].compactMap { $0 }
                )
            } catch {
                appState.log(
                    "⚠️ Could not verify previous backup network: \(Self.errorDescription(error))"
                )
            }
            return
        }

        // Any other network is unmanaged. Wait for the radio to settle and
        // rescan P: P visible means a manual switch (stop); P missing means the
        // system fell back after P was lost (try to recover to B and continue).
        switch await isPriorityVisibleAfterSettling() {
        case .some(true):
            stopForManualOverride(
                logMessage: "⚠️ Switched to unmanaged network (\(newSSID ?? "Unknown")). Auto-switch stopped."
            )
        case .some(false):
            appState.log(
                "ℹ️ P was lost after switch to \(newSSID ?? "Unknown"). Treating it as system fallback."
            )
            do {
                let backupNetwork = try await scanNetwork(named: appState.ssidB)
                await recoverToConfiguredBackupIfNeeded(
                    from: newSSID,
                    networks: [backupNetwork].compactMap { $0 }
                )
            } catch {
                appState.log(
                    "⚠️ Could not recover backup network: \(Self.errorDescription(error))"
                )
            }
        case .none:
            appState.log("Could not verify P after an unmanaged network change; keeping monitoring active.")
            appState.diagnostic("classification.priority_visibility_unknown")
        }
    }

    /// Repeatedly probes for P after an observed SSID change.
    ///
    /// A single immediate scan cannot prove that P is available: CoreWLAN may
    /// serve a system scan cache that still lists the network the radio just
    /// lost, and that stale entry is exactly what made a lost P look like a
    /// manual switch. The result of the newest successful scan wins, so a
    /// cached hit gets a chance to be replaced by a real scan before anything
    /// stops monitoring.
    private func isPriorityVisibleAfterSettling(
        settleDelay: TimeInterval? = nil,
        attempts: Int? = nil,
        interval: TimeInterval? = nil,
        considerEarlierScans: Bool = false,
        confirmsObservedChange: Bool = true
    ) async -> Bool? {
        if confirmsObservedChange {
            isConfirmingPriorityVisibility = true
        }
        defer {
            if confirmsObservedChange {
                isConfirmingPriorityVisibility = false
            }
        }

        let delay = settleDelay ?? observedChangeSettleDelay
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }

        let attemptCount = max(attempts ?? observedChangeRescanAttempts, 1)
        let rescanInterval = interval ?? observedChangeRescanInterval
        var lastSuccessfulObservation: Bool?
        var sawPriority = false

        for attempt in 0..<attemptCount {
            if attempt > 0, rescanInterval > 0 {
                try? await Task.sleep(for: .seconds(rescanInterval))
            }
            if confirmsObservedChange, !appState.isRunning {
                return nil
            }

            // Re-resolve the interface so a scan does not reuse a CoreWLAN
            // snapshot created before the radio changed networks.
            if let resolved = resolvedInterface() {
                interface = resolved
            }

            do {
                let visible = try await scanNetwork(named: appState.ssidP) != nil
                lastSuccessfulObservation = visible
                sawPriority = sawPriority || visible
                appState.diagnostic(
                    "classification.scan attempt=\(attempt + 1) priorityVisible=\(visible)"
                )
            } catch {
                appState.diagnostic("classification.scan attempt=\(attempt + 1) failed")
            }
        }

        if considerEarlierScans, sawPriority {
            return true
        }
        // `nil` means every scan failed. It must not be collapsed into
        // `false`, which would claim that P was proven unavailable.
        return lastSuccessfulObservation
    }

    private var isRecentProgrammaticBackup: Bool {
        let now = Date()

        // A timed-out association may still complete later. Keep honoring its
        // intent until the underlying CoreWLAN call returns, but only for a
        // bounded grace period.
        if let intent = activeProgrammaticAssociation,
           intent.ssid == appState.ssidB,
           intent.generation == associationGeneration,
           now <= intent.deadline {
            return true
        }

        guard let lastProgrammaticBackupAt else {
            return false
        }
        return now.timeIntervalSince(lastProgrammaticBackupAt) <= programmaticBackupWindow
    }

    public func getAvailableNetworks() async -> [String] {
        do {
            let networks = try await scanNetworks()
            let ssids = networks
                .compactMap { $0.ssid }
                .filter { !$0.isEmpty }
            
            let uniqueSSIDs = Array(Set(ssids)).sorted()
            return uniqueSSIDs
        } catch {
            appState.log("❌ Scan error: \(Self.errorDescription(error))")
            if error.localizedDescription.contains("location") {
                 appState.log("💡 Try checking Location Services permissions again.")
            }
            return []
        }
    }
    
    private func connect(networkNamed ssid: String, password: String) async {
        guard !ssid.isEmpty else { return }

        let role = associationRole(for: ssid)
        guard appState.hasActiveAssociationCooldown(for: ssid) == false else {
            appState.diagnostic("association.skipped role=\(role) cooldownActive=true")
            return
        }

        guard let interface = activeInterface() else { return }

        if interface.ssid() == ssid {
            appState.diagnostic("association.skipped alreadyConnected=true role=\(role)")
            return
        }

        guard !isAssociating else {
            pendingAssociationRequested = true
            return
        }

        // Every association gets a token. Stopping (or restarting) monitoring
        // invalidates in-flight attempts so a late completion cannot apply a
        // cooldown or status change to the new session.
        associationGeneration &+= 1
        let generation = associationGeneration
        let policyGeneration = policy?.associationStarted(ssid: ssid)

        appState.diagnostic("association.attempt role=\(role)")
        isAssociating = true
        defer {
            isAssociating = false
            if generation == associationGeneration {
                schedulePendingAssociationIfNeeded()
            }
        }

        // Record intent before the association completes so an SSID event that
        // lands on B after the association is recognized as an app-initiated
        // failover rather than a manual override.
        activeProgrammaticAssociation = nil
        let timeout = associationTimeout
        if ssid == appState.ssidB {
            lastProgrammaticBackupAt = Date()
            activeProgrammaticAssociation = ProgrammaticAssociationIntent(
                ssid: ssid,
                generation: generation,
                deadline: Date().addingTimeInterval(timeout + 60)
            )
        }

        let operation = WiFiOperation(interface: interface)
        let result = await withCheckedContinuation { continuation in
            let completion = AssociationContinuation(continuation)

            Task.detached(priority: .userInitiated) { [weak self] in
                let result: AssociationResult
                do {
                    // Keep the CWNetwork object on the same CoreWLAN operation
                    // and thread that created it. Passing it from a scan task to
                    // a later association task can yield kCWInvalidParameterErr.
                    try operation.scanAndAssociate(networkNamed: ssid, password: password)
                    result = .succeeded
                } catch {
                    let nsError = error as NSError
                    result = .failed(
                        domain: nsError.domain,
                        code: nsError.code,
                        description: nsError.localizedDescription
                    )
                }

                if !completion.resume(returning: result) {
                    // The UI already timed out, but CoreWLAN cannot be
                    // cancelled. Let the manager know when the real call
                    // finishes so a late success is still attributed to us.
                    Task { @MainActor [weak self] in
                        self?.handleLateAssociationCompletion(
                            result,
                            ssid: ssid,
                            generation: generation,
                            policyGeneration: policyGeneration
                        )
                    }
                }
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                completion.resume(returning: .timedOut)
            }
        }

        guard generation == associationGeneration else {
            if activeProgrammaticAssociation?.generation == generation {
                activeProgrammaticAssociation = nil
            }
            appState.diagnostic("association.stale")
            return
        }

        switch result {
        case .succeeded:
            if let policyGeneration {
                _ = policy?.associationResult(
                    ssid: ssid,
                    generation: policyGeneration,
                    outcome: .success
                )
            }
            activeProgrammaticAssociation = nil
            if !isHandlingObservedChange, !isConfirmingPriorityVisibility {
                lastObservedSSID = ssid
            }
            if ssid == appState.ssidP {
                lastProgrammaticBackupAt = nil
            } else if ssid == appState.ssidB {
                // Refresh the window from completion, not from the scan that
                // preceded a slow association.
                lastProgrammaticBackupAt = Date()
            }
            appState.clearAssociationCooldown()
            appState.log("Successfully connected to \(ssid).")
            appState.diagnostic("association.success")
            // Do not call refreshStatus() here: CoreWLAN may not report the new
            // SSID immediately, which would briefly downgrade the status we
            // just confirmed. The next scheduled check reconciles it.
            appState.setNetworkStatus(.connected(ssid: ssid, role: networkRole(for: ssid)))
        case .timedOut:
            if let policyGeneration {
                _ = policy?.associationResult(
                    ssid: ssid,
                    generation: policyGeneration,
                    outcome: .timeout
                )
            }
            if ssid == appState.ssidB {
                lastProgrammaticBackupAt = nil
                // Keep `activeProgrammaticAssociation` alive until the real
                // CoreWLAN call returns (or its bounded grace period expires).
            } else {
                activeProgrammaticAssociation = nil
            }
            appState.beginAssociationCooldown(duration: associationCooldown, for: ssid)
            appState.log("Failed to connect to \(ssid): timed out after \(Int(timeout.rounded())) seconds.")
            appState.diagnostic("association.timeout cooldown=\(associationCooldown)")
            refreshStatus()
        case let .failed(domain, code, description):
            if let policyGeneration {
                _ = policy?.associationResult(
                    ssid: ssid,
                    generation: policyGeneration,
                    outcome: .failure
                )
            }
            activeProgrammaticAssociation = nil
            if ssid == appState.ssidB {
                lastProgrammaticBackupAt = nil
            }
            appState.beginAssociationCooldown(duration: associationCooldown, for: ssid)
            appState.log("Failed to connect to \(ssid): \(description) [\(domain) \(code)]")
            appState.diagnostic("association.failure domain=\(domain) code=\(code) cooldown=\(associationCooldown)")
            refreshStatus()
        }
    }

    private func handleLateAssociationCompletion(
        _ result: AssociationResult,
        ssid: String,
        generation: UInt64,
        policyGeneration: UInt64?
    ) {
        guard generation == associationGeneration else { return }
        guard let intent = activeProgrammaticAssociation,
              intent.ssid == ssid,
              intent.generation == generation
        else {
            return
        }

        if let policyGeneration {
            let succeeded: Bool
            if case .succeeded = result {
                succeeded = true
            } else {
                succeeded = false
            }
            _ = policy?.lateAssociationResult(
                ssid: ssid,
                generation: policyGeneration,
                succeeded: succeeded
            )
        }

        activeProgrammaticAssociation = nil

        switch result {
        case .succeeded:
            if !isHandlingObservedChange, !isConfirmingPriorityVisibility {
                lastObservedSSID = ssid
            }
            if ssid == appState.ssidB {
                lastProgrammaticBackupAt = Date()
            }
            appState.clearAssociationCooldown()
            appState.setNetworkStatus(.connected(ssid: ssid, role: networkRole(for: ssid)))
            appState.log("Successfully connected to \(ssid) after the initial wait.")
            appState.diagnostic("association.late_success")
        case .timedOut, .failed:
            // The cooldown was already applied when the UI timed out.
            appState.diagnostic("association.late_failure")
        }
    }

    private func schedulePendingAssociationIfNeeded() {
        guard pendingAssociationRequested else { return }
        pendingAssociationRequested = false
        guard appState.isRunning else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + associationRetryDelay) {
            Task { @MainActor in
                guard self.appState.isRunning else { return }
                await self.checkConnection()
            }
        }
    }

    private func resetMonitoringState() {
        _ = policy?.stop()
        manualOverrideVerificationTask?.cancel()
        manualOverrideVerificationTask = nil
        timer?.invalidate()
        timer = nil
        nextCheckTime = nil
        pendingAssociationRequested = false
        pendingObservedChange = nil
        activeProgrammaticAssociation = nil
        needsImmediateRecheck = false
        associationGeneration &+= 1
        lastProgrammaticBackupAt = nil
        appState.isRunning = false
    }

    private func handleCheckIntervalChange() {
        guard appState.isRunning else { return }
        scheduleTimer()
    }

    private func scanNetworks() async throws -> [WiFiNetworkProtocol] {
        // User-initiated scan: refresh the interface cache instead of trusting
        // an interface resolved before a hardware change.
        self.interface = resolvedInterface()
        guard let interface = self.interface else {
            throw WifiManagerError.noInterface
        }

        let operation = WiFiOperation(interface: interface)
        let result = try await Task.detached(priority: .userInitiated) {
            try operation.scan()
        }.value
        return result.networks
    }

    private func scanNetwork(named ssid: String) async throws -> WiFiNetworkProtocol? {
        guard !ssid.isEmpty else { return nil }

        guard let interface = activeInterface() else {
            throw WifiManagerError.noInterface
        }

        let operation = WiFiOperation(interface: interface)
        let ssidData = Data(ssid.utf8)
        let result = try await Task.detached(priority: .userInitiated) {
            try operation.scan(ssid: ssidData)
        }.value

        // A sandboxed process can receive usable CWNetwork objects while their
        // ssid property is privacy-redacted. Because this was an exact SSID
        // scan, every returned object is a candidate for the requested network.
        return result.networks.max(by: { $0.rssiValue < $1.rssiValue })
    }

    private func bestNetwork(named ssid: String, in networks: [WiFiNetworkProtocol]) -> WiFiNetworkProtocol? {
        networks
            .filter { $0.ssid == ssid }
            .max(by: { $0.rssiValue < $1.rssiValue })
    }

    private func syncConfiguredNetworks() {
        policy?.setConfig(ssidP: appState.ssidP, ssidB: appState.ssidB)

        guard trackedBackupSSID != appState.ssidB else {
            return
        }

        if !trackedBackupSSID.isEmpty {
            previousBackupSSID = trackedBackupSSID
        }
        trackedBackupSSID = appState.ssidB
    }

    private func recoverToConfiguredBackupIfNeeded(from currentSSID: String?, networks: [WiFiNetworkProtocol]) async {
        let currentBackupSSID = appState.ssidB

        guard !currentBackupSSID.isEmpty else {
            appState.log("Current backup network is not configured.")
            return
        }

        if currentSSID == currentBackupSSID {
            appState.log("Connected to current backup network B (\(currentBackupSSID)). Auto-switch continues.")
            return
        }

        if bestNetwork(named: currentBackupSSID, in: networks) != nil {
            appState.log("Priority network lost. Reconnecting to current backup network (\(currentBackupSSID)).")
            await connect(networkNamed: currentBackupSSID, password: appState.passwordB)
            return
        }

        appState.log("Current backup network (\(currentBackupSSID)) not found. Waiting for next check.")
    }

    /// The interface cached by the last resolution. Scanning and association
    /// reuse it so a single check does not enumerate every system interface
    /// several times; `refreshStatus`/`checkConnection`/SSID events refresh it.
    private func activeInterface() -> WiFiInterfaceProtocol? {
        if let interface {
            return interface
        }

        let resolved = resolvedInterface()
        interface = resolved
        return resolved
    }

    private func resolvedInterface() -> WiFiInterfaceProtocol? {
        Self.resolveInterface(from: client)
    }

    private static func resolveInterface(from client: WiFiClientProtocol) -> WiFiInterfaceProtocol? {
        // The common path: the default interface is associated. Avoid the
        // expensive SystemConfiguration enumeration unless it is needed.
        let defaultInterface = client.interface()
        if let defaultInterface, defaultInterface.ssid() != nil {
            return defaultInterface
        }

        let availableInterfaces = client.interfacesProtocol()
        if let connectedInterface = availableInterfaces.first(where: { $0.ssid() != nil }) {
            return connectedInterface
        }

        if let defaultInterface {
            return defaultInterface
        }
        if let firstInterface = availableInterfaces.first {
            return firstInterface
        }

        // Last resort: names reported by SystemConfiguration, which can still
        // find the BSD interface for a sandboxed process.
        for name in client.interfaceNamesProtocol() {
            if let namedInterface = client.interfaceProtocol(withName: name) {
                return namedInterface
            }
        }
        return nil
    }

    private func updateInterfaceStatus(_ interface: WiFiInterfaceProtocol) {
        let name = interface.interfaceNameProtocol() ?? "unknown"
        let power = interface.isPowerOnProtocol() ? "on" : "off"
        appState.interfaceStatus = "Interface: \(name) · Wi-Fi: \(power)"
        appState.diagnostic("interface.resolved name=\(name) power=\(power)")
    }

    private func interfaceLookupSummary() -> String {
        let listedCount = client.interfacesProtocol().count
        let names = client.interfaceNamesProtocol()
        let nameSummary = names.isEmpty ? "none" : names.joined(separator: ", ")
        return "CoreWLAN listed \(listedCount); detected names: \(nameSummary)."
    }

    private static func policyPermission(
        for status: CLAuthorizationStatus
    ) -> WifiPolicyPermission {
        switch status {
        case .authorizedAlways:
            return .authorized
        case .denied, .restricted:
            return .denied
        default:
            return .unknown
        }
    }

    private static func errorDescription(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.localizedDescription) [\(nsError.domain) \(nsError.code)]"
    }
}

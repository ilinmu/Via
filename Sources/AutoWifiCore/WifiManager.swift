import Foundation
import CoreWLAN
import CoreLocation

// MARK: - Protocols

public protocol WiFiClientProtocol: AnyObject {
    var delegate: AnyObject? { get set }
    func interface() -> WiFiInterfaceProtocol?
    func startMonitoringEvent(with type: CWEventType) throws
}

public protocol WiFiNetworkProtocol: AnyObject {
    var ssid: String? { get }
    var rssiValue: Int { get }
}

public protocol WiFiInterfaceProtocol: AnyObject {
    func ssid() -> String?
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
}

extension CWInterface: WiFiInterfaceProtocol {
    public func scanForNetworksProtocol(withSSID ssid: Data?) throws -> [WiFiNetworkProtocol] {
        let networks = try self.scanForNetworks(withSSID: ssid)
        return networks.map { $0 as WiFiNetworkProtocol }
    }
    
    public func associateNetwork(_ network: WiFiNetworkProtocol, password: String) throws {
        guard let cwNetwork = network as? CWNetwork else {
            throw NSError(domain: "AutoWifi", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid network type"])
        }
        try self.associate(to: cwNetwork, password: password)
    }
}

extension CLLocationManager: LocationManagerProtocol {}

enum WifiManagerError: LocalizedError {
    case noInterface

    var errorDescription: String? {
        switch self {
        case .noInterface:
            return "No Wi-Fi interface found."
        }
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
    
    private var isSwitchingNetwork = false
    private var lastObservedSSID: String?
    private var trackedBackupSSID: String
    private var previousBackupSSID: String?
    private var lastManagedDisconnectAt: Date?
    private let managedDisconnectWindow: TimeInterval = 12
    
    public init(appState: AppState,
                client: WiFiClientProtocol = CWWiFiClient.shared(),
                locationManager: LocationManagerProtocol = CLLocationManager()) {
        self.appState = appState
        self.client = client
        self.locationManager = locationManager
        self.trackedBackupSSID = appState.ssidB
        super.init()
        
        self.interface = client.interface()
        self.locationManager.delegate = self
        self.client.delegate = self
        
        do {
            try self.client.startMonitoringEvent(with: .ssidDidChange)
        } catch {
            print("Failed to start monitoring SSID changes: \(error)")
        }
        
        // Initial status check
        Task { @MainActor in
            self.refreshStatus()
        }
    }
    
    // ... (refreshStatus and requestPermissions remain same)
    
    public func refreshStatus() {
        syncConfiguredNetworks()
        let authStatus = locationManager.authorizationStatus
        
        if authStatus == .denied || authStatus == .restricted {
            appState.currentNetworkName = "Location Permission Denied"
            appState.connectedNetworkType = .none
            appState.log("⚠️ Location permission denied. Cannot read SSID.")
            return
        }
        
        // Update interface reference in case it changed
        self.interface = client.interface()
        
        if let interface = self.interface {
            let currentSSID = interface.ssid()
            lastObservedSSID = currentSSID
            if let ssid = currentSSID {
                appState.currentNetworkName = ssid
            } else {
                // Try to diagnose why SSID is nil
                if authStatus == .notDetermined {
                    appState.currentNetworkName = LocalizationManager.shared.localizedString("permission_pending")
                    requestPermissions()
                } else {
                    appState.currentNetworkName = "Not Connected"
                }
            }
            
            // Update network type
            if let ssid = currentSSID {
                if ssid == appState.ssidP {
                    appState.connectedNetworkType = .priority
                    clearManagedDisconnectContext()
                } else if ssid == appState.ssidB {
                    appState.connectedNetworkType = .backup
                    clearManagedDisconnectContext()
                } else {
                    appState.connectedNetworkType = .other
                }
            } else {
                appState.connectedNetworkType = .none
            }
            
        } else {
            appState.currentNetworkName = "No Interface"
            appState.connectedNetworkType = .none
        }
    }
    
    public func requestPermissions() {
        locationManager.requestWhenInUseAuthorization()
    }

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.refreshStatus()
        }
    }
    
    nonisolated public func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in
            print("DEBUG: SSID Changed notification received")
            self.syncConfiguredNetworks()
            
            // 1. If we are programmatically switching, ignore this notification
            if self.isSwitchingNetwork {
                self.checkConnection()
                return
            }
            
            // 2. If monitoring is stopped, just update status
            if !self.appState.isRunning {
                self.refreshStatus()
                return
            }
            
            // 3. Get new SSID
            let previousSSID = self.lastObservedSSID
            self.interface = self.client.interface()
            let newSSID = self.interface?.ssid()
            self.lastObservedSSID = newSSID
            
            // 4. Analyze the change
            
            // Case A: Switched to Priority Network (P)
            if newSSID == self.appState.ssidP {
                self.clearManagedDisconnectContext()
                self.appState.log("Connected to Priority Network (P). Auto-switch active.")
                self.refreshStatus()
                return
            }
            
            // Case B: Disconnected (nil)
            // This is often a transient state during switching. We should NOT stop monitoring.
            if newSSID == nil {
                if self.isManagedSSID(previousSSID) {
                    self.lastManagedDisconnectAt = Date()
                }
                self.appState.log("Network disconnected. Waiting...")
                self.refreshStatus()
                return
            }
            
            // Case C/D: Switched away from priority network.
            self.handleObservedNetworkChange(to: newSSID)
            self.refreshStatus()
        }
    }
    
    @Published public var nextCheckTime: Date?
    @Published public var currentCheckInterval: TimeInterval = AppState.defaultCheckInterval
    
    public func startMonitoring() {
        requestPermissions()

        guard !appState.ssidP.isEmpty, !appState.ssidB.isEmpty else {
            appState.log("Error: SSIDs not configured.")
            return
        }

        resetMonitoringState()
        appState.isRunning = true
        appState.log("Started monitoring...")
        
        // Run immediately
        checkConnection()
        
        if appState.isRunning {
            scheduleTimer()
        }
    }
    
    private func scheduleTimer() {
        let interval = appState.checkInterval
        timer?.invalidate()
        currentCheckInterval = interval
        nextCheckTime = Date().addingTimeInterval(interval)
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.checkConnection()
                // Reschedule if still running
                if self?.appState.isRunning == true {
                    self?.scheduleTimer()
                }
            }
        }
    }
    
    public func stopMonitoring() {
        stopMonitoring(logMessage: "Stopped monitoring.")
    }

    private func stopMonitoring(logMessage: String?) {
        let wasRunning = appState.isRunning || timer != nil
        resetMonitoringState()

        if wasRunning, let logMessage {
            appState.log(logMessage)
        }
    }
    
    private func checkConnection(scannedNetworks: [WiFiNetworkProtocol]? = nil) {
        syncConfiguredNetworks()
        self.interface = client.interface()

        guard let interface = self.interface else {
            appState.connectedNetworkType = .none
            appState.currentNetworkName = "No Interface"
            appState.log("Error: No Wi-Fi interface found.")
            return
        }

        let ssidP = appState.ssidP
        let ssidB = appState.ssidB
        
        if ssidP.isEmpty || ssidB.isEmpty {
            appState.log("Error: SSIDs not configured.")
            return
        }
        
        let currentSSID = interface.ssid()
        lastObservedSSID = currentSSID
        appState.currentNetworkName = currentSSID ?? "Not Connected"
        
        // Update network type
        if let ssid = currentSSID {
            if ssid == ssidP {
                appState.connectedNetworkType = .priority
                clearManagedDisconnectContext()
            } else if ssid == ssidB {
                appState.connectedNetworkType = .backup
                clearManagedDisconnectContext()
            } else {
                appState.connectedNetworkType = .other
            }
        } else {
            appState.connectedNetworkType = .none
        }
        
        // If already connected to P, we are good.
        if currentSSID == ssidP {
            return
        }
        
        do {
            let networks: [WiFiNetworkProtocol]
            if let scannedNetworks {
                networks = scannedNetworks
            } else {
                appState.log("Scanning...")
                networks = try scanNetworks()
            }
            
            // Check for P
            if let targetNetworkP = bestNetwork(named: ssidP, in: networks) {
                appState.log("Found network P (\(ssidP)). Connecting...")
                connect(to: targetNetworkP, password: appState.passwordP)
                return
            }
            
            // If P not found, and not connected to B, check for B
            if currentSSID != ssidB {
                if let targetNetworkB = bestNetwork(named: ssidB, in: networks) {
                    appState.log("Network P not found. Found network B (\(ssidB)). Connecting...")
                    connect(to: targetNetworkB, password: appState.passwordB)
                    return
                } else {
                    appState.log("Neither network P nor B found.")
                }
            } else {
                appState.log("Connected to backup network B (\(ssidB)). Network P not found.")
            }
            
        } catch {
            appState.log("Scan failed: \(error.localizedDescription)")
        }
    }

    private func handleObservedNetworkChange(to newSSID: String?) {
        do {
            let networks = try scanNetworks()
            let isPriorityAvailable = bestNetwork(named: appState.ssidP, in: networks) != nil
            let hasRecentManagedDisconnect = self.hasRecentManagedDisconnect
            let isLegacyBackup = newSSID == previousBackupSSID && newSSID != appState.ssidB

            if newSSID == appState.ssidB {
                appState.log("Switched to Backup Network (B). Checking cause...")

                if hasRecentManagedDisconnect {
                    appState.log("ℹ️ Managed network was just lost. Keeping auto-switch active.")
                } else if isPriorityAvailable {
                    appState.log("ℹ️ Priority network is available again. Switching back while keeping auto-switch active.")
                } else {
                    appState.log("ℹ️ Network P not found. Assuming system fallback. Auto-switch continues.")
                }

                // A configured backup is part of the automatic failover flow, so
                // connecting to it must never be treated as a manual override. Run
                // the normal priority-first check with this scan result: it returns
                // to P immediately when P is already visible, otherwise it remains
                // on B and the scheduled checks continue.
                checkConnection(scannedNetworks: networks)
                return
            }

            if isLegacyBackup {
                appState.log(
                    "ℹ️ Switched to previous backup network (\(newSSID ?? "Unknown")). Reconnecting to current backup configuration."
                )
                recoverToConfiguredBackupIfNeeded(from: newSSID, networks: networks)
            } else if hasRecentManagedDisconnect {
                appState.log(
                    "ℹ️ Managed network was just lost before switching to \(newSSID ?? "Unknown"). Auto-switch continues."
                )
                recoverToConfiguredBackupIfNeeded(from: newSSID, networks: networks)
            } else if isPriorityAvailable {
                stopMonitoring(
                    logMessage: "⚠️ Switched to unmanaged network (\(newSSID ?? "Unknown")). Priority network is still available, assuming manual override."
                )
            } else {
                appState.log(
                    "ℹ️ Network P not found after switch to \(newSSID ?? "Unknown"). Treating it as system fallback."
                )
                recoverToConfiguredBackupIfNeeded(from: newSSID, networks: networks)
            }
        } catch {
            appState.log(
                "⚠️ Could not verify why Wi-Fi changed to \(newSSID ?? "Unknown"): \(error.localizedDescription)"
            )
        }
    }
    
    public func getAvailableNetworks() async -> [String] {
        do {
            let networks = try scanNetworks()
            let ssids = networks
                .compactMap { $0.ssid }
                .filter { !$0.isEmpty }
            
            let uniqueSSIDs = Array(Set(ssids)).sorted()
            return uniqueSSIDs
        } catch {
            appState.log("❌ Scan error: \(error.localizedDescription)")
            if error.localizedDescription.contains("location") {
                 appState.log("💡 Try checking Location Services permissions again.")
            }
            return []
        }
    }
    
    private func connect(to network: WiFiNetworkProtocol, password: String) {
        guard let interface = self.interface else { return }
        
        self.isSwitchingNetwork = true
        // Reset flag after a delay to cover notification window
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isSwitchingNetwork = false
        }
        
        do {
            try interface.associateNetwork(network, password: password)
            lastObservedSSID = network.ssid
            if network.ssid == appState.ssidP || network.ssid == appState.ssidB {
                clearManagedDisconnectContext()
            }
            appState.log("Successfully connected to \(network.ssid ?? "Unknown").")
            refreshStatus()
        } catch {
            appState.log("Failed to connect to \(network.ssid ?? "Unknown"): \(error.localizedDescription)")
        }
    }

    private func resetMonitoringState() {
        timer?.invalidate()
        timer = nil
        nextCheckTime = nil
        appState.isRunning = false
        clearManagedDisconnectContext()
    }

    private func scanNetworks() throws -> [WiFiNetworkProtocol] {
        self.interface = client.interface()

        guard let interface = self.interface else {
            throw WifiManagerError.noInterface
        }

        return try interface.scanForNetworksProtocol(withSSID: nil)
    }

    private func bestNetwork(named ssid: String, in networks: [WiFiNetworkProtocol]) -> WiFiNetworkProtocol? {
        networks
            .filter { $0.ssid == ssid }
            .max(by: { $0.rssiValue < $1.rssiValue })
    }

    private var hasRecentManagedDisconnect: Bool {
        guard let lastManagedDisconnectAt else {
            return false
        }

        return Date().timeIntervalSince(lastManagedDisconnectAt) <= managedDisconnectWindow
    }

    private func isManagedSSID(_ ssid: String?) -> Bool {
        guard let ssid else {
            return false
        }

        return ssid == appState.ssidP || ssid == appState.ssidB || ssid == previousBackupSSID
    }

    private func syncConfiguredNetworks() {
        guard trackedBackupSSID != appState.ssidB else {
            return
        }

        if !trackedBackupSSID.isEmpty {
            previousBackupSSID = trackedBackupSSID
        }
        trackedBackupSSID = appState.ssidB
    }

    private func clearManagedDisconnectContext() {
        lastManagedDisconnectAt = nil
    }

    private func recoverToConfiguredBackupIfNeeded(from currentSSID: String?, networks: [WiFiNetworkProtocol]) {
        let currentBackupSSID = appState.ssidB

        guard !currentBackupSSID.isEmpty else {
            appState.log("Current backup network is not configured.")
            return
        }

        if currentSSID == currentBackupSSID {
            appState.log("Connected to current backup network B (\(currentBackupSSID)). Auto-switch continues.")
            clearManagedDisconnectContext()
            return
        }

        if let targetNetworkB = bestNetwork(named: currentBackupSSID, in: networks) {
            appState.log("Priority network lost. Reconnecting to current backup network (\(currentBackupSSID)).")
            connect(to: targetNetworkB, password: appState.passwordB)
            return
        }

        appState.log("Current backup network (\(currentBackupSSID)) not found. Waiting for next check.")
    }
}

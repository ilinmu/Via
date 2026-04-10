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

// MARK: - WifiManager

@MainActor
public class WifiManager: NSObject, ObservableObject, CLLocationManagerDelegate, CWEventDelegate {
    private var client: WiFiClientProtocol
    private var interface: WiFiInterfaceProtocol?
    private var timer: Timer?
    private var appState: AppState
    private var locationManager: LocationManagerProtocol
    
    private var isSwitchingNetwork = false
    
    public init(appState: AppState,
                client: WiFiClientProtocol = CWWiFiClient.shared(),
                locationManager: LocationManagerProtocol = CLLocationManager()) {
        self.appState = appState
        self.client = client
        self.locationManager = locationManager
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
        let authStatus = locationManager.authorizationStatus
        
        if authStatus == .denied || authStatus == .restricted {
            appState.currentNetworkName = "Location Permission Denied"
            appState.log("⚠️ Location permission denied. Cannot read SSID.")
            return
        }
        
        // Update interface reference in case it changed
        self.interface = client.interface()
        
        if let interface = self.interface {
            let currentSSID = interface.ssid()
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
                } else if ssid == appState.ssidB {
                    appState.connectedNetworkType = .backup
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
            self.interface = self.client.interface()
            let newSSID = self.interface?.ssid()
            
            // 4. Analyze the change
            
            // Case A: Switched to Priority Network (P)
            if newSSID == self.appState.ssidP {
                self.appState.log("Connected to Priority Network (P). Auto-switch active.")
                self.refreshStatus()
                return
            }
            
            // Case B: Disconnected (nil)
            // This is often a transient state during switching. We should NOT stop monitoring.
            if newSSID == nil {
                self.appState.log("Network disconnected. Waiting...")
                self.refreshStatus()
                return
            }
            
            // Case C: Switched to Backup Network (B)
            if newSSID == self.appState.ssidB {
                self.appState.log("Switched to Backup Network (B). Checking cause...")
                
                // We need to determine if this was Manual (User) or System (Signal Loss).
                // Heuristic: Scan for P.
                // - If P is visible and strong -> User likely manually chose B. -> STOP.
                // - If P is missing or weak -> System likely fell back to B. -> CONTINUE.
                
                let networks = await self.getAvailableNetworks()
                let isPAvailable = networks.contains(self.appState.ssidP)
                
                if isPAvailable {
                    self.appState.log("⚠️ Network P is available but we are on B. Assuming manual override.")
                    self.stopMonitoring()
                } else {
                    self.appState.log("ℹ️ Network P not found. Assuming system fallback. Auto-switch continues.")
                    // Trigger a check to ensure we are settled
                    self.checkConnection()
                }
                self.refreshStatus()
                return
            }
            
            // Case D: Switched to Unmanaged Network (Neither P nor B)
            // We assume this is a manual user action to use a different network.
            self.appState.log("⚠️ Switched to unmanaged network (\(newSSID ?? "Unknown")). Stopping auto-switch.")
            self.stopMonitoring()
            self.refreshStatus()
        }
    }
    
    @Published public var nextCheckTime: Date?
    @Published public var currentCheckInterval: TimeInterval = 60 // Add this to track the interval used for current timer
    
    public func startMonitoring() {
        requestPermissions()
        stopMonitoring()
        appState.isRunning = true
        appState.log("Started monitoring...")
        
        // Run immediately
        checkConnection()
        
        // Schedule timer
        scheduleTimer()
    }
    
    private func scheduleTimer() {
        let interval = appState.checkInterval
        currentCheckInterval = interval // Store the interval used for this cycle
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
        timer?.invalidate()
        timer = nil
        nextCheckTime = nil
        appState.isRunning = false
        appState.log("Stopped monitoring.")
    }
    
    private func checkConnection() {
        // Update interface
        self.interface = client.interface()
        
        guard let interface = self.interface else {
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
        appState.currentNetworkName = currentSSID ?? "Not Connected"
        
        // Update network type
        if let ssid = currentSSID {
            if ssid == ssidP {
                appState.connectedNetworkType = .priority
            } else if ssid == ssidB {
                appState.connectedNetworkType = .backup
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
        
        // Scan for networks
        appState.log("Scanning...")
        do {
            let networks = try interface.scanForNetworksProtocol(withSSID: nil)
            
            let networkMap = Dictionary(grouping: networks, by: { $0.ssid ?? "" })
            
            // Check for P
            if let networksP = networkMap[ssidP], let targetNetworkP = networksP.first {
                appState.log("Found network P (\(ssidP)). Connecting...")
                connect(to: targetNetworkP, password: appState.passwordP)
                return
            }
            
            // If P not found, and not connected to B, check for B
            if currentSSID != ssidB {
                if let networksB = networkMap[ssidB], let targetNetworkB = networksB.first {
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
    
    public func getAvailableNetworks() async -> [String] {
        let client = CWWiFiClient.shared()
        // Call the original CoreWLAN interface() method, not our protocol extension
        guard let cwInterface: CWInterface = (client as CWWiFiClient).interface() else {
            await appState.log("❌ Error: No Wi-Fi interface found")
            return []
        }
        
        do {
            let networks = try cwInterface.scanForNetworks(withSSID: nil as Data?)
            let ssids = networks
                .compactMap { $0.ssid }
                .filter { !$0.isEmpty }
            
            let uniqueSSIDs = Array(Set(ssids)).sorted()
            return uniqueSSIDs
        } catch {
            await appState.log("❌ Scan error: \(error.localizedDescription)")
            if error.localizedDescription.contains("location") {
                 await appState.log("💡 Try checking Location Services permissions again.")
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
            appState.log("Successfully connected to \(network.ssid ?? "Unknown").")
            refreshStatus()
        } catch {
            appState.log("Failed to connect to \(network.ssid ?? "Unknown"): \(error.localizedDescription)")
        }
    }
}

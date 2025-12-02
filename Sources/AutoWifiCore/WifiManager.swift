import Foundation
import CoreWLAN
import CoreLocation

// MARK: - Protocols

public protocol WiFiClientProtocol: AnyObject {
    var delegate: CWEventDelegate? { get set }
    func interface() -> WiFiInterfaceProtocol?
    func startMonitoringEvent(with type: CWEventType) throws
}

public protocol WiFiNetworkProtocol: AnyObject {
    var ssid: String? { get }
    var rssiValue: Int { get }
}

public protocol WiFiInterfaceProtocol: AnyObject {
    func ssid() -> String?
    func scanForNetworks(withSSID ssid: Data?) throws -> [WiFiNetworkProtocol]
    func associate(to network: WiFiNetworkProtocol, password: String) throws
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
    public func scanForNetworks(withSSID ssid: Data?) throws -> [WiFiNetworkProtocol] {
        let networks = try self.scanForNetworks(withSSID: ssid)
        return networks.map { $0 as WiFiNetworkProtocol }
    }
    
    public func associate(to network: WiFiNetworkProtocol, password: String) throws {
        guard let cwNetwork = network as? CWNetwork else {
            throw NSError(domain: "AutoWifi", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid network type"])
        }
        try self.associate(to: cwNetwork, password: password)
    }
}

extension CLLocationManager: LocationManagerProtocol {}

// MARK: - WifiManager

@MainActor
public class WifiManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var client: WiFiClientProtocol
    private var interface: WiFiInterfaceProtocol?
    private var timer: Timer?
    private var appState: AppState
    private var locationManager: LocationManagerProtocol
    
    public init(appState: AppState,
                client: WiFiClientProtocol = CWWiFiClient.shared(),
                locationManager: LocationManagerProtocol = CLLocationManager()) {
        self.appState = appState
        self.client = client
        self.locationManager = locationManager
        super.init()
        
        self.interface = client.interface()
        self.locationManager.delegate = self
        // self.client.delegate = self
        
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
                    appState.currentNetworkName = "Permission Pending..."
                    requestPermissions()
                } else {
                    appState.currentNetworkName = "Not Connected"
                }
            }
        } else {
            appState.currentNetworkName = "No Interface"
        }
    }
    
    public func requestPermissions() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Handle authorization changes if needed
    }
    
    /*
    nonisolated public func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in
            self.refreshStatus()
        }
    }
    */
    
    public func startMonitoring() {
        requestPermissions()
        stopMonitoring()
        appState.isRunning = true
        appState.log("Started monitoring...")
        
        // Run immediately
        checkConnection()
        
        // Schedule timer
        timer = Timer.scheduledTimer(withTimeInterval: appState.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkConnection()
            }
        }
    }
    
    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
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
        
        let ssidA = appState.ssidA
        let ssidB = appState.ssidB
        
        if ssidA.isEmpty || ssidB.isEmpty {
            appState.log("Error: SSIDs not configured.")
            return
        }
        
        let currentSSID = interface.ssid()
        appState.currentNetworkName = currentSSID ?? "Not Connected"
        // appState.log("Current network: \(currentSSID ?? "None")")
        
        // If already connected to A, we are good.
        if currentSSID == ssidA {
            // appState.log("Connected to preferred network A (\(ssidA)).")
            return
        }
        
        // Scan for networks
        appState.log("Scanning...")
        do {
            let networks = try interface.scanForNetworks(withSSID: nil)
            
            // Debug: Log all found networks
            // appState.log("Found \(networks.count) networks")
            
            let networkMap = Dictionary(grouping: networks, by: { $0.ssid ?? "" })
            
            // Check for A
            if let networksA = networkMap[ssidA], let targetNetworkA = networksA.first {
                appState.log("Found network A (\(ssidA)). Connecting...")
                connect(to: targetNetworkA, password: appState.passwordA)
                return
            }
            
            // If A not found, and not connected to B, check for B
            if currentSSID != ssidB {
                if let networksB = networkMap[ssidB], let targetNetworkB = networksB.first {
                    appState.log("Network A not found. Found network B (\(ssidB)). Connecting...")
                    connect(to: targetNetworkB, password: appState.passwordB)
                    return
                } else {
                    appState.log("Neither network A nor B found.")
                }
            } else {
                appState.log("Connected to backup network B (\(ssidB)). Network A not found.")
            }
            
        } catch {
            appState.log("Scan failed: \(error.localizedDescription)")
        }
    }
    
    /*
    public func getAvailableNetworks() async -> [String] {
        // Note: This method creates a new client instance for async scanning
        // In a real testable scenario, we might want to inject a factory or use the existing client
        // For now, we'll keep using the shared client for simplicity in the main app, 
        // but for testing we might need to adjust this if we want to mock it.
        // However, this method is nonisolated and creates its own client.
        // To make it testable, we would need to refactor it to use the injected client.
        // But since it's async and nonisolated, it's tricky with the actor isolation.
        // For now, let's leave it as is, but maybe we can't easily test this specific method with mocks
        // without more significant refactoring.
        
        let client = CWWiFiClient.shared()
        guard let interface = client.interface() else {
            await appState.log("❌ Error: No Wi-Fi interface found")
            return []
        }
        
        do {
            let networks = try interface.scanForNetworks(withSSID: nil)
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
    */
    
    private func connect(to network: WiFiNetworkProtocol, password: String) {
        guard let interface = self.interface else { return }
        
        do {
            try interface.associate(to: network, password: password)
            appState.log("Successfully connected to \(network.ssid ?? "Unknown").")
            refreshStatus()
        } catch {
            appState.log("Failed to connect to \(network.ssid ?? "Unknown"): \(error.localizedDescription)")
        }
    }
}

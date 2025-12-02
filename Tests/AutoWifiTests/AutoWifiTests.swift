import XCTest
import CoreLocation
import CoreWLAN
@testable import AutoWifiCore

// MARK: - Mocks

class MockWiFiNetwork: WiFiNetworkProtocol {
    var ssid: String?
    var rssiValue: Int
    
    init(ssid: String?, rssiValue: Int = -50) {
        self.ssid = ssid
        self.rssiValue = rssiValue
    }
}

class MockWiFiInterface: WiFiInterfaceProtocol {
    var currentSSID: String?
    var availableNetworks: [WiFiNetworkProtocol] = []
    var associatedNetwork: WiFiNetworkProtocol?
    var associateError: Error?
    var scanError: Error?
    
    func ssid() -> String? {
        return currentSSID
    }
    
    func scanForNetworks(withSSID ssid: Data?) throws -> [WiFiNetworkProtocol] {
        if let error = scanError {
            throw error
        }
        return availableNetworks
    }
    
    func associate(to network: WiFiNetworkProtocol, password: String) throws {
        if let error = associateError {
            throw error
        }
        associatedNetwork = network
        currentSSID = network.ssid
    }
}

class MockWiFiClient: WiFiClientProtocol {
    var delegate: CWEventDelegate?
    var mockInterface: MockWiFiInterface? = MockWiFiInterface()
    
    func interface() -> WiFiInterfaceProtocol? {
        return mockInterface
    }
    
    func startMonitoringEvent(with type: CWEventType) throws {
        // No-op for mock
    }
    
    func simulateSSIDChange(to newSSID: String) {
        mockInterface?.currentSSID = newSSID
        delegate?.ssidDidChangeForWiFiInterface?(withName: "en0")
    }
}

class MockLocationManager: LocationManagerProtocol {
    var delegate: CLLocationManagerDelegate?
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var requestAuthorizationCalled = false
    
    func requestWhenInUseAuthorization() {
        requestAuthorizationCalled = true
    }
}

// MARK: - Tests

@MainActor
final class AutoWifiTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        print("Starting test: \(name)")
    }
    
    override func tearDown() {
        print("Finished test: \(name)")
        super.tearDown()
    }
    
    func testDummy() {
        XCTAssertTrue(true)
    }
    
    // MARK: - AppState Tests
    
    func testAppStateInitialization() {
        // ...
    }
    // ... (rest of tests)
    */
        let defaults = UserDefaults(suiteName: "testAppStateInitialization")!
        defaults.removePersistentDomain(forName: "testAppStateInitialization")
        
        let appState = AppState(userDefaults: defaults)
        
        XCTAssertEqual(appState.ssidA, "")
        XCTAssertEqual(appState.checkInterval, 60)
        XCTAssertEqual(appState.currentNetworkName, "Not Connected")
    }
    
    func testAppStatePersistence() {
        let defaults = UserDefaults(suiteName: "testAppStatePersistence")!
        defaults.removePersistentDomain(forName: "testAppStatePersistence")
        
        let appState = AppState(userDefaults: defaults)
        
        appState.ssidA = "TestNetworkA"
        appState.passwordA = "password123"
        
        // Create new instance to verify persistence
        let newAppState = AppState(userDefaults: defaults)
        XCTAssertEqual(newAppState.ssidA, "TestNetworkA")
        XCTAssertEqual(newAppState.passwordA, "password123")
    }
    
    func testAppStateLogging() {
        let appState = AppState(userDefaults: UserDefaults(suiteName: "testLog")!)
        appState.log("Test message")
        
        XCTAssertTrue(appState.lastLog.contains("Test message"))
    }
    
    // MARK: - LocalizationManager Tests
    
    func testLocalization() {
        let i18n = LocalizationManager.shared
        
        // Reset to default
        i18n.language = .chinese
        XCTAssertEqual(i18n.localizedString("scan_networks"), "扫描网络")
        
        i18n.toggleLanguage()
        XCTAssertEqual(i18n.language, .english)
        XCTAssertEqual(i18n.localizedString("scan_networks"), "Scan Networks")
        
        i18n.toggleLanguage()
        XCTAssertEqual(i18n.language, .chinese)
    }
    
    // MARK: - WifiManager Tests
    
    func testWifiManagerInitialization() {
        let appState = AppState(userDefaults: UserDefaults(suiteName: "testInit")!)
        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        
        let _ = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        
        // Should start monitoring ssid changes
        // (Implicitly tested by no crash and delegate assignment)
        XCTAssertNotNil(mockClient.delegate)
    }
    
    func testStatusCheck_PermissionDenied() {
        let appState = AppState(userDefaults: UserDefaults(suiteName: "testPermDenied")!)
        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        mockLocation.authorizationStatus = .denied
        
        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.refreshStatus()
        
        XCTAssertEqual(appState.currentNetworkName, "Location Permission Denied")
    }
    
    func testStatusCheck_Connected() {
        let appState = AppState(userDefaults: UserDefaults(suiteName: "testConnected")!)
        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        mockClient.mockInterface?.currentSSID = "HomeWiFi"
        
        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.refreshStatus()
        
        XCTAssertEqual(appState.currentNetworkName, "HomeWiFi")
    }
    
    func testAutoConnect_PriorityNetwork() {
        let appState = AppState(userDefaults: UserDefaults(suiteName: "testAutoConnectA")!)
        appState.ssidA = "NetworkA"
        appState.passwordA = "passA"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"
        
        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        
        // Currently connected to nothing
        mockInterface.currentSSID = nil
        
        // Available networks include A
        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkA"),
            MockWiFiNetwork(ssid: "Other")
        ]
        
        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.startMonitoring() // Triggers checkConnection
        
        // Should connect to A
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkA")
        // Status should update
        XCTAssertEqual(appState.currentNetworkName, "NetworkA")
    }
    
    func testAutoConnect_BackupNetwork() {
        let appState = AppState(userDefaults: UserDefaults(suiteName: "testAutoConnectB")!)
        appState.ssidA = "NetworkA"
        appState.passwordA = "passA"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"
        
        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        
        // Currently connected to nothing
        mockInterface.currentSSID = nil
        
        // Available networks include B but NOT A
        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkB"),
            MockWiFiNetwork(ssid: "Other")
        ]
        
        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.startMonitoring()
        
        // Should connect to B
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkB")
        XCTAssertEqual(appState.currentNetworkName, "NetworkB")
    }
    
    func testAutoSwitch_BackToPriority() {
        let appState = AppState(userDefaults: UserDefaults(suiteName: "testSwitchBack")!)
        appState.ssidA = "NetworkA"
        appState.passwordA = "passA"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"
        
        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        
        // Currently connected to B
        mockInterface.currentSSID = "NetworkB"
        
        // A becomes available
        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkA"),
            MockWiFiNetwork(ssid: "NetworkB")
        ]
        
        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.startMonitoring()
        
        // Should switch to A
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkA")
        XCTAssertEqual(appState.currentNetworkName, "NetworkA")
    }
    
    func testSSIDChangeDelegate() {
        let appState = AppState(userDefaults: UserDefaults(suiteName: "testDelegate")!)
        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        
        let _ = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        
        // Simulate external change
        mockClient.simulateSSIDChange(to: "NewWiFi")
        
        // Wait for main actor update
        let expectation = XCTestExpectation(description: "Status update")
        DispatchQueue.main.async {
            if appState.currentNetworkName == "NewWiFi" {
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}

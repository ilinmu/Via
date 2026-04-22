import XCTest
import CoreLocation
import CoreWLAN
@testable import AutoWifiCore

// MARK: - Mocks

final class MockSecureStore: SecureStoreProtocol {
    var storage: [String: String] = [:]

    func string(forKey key: String) throws -> String? {
        storage[key]
    }

    func setString(_ value: String, forKey key: String) throws {
        storage[key] = value
    }

    func removeValue(forKey key: String) throws {
        storage.removeValue(forKey: key)
    }
}

final class MockWiFiNetwork: WiFiNetworkProtocol {
    let ssid: String?
    let rssiValue: Int

    init(ssid: String?, rssiValue: Int = -50) {
        self.ssid = ssid
        self.rssiValue = rssiValue
    }
}

final class MockWiFiInterface: WiFiInterfaceProtocol {
    var currentSSID: String?
    var availableNetworks: [WiFiNetworkProtocol] = []
    var associatedNetwork: WiFiNetworkProtocol?
    var associatedPassword: String?
    var associateError: Error?
    var scanError: Error?

    func ssid() -> String? {
        currentSSID
    }

    func scanForNetworksProtocol(withSSID ssid: Data?) throws -> [WiFiNetworkProtocol] {
        if let scanError {
            throw scanError
        }

        return availableNetworks
    }

    func associateNetwork(_ network: WiFiNetworkProtocol, password: String) throws {
        if let associateError {
            throw associateError
        }

        associatedNetwork = network
        associatedPassword = password
        currentSSID = network.ssid
    }
}

final class MockWiFiClient: WiFiClientProtocol {
    var delegate: AnyObject?
    var mockInterface: MockWiFiInterface? = MockWiFiInterface()
    var monitoredEventCount = 0

    func interface() -> WiFiInterfaceProtocol? {
        mockInterface
    }

    func startMonitoringEvent(with type: CWEventType) throws {
        monitoredEventCount += 1
    }

    func simulateSSIDChange(to newSSID: String?) {
        mockInterface?.currentSSID = newSSID
        (delegate as? CWEventDelegate)?.ssidDidChangeForWiFiInterface?(withName: "en0")
    }
}

final class MockLocationManager: LocationManagerProtocol {
    var delegate: CLLocationManagerDelegate?
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    var requestAuthorizationCalled = false

    func requestWhenInUseAuthorization() {
        requestAuthorizationCalled = true
    }
}

// MARK: - Tests

@MainActor
final class AutoWifiTests: XCTestCase {
    private func makeDefaults(_ suffix: String = UUID().uuidString) -> UserDefaults {
        let suiteName = "AutoWifiTests.\(suffix)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeAppState(
        defaults: UserDefaults? = nil,
        launchService: MockLaunchService? = nil,
        secureStore: MockSecureStore? = nil
    ) -> AppState {
        AppState(
            userDefaults: defaults ?? makeDefaults(),
            launchService: launchService ?? MockLaunchService(),
            secureStore: secureStore ?? MockSecureStore()
        )
    }

    func testAppStateInitializationUsesSecureStoreValues() {
        let defaults = makeDefaults("initialization")
        defaults.set("NetworkP", forKey: "ssidP")
        defaults.set("NetworkB", forKey: "ssidB")
        defaults.set(30.0, forKey: "checkInterval")

        let secureStore = MockSecureStore()
        secureStore.storage["passwordP"] = "passP"
        secureStore.storage["passwordB"] = "passB"

        let appState = makeAppState(defaults: defaults, secureStore: secureStore)

        XCTAssertEqual(appState.ssidP, "NetworkP")
        XCTAssertEqual(appState.passwordP, "passP")
        XCTAssertEqual(appState.ssidB, "NetworkB")
        XCTAssertEqual(appState.passwordB, "passB")
        XCTAssertEqual(appState.checkInterval, 30)
        XCTAssertEqual(appState.currentNetworkName, "Not Connected")
    }

    func testAppStateMigratesLegacyPasswordsToSecureStore() {
        let defaults = makeDefaults("migration")
        defaults.set("legacyP", forKey: "passwordP")
        defaults.set("legacyB", forKey: "passwordB")

        let secureStore = MockSecureStore()
        let appState = makeAppState(defaults: defaults, secureStore: secureStore)

        XCTAssertEqual(appState.passwordP, "legacyP")
        XCTAssertEqual(appState.passwordB, "legacyB")
        XCTAssertEqual(secureStore.storage["passwordP"], "legacyP")
        XCTAssertEqual(secureStore.storage["passwordB"], "legacyB")
        XCTAssertNil(defaults.string(forKey: "passwordP"))
        XCTAssertNil(defaults.string(forKey: "passwordB"))
    }

    func testAppStatePersistsConfigurationAndNormalizesInterval() {
        let defaults = makeDefaults("persistence")
        let secureStore = MockSecureStore()

        let appState = makeAppState(defaults: defaults, secureStore: secureStore)
        appState.ssidP = "OfficeWiFi"
        appState.passwordP = "office-pass"
        appState.ssidB = "PhoneHotspot"
        appState.passwordB = "hotspot-pass"
        appState.checkInterval = 1

        let reloaded = makeAppState(defaults: defaults, secureStore: secureStore)

        XCTAssertEqual(reloaded.ssidP, "OfficeWiFi")
        XCTAssertEqual(reloaded.passwordP, "office-pass")
        XCTAssertEqual(reloaded.ssidB, "PhoneHotspot")
        XCTAssertEqual(reloaded.passwordB, "hotspot-pass")
        XCTAssertEqual(reloaded.checkInterval, AppState.minimumCheckInterval)
    }

    func testLaunchAtLoginRevertsOnFailure() {
        let defaults = makeDefaults("launchAtLogin")
        let secureStore = MockSecureStore()
        let launchService = MockLaunchService()
        launchService.shouldFail = true

        let appState = makeAppState(
            defaults: defaults,
            launchService: launchService,
            secureStore: secureStore
        )

        appState.launchAtLogin = true

        XCTAssertFalse(appState.launchAtLogin)
        XCTAssertFalse(launchService.isEnabled)
        XCTAssertTrue(appState.lastLog.contains("Failed to toggle"))
    }

    func testWifiManagerInitializationRegistersForSSIDChanges() {
        let appState = makeAppState()
        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()

        _ = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)

        XCTAssertNotNil(mockClient.delegate)
        XCTAssertEqual(mockClient.monitoredEventCount, 1)
    }

    func testRefreshStatusPermissionDeniedClearsNetworkType() {
        let appState = makeAppState()
        appState.connectedNetworkType = .priority

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        mockLocation.authorizationStatus = .denied

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.refreshStatus()

        XCTAssertEqual(appState.currentNetworkName, "Location Permission Denied")
        XCTAssertEqual(appState.connectedNetworkType, .none)
    }

    func testAutoConnectPrefersStrongestPriorityNetwork() {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        let weakPriority = MockWiFiNetwork(ssid: "NetworkP", rssiValue: -72)
        let strongPriority = MockWiFiNetwork(ssid: "NetworkP", rssiValue: -38)

        mockInterface.availableNetworks = [
            weakPriority,
            strongPriority,
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -40)
        ]

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.startMonitoring()

        XCTAssertTrue(mockLocation.requestAuthorizationCalled)
        XCTAssertTrue((mockInterface.associatedNetwork as AnyObject?) === strongPriority)
        XCTAssertEqual(mockInterface.associatedPassword, "passP")
        XCTAssertEqual(appState.currentNetworkName, "NetworkP")

        manager.stopMonitoring()
    }

    func testAutoConnectFallsBackToBackupNetwork() {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.availableNetworks = [MockWiFiNetwork(ssid: "NetworkB", rssiValue: -45)]

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.startMonitoring()

        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkB")
        XCTAssertEqual(mockInterface.associatedPassword, "passB")
        XCTAssertEqual(appState.currentNetworkName, "NetworkB")

        manager.stopMonitoring()
    }

    func testGetAvailableNetworksUsesInjectedInterfaceAndDeduplicatesResults() async {
        let appState = makeAppState()
        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "Office"),
            MockWiFiNetwork(ssid: "Guest"),
            MockWiFiNetwork(ssid: "Office"),
            MockWiFiNetwork(ssid: nil)
        ]

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        let networks = await manager.getAvailableNetworks()

        XCTAssertEqual(networks, ["Guest", "Office"])
    }

    func testSSIDChangeUpdatesStatusWhenMonitoringIsStopped() async {
        let appState = makeAppState()
        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()

        _ = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        mockClient.simulateSSIDChange(to: "NewWiFi")
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(appState.currentNetworkName, "NewWiFi")
    }

    func testSSIDChangeToBackupStopsMonitoringWhenPriorityIsVisible() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = "NetworkP"
        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkP", rssiValue: -50),
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -45)
        ]

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.startMonitoring()
        mockClient.simulateSSIDChange(to: "NetworkB")
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(appState.isRunning)
        XCTAssertTrue(appState.currentStatus.contains("manual override"))
    }

    func testSSIDChangeToUnmanagedNetworkStopsMonitoring() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = "NetworkP"
        mockInterface.availableNetworks = [MockWiFiNetwork(ssid: "NetworkP", rssiValue: -40)]

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.startMonitoring()
        mockClient.simulateSSIDChange(to: "CoffeeShop")
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(appState.isRunning)
        XCTAssertEqual(appState.currentNetworkName, "CoffeeShop")
        XCTAssertTrue(appState.currentStatus.contains("CoffeeShop"))
    }
}

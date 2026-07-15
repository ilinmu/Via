import XCTest
import CoreLocation
import CoreWLAN
@testable import AutoWifiCore

// MARK: - Mocks

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
        launchService: MockLaunchService? = nil
    ) -> AppState {
        AppState(
            userDefaults: defaults ?? makeDefaults(),
            launchService: launchService ?? MockLaunchService()
        )
    }

    func testAppStateInitializationUsesStoredValues() {
        let defaults = makeDefaults("initialization")
        defaults.set("NetworkP", forKey: "ssidP")
        defaults.set("NetworkB", forKey: "ssidB")
        defaults.set("passP", forKey: "passwordP")
        defaults.set("passB", forKey: "passwordB")
        defaults.set(30.0, forKey: "checkInterval")

        let appState = makeAppState(defaults: defaults)

        XCTAssertEqual(appState.ssidP, "NetworkP")
        XCTAssertEqual(appState.passwordP, "passP")
        XCTAssertEqual(appState.ssidB, "NetworkB")
        XCTAssertEqual(appState.passwordB, "passB")
        XCTAssertEqual(appState.checkInterval, 30)
        XCTAssertEqual(appState.currentNetworkName, "Not Connected")
    }

    func testAppStatePersistsConfigurationAndNormalizesInterval() {
        let defaults = makeDefaults("persistence")

        let appState = makeAppState(defaults: defaults)
        appState.ssidP = "OfficeWiFi"
        appState.passwordP = "office-pass"
        appState.ssidB = "PhoneHotspot"
        appState.passwordB = "hotspot-pass"
        appState.checkInterval = 1

        let reloaded = makeAppState(defaults: defaults)

        XCTAssertEqual(reloaded.ssidP, "OfficeWiFi")
        XCTAssertEqual(reloaded.passwordP, "office-pass")
        XCTAssertEqual(reloaded.ssidB, "PhoneHotspot")
        XCTAssertEqual(reloaded.passwordB, "hotspot-pass")
        XCTAssertEqual(reloaded.checkInterval, AppState.minimumCheckInterval)
    }

    func testLaunchAtLoginRevertsOnFailure() {
        let defaults = makeDefaults("launchAtLogin")
        let launchService = MockLaunchService()
        launchService.shouldFail = true

        let appState = makeAppState(
            defaults: defaults,
            launchService: launchService
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

    func testSSIDChangeToBackupReturnsToPriorityAndKeepsMonitoringWhenPriorityIsVisible() async {
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

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkP")
        XCTAssertEqual(mockInterface.associatedPassword, "passP")
        XCTAssertEqual(appState.currentNetworkName, "NetworkP")
        XCTAssertEqual(appState.connectedNetworkType, .priority)
    }

    func testSSIDChangeToBackupKeepsMonitoringWhenPriorityIsMissing() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = "NetworkP"

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.startMonitoring()

        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -45)
        ]
        mockClient.simulateSSIDChange(to: "NetworkB")
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(appState.currentNetworkName, "NetworkB")
        XCTAssertEqual(appState.connectedNetworkType, .backup)
    }

    func testSSIDChangeToBackupAfterDisconnectReturnsToPriorityWhenItIsVisible() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = "NetworkP"

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.startMonitoring()

        mockClient.simulateSSIDChange(to: nil)
        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkP", rssiValue: -80),
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -45)
        ]
        mockClient.simulateSSIDChange(to: "NetworkB")
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkP")
        XCTAssertEqual(mockInterface.associatedPassword, "passP")
        XCTAssertEqual(appState.currentNetworkName, "NetworkP")
        XCTAssertEqual(appState.connectedNetworkType, .priority)
    }

    func testPriorityLossFallsBackToBackupThenReturnsToPriorityWithoutDisablingAutoSwitch() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = "NetworkP"

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.startMonitoring()

        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -45)
        ]
        mockClient.simulateSSIDChange(to: nil)
        mockClient.simulateSSIDChange(to: "NetworkB")
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(appState.currentNetworkName, "NetworkB")
        XCTAssertEqual(appState.connectedNetworkType, .backup)

        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkP", rssiValue: -40),
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -45)
        ]
        mockClient.simulateSSIDChange(to: "NetworkB")
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkP")
        XCTAssertEqual(mockInterface.associatedPassword, "passP")
        XCTAssertEqual(appState.currentNetworkName, "NetworkP")
        XCTAssertEqual(appState.connectedNetworkType, .priority)
    }

    func testSSIDChangeToLegacyBackupReconnectsCurrentBackupAndKeepsMonitoring() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "BackupA"
        appState.passwordB = "passA"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = "NetworkP"

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.startMonitoring()

        appState.ssidB = "BackupB"
        appState.passwordB = "passB"
        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "BackupA", rssiValue: -42),
            MockWiFiNetwork(ssid: "BackupB", rssiValue: -38)
        ]
        mockClient.simulateSSIDChange(to: "BackupA")
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "BackupB")
        XCTAssertEqual(mockInterface.associatedPassword, "passB")
        XCTAssertEqual(appState.currentNetworkName, "BackupB")
    }

    func testSSIDChangeToPreviousBackupReconnectsCurrentBackupAfterConfigurationChange() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "BackupA"
        appState.passwordB = "passA"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = "NetworkP"

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.startMonitoring()

        appState.ssidB = "BackupB"
        appState.passwordB = "passB"
        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkP", rssiValue: -78),
            MockWiFiNetwork(ssid: "BackupA", rssiValue: -40),
            MockWiFiNetwork(ssid: "BackupB", rssiValue: -35)
        ]
        mockClient.simulateSSIDChange(to: "BackupA")
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "BackupB")
        XCTAssertEqual(mockInterface.associatedPassword, "passB")
        XCTAssertEqual(appState.currentNetworkName, "BackupB")
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

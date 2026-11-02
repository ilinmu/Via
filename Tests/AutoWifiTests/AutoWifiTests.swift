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
    var interfaceName = "en0"
    var powerOn = true
    var currentSSID: String?
    var availableNetworks: [WiFiNetworkProtocol] = []
    var associatedNetwork: WiFiNetworkProtocol?
    var associatedPassword: String?
    var associateError: Error?
    var scanError: Error?
    var scanRanOnMainThread: Bool?
    var associationRanOnMainThread: Bool?
    var scanCallCount = 0
    var associationCallCount = 0
    var blockScan = false
    var blockAssociation = false
    private let scanBlockSemaphore = DispatchSemaphore(value: 0)
    private let associationBlockSemaphore = DispatchSemaphore(value: 0)

    func ssid() -> String? {
        currentSSID
    }

    func interfaceNameProtocol() -> String? {
        interfaceName
    }

    func isPowerOnProtocol() -> Bool {
        powerOn
    }

    func scanForNetworksProtocol(withSSID ssid: Data?) throws -> [WiFiNetworkProtocol] {
        scanRanOnMainThread = Thread.isMainThread
        scanCallCount += 1
        if blockScan {
            scanBlockSemaphore.wait()
        }
        if let scanError {
            throw scanError
        }

        guard let ssid, let requestedName = String(data: ssid, encoding: .utf8) else {
            return availableNetworks
        }

        return availableNetworks.filter { $0.ssid == requestedName }
    }

    func associateNetwork(_ network: WiFiNetworkProtocol, password: String) throws {
        associationRanOnMainThread = Thread.isMainThread
        associationCallCount += 1
        if blockAssociation {
            associationBlockSemaphore.wait()
        }
        if let associateError {
            throw associateError
        }

        associatedNetwork = network
        associatedPassword = password
        currentSSID = network.ssid
    }

    @MainActor
    func waitForAssociationStart(timeout: TimeInterval = 3) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if associationCallCount > 0 {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return associationCallCount > 0
    }

    @MainActor
    func releaseAssociationBlock() {
        associationBlockSemaphore.signal()
    }

    @MainActor
    func releaseScanBlock() {
        scanBlockSemaphore.signal()
    }
}

final class MockWiFiClient: WiFiClientProtocol {
    var delegate: AnyObject?
    var mockInterface: MockWiFiInterface? = MockWiFiInterface()
    var fallbackInterfaces: [MockWiFiInterface] = []
    var namedInterfaces: [String: MockWiFiInterface] = [:]
    var monitoredEventCount = 0

    func interface() -> WiFiInterfaceProtocol? {
        mockInterface
    }

    func interfacesProtocol() -> [WiFiInterfaceProtocol] {
        if fallbackInterfaces.isEmpty, let mockInterface {
            return [mockInterface]
        }
        return fallbackInterfaces
    }

    func interfaceNamesProtocol() -> [String] {
        Array(namedInterfaces.keys).sorted()
    }

    func interfaceProtocol(withName name: String) -> WiFiInterfaceProtocol? {
        namedInterfaces[name]
    }

    func startMonitoringEvent(with type: CWEventType) throws {
        monitoredEventCount += 1
    }

    func simulateSSIDChange(to newSSID: String?) {
        mockInterface?.currentSSID = newSSID
        (delegate as? CWEventDelegate)?.ssidDidChangeForWiFiInterface?(withName: "en0")
    }
}

final class MockCredentialStore: CredentialStore, @unchecked Sendable {
    var passwords: [String: String] = [:]
    var failReads = false
    var failWrites = false

    private var failure: CredentialStoreError { .keychain(-1) }

    func password(for account: String) throws -> String? {
        if failReads { throw failure }
        return passwords[account]
    }

    func setPassword(_ password: String, for account: String) throws {
        if failWrites { throw failure }
        if password.isEmpty {
            passwords.removeValue(forKey: account)
        } else {
            passwords[account] = password
        }
    }

    func removePassword(for account: String) throws {
        if failWrites { throw failure }
        passwords.removeValue(forKey: account)
    }
}

@MainActor
final class MockLaunchService: LaunchServiceProtocol {
    var status: LaunchAtLoginStatus = .notRegistered
    var statusAfterEnable: LaunchAtLoginStatus = .enabled
    var shouldFail = false

    func enable() throws {
        if shouldFail {
            throw NSError(
                domain: "MockLaunchService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Mock failure"]
            )
        }
        status = statusAfterEnable
    }

    func disable() throws {
        if shouldFail {
            throw NSError(
                domain: "MockLaunchService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Mock failure"]
            )
        }
        status = .notRegistered
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
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func makeAppState(
        defaults: UserDefaults? = nil,
        launchService: MockLaunchService? = nil,
        credentialStore: MockCredentialStore? = nil
    ) -> AppState {
        AppState(
            userDefaults: defaults ?? makeDefaults(),
            launchService: launchService ?? MockLaunchService(),
            credentialStore: credentialStore ?? MockCredentialStore()
        )
    }

    private func makeImmediateClassification(_ manager: WifiManager) {
        // Real hardware waits for the Wi-Fi radio to settle before rescanning
        // to classify a change. Tests classify immediately to stay fast.
        manager.observedChangeSettleDelay = 0
        manager.observedChangeRescanInterval = 0
        manager.observedChangeRescanAttempts = 1
    }


    func testAppStateInitializationUsesStoredValues() {
        let defaults = makeDefaults("initialization")
        defaults.set("NetworkP", forKey: "ssidP")
        defaults.set("NetworkB", forKey: "ssidB")
        defaults.set("passP", forKey: "passwordP")
        defaults.set("passB", forKey: "passwordB")
        defaults.set(30.0, forKey: "checkInterval")
        defaults.set(true, forKey: "isRunning")

        let appState = makeAppState(defaults: defaults)

        XCTAssertEqual(appState.ssidP, "NetworkP")
        XCTAssertEqual(appState.passwordP, "passP")
        XCTAssertEqual(appState.ssidB, "NetworkB")
        XCTAssertEqual(appState.passwordB, "passB")
        XCTAssertEqual(appState.checkInterval, 30)
        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(appState.currentNetworkName, "Not Connected")
    }

    func testAppStatePersistsConfigurationAndNormalizesInterval() {
        let defaults = makeDefaults("persistence")
        let credentials = MockCredentialStore()

        let appState = makeAppState(defaults: defaults, credentialStore: credentials)
        appState.ssidP = "OfficeWiFi"
        appState.passwordP = "office-pass"
        appState.ssidB = "PhoneHotspot"
        appState.passwordB = "hotspot-pass"
        appState.checkInterval = 1
        appState.isRunning = true
        appState.flushPendingPasswordSaves()

        let reloaded = makeAppState(defaults: defaults, credentialStore: credentials)

        XCTAssertEqual(reloaded.ssidP, "OfficeWiFi")
        XCTAssertEqual(reloaded.passwordP, "office-pass")
        XCTAssertEqual(reloaded.ssidB, "PhoneHotspot")
        XCTAssertEqual(reloaded.passwordB, "hotspot-pass")
        XCTAssertEqual(reloaded.checkInterval, AppState.minimumCheckInterval)
        XCTAssertTrue(reloaded.isRunning)
        XCTAssertEqual(credentials.passwords["passwordP"], "office-pass")
        XCTAssertEqual(credentials.passwords["passwordB"], "hotspot-pass")
        XCTAssertNil(defaults.string(forKey: "passwordP"))
        XCTAssertNil(defaults.string(forKey: "passwordB"))
    }

    func testLegacyPlaintextPasswordsMigrateToCredentialStore() {
        let defaults = makeDefaults("migration")
        defaults.set("legacy-priority", forKey: "passwordP")
        defaults.set("legacy-backup", forKey: "passwordB")
        let credentials = MockCredentialStore()

        let appState = makeAppState(defaults: defaults, credentialStore: credentials)

        XCTAssertEqual(appState.passwordP, "legacy-priority")
        XCTAssertEqual(appState.passwordB, "legacy-backup")
        XCTAssertEqual(credentials.passwords["passwordP"], "legacy-priority")
        XCTAssertEqual(credentials.passwords["passwordB"], "legacy-backup")
        XCTAssertNil(defaults.string(forKey: "passwordP"))
        XCTAssertNil(defaults.string(forKey: "passwordB"))
    }

    func testLegacyPlaintextRetainedWhenKeychainMigrationFails() {
        let defaults = makeDefaults("migrationFailure")
        defaults.set("legacy-priority", forKey: "passwordP")
        defaults.set("legacy-backup", forKey: "passwordB")
        let credentials = MockCredentialStore()
        credentials.failWrites = true

        let appState = makeAppState(defaults: defaults, credentialStore: credentials)

        XCTAssertEqual(appState.passwordP, "legacy-priority")
        XCTAssertEqual(appState.passwordB, "legacy-backup")
        XCTAssertEqual(defaults.string(forKey: "passwordP"), "legacy-priority")
        XCTAssertEqual(defaults.string(forKey: "passwordB"), "legacy-backup")
        XCTAssertEqual(
            appState.credentialStorageWarning,
            .migrationFailed(account: CredentialAccount.priority)
        )
    }

    func testCredentialWriteFailureIsSurfacedAndResolvedOnRetry() {
        let defaults = makeDefaults("credentialWriteFailure")
        let credentials = MockCredentialStore()
        let appState = makeAppState(defaults: defaults, credentialStore: credentials)

        credentials.failWrites = true
        appState.passwordP = "office-pass"
        appState.flushPendingPasswordSaves()

        XCTAssertEqual(
            appState.credentialStorageWarning,
            .writeFailed(account: CredentialAccount.priority)
        )

        credentials.failWrites = false
        appState.passwordP = "office-pass-2"
        appState.flushPendingPasswordSaves()

        XCTAssertNil(appState.credentialStorageWarning)
        XCTAssertEqual(credentials.passwords[CredentialAccount.priority], "office-pass-2")
    }

    func testLaunchAtLoginRequiresApprovalIsExposed() {
        let defaults = makeDefaults("launchAtLoginApproval")
        let launchService = MockLaunchService()
        launchService.statusAfterEnable = .requiresApproval

        let appState = makeAppState(
            defaults: defaults,
            launchService: launchService
        )

        appState.launchAtLogin = true

        XCTAssertFalse(appState.launchAtLogin)
        XCTAssertEqual(appState.launchAtLoginStatus, .requiresApproval)
        XCTAssertTrue(appState.launchAtLoginRequiresApproval)
        XCTAssertTrue(appState.lastLog.contains("requires approval"))
    }

    func testStartMonitoringWithoutConfiguredNetworksClearsPersistedRunningState() async {
        let defaults = makeDefaults("missingNetworks")
        let appState = makeAppState(defaults: defaults)
        appState.isRunning = true
        let manager = WifiManager(
            appState: appState,
            client: MockWiFiClient(),
            locationManager: MockLocationManager()
        )

        await manager.startMonitoring()

        XCTAssertFalse(appState.isRunning)
        XCTAssertFalse(defaults.bool(forKey: "isRunning"))
        XCTAssertTrue(appState.currentStatus.contains("not configured"))
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
        appState.setNetworkStatus(.connected(ssid: "NetworkP", role: .priority))

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        mockLocation.authorizationStatus = .denied

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.refreshStatus()

        XCTAssertEqual(appState.currentNetworkName, "Location Permission Denied")
        XCTAssertEqual(appState.connectedNetworkType, .none)
    }

    func testRefreshStatusFallsBackToListedInterfaceWhenDefaultInterfaceIsMissing() {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.ssidB = "NetworkB"

        let mockClient = MockWiFiClient()
        mockClient.mockInterface = nil
        let connectedInterface = MockWiFiInterface()
        connectedInterface.currentSSID = "NetworkB"
        mockClient.fallbackInterfaces = [connectedInterface]

        let manager = WifiManager(
            appState: appState,
            client: mockClient,
            locationManager: MockLocationManager()
        )
        manager.refreshStatus()

        XCTAssertEqual(appState.currentNetworkName, "NetworkB")
        XCTAssertEqual(appState.connectedNetworkType, .backup)
    }

    func testAutoConnectUsesListedInterfaceWhenDefaultInterfaceIsMissing() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        mockClient.mockInterface = nil
        let fallbackInterface = MockWiFiInterface()
        fallbackInterface.currentSSID = "NetworkB"
        fallbackInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkP", rssiValue: -42),
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -50)
        ]
        mockClient.fallbackInterfaces = [fallbackInterface]

        let manager = WifiManager(
            appState: appState,
            client: mockClient,
            locationManager: MockLocationManager()
        )
        await manager.startMonitoring()

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(fallbackInterface.associatedNetwork?.ssid, "NetworkP")
        XCTAssertEqual(fallbackInterface.associatedPassword, "passP")
        XCTAssertEqual(appState.currentNetworkName, "NetworkP")
        XCTAssertEqual(appState.connectedNetworkType, .priority)

        manager.stopMonitoring()
    }

    func testAutoConnectUsesNamedInterfaceWhenCoreWLANListsAreEmpty() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        mockClient.mockInterface = nil
        mockClient.fallbackInterfaces = []

        let namedInterface = MockWiFiInterface()
        namedInterface.interfaceName = "en1"
        namedInterface.currentSSID = "NetworkB"
        namedInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkP", rssiValue: -40),
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -48)
        ]
        mockClient.namedInterfaces = ["en1": namedInterface]

        let manager = WifiManager(
            appState: appState,
            client: mockClient,
            locationManager: MockLocationManager()
        )
        await manager.startMonitoring()

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(namedInterface.associatedNetwork?.ssid, "NetworkP")
        XCTAssertEqual(namedInterface.associatedPassword, "passP")
        XCTAssertEqual(appState.currentNetworkName, "NetworkP")
        XCTAssertEqual(appState.interfaceStatus, "Interface: en1 · Wi-Fi: on")

        manager.stopMonitoring()
    }

    func testRefreshStatusPrefersConnectedListedInterfaceOverDisconnectedDefault() {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.ssidB = "NetworkB"

        let mockClient = MockWiFiClient()
        mockClient.mockInterface?.currentSSID = nil
        let connectedInterface = MockWiFiInterface()
        connectedInterface.currentSSID = "NetworkB"
        mockClient.fallbackInterfaces = [connectedInterface]

        let manager = WifiManager(
            appState: appState,
            client: mockClient,
            locationManager: MockLocationManager()
        )
        manager.refreshStatus()

        XCTAssertEqual(appState.currentNetworkName, "NetworkB")
        XCTAssertEqual(appState.connectedNetworkType, .backup)
    }

    func testAutomaticScanAndAssociationRunOffMainThread() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockInterface = mockClient.mockInterface!
        mockInterface.availableNetworks = [MockWiFiNetwork(ssid: "NetworkP")]

        let manager = WifiManager(
            appState: appState,
            client: mockClient,
            locationManager: MockLocationManager()
        )
        await manager.startMonitoring()

        XCTAssertEqual(mockInterface.scanRanOnMainThread, false)
        XCTAssertEqual(mockInterface.associationRanOnMainThread, false)

        manager.stopMonitoring()
    }

    func testAutoConnectPrefersStrongestPriorityNetwork() async {
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
        await manager.startMonitoring()

        XCTAssertTrue(mockLocation.requestAuthorizationCalled)
        XCTAssertTrue((mockInterface.associatedNetwork as AnyObject?) === strongPriority)
        XCTAssertEqual(mockInterface.associatedPassword, "passP")
        XCTAssertEqual(appState.currentNetworkName, "NetworkP")

        manager.stopMonitoring()
    }

    func testAutoConnectFallsBackToBackupNetwork() async {
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
        await manager.startMonitoring()

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
        _ = await waitUntil { appState.currentNetworkName == "NewWiFi" }

        XCTAssertEqual(appState.currentNetworkName, "NewWiFi")
    }

    func testManualSwitchToBackupStopsMonitoringWhenPriorityIsVisible() async {
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
        makeImmediateClassification(manager)
        await manager.startMonitoring()
        mockClient.simulateSSIDChange(to: "NetworkB")
        _ = await waitUntil { !appState.isRunning }

        XCTAssertFalse(appState.isRunning)
        XCTAssertEqual(appState.currentNetworkName, "NetworkB")
        XCTAssertEqual(appState.connectedNetworkType, .backup)
        XCTAssertNil(mockInterface.associatedNetwork)
    }

    func testFailoverToBackupThenManualSwitchToBackupStopsMonitoring() async {
        // 1) P disappears: checkConnection scans, finds only B, and connects to
        //    B itself (automatic failover), keeping monitoring.
        // 2) P becomes visible again: the next scheduled check reconnects to P.
        // 3) The user then manually switches to B while P is visible: manual
        //    override, monitoring must stop.
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
        makeImmediateClassification(manager)
        await manager.startMonitoring()

        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -45)
        ]
        mockInterface.currentSSID = nil
        await manager.checkConnection()
        _ = await waitUntil { mockInterface.associatedNetwork?.ssid == "NetworkB" }

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkB")
        XCTAssertEqual(appState.connectedNetworkType, .backup)

        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkP", rssiValue: -50),
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -45)
        ]
        await manager.checkConnection()
        _ = await waitUntil { mockInterface.associatedNetwork?.ssid == "NetworkP" }

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkP")
        XCTAssertEqual(appState.connectedNetworkType, .priority)

        mockClient.simulateSSIDChange(to: "NetworkB")
        _ = await waitUntil { !appState.isRunning }

        XCTAssertFalse(appState.isRunning)
        XCTAssertEqual(appState.connectedNetworkType, .backup)
    }

    func testSSIDChangeToBackupKeepsMonitoringWhenPriorityIsMissing() async {
        // When P disappears, the app connects to B itself (automatic failover).
        // The macOS SSID event that follows must be recognized as app-initiated
        // and keep monitoring rather than being treated as a manual override.
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
        await manager.startMonitoring()

        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -45)
        ]
        mockInterface.currentSSID = nil
        await manager.checkConnection()
        _ = await waitUntil { mockInterface.associatedNetwork?.ssid == "NetworkB" }
        mockClient.simulateSSIDChange(to: "NetworkB")
        _ = await waitUntil { appState.connectedNetworkType == .backup }

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkB")
        XCTAssertEqual(appState.currentNetworkName, "NetworkB")
        XCTAssertEqual(appState.connectedNetworkType, .backup)
    }

    func testManualSwitchToBackupAfterDisconnectStopsMonitoringWhenPriorityIsVisible() async {
        // Real macOS manual switch emits P → nil → B while P remains visible.
        // The transient nil event must not be mistaken for automatic failover:
        // landing on B with P still visible is a manual override and must stop.
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
        makeImmediateClassification(manager)
        await manager.startMonitoring()

        mockClient.simulateSSIDChange(to: nil)
        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkP", rssiValue: -80),
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -45)
        ]
        mockClient.simulateSSIDChange(to: "NetworkB")
        _ = await waitUntil { !appState.isRunning }

        XCTAssertFalse(appState.isRunning)
        XCTAssertEqual(appState.currentNetworkName, "NetworkB")
        XCTAssertEqual(appState.connectedNetworkType, .backup)
        XCTAssertNil(mockInterface.associatedNetwork)
    }

    func testPriorityLossFallsBackToBackupThenReturnsToPriorityWithoutDisablingAutoSwitch() async {
        // P disappears: the app connects to B itself and keeps monitoring.
        // When P becomes visible again, the next check reconnects to P.
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
        await manager.startMonitoring()

        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -45)
        ]
        mockInterface.currentSSID = nil
        await manager.checkConnection()
        _ = await waitUntil { mockInterface.associatedNetwork?.ssid == "NetworkB" }

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkB")
        XCTAssertEqual(appState.currentNetworkName, "NetworkB")
        XCTAssertEqual(appState.connectedNetworkType, .backup)

        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkP", rssiValue: -40),
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -45)
        ]
        await manager.checkConnection()
        _ = await waitUntil { mockInterface.associatedNetwork?.ssid == "NetworkP" }

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkP")
        XCTAssertEqual(mockInterface.associatedPassword, "passP")
        XCTAssertEqual(appState.currentNetworkName, "NetworkP")
        XCTAssertEqual(appState.connectedNetworkType, .priority)
    }

    func testPriorityLossConnectsToBackupOnDisconnectBeforeMacOSRoams() async {
        // When P disappears, the app must proactively connect to B on the
        // disconnect event, instead of waiting for macOS to roam to some other
        // saved network X.
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
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -45)
        ]

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        makeImmediateClassification(manager)
        await manager.startMonitoring()

        mockClient.simulateSSIDChange(to: nil)
        _ = await waitUntil { mockInterface.associatedNetwork?.ssid == "NetworkB" }

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkB")
        XCTAssertEqual(mockInterface.associatedPassword, "passB")
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
        await manager.startMonitoring()

        appState.ssidB = "BackupB"
        appState.passwordB = "passB"
        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "BackupA", rssiValue: -42),
            MockWiFiNetwork(ssid: "BackupB", rssiValue: -38)
        ]
        mockClient.simulateSSIDChange(to: "BackupA")
        _ = await waitUntil { appState.currentNetworkName == "BackupB" }

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
        await manager.startMonitoring()

        appState.ssidB = "BackupB"
        appState.passwordB = "passB"
        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkP", rssiValue: -78),
            MockWiFiNetwork(ssid: "BackupA", rssiValue: -40),
            MockWiFiNetwork(ssid: "BackupB", rssiValue: -35)
        ]
        mockClient.simulateSSIDChange(to: "BackupA")
        _ = await waitUntil { appState.currentNetworkName == "BackupB" }

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
        makeImmediateClassification(manager)
        await manager.startMonitoring()
        mockClient.simulateSSIDChange(to: "CoffeeShop")
        _ = await waitUntil { !appState.isRunning }

        XCTAssertFalse(appState.isRunning)
        XCTAssertEqual(appState.currentNetworkName, "CoffeeShop")
        XCTAssertTrue(appState.currentStatus.contains("CoffeeShop"))
    }

    func testStartMonitoringClearsPersistedCooldownAndRecoversToPriority() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = nil
        mockInterface.availableNetworks = [MockWiFiNetwork(ssid: "NetworkP")]

        appState.beginAssociationCooldown(duration: 300, for: "NetworkP")
        let countBefore = mockInterface.associationCallCount

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        await manager.startMonitoring()

        XCTAssertEqual(mockInterface.associationCallCount, countBefore + 1)
        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkP")
    }

    func testAssociationCooldownSkipsSameTargetDuringRunningSession() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = nil
        mockInterface.availableNetworks = [MockWiFiNetwork(ssid: "NetworkP")]

        appState.isRunning = true
        appState.beginAssociationCooldown(duration: 300, for: "NetworkP")
        let countBefore = mockInterface.associationCallCount

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        await manager.checkConnection()

        XCTAssertEqual(mockInterface.associationCallCount, countBefore)
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, nil)
    }

    func testTimerCheckReconnectsToPriorityWhileCooldownTargetsBackup() async {
        // Regression: after a failed B association, the cooldown must not
        // block the next timer check from connecting to P when P is visible.
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = "NetworkB"
        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkP", rssiValue: -40),
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -45)
        ]

        appState.beginAssociationCooldown(duration: 300, for: "NetworkB")

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.refreshStatus()
        appState.isRunning = true
        await manager.checkConnection()

        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkP")
        XCTAssertEqual(appState.connectedNetworkType, .priority)
    }

    func testTimerCheckOnBackupConnectsToPriorityWhenVisible() async {
        // Regression: a scheduled check while connected to B must switch back
        // to P immediately when P is visible (no confirm-window suppression).
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = "NetworkB"
        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkP", rssiValue: -40),
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -45)
        ]

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.refreshStatus()
        appState.isRunning = true
        await manager.checkConnection()

        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkP")
        XCTAssertEqual(mockInterface.associatedPassword, "passP")
        XCTAssertEqual(appState.currentNetworkName, "NetworkP")
        XCTAssertEqual(appState.connectedNetworkType, .priority)
    }

    func testConcurrentAssociationAttemptsAreDeduplicated() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = "OtherNet"
        mockInterface.availableNetworks = [
            MockWiFiNetwork(ssid: "NetworkP", rssiValue: -45),
            MockWiFiNetwork(ssid: "NetworkB", rssiValue: -50)
        ]
        mockInterface.blockAssociation = true

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        let monitorTask = Task { @MainActor in
            await manager.startMonitoring()
        }

        let started = await mockInterface.waitForAssociationStart()
        XCTAssertTrue(started)
        XCTAssertEqual(mockInterface.associationCallCount, 1)

        mockClient.simulateSSIDChange(to: nil)
        mockClient.simulateSSIDChange(to: "OtherNet")
        // A negative assertion: wait up to 200 ms for an incorrect second
        // association, then verify none happened.
        _ = await waitUntil(timeout: 0.2) { mockInterface.associationCallCount > 1 }

        XCTAssertEqual(mockInterface.associationCallCount, 1)
        XCTAssertTrue(appState.isRunning)

        mockInterface.releaseAssociationBlock()
        _ = await monitorTask.value
        manager.stopMonitoring()
    }

    func testStartMonitoringWaitsForLocationAuthorizationAndResumesAfterGrant() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        mockLocation.authorizationStatus = .notDetermined
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = nil
        mockInterface.availableNetworks = [MockWiFiNetwork(ssid: "NetworkP", rssiValue: -40)]

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        await manager.startMonitoring()

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(appState.networkStatus, .permissionPending)
        XCTAssertEqual(mockInterface.associationCallCount, 0)

        mockLocation.authorizationStatus = .authorizedAlways
        mockLocation.delegate?.locationManagerDidChangeAuthorization?(CLLocationManager())
        _ = await waitUntil {
            appState.networkStatus == .connected(ssid: "NetworkP", role: .priority)
        }

        XCTAssertEqual(appState.networkStatus, .connected(ssid: "NetworkP", role: .priority))
        XCTAssertEqual(mockInterface.associatedNetwork?.ssid, "NetworkP")

        manager.stopMonitoring()
    }

    func testAssociationTimeoutAppliesCooldown() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = nil
        mockInterface.availableNetworks = [MockWiFiNetwork(ssid: "NetworkP", rssiValue: -40)]
        mockInterface.blockAssociation = true

        appState.isRunning = true
        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.associationTimeout = 0.1
        await manager.checkConnection()

        XCTAssertTrue(appState.isRunning)
        XCTAssertTrue(appState.hasActiveAssociationCooldown(for: "NetworkP"))
        XCTAssertNil(mockInterface.associatedNetwork)

        mockInterface.releaseAssociationBlock()
        manager.stopMonitoring()
    }

    func testCheckConnectionAbortsWhenConfiguredSSIDChangesDuringScan() async {
        let appState = makeAppState()
        appState.ssidP = "OldNetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"
        appState.isRunning = true

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = nil
        mockInterface.availableNetworks = [MockWiFiNetwork(ssid: "OldNetworkP", rssiValue: -40)]
        mockInterface.blockScan = true

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        let checkTask = Task { await manager.checkConnection() }

        let scanStarted = await waitUntil { mockInterface.scanCallCount > 0 }
        XCTAssertTrue(scanStarted)

        appState.ssidP = "NewNetworkP"
        mockInterface.blockScan = false
        mockInterface.releaseScanBlock()
        await checkTask.value

        // The re-check runs with the new P, which is not visible, and B is not
        // visible either. The stale scan result must never be associated.
        _ = await waitUntil(timeout: 0.2) { mockInterface.associationCallCount > 0 }
        XCTAssertEqual(mockInterface.associationCallCount, 0)
        XCTAssertNil(mockInterface.associatedNetwork)
    }

    func testLateAssociationSuccessAfterTimeoutKeepsMonitoring() async {
        let appState = makeAppState()
        appState.ssidP = "NetworkP"
        appState.passwordP = "passP"
        appState.ssidB = "NetworkB"
        appState.passwordB = "passB"

        let mockClient = MockWiFiClient()
        let mockLocation = MockLocationManager()
        let mockInterface = mockClient.mockInterface!
        mockInterface.currentSSID = "OtherNetwork"
        mockInterface.availableNetworks = [MockWiFiNetwork(ssid: "NetworkB", rssiValue: -40)]
        mockInterface.blockAssociation = true

        let manager = WifiManager(appState: appState, client: mockClient, locationManager: mockLocation)
        manager.associationTimeout = 0.1
        await manager.startMonitoring()

        XCTAssertTrue(appState.hasActiveAssociationCooldown(for: "NetworkB"))
        XCTAssertTrue(appState.isRunning)

        mockInterface.releaseAssociationBlock()
        let reachedBackup = await waitUntil {
            appState.connectedNetworkType == .backup
        }
        XCTAssertTrue(reachedBackup)

        mockClient.simulateSSIDChange(to: "NetworkB")
        _ = await waitUntil(timeout: 0.2) { !appState.isRunning }

        XCTAssertTrue(appState.isRunning)
        XCTAssertEqual(appState.connectedNetworkType, .backup)

        manager.stopMonitoring()
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

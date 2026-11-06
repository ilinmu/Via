import XCTest
@testable import Via

final class PolicyCoreTests: XCTestCase {
    func testStartingOnPriorityRefreshesStatus() throws {
        let engine = try XCTUnwrap(PolicyEngine(ssidP: "NetworkP", ssidB: "NetworkB"))

        let actions = engine.start(permission: .authorized, currentSSID: "NetworkP")

        XCTAssertEqual(actions, [.refreshStatus])
        let snapshot = engine.snapshot()
        XCTAssertTrue(snapshot.running)
        XCTAssertEqual(snapshot.currentSSID, "NetworkP")
        XCTAssertEqual(snapshot.role, .priority)
        XCTAssertEqual(snapshot.permission, .authorized)
    }

    func testStartingAwayFromPriorityScansForIt() throws {
        let engine = try XCTUnwrap(PolicyEngine(ssidP: "NetworkP", ssidB: "NetworkB"))

        let actions = engine.start(permission: .authorized, currentSSID: "OtherNetwork")

        XCTAssertEqual(actions, [.scan(.priorityCheck)])
        XCTAssertTrue(engine.snapshot().running)
    }

    func testMissingConfigurationStopsMonitoring() throws {
        let engine = try XCTUnwrap(PolicyEngine(ssidP: "NetworkP", ssidB: ""))

        let actions = engine.start(permission: .authorized, currentSSID: "NetworkP")

        XCTAssertEqual(actions, [.stop(.notConfigured)])
        XCTAssertFalse(engine.snapshot().running)
    }

    func testStopClearsRunningState() throws {
        let engine = try XCTUnwrap(PolicyEngine(ssidP: "NetworkP", ssidB: "NetworkB"))
        _ = engine.start(permission: .authorized, currentSSID: "NetworkP")

        XCTAssertEqual(engine.stop(), [])
        XCTAssertFalse(engine.snapshot().running)
    }

    func testMissingPriorityRequestsBackupScan() throws {
        let engine = try XCTUnwrap(PolicyEngine(ssidP: "NetworkP", ssidB: "NetworkB"))
        _ = engine.start(permission: .authorized, currentSSID: "OtherNetwork")

        XCTAssertEqual(engine.scanResult(found: Optional(false)), [.scan(.backupCheck)])
    }

    func testObservedChangeSupersedesStaleScanResult() throws {
        let engine = try XCTUnwrap(PolicyEngine(ssidP: "NetworkP", ssidB: "NetworkB"))
        _ = engine.start(permission: .authorized, currentSSID: "OtherNetwork")

        let observed = engine.observedChange(previous: "NetworkP", new: "NetworkB")
        let stale = engine.scanResult(found: Optional(true))

        XCTAssertEqual(observed, [.scan(.priorityClassification)])
        XCTAssertEqual(stale, [])
        XCTAssertEqual(
            engine.classificationResult(priorityVisible: Optional(false)),
            [.log(.systemJoinedBackup), .checkNow]
        )
        XCTAssertTrue(engine.snapshot().running)
    }

    func testUnknownPriorityScanKeepsMonitoring() throws {
        let engine = try XCTUnwrap(PolicyEngine(ssidP: "NetworkP", ssidB: "NetworkB"))
        _ = engine.start(permission: .authorized, currentSSID: "NetworkP")
        XCTAssertEqual(
            engine.observedChange(previous: "NetworkP", new: nil),
            [.scan(.priorityClassification)]
        )

        let actions = engine.scanResult(found: nil)

        XCTAssertEqual(actions, [.log(.priorityVisibleUnknown), .refreshStatus])
        XCTAssertTrue(engine.snapshot().running)
    }

    func testAdvisoryAssociationEndsWithoutCooldown() throws {
        let engine = try XCTUnwrap(PolicyEngine(ssidP: "NetworkP", ssidB: "NetworkB"))
        _ = engine.start(permission: .authorized, currentSSID: "NetworkP")
        let generation = engine.associationStarted(ssid: "NetworkP")

        let actions = engine.associationResult(
            ssid: "NetworkP",
            generation: generation,
            outcome: 3
        )

        XCTAssertEqual(actions, [.refreshStatus])
        XCTAssertFalse(engine.snapshot().isAssociating)
        XCTAssertEqual(engine.snapshot().cooldownUntilMs, 0)
        XCTAssertTrue(engine.snapshot().running)
    }

    func testPermissionRequiredWaits() throws {
        let engine = try XCTUnwrap(PolicyEngine(ssidP: "NetworkP", ssidB: "NetworkB"))

        let actions = engine.start(permission: .denied, currentSSID: "NetworkP")

        XCTAssertEqual(actions, [.waitForPermission])
        XCTAssertTrue(engine.snapshot().running)
    }
}

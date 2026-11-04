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

        XCTAssertEqual(engine.scanResult(found: false), [.scan(.backupCheck)])
    }

    func testPermissionRequiredWaits() throws {
        let engine = try XCTUnwrap(PolicyEngine(ssidP: "NetworkP", ssidB: "NetworkB"))

        let actions = engine.start(permission: .denied, currentSSID: "NetworkP")

        XCTAssertEqual(actions, [.waitForPermission])
        XCTAssertTrue(engine.snapshot().running)
    }
}

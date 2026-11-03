import XCTest
@testable import AutoWifi

final class L10nTests: XCTestCase {
    func testKnownKeysAreLocalized() {
        XCTAssertEqual(L10n.t("tab_status", "zh"), "状态")
        XCTAssertEqual(L10n.t("tab_status", "en"), "Status")
        XCTAssertEqual(L10n.t("role_priority", "zh"), "优先网络")
        XCTAssertEqual(L10n.t("role_priority", "en"), "Priority")
    }

    func testUnknownKeyFallsBackToKey() {
        XCTAssertEqual(L10n.t("missing_key", "zh"), "missing_key")
        XCTAssertEqual(L10n.t("missing_key", "en"), "missing_key")
    }

    func testUnknownLanguageFallsBackToChinese() {
        XCTAssertEqual(L10n.t("tab_status", "fr"), "状态")
    }
}

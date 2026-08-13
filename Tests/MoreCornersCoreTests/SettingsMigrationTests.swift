import XCTest
@testable import MoreCornersCore

/// Migration of the v1 settings format (single action + modifier requirement
/// per corner) onto the current default-plus-overrides model.
final class SettingsMigrationTests: XCTestCase {

    // Structural mirrors of the private v1 types; encoding these produces the
    // same JSON the migrator decodes.
    private struct LegacyCorner: Codable {
        var action: ActionType
        var modifier: String
        var parameter: String
    }
    private struct LegacySnapshot: Codable {
        var corners: [Corner: LegacyCorner]
        var dwell: Double
        var cornerSize: Double
        var allScreens: Bool
        var enabled: Bool
    }

    private func migrate(_ snapshot: LegacySnapshot) throws -> AppSettings.MigratedSettings {
        let data = try JSONEncoder().encode(snapshot)
        return try XCTUnwrap(AppSettings.migrateLegacyData(data))
    }

    func testModifierRequirementBecomesAnOverride() throws {
        let snap = LegacySnapshot(
            corners: [.topLeft: LegacyCorner(action: .lockScreen,
                                             modifier: "command", parameter: "")],
            dwell: 0.3, cornerSize: 8, allScreens: true, enabled: true)
        let result = try migrate(snap)

        let config = try XCTUnwrap(result.corners[.topLeft])
        XCTAssertEqual(config.base.action, .none)
        XCTAssertEqual(config.variants.count, 1)
        XCTAssertEqual(config.variants.first?.modifiers, .command)
        XCTAssertEqual(config.variants.first?.spec.action, .lockScreen)
    }

    func testPlainAndAnyBecomeTheDefaultAction() throws {
        let snap = LegacySnapshot(
            corners: [
                .topRight: LegacyCorner(action: .missionControl, modifier: "any", parameter: ""),
                .bottomLeft: LegacyCorner(action: .showDesktop, modifier: "plain", parameter: ""),
            ],
            dwell: 0.25, cornerSize: 6, allScreens: false, enabled: true)
        let result = try migrate(snap)

        let tr = try XCTUnwrap(result.corners[.topRight])
        XCTAssertEqual(tr.base.action, .missionControl)
        XCTAssertTrue(tr.variants.isEmpty)

        let bl = try XCTUnwrap(result.corners[.bottomLeft])
        XCTAssertEqual(bl.base.action, .showDesktop)
        XCTAssertTrue(bl.variants.isEmpty)
    }

    func testParametersAndBehaviorFieldsSurvive() throws {
        let snap = LegacySnapshot(
            corners: [.bottomRight: LegacyCorner(action: .openURL, modifier: "option",
                                                 parameter: "https://apple.com")],
            dwell: 0.42, cornerSize: 12, allScreens: false, enabled: false)
        let result = try migrate(snap)

        XCTAssertEqual(result.dwell, 0.42)
        XCTAssertEqual(result.cornerSize, 12)
        XCTAssertFalse(result.allScreens)
        XCTAssertFalse(result.enabled)
        XCTAssertEqual(result.corners[.bottomRight]?.variants.first?.spec.parameter,
                       "https://apple.com")
        XCTAssertEqual(result.corners[.bottomRight]?.variants.first?.modifiers, .option)
    }

    func testGarbageDataReturnsNil() {
        XCTAssertNil(AppSettings.migrateLegacyData(Data("not json".utf8)))
    }
}

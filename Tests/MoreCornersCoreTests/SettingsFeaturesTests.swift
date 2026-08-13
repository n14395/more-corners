import XCTest
@testable import MoreCornersCore

/// Covers the new per-corner enable flag, app-exclusion / full-screen suppression
/// decision, and settings export/import.
final class SettingsFeaturesTests: XCTestCase {

    // MARK: Per-corner enable — backward-compatible decode

    func testCornerConfigDecodesMissingEnabledAsOn() throws {
        // A blob written before `enabled` existed must still decode (a throw here
        // would fail the whole settings decode and wipe the user's config).
        let json = #"{"base":{"action":"missionControl","parameter":""},"variants":[]}"#
        let cfg = try JSONDecoder().decode(CornerConfig.self, from: Data(json.utf8))
        XCTAssertTrue(cfg.enabled)
        XCTAssertEqual(cfg.base.action, .missionControl)
    }

    func testCornerConfigRoundTripsEnabled() throws {
        var cfg = CornerConfig(base: ActionSpec(action: .showDesktop))
        cfg.enabled = false
        let back = try JSONDecoder().decode(CornerConfig.self,
                                            from: JSONEncoder().encode(cfg))
        XCTAssertFalse(back.enabled)
        XCTAssertEqual(back, cfg)
    }

    // MARK: Suppression decision

    func testExcludesMatchesBundleID() {
        let s = AppSettings.shared
        let saved = s.excludedApps
        defer { s.excludedApps = saved }
        s.excludedApps = [ExcludedApp(bundleID: "com.foo.bar", name: "Bar")]
        XCTAssertTrue(s.excludes(bundleID: "com.foo.bar"))
        XCTAssertFalse(s.excludes(bundleID: "com.other.app"))
        XCTAssertFalse(s.excludes(bundleID: nil))
    }

    func testShouldSuppressCombinesFullScreenAndExclusions() {
        let s = AppSettings.shared
        let savedApps = s.excludedApps, savedFS = s.suppressInFullScreen
        defer { s.excludedApps = savedApps; s.suppressInFullScreen = savedFS }
        s.excludedApps = [ExcludedApp(bundleID: "com.game.x", name: "Game")]

        s.suppressInFullScreen = false
        XCTAssertTrue(s.shouldSuppress(frontmostBundleID: "com.game.x", isFullScreen: true),
                      "excluded app suppresses regardless of full-screen")
        XCTAssertFalse(s.shouldSuppress(frontmostBundleID: "com.safe.y", isFullScreen: true),
                       "full-screen off → a full-screen non-excluded app fires")

        s.suppressInFullScreen = true
        XCTAssertTrue(s.shouldSuppress(frontmostBundleID: "com.safe.y", isFullScreen: true))
        XCTAssertFalse(s.shouldSuppress(frontmostBundleID: "com.safe.y", isFullScreen: false))
    }

    // MARK: Export / import round-trip

    func testExportImportRoundTrip() throws {
        let s = AppSettings.shared
        let saved = (s.corners, s.dwell, s.suppressInFullScreen, s.excludedApps,
                     s.feedbackFlash, s.feedbackSoundName)
        defer {
            (s.corners, s.dwell, s.suppressInFullScreen, s.excludedApps,
             s.feedbackFlash, s.feedbackSoundName) = saved
        }

        s.dwell = 0.42
        s.suppressInFullScreen = true
        s.excludedApps = [ExcludedApp(bundleID: "com.a.b", name: "AB")]
        s.feedbackFlash = true
        s.feedbackSoundName = "Glass"
        var cfg = CornerConfig(base: ActionSpec(action: .missionControl))
        cfg.enabled = false
        s.corners = [.topLeft: cfg]

        let data = try XCTUnwrap(s.exportData())

        // Clobber, then import back.
        s.dwell = 0; s.suppressInFullScreen = false; s.excludedApps = []
        s.feedbackFlash = false; s.feedbackSoundName = "Tink"; s.corners = [:]

        XCTAssertTrue(s.importData(data))
        XCTAssertEqual(s.dwell, 0.42, accuracy: 0.0001)
        XCTAssertTrue(s.suppressInFullScreen)
        XCTAssertEqual(s.excludedApps, [ExcludedApp(bundleID: "com.a.b", name: "AB")])
        XCTAssertTrue(s.feedbackFlash)
        XCTAssertEqual(s.feedbackSoundName, "Glass")
        XCTAssertEqual(s.corners[.topLeft]?.enabled, false)
        XCTAssertEqual(s.corners[.topLeft]?.base.action, .missionControl)
    }

    func testImportRejectsGarbage() {
        XCTAssertFalse(AppSettings.shared.importData(Data("not settings".utf8)))
    }

    // MARK: Reset to defaults (baked-in factory layout)

    func testResetToDefaultsSeedsBakedLayout() throws {
        let s = AppSettings.shared
        let saved = try XCTUnwrap(s.exportData())
        defer { s.importData(saved) }

        // Clobber everything, then reset.
        s.corners = [:]
        s.dwell = 0.9
        s.feedbackHaptic = false
        s.slamToActivate = true
        s.resetToDefaults()

        XCTAssertEqual(s.corners[.topLeft]?.base.action, .openAppleMenu)
        XCTAssertEqual(s.corners[.topLeft]?.variants.count, 2)
        XCTAssertEqual(s.corners[.topRight]?.base.action, .openNotificationCenter)
        XCTAssertEqual(s.corners[.bottomLeft]?.base.action, .openQuickNote)
        XCTAssertEqual(s.corners[.bottomRight]?.base.action, .showDesktop)
        XCTAssertEqual(s.cornerSize, 16)
        XCTAssertTrue(s.feedbackHaptic)
        XCTAssertFalse(s.slamToActivate)
    }
}

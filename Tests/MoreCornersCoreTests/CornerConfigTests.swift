// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import MoreCornersCore

/// The core dispatch logic: given the modifiers held when a corner fires,
/// which action (if any) runs.
final class CornerConfigTests: XCTestCase {

    func testBaseActionRunsWithNoModifiers() {
        var config = CornerConfig()
        config.base = ActionSpec(action: .missionControl)
        XCTAssertEqual(config.resolve(held: [])?.action, .missionControl)
    }

    func testBaseActionIsTheFallbackForAnyUnmatchedModifiers() {
        var config = CornerConfig()
        config.base = ActionSpec(action: .missionControl)
        // No override for ⌘, so the base still runs.
        XCTAssertEqual(config.resolve(held: .command)?.action, .missionControl)
        XCTAssertEqual(config.resolve(held: [.command, .shift])?.action, .missionControl)
    }

    func testModifierOverrideMatchesExactly() {
        var config = CornerConfig()
        config.base = ActionSpec(action: .missionControl)
        config.variants = [.init(modifiers: .command, spec: ActionSpec(action: .lockScreen))]

        XCTAssertEqual(config.resolve(held: .command)?.action, .lockScreen)
        // Superset of the override's modifiers does NOT match it.
        XCTAssertEqual(config.resolve(held: [.command, .shift])?.action, .missionControl)
        // A different single modifier falls back to base.
        XCTAssertEqual(config.resolve(held: .option)?.action, .missionControl)
    }

    func testComboOverride() {
        var config = CornerConfig()
        config.variants = [.init(modifiers: [.command, .shift],
                                 spec: ActionSpec(action: .screenshotArea))]
        XCTAssertEqual(config.resolve(held: [.command, .shift])?.action, .screenshotArea)
        XCTAssertNil(config.resolve(held: .command))
    }

    func testModifierOnlyCornerReturnsNilUntilModifierHeld() {
        var config = CornerConfig()
        config.variants = [.init(modifiers: .command, spec: ActionSpec(action: .lockScreen))]
        // Base is None and no plain match → nothing fires on a plain hit.
        XCTAssertNil(config.resolve(held: []))
        XCTAssertEqual(config.resolve(held: .command)?.action, .lockScreen)
    }

    func testVariantWithEmptyModifiersIsIgnored() {
        var config = CornerConfig()
        config.variants = [.init(modifiers: [], spec: ActionSpec(action: .lockScreen))]
        XCTAssertNil(config.resolve(held: []))
    }

    func testVariantWithNoneActionIsIgnored() {
        var config = CornerConfig()
        config.variants = [.init(modifiers: .command, spec: ActionSpec(action: .none))]
        XCTAssertNil(config.resolve(held: .command))
    }

    func testFirstMatchingVariantWins() {
        var config = CornerConfig()
        config.variants = [
            .init(modifiers: .command, spec: ActionSpec(action: .lockScreen)),
            .init(modifiers: .command, spec: ActionSpec(action: .screenSaver)),
        ]
        XCTAssertEqual(config.resolve(held: .command)?.action, .lockScreen)
    }

    func testParameterIsCarriedThrough() {
        var config = CornerConfig()
        config.base = ActionSpec(action: .openURL, parameter: "https://example.com")
        XCTAssertEqual(config.resolve(held: [])?.parameter, "https://example.com")
    }

    func testIsConfigured() {
        XCTAssertFalse(CornerConfig().isConfigured)

        var withBase = CornerConfig()
        withBase.base = ActionSpec(action: .missionControl)
        XCTAssertTrue(withBase.isConfigured)

        var withVariant = CornerConfig()
        withVariant.variants = [.init(modifiers: .command,
                                      spec: ActionSpec(action: .lockScreen))]
        XCTAssertTrue(withVariant.isConfigured)

        var emptyVariantOnly = CornerConfig()
        emptyVariantOnly.variants = [.init(modifiers: .command,
                                           spec: ActionSpec(action: .none))]
        XCTAssertFalse(emptyVariantOnly.isConfigured)
    }
}

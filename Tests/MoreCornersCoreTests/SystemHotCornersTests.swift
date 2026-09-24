// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import MoreCornersCore

/// Detection of clashes with macOS's own hot corner assignments.
final class SystemHotCornersTests: XCTestCase {

    private func config(base: ActionType = .none,
                        variants: [(ModifierKeys, ActionType)] = []) -> CornerConfig {
        var c = CornerConfig()
        c.base = ActionSpec(action: base)
        c.variants = variants.map { .init(modifiers: $0.0, spec: ActionSpec(action: $0.1)) }
        return c
    }

    func testNames() {
        XCTAssertEqual(SystemHotCorners.name(for: 4), "Desktop")
        XCTAssertEqual(SystemHotCorners.name(for: 11), "Launchpad")
        XCTAssertEqual(SystemHotCorners.name(for: 13), "Lock Screen")
        XCTAssertEqual(SystemHotCorners.name(for: 12), "Notification Center")
        XCTAssertEqual(SystemHotCorners.name(for: 999), "an action")
    }

    func testUnmodifiedSystemCornerClashesWithAnyConfiguredCorner() {
        let assignment = SystemHotCorners.Assignment(code: 4, modifiers: [])
        XCTAssertTrue(SystemHotCorners.clashes(assignment, with: config(base: .missionControl)))
        // But not with an empty corner.
        XCTAssertFalse(SystemHotCorners.clashes(assignment, with: config()))
    }

    func testModifiedSystemCornerClashesOnlyWhenTheCornerRespondsToThatModifier() {
        let assignment = SystemHotCorners.Assignment(code: 4, modifiers: .command)

        // A ⌘ override responds → clash.
        XCTAssertTrue(SystemHotCorners.clashes(
            assignment, with: config(variants: [(.command, .lockScreen)])))

        // A plain base action still fires when ⌘ is held (base is the
        // fallback), so it also clashes.
        XCTAssertTrue(SystemHotCorners.clashes(assignment, with: config(base: .missionControl)))

        // Only an ⌥ override and no base → nothing fires on ⌘ → no clash.
        XCTAssertFalse(SystemHotCorners.clashes(
            assignment, with: config(variants: [(.option, .lockScreen)])))
    }
}

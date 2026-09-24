// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import MoreCornersCore

/// `CornerMonitor.dwellLabel` — the dwell HUD's caption: what will fire for
/// the held modifiers, or a variants hint when nothing matches yet.
final class DwellLabelTests: XCTestCase {

    func testResolvedActionNamesItself() {
        var config = CornerConfig(base: ActionSpec(action: .missionControl))
        config.variants = [.init(modifiers: .control,
                                 spec: ActionSpec(action: .nextSpace))]
        XCTAssertEqual(CornerMonitor.dwellLabel(for: config, held: []),
                       "Mission Control")
        XCTAssertEqual(CornerMonitor.dwellLabel(for: config, held: .control),
                       "Next Space")
    }

    func testModifierOnlyCornerHintsItsVariants() {
        let config = CornerConfig(
            base: ActionSpec(),
            variants: [.init(modifiers: .option, spec: ActionSpec(action: .showDesktop)),
                       .init(modifiers: [.command, .shift],
                             spec: ActionSpec(action: .lockScreen))])
        XCTAssertEqual(CornerMonitor.dwellLabel(for: config, held: []),
                       "Hold ⌥ Show Desktop · ⇧⌘ Lock Screen")
    }

    func testUnconfiguredCornerHasNoLabel() {
        XCTAssertEqual(CornerMonitor.dwellLabel(for: CornerConfig(), held: []), "")
    }
}

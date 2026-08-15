import XCTest
@testable import MoreCornersCore

/// Invariants over the whole action catalog — cheap guards that catch a new
/// action being added without a label, group, or parameter placeholder.
final class ActionCatalogTests: XCTestCase {

    private var realActions: [ActionType] {
        ActionType.allCases.filter { $0 != .none }
    }

    func testEveryActionHasANonEmptyUniqueLabel() {
        var seen = Set<String>()
        for action in ActionType.allCases {
            XCTAssertFalse(action.label.isEmpty, "\(action) has an empty label")
            XCTAssertTrue(seen.insert(action.label).inserted,
                          "Duplicate label: \(action.label)")
        }
    }

    func testEveryActionBelongsToItsGroupListing() {
        for action in realActions {
            XCTAssertTrue(action.group.actions.contains(action),
                          "\(action) is missing from group \(action.group.rawValue)")
        }
    }

    func testGroupsPartitionAllActions() {
        let grouped = ActionGroup.allCases.flatMap { $0.actions }
        XCTAssertEqual(Set(grouped), Set(realActions),
                       "Groups do not cover exactly the non-none actions")
        XCTAssertEqual(grouped.count, realActions.count, "An action appears in two groups")
    }

    func testParameterizedActionsHavePlaceholders() {
        for action in realActions where action.needsParameter {
            XCTAssertFalse(action.parameterPlaceholder.isEmpty,
                           "\(action) needs a parameter but has no placeholder")
        }
    }

    func testNonParameterizedActionsNeedNoPlaceholder() {
        for action in realActions where !action.needsParameter {
            XCTAssertTrue(action.parameterPlaceholder.isEmpty,
                          "\(action) has a placeholder but takes no parameter")
        }
    }

    func testFilePickerActionsAlsoTakeAParameter() {
        for action in ActionType.allCases where action.usesFilePicker {
            XCTAssertTrue(action.needsParameter,
                          "\(action) uses a file picker but isn't parameterized")
        }
    }

    func testKnownAccessibilityActionsAreFlagged() {
        let expected: Set<ActionType> = [
            .brightnessUp, .brightnessDown, .playPause, .nextTrack, .previousTrack,
            .pressKeys, .openControlCenter, .openNotificationCenter,
            .openAppleMenu, .openQuickNote,
        ]
        for action in expected {
            XCTAssertTrue(action.needsAccessibility,
                          "\(action) should require Accessibility")
        }
    }

    func testDestructiveActionsAreExactlyTheExpectedSet() {
        XCTAssertEqual(Set(ActionType.allCases.filter(\.isDestructive)),
                       [.quitFrontApp, .emptyTrash, .logOut])
    }

    func testCodableRoundTripForActionSpec() throws {
        let spec = ActionSpec(action: .runShell, parameter: "say hi")
        let data = try JSONEncoder().encode(spec)
        XCTAssertEqual(try JSONDecoder().decode(ActionSpec.self, from: data), spec)
    }
}

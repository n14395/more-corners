import XCTest
import AppKit
@testable import MoreCornersCore

/// Parsing of user key specs ("cmd+shift+4") and of macOS's stored symbolic
/// hotkey entries (Show Desktop / App Exposé).
final class KeyParsingTests: XCTestCase {

    // MARK: parseKeySpec

    func testParsesModifiersAndKey() {
        let (code, flags) = try! XCTUnwrap(ActionRunner.parseKeySpec("cmd+shift+4"))
        XCTAssertEqual(code, 21)                       // ANSI "4"
        XCTAssertEqual(flags, [.maskCommand, .maskShift])
    }

    func testWhitespaceSeparatorAndArrowKey() {
        let (code, flags) = try! XCTUnwrap(ActionRunner.parseKeySpec("ctrl left"))
        XCTAssertEqual(code, 123)                      // Left arrow
        XCTAssertEqual(flags, .maskControl)
    }

    func testBareFunctionKey() {
        let (code, flags) = try! XCTUnwrap(ActionRunner.parseKeySpec("f11"))
        XCTAssertEqual(code, 103)
        XCTAssertEqual(flags, [])
    }

    func testFnModifier() {
        let (code, flags) = try! XCTUnwrap(ActionRunner.parseKeySpec("fn+q"))
        XCTAssertEqual(code, 12)
        XCTAssertEqual(flags, .maskSecondaryFn)
    }

    func testNamedKeysAndAliases() {
        XCTAssertEqual(ActionRunner.parseKeySpec("escape")?.0, 53)
        XCTAssertEqual(ActionRunner.parseKeySpec("esc")?.0, 53)
        XCTAssertEqual(ActionRunner.parseKeySpec("space")?.0, 49)
        XCTAssertEqual(ActionRunner.parseKeySpec("return")?.0, 36)
        XCTAssertEqual(ActionRunner.parseKeySpec("enter")?.0, 36)
    }

    func testUnparseableSpecsReturnNil() {
        XCTAssertNil(ActionRunner.parseKeySpec(""))
        XCTAssertNil(ActionRunner.parseKeySpec("shift"))          // modifiers only
        XCTAssertNil(ActionRunner.parseKeySpec("nonsense"))
    }

    // MARK: parseSymbolicHotkey

    private func hotkeys(_ id: String, enabled: Bool,
                         key: Int, mods: Int) -> [String: Any] {
        [id: ["enabled": enabled,
              "value": ["parameters": [65535, key, mods]]]]
    }

    func testDecodesShowDesktopDefault() {
        // fn (0x800000) + F11 (103)
        let dict = hotkeys("36", enabled: true, key: 103, mods: 8_388_608)
        let (code, flags) = try! XCTUnwrap(ActionRunner.parseSymbolicHotkey(id: 36, from: dict))
        XCTAssertEqual(code, 103)
        XCTAssertEqual(flags, .maskSecondaryFn)
    }

    func testDecodesControlShiftCombo() {
        let dict = hotkeys("33", enabled: true, key: 125, mods: 262_144 | 131_072)
        let (_, flags) = try! XCTUnwrap(ActionRunner.parseSymbolicHotkey(id: 33, from: dict))
        XCTAssertEqual(flags, [.maskControl, .maskShift])
    }

    func testDisabledEntryReturnsNil() {
        let dict = hotkeys("36", enabled: false, key: 103, mods: 8_388_608)
        XCTAssertNil(ActionRunner.parseSymbolicHotkey(id: 36, from: dict))
    }

    func testMissingEntryReturnsNil() {
        XCTAssertNil(ActionRunner.parseSymbolicHotkey(id: 36, from: [:]))
    }

    func testMalformedEntryReturnsNil() {
        let dict: [String: Any] = ["36": ["enabled": true,
                                          "value": ["parameters": [65535]]]]
        XCTAssertNil(ActionRunner.parseSymbolicHotkey(id: 36, from: dict))
    }
}

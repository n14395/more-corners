// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest
import AppKit
@testable import MoreCornersCore

final class ModifierKeysTests: XCTestCase {

    func testInitFromEventFlags() {
        XCTAssertEqual(ModifierKeys(flags: []), [])
        XCTAssertEqual(ModifierKeys(flags: .command), .command)
        XCTAssertEqual(ModifierKeys(flags: [.command, .shift]), [.command, .shift])
        XCTAssertEqual(ModifierKeys(flags: [.control, .option]), [.control, .option])
    }

    func testInitIgnoresNonChordFlags() {
        // Caps lock / function / numeric-pad flags are not part of a chord.
        let flags: NSEvent.ModifierFlags = [.command, .capsLock, .numericPad]
        XCTAssertEqual(ModifierKeys(flags: flags), .command)
    }

    func testSymbolsUseStandardOrder() {
        XCTAssertEqual(ModifierKeys([]).symbols, "")
        XCTAssertEqual(ModifierKeys.command.symbols, "⌘")
        XCTAssertEqual(ModifierKeys([.control, .command]).symbols, "⌃⌘")
        XCTAssertEqual(ModifierKeys([.control, .option, .shift, .command]).symbols, "⌃⌥⇧⌘")
        XCTAssertEqual(ModifierKeys([.command, .shift]).symbols, "⇧⌘")
    }

    func testExactEquality() {
        XCTAssertNotEqual(ModifierKeys.command, ModifierKeys([.command, .shift]))
        XCTAssertNotEqual(ModifierKeys.command, ModifierKeys.control)
    }

    func testCodableRoundTrip() throws {
        let value: ModifierKeys = [.command, .option]
        let data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(ModifierKeys.self, from: data), value)
    }
}

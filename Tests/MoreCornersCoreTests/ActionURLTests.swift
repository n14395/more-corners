import XCTest
@testable import MoreCornersCore

/// `ActionRunner.normalizedURL` — the Open URL action's tolerance for URL text
/// typed without a scheme.
final class ActionURLTests: XCTestCase {

    func testAddsHTTPSWhenSchemeMissing() {
        XCTAssertEqual(ActionRunner.normalizedURL(from: "example.com")?.absoluteString,
                       "https://example.com")
    }

    func testKeepsExistingScheme() {
        XCTAssertEqual(ActionRunner.normalizedURL(from: "http://example.com")?.absoluteString,
                       "http://example.com")
        XCTAssertEqual(ActionRunner.normalizedURL(from: "mailto:a@b.com")?.scheme, "mailto")
    }

    func testPreservesPathAndQuery() {
        XCTAssertEqual(ActionRunner.normalizedURL(from: "example.com/a?b=1")?.absoluteString,
                       "https://example.com/a?b=1")
    }

    func testEmptyOrBlankIsNil() {
        XCTAssertNil(ActionRunner.normalizedURL(from: ""))
        XCTAssertNil(ActionRunner.normalizedURL(from: "   "))
    }
}

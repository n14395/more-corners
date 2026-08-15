import XCTest
@testable import MoreCornersCore

/// `SpaceControl.tiledFrame` — the pure geometry behind the window-management
/// corner actions (halves, maximize, center).
final class WindowTilingTests: XCTestCase {

    /// A display's visible area: 1000×800 frame minus a 25 pt menu bar
    /// (top-left-origin coordinates, as AX uses).
    private let visible = CGRect(x: 0, y: 25, width: 1000, height: 775)

    func testHalvesSplitTheVisibleArea() {
        let window = CGRect(x: 300, y: 300, width: 400, height: 300)
        XCTAssertEqual(SpaceControl.tiledFrame(.leftHalf, window: window, visible: visible),
                       CGRect(x: 0, y: 25, width: 500, height: 775))
        XCTAssertEqual(SpaceControl.tiledFrame(.rightHalf, window: window, visible: visible),
                       CGRect(x: 500, y: 25, width: 500, height: 775))
    }

    func testMaximizeFillsTheVisibleArea() {
        let window = CGRect(x: 300, y: 300, width: 400, height: 300)
        XCTAssertEqual(SpaceControl.tiledFrame(.maximize, window: window, visible: visible),
                       visible)
    }

    func testCenterKeepsSizeAndCenters() {
        let window = CGRect(x: 10, y: 40, width: 400, height: 300)
        let centered = SpaceControl.tiledFrame(.center, window: window, visible: visible)
        XCTAssertEqual(centered.size, window.size)
        XCTAssertEqual(centered.origin.x, 300)               // (1000-400)/2
        XCTAssertEqual(centered.origin.y, 25 + 238)          // (775-300)/2 rounded
    }

    func testCenterClampsOversizedWindows() {
        let huge = CGRect(x: 0, y: 0, width: 2000, height: 2000)
        XCTAssertEqual(SpaceControl.tiledFrame(.center, window: huge, visible: visible),
                       visible)
    }

    func testTilingOnAnOffsetDisplay() {
        // A secondary display's visible area offset in global space: results
        // stay relative to that display, not the global origin.
        let secondary = CGRect(x: 1000, y: -200, width: 800, height: 600)
        let window = CGRect(x: 1100, y: 0, width: 300, height: 200)
        XCTAssertEqual(SpaceControl.tiledFrame(.leftHalf, window: window, visible: secondary),
                       CGRect(x: 1000, y: -200, width: 400, height: 600))
        XCTAssertEqual(SpaceControl.tiledFrame(.rightHalf, window: window, visible: secondary),
                       CGRect(x: 1400, y: -200, width: 400, height: 600))
    }
}

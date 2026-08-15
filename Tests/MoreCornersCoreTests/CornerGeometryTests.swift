import XCTest
@testable import MoreCornersCore

/// `CornerMonitor`'s pure geometry helpers: where each corner sits and whether
/// it is an exposed edge of the combined desktop (vs. butting against another
/// display).
final class CornerGeometryTests: XCTestCase {

    private let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testCornerPoints() {
        // NSScreen frames use a bottom-left origin with y increasing upward.
        XCTAssertEqual(CornerMonitor.point(of: .topLeft, in: frame), CGPoint(x: 0, y: 800))
        XCTAssertEqual(CornerMonitor.point(of: .topRight, in: frame), CGPoint(x: 1000, y: 800))
        XCTAssertEqual(CornerMonitor.point(of: .bottomLeft, in: frame), CGPoint(x: 0, y: 0))
        XCTAssertEqual(CornerMonitor.point(of: .bottomRight, in: frame), CGPoint(x: 1000, y: 0))
    }

    func testAllCornersExposedOnASingleDisplay() {
        let frames = [frame]
        for corner in Corner.allCases {
            let point = CornerMonitor.point(of: corner, in: frame)
            XCTAssertTrue(CornerMonitor.isExposed(corner: corner, point: point,
                                                  allFrames: frames),
                          "\(corner) should be exposed on a lone display")
        }
    }

    func testCornerAgainstADiagonalNeighborIsNotExposed() {
        // A second display sitting up-and-to-the-right of the primary's
        // top-right corner covers that corner's outward probe point.
        let neighbor = CGRect(x: 1000, y: 800, width: 500, height: 500)
        let frames = [frame, neighbor]

        let topRight = CornerMonitor.point(of: .topRight, in: frame)
        XCTAssertFalse(CornerMonitor.isExposed(corner: .topRight, point: topRight,
                                               allFrames: frames))

        // The primary's top-left is still a free edge.
        let topLeft = CornerMonitor.point(of: .topLeft, in: frame)
        XCTAssertTrue(CornerMonitor.isExposed(corner: .topLeft, point: topLeft,
                                              allFrames: frames))

        // And symmetrically, the neighbor's bottom-left butts against the primary.
        let neighborBL = CornerMonitor.point(of: .bottomLeft, in: neighbor)
        XCTAssertFalse(CornerMonitor.isExposed(corner: .bottomLeft, point: neighborBL,
                                               allFrames: frames))
    }

    // MARK: - Restore-point nudge (CG / top-left-origin coordinates)

    /// A CG-coordinate display: (0,0) is the top-left, y grows downward.
    private let cgBounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testNudgeMovesEachCornerJustOutsideItsZone() {
        let size: CGFloat = 6
        let clear = size + 4   // 10
        let cases: [(name: String, point: CGPoint, expected: CGPoint)] = [
            ("top-left", CGPoint(x: 2, y: 2), CGPoint(x: clear, y: clear)),
            ("top-right", CGPoint(x: 998, y: 3), CGPoint(x: 1000 - clear, y: clear)),
            ("bottom-left", CGPoint(x: 1, y: 797), CGPoint(x: clear, y: 800 - clear)),
            ("bottom-right", CGPoint(x: 999, y: 799), CGPoint(x: 1000 - clear, y: 800 - clear)),
        ]
        for c in cases {
            let out = CornerMonitor.nudgeOutOfCornerZone(c.point, bounds: cgBounds, size: size)
            XCTAssertEqual(out, c.expected, "\(c.name) should nudge just outside its zone")
            // The result must be clear of the zone on at least one axis.
            let dx = min(out.x - cgBounds.minX, cgBounds.maxX - out.x)
            let dy = min(out.y - cgBounds.minY, cgBounds.maxY - out.y)
            XCTAssertTrue(dx > size && dy > size, "\(c.name) still inside a corner zone")
        }
    }

    func testNudgeLeavesEdgeAndInteriorPointsUnchanged() {
        let size: CGFloat = 6
        // Hugging the left edge but centered vertically — not a corner zone.
        let leftEdge = CGPoint(x: 2, y: 400)
        XCTAssertEqual(CornerMonitor.nudgeOutOfCornerZone(leftEdge, bounds: cgBounds, size: size), leftEdge)
        // Interior.
        let center = CGPoint(x: 500, y: 400)
        XCTAssertEqual(CornerMonitor.nudgeOutOfCornerZone(center, bounds: cgBounds, size: size), center)
        // Just outside a corner zone already (7px in on both axes) — left alone.
        let justOut = CGPoint(x: 7, y: 7)
        XCTAssertEqual(CornerMonitor.nudgeOutOfCornerZone(justOut, bounds: cgBounds, size: size), justOut)
    }

    func testCoversDisplayDistinguishesFullScreenFromMaximized() {
        let display = CGRect(x: 0, y: 0, width: 2056, height: 1329)
        // Native full-screen: window == display.
        XCTAssertTrue(CornerMonitor.coversDisplay(windowBounds: display, displayBounds: display))
        // Borderless game 1px off — within tolerance.
        XCTAssertTrue(CornerMonitor.coversDisplay(
            windowBounds: CGRect(x: 0, y: 0, width: 2055, height: 1328), displayBounds: display))
        // Maximized: covers the visible frame (menu bar ~39px shorter) → NOT full-screen.
        XCTAssertFalse(CornerMonitor.coversDisplay(
            windowBounds: CGRect(x: 0, y: 39, width: 2056, height: 1290), displayBounds: display))
        // A small window.
        XCTAssertFalse(CornerMonitor.coversDisplay(
            windowBounds: CGRect(x: 190, y: 184, width: 64, height: 102), displayBounds: display))
    }

    func testNudgeRespectsDisplayOrigin() {
        // A secondary display offset in the global CG space: nudges are relative
        // to that display's own corner, not the global origin.
        let bounds = CGRect(x: 1000, y: -200, width: 800, height: 600)
        let size: CGFloat = 8
        let clear = size + 4
        let topLeft = CGPoint(x: 1003, y: -198)
        XCTAssertEqual(CornerMonitor.nudgeOutOfCornerZone(topLeft, bounds: bounds, size: size),
                       CGPoint(x: 1000 + clear, y: -200 + clear))
    }

    // MARK: - Adaptive polling: near-a-corner decision

    func testPointerNearACornerControlsFastPolling() {
        let frames = [frame]   // 1000×800 lone display
        XCTAssertTrue(CornerMonitor.pointerIsNearACorner(
            CGPoint(x: 100, y: 100), monitored: frames, all: frames),
            "100 pt from the bottom-left corner is near")
        XCTAssertFalse(CornerMonitor.pointerIsNearACorner(
            CGPoint(x: 500, y: 400), monitored: frames, all: frames),
            "screen center is far from every corner")
    }

    func testUnexposedCornersDoNotCountAsNear() {
        // A neighbor covers the primary's top-right corner probe, so proximity
        // to that (skipped) corner must not force fast polling.
        let neighbor = CGRect(x: 1000, y: 800, width: 500, height: 500)
        XCTAssertFalse(CornerMonitor.pointerIsNearACorner(
            CGPoint(x: 990, y: 790), monitored: [frame], all: [frame, neighbor]))
    }
}

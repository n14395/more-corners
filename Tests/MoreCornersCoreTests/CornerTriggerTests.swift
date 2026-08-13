import XCTest
@testable import MoreCornersCore

/// The dwell-and-rearm state machine, driven with simulated time and a fake
/// fire closure — no mouse, no clock.
final class CornerTriggerTests: XCTestCase {

    func testEnteringZoneStartsDwelling() {
        var t = CornerTrigger()
        t.update(inZone: true, beyondRearm: false, now: 0, dwell: 0.25) { true }
        XCTAssertEqual(t.phase, .dwelling(since: 0))
    }

    func testFiresOnlyAfterDwellElapses() {
        var t = CornerTrigger()
        var fireCount = 0
        let fire = { () -> Bool in fireCount += 1; return true }

        XCTAssertFalse(t.update(inZone: true, beyondRearm: false, now: 0, dwell: 0.25, fire: fire))
        XCTAssertFalse(t.update(inZone: true, beyondRearm: false, now: 0.1, dwell: 0.25, fire: fire))
        XCTAssertEqual(fireCount, 0, "must not fire before the dwell elapses")

        XCTAssertTrue(t.update(inZone: true, beyondRearm: false, now: 0.3, dwell: 0.25, fire: fire))
        XCTAssertEqual(fireCount, 1)
        XCTAssertEqual(t.phase, .fired)
    }

    func testLeavingZoneBeforeDwellResets() {
        var t = CornerTrigger()
        t.update(inZone: true, beyondRearm: false, now: 0, dwell: 0.25) { true }
        t.update(inZone: false, beyondRearm: false, now: 0.1, dwell: 0.25) { true }
        XCTAssertEqual(t.phase, .idle)
    }

    func testDoesNotRefireWhileParkedInCorner() {
        var t = CornerTrigger()
        var fireCount = 0
        let fire = { () -> Bool in fireCount += 1; return true }

        t.update(inZone: true, beyondRearm: false, now: 0, dwell: 0, fire: fire)  // fires
        // Staying in the zone must not fire again.
        for tick in 1...5 {
            t.update(inZone: true, beyondRearm: false, now: Double(tick), dwell: 0, fire: fire)
        }
        XCTAssertEqual(fireCount, 1)
        XCTAssertEqual(t.phase, .fired)
    }

    func testRearmsOnlyAfterMovingPastRearmDistance() {
        var t = CornerTrigger()
        var fireCount = 0
        let fire = { () -> Bool in fireCount += 1; return true }

        t.update(inZone: true, beyondRearm: false, now: 0, dwell: 0, fire: fire)  // enters dwell
        t.update(inZone: true, beyondRearm: false, now: 1, dwell: 0, fire: fire)  // fires
        XCTAssertEqual(fireCount, 1)
        // Still near the corner: stays fired.
        t.update(inZone: false, beyondRearm: false, now: 2, dwell: 0, fire: fire)
        XCTAssertEqual(t.phase, .fired)
        // Moves far away: rearms.
        t.update(inZone: false, beyondRearm: true, now: 3, dwell: 0, fire: fire)
        XCTAssertEqual(t.phase, .idle)
        // Returning and dwelling again fires a second time.
        t.update(inZone: true, beyondRearm: false, now: 4, dwell: 0, fire: fire)  // enters dwell
        t.update(inZone: true, beyondRearm: false, now: 5, dwell: 0, fire: fire)  // fires
        XCTAssertEqual(fireCount, 2)
    }

    func testStaysArmedWhenFireIsRefused() {
        // A modifier mismatch makes `fire` return false; the machine should
        // stay dwelling and fire as soon as the condition is satisfied.
        var t = CornerTrigger()
        var allow = false
        let fire = { () -> Bool in allow }

        XCTAssertFalse(t.update(inZone: true, beyondRearm: false, now: 0, dwell: 0, fire: fire))
        XCTAssertEqual(t.phase, .dwelling(since: 0))

        allow = true
        XCTAssertTrue(t.update(inZone: true, beyondRearm: false, now: 0.05, dwell: 0, fire: fire))
        XCTAssertEqual(t.phase, .fired)
    }
}

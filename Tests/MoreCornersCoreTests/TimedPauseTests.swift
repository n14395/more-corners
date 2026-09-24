// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import MoreCornersCore

/// `TimedPause.decide` — restoring a persisted timed pause at launch, so
/// "pause for an hour" can't silently become "paused forever" across a
/// relaunch.
final class TimedPauseTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testNoStoredDeadlineDoesNothing() {
        XCTAssertEqual(TimedPause.decide(now: now, until: nil, enabled: false), .none)
        XCTAssertEqual(TimedPause.decide(now: now, until: nil, enabled: true), .none)
    }

    func testEnabledClearsAStaleDeadline() {
        // Corners are on, so any leftover deadline is stale — no pause restored.
        let future = now.addingTimeInterval(600)
        XCTAssertEqual(TimedPause.decide(now: now, until: future, enabled: true), .none)
    }

    func testPastDeadlineResumes() {
        let past = now.addingTimeInterval(-60)
        XCTAssertEqual(TimedPause.decide(now: now, until: past, enabled: false), .resume)
    }

    func testFutureDeadlineRearms() {
        let future = now.addingTimeInterval(600)
        XCTAssertEqual(TimedPause.decide(now: now, until: future, enabled: false),
                       .rearm(future))
    }
}

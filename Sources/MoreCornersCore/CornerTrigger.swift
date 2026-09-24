// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Pure state machine for one corner's dwell-and-rearm behavior, factored out
/// of `CornerMonitor` so it can be unit tested without a mouse or displays.
///
/// Lifecycle for a single visit to a corner:
///   idle → (pointer enters) → dwelling → (dwell elapses) → fires → fired
///   fired → (pointer moves past the rearm distance) → idle
/// Leaving the zone before the dwell elapses returns to idle without firing.
struct CornerTrigger: Equatable {
    enum Phase: Equatable {
        case idle
        case dwelling(since: TimeInterval)
        case fired
    }

    private(set) var phase: Phase = .idle

    /// Advance the machine by one tick.
    ///
    /// - Parameters:
    ///   - inZone: whether the pointer is within the corner's hot zone.
    ///   - beyondRearm: whether the pointer has moved past the re-arm distance
    ///     (only consulted in the `.fired` phase).
    ///   - now: current time (monotonic seconds).
    ///   - dwell: required dwell duration before firing.
    ///   - fire: invoked when the dwell completes; returns whether the action
    ///     actually ran. `false` (e.g. a modifier mismatch) keeps the machine
    ///     armed so it fires as soon as the condition is satisfied.
    /// - Returns: `true` if the action fired on this tick.
    @discardableResult
    mutating func update(inZone: Bool, beyondRearm: Bool, now: TimeInterval,
                         dwell: TimeInterval, fire: () -> Bool) -> Bool {
        switch phase {
        case .idle:
            if inZone { phase = .dwelling(since: now) }
        case .dwelling(let since):
            if !inZone {
                phase = .idle
            } else if now - since >= dwell {
                if fire() {
                    phase = .fired
                    return true
                }
            }
        case .fired:
            if beyondRearm { phase = .idle }
        }
        return false
    }
}

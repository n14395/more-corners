import AppKit
import Combine

/// Watches the global mouse location and fires corner actions.
///
/// Uses polling of `NSEvent.mouseLocation` (no special permissions needed),
/// with a dwell delay before firing and a hysteresis zone after firing so an
/// action runs once per visit to the corner. Polling is adaptive: fast only
/// while the pointer is near a corner (or mid-dwell), slow when idle, stopped
/// while hot corners are disabled, and a bare heartbeat at the lock screen.
final class CornerMonitor {
    private var triggers: [String: CornerTrigger] = [:]
    private var timer: Timer?
    private var enabledCancellable: AnyCancellable?
    /// Lock screen / screensaver: corners never fire there.
    private var sessionSuspended = false
    /// True while a destructive-action confirmation alert is up.
    private var confirmInFlight = false

    /// Poll cadences. Fast matches the old fixed rate; idle saves energy when
    /// the pointer is nowhere near a corner; suspended is a backstop heartbeat
    /// while locked (the unlock notification normally wakes us immediately).
    private static let activeInterval: TimeInterval = 0.05
    private static let idleInterval: TimeInterval = 0.12
    private static let suspendedInterval: TimeInterval = 2.0
    /// Chebyshev distance within which a corner counts as "near" (fast polling).
    static let nearDistance: CGFloat = 300

    func start() {
        sessionSuspended = Self.sessionIsLocked()
        observeSessionState()
        // tick() stops rescheduling while hot corners are disabled, so a
        // re-enable (menu, Settings, timed-pause expiry) must wake the loop.
        enabledCancellable = AppSettings.shared.$enabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled { self?.scheduleTick(after: 0.01) }
            }
        scheduleTick(after: 0.01)
    }

    /// Schedules the next poll, replacing any pending one (idempotent).
    private func scheduleTick(after interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Watches lock/unlock and screensaver notifications so polling all but
    /// stops while no user session is interactive (and can never fire there).
    private func observeSessionState() {
        let center = DistributedNotificationCenter.default()
        let events: [(name: String, suspends: Bool)] = [
            ("com.apple.screenIsLocked", true),
            ("com.apple.screenIsUnlocked", false),
            ("com.apple.screensaver.didstart", true),
            ("com.apple.screensaver.didstop", false),
        ]
        for event in events {
            center.addObserver(forName: Notification.Name(event.name), object: nil,
                               queue: .main) { [weak self] _ in
                guard let self else { return }
                // On a wake event, re-check the real lock state: the saver can
                // stop while the screen is still locked.
                self.sessionSuspended = event.suspends || Self.sessionIsLocked()
                if !self.sessionSuspended { self.scheduleTick(after: 0.05) }
            }
        }
    }

    /// Whether the login session is at the lock screen, per the window server.
    static func sessionIsLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return (dict["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    }

    private func tick() {
        let settings = AppSettings.shared
        guard settings.enabled else {
            triggers.removeAll()
            DwellHint.hide()
            return   // no reschedule — the $enabled subscription wakes us
        }
        guard !sessionSuspended else {
            triggers.removeAll()
            DwellHint.hide()
            scheduleTick(after: Self.suspendedInterval)
            return
        }
        // Don't fire while a drag/selection or a confirmation alert is up.
        guard NSEvent.pressedMouseButtons == 0, !confirmInFlight else {
            DwellHint.hide()
            scheduleTick(after: Self.activeInterval)
            return
        }

        let pointer = NSEvent.mouseLocation
        let allFrames = NSScreen.screens.map(\.frame)
        let screens = settings.allScreens ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        // Slam mode: fire the instant the pointer reaches the corner (a tiny zone,
        // no dwell). Otherwise dwell inside the configured `cornerSize` zone.
        let cornerSize = max(2, settings.cornerSize)
        let size = settings.slamToActivate ? Self.slamZone : cornerSize
        let dwell = settings.slamToActivate ? 0 : settings.dwell
        // Re-arm distance stays generous (based on the configured size) in both
        // modes, so a jitter in the corner can't double-fire.
        let rearm = max(40, cornerSize * 5)
        let now = Date().timeIntervalSinceReferenceDate
        var dwellHint: (corner: Corner, screen: NSScreen, progress: Double, label: String)?

        for (index, screen) in screens.enumerated() {
            let frame = screen.frame
            for corner in Corner.allCases {
                let key = "\(index).\(corner.rawValue)"
                let cp = Self.point(of: corner, in: frame)

                // Skip corners that sit against another display (mid-desktop),
                // so the pointer can cross between monitors without triggering.
                guard Self.isExposed(corner: corner, point: cp, allFrames: allFrames) else {
                    triggers[key] = nil
                    continue
                }

                let dx = abs(pointer.x - cp.x)
                let dy = abs(pointer.y - cp.y)
                let inZone = dx <= size && dy <= size
                let beyondRearm = dx > rearm || dy > rearm

                var trigger = triggers[key] ?? CornerTrigger()
                trigger.update(inZone: inZone, beyondRearm: beyondRearm, now: now,
                               dwell: dwell) { self.fire(corner, on: screen) }
                triggers[key] = trigger

                // Dwell HUD (opt-in): progress toward firing plus what will fire.
                if case .dwelling(let since) = trigger.phase, inZone,
                   settings.feedbackDwellHint, dwell >= 0.15 {
                    let held = ModifierKeys(flags: NSEvent.modifierFlags)
                    dwellHint = (corner, screen, min(1, (now - since) / dwell),
                                 Self.dwellLabel(for: settings.config(for: corner),
                                                 held: held))
                }
            }
        }

        if let hint = dwellHint {
            DwellHint.show(corner: hint.corner, on: hint.screen,
                           progress: hint.progress, label: hint.label)
        } else {
            DwellHint.hide()
        }
        let near = Self.pointerIsNearACorner(pointer, monitored: screens.map(\.frame),
                                             all: allFrames)
        scheduleTick(after: near ? Self.activeInterval : Self.idleInterval)
    }

    /// Whether the pointer is within `threshold` (Chebyshev) of any exposed
    /// corner of the monitored frames — tick()'s fast-vs-idle poll decision.
    /// Pure — exposed for unit testing.
    static func pointerIsNearACorner(_ pointer: CGPoint, monitored: [CGRect],
                                     all: [CGRect],
                                     threshold: CGFloat = nearDistance) -> Bool {
        for frame in monitored {
            for corner in Corner.allCases {
                let cp = point(of: corner, in: frame)
                guard isExposed(corner: corner, point: cp, allFrames: all) else { continue }
                if max(abs(pointer.x - cp.x), abs(pointer.y - cp.y)) <= threshold {
                    return true
                }
            }
        }
        return false
    }

    /// The caption for the dwell HUD: the action that will fire for the held
    /// modifiers — or, when nothing matches yet (a modifier-only corner), a
    /// hint listing up to two of its modifier variants. Pure — for testing.
    static func dwellLabel(for config: CornerConfig, held: ModifierKeys) -> String {
        if let spec = config.resolve(held: held) { return spec.action.label }
        let hints = config.variants
            .filter { !$0.modifiers.isEmpty && $0.spec.action != .none }
            .prefix(2)
            .map { "\($0.modifiers.symbols) \($0.spec.action.label)" }
        return hints.isEmpty ? "" : "Hold " + hints.joined(separator: " · ")
    }

    private func fire(_ corner: Corner, on screen: NSScreen) -> Bool {
        let settings = AppSettings.shared
        let config = settings.config(for: corner)
        // A configured-but-disabled corner is inert; consume the trigger so it
        // doesn't keep retrying. isConfigured guards blank corners.
        guard config.isConfigured, config.enabled else { return true }
        let held = ModifierKeys(flags: NSEvent.modifierFlags)
        guard let spec = config.resolve(held: held) else {
            // Nothing matches the current modifiers (e.g. only modifier
            // overrides are set): keep dwelling so the action fires the
            // moment the right modifiers are pressed.
            return false
        }
        // Suppression: full-screen apps and per-app exclusions. Only query the
        // (relatively costly) window list when full-screen suppression is on.
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isFullScreen = settings.suppressInFullScreen ? Self.frontmostIsFullScreen() : false
        if settings.shouldSuppress(frontmostBundleID: bundleID, isFullScreen: isFullScreen) {
            return true
        }
        // Opt-in guard for destructive actions — corner triggers only (the
        // menu and ▶ test buttons are explicit intent and run immediately).
        if settings.confirmDestructive && spec.action.isDestructive {
            presentDestructiveConfirmation(spec, corner: corner, screen: screen)
            return true
        }
        ActionRunner.run(spec)
        TriggerFeedback.play(corner: corner, on: screen)
        return true
    }

    /// Asks before running a destructive corner action. The alert runs outside
    /// the tick, and `confirmInFlight` keeps the corner from re-firing and
    /// stacking alerts while one is up.
    private func presentDestructiveConfirmation(_ spec: ActionSpec, corner: Corner,
                                                screen: NSScreen) {
        confirmInFlight = true
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = "Run “\(spec.action.label)”?"
            alert.informativeText = "Triggered by the \(corner.label.lowercased()) hot corner."
            alert.addButton(withTitle: "Run")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            let confirmed = alert.runModal() == .alertFirstButtonReturn
            self?.confirmInFlight = false
            if confirmed {
                ActionRunner.run(spec)
                TriggerFeedback.play(corner: corner, on: screen)
            }
        }
    }

    /// Whether the frontmost app's front window covers its entire display (native
    /// or borderless full-screen), distinct from a merely maximized window (which
    /// leaves the menu-bar strip). Uses the window list only — no permissions.
    static func frontmostIsFullScreen() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let infos = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        for info in infos {   // front-to-back z-order
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let boundsDict = info[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary)
            else { continue }
            return coversWholeDisplay(rect)          // the app's frontmost window
        }
        return false
    }

    private static func coversWholeDisplay(_ rect: CGRect) -> Bool {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return false }
        for i in 0..<Int(count) where CGDisplayBounds(ids[i]).contains(center) {
            return coversDisplay(windowBounds: rect, displayBounds: CGDisplayBounds(ids[i]))
        }
        return false
    }

    /// Whether a window covers its whole display (native/borderless full-screen),
    /// distinct from a maximized window that leaves the menu-bar strip. A 2px
    /// tolerance absorbs rounding. Pure — for testing.
    static func coversDisplay(windowBounds: CGRect, displayBounds: CGRect) -> Bool {
        windowBounds.width >= displayBounds.width - 2
            && windowBounds.height >= displayBounds.height - 2
    }

    /// Half-size of the slam-mode hot zone: the pointer must reach within this
    /// many points of the corner on both axes. Small enough that only actually
    /// hitting the corner triggers, with a little tolerance for cursor rounding.
    static let slamZone: CGFloat = 2

    static func point(of corner: Corner, in frame: CGRect) -> CGPoint {
        CGPoint(x: corner.isLeft ? frame.minX : frame.maxX,
                y: corner.isBottom ? frame.minY : frame.maxY)
    }

    static func isExposed(corner: Corner, point: CGPoint, allFrames: [CGRect]) -> Bool {
        let probe = CGPoint(x: point.x + (corner.isLeft ? -2 : 2),
                            y: point.y + (corner.isBottom ? -2 : 2))
        return !allFrames.contains { $0.insetBy(dx: -1, dy: -1).contains(probe) }
    }

    /// Nudges a cursor-restore point out of any hot-corner trigger zone. Actions
    /// that warp the cursor away and then restore it (the window move, cross-display
    /// menu-bar clicks) call this so landing back in the corner that launched them
    /// doesn't immediately re-fire it. Points not already inside a corner zone are
    /// returned unchanged.
    ///
    /// `point` is in CG global coordinates (top-left origin) — as produced by
    /// `CGEvent.location` and consumed by `CGWarpMouseCursorPosition`. The zone
    /// matches `tick()`'s: within `cornerSize` of a corner on both axes.
    static func restorePointClearOfCornerZones(_ point: CGPoint) -> CGPoint {
        let size = max(2, AppSettings.shared.cornerSize)
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success,
              let bounds = (0..<Int(count)).map({ CGDisplayBounds(ids[$0]) })
                  .first(where: { $0.contains(point) }) else { return point }
        return nudgeOutOfCornerZone(point, bounds: bounds, size: size)
    }

    /// Pure geometry for `restorePointClearOfCornerZones`: if `point` lies within
    /// `size` of a corner of `bounds` on both axes (a trigger zone), return it
    /// nudged `size + 4` inward from those edges; otherwise return it unchanged.
    /// Coordinates are top-left-origin, so `minY` is the top edge.
    static func nudgeOutOfCornerZone(_ point: CGPoint, bounds: CGRect, size: CGFloat) -> CGPoint {
        let clearance = size + 4
        let nearLeft = point.x - bounds.minX <= size
        let nearRight = bounds.maxX - point.x <= size
        let nearTop = point.y - bounds.minY <= size
        let nearBottom = bounds.maxY - point.y <= size
        guard (nearLeft || nearRight) && (nearTop || nearBottom) else { return point }
        var p = point
        if nearLeft { p.x = bounds.minX + clearance }
        else if nearRight { p.x = bounds.maxX - clearance }
        if nearTop { p.y = bounds.minY + clearance }
        else if nearBottom { p.y = bounds.maxY - clearance }
        return p
    }
}

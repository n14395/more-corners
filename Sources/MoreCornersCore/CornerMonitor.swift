import AppKit

/// Watches the global mouse location and fires corner actions.
///
/// Uses polling of `NSEvent.mouseLocation` (no special permissions needed),
/// with a dwell delay before firing and a hysteresis zone after firing so an
/// action runs once per visit to the corner.
final class CornerMonitor {
    private var triggers: [String: CornerTrigger] = [:]
    private var timer: Timer?

    func start() {
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let settings = AppSettings.shared
        guard settings.enabled else {
            if !triggers.isEmpty { triggers.removeAll() }
            return
        }
        // Don't fire while a drag/selection is in progress.
        guard NSEvent.pressedMouseButtons == 0 else { return }

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
            }
        }
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
        ActionRunner.run(spec)
        TriggerFeedback.play(corner: corner, on: screen)
        return true
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

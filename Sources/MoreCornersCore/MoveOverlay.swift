// Copyright 2026 Nick Fay
// SPDX-License-Identifier: Apache-2.0

import AppKit
import CoreGraphics

/// A tiny transparent panel that catches the synthetic mouse-down the
/// SkyLight window-drag binds to — ported (and trimmed) from WindowShift's
/// GrabOverlay.
///
/// `SLSDragWindowRelativeToMouse` binds to a mouse button that is already
/// down. The space-move has to put one down somewhere, but the pointer is at a
/// screen corner (a hot corner fired), so a down there would open a menu or
/// click whatever app sits under it. Instead the down lands on this panel,
/// which belongs to us and does nothing with it. Since no drag events follow
/// (only the "Move a space" chord), the panel never has to track anything —
/// it just has to exist, on screen, when the down is posted.
///
/// The load-bearing properties, each measured by WindowShift:
///  - **Non-activating panel** — a plain window would make MoreCorners
///    frontmost, and the native "Move a space" chord acts on the frontmost
///    window; the target must stay frontmost.
///  - **Above everything** — at the maximum window level, so the down lands
///    here and not on a window sitting at the same point.
///  - **Visible to the window list** (no `sharingType = .none`) — the
///    readiness check reads the panel's own window-list entry, which
///    sharing-none windows never get. It draws nothing, so it can't be seen.
///  - **The down must wait for the server.** `orderFront` returning does not
///    make the panel hit-testable; `isReady` reports true only once the window
///    server lists the panel as on screen.
///
/// `show`/`hide` hop to the main thread; `isReady` is safe to poll from the
/// background move thread.
final class MoveOverlay {
    /// Small, like WindowShift's — a large panel is hit-tested past at high
    /// window levels and absorbs nothing.
    static let size: CGFloat = 40

    private var panel: NSPanel?
    private let lock = NSLock()
    private var shown = false
    private var windowID: CGWindowID = 0
    private var serverConfirmed = false

    /// True once the panel is ordered front AND the window server lists it as
    /// on screen — only then will a synthetic down actually land on it.
    var isReady: Bool {
        lock.lock()
        let ordered = shown, confirmed = serverConfirmed, wid = windowID
        lock.unlock()
        guard ordered, wid != 0 else { return false }
        if confirmed { return true }
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], wid)
                as? [[String: Any]],
              let entry = list.first,
              (entry[kCGWindowIsOnscreen as String] as? Bool) == true else { return false }
        lock.lock(); serverConfirmed = true; lock.unlock()
        return true
    }

    /// Place the panel centred on a CG (top-left origin) point and show it.
    func show(atCG point: CGPoint) {
        lock.lock(); serverConfirmed = false; lock.unlock()
        DispatchQueue.main.async { [self] in
            guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
            let panel = panel ?? makePanel()
            // AppKit is y-up off the primary screen's height; correct for
            // displays at negative coordinates too.
            panel.setFrameOrigin(NSPoint(x: point.x - Self.size / 2,
                                         y: primaryHeight - point.y - Self.size / 2))
            panel.orderFrontRegardless()
            lock.lock()
            shown = true
            windowID = CGWindowID(panel.windowNumber)
            lock.unlock()
        }
    }

    func hide() {
        lock.lock(); shown = false; serverConfirmed = false; lock.unlock()
        DispatchQueue.main.async { [self] in panel?.orderOut(nil) }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false   // must absorb the down, not pass it through
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary]
        panel.setAccessibilityElement(false)
        panel.contentView?.setAccessibilityElement(false)
        self.panel = panel
        return panel
    }
}

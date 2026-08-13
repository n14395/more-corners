import AppKit

/// Switches spaces and moves windows between spaces without simulating the
/// keyboard — by posting synthetic dock-swipe gestures (the technique from the
/// SpacesMenu app). On macOS 27+ the gesture events must carry a serialized
/// IOHID payload in CGEvent field 4205 or the window server ignores them.
///
/// Moving a window between spaces uses the private CGS window-server call. Apple
/// restricted that call for unentitled apps on macOS 26+, where it silently
/// no-ops — so the move is *verified* and, when the OS blocks it, the action
/// beeps and logs instead of pretending it worked.
enum SpaceControl {

    // MARK: - Public API

    /// Slide to the adjacent space on the display under the pointer.
    static func switchSpace(next: Bool) {
        guard AXIsProcessTrusted() else { return }
        SystemEventPoster().postFlick(goRight: next, velocity: flickVelocity)
    }

    /// Move the focused window to the adjacent space and follow it there.
    ///
    /// The private `CGSMoveWindowsToManagedSpace` call no-ops for unentitled apps
    /// on macOS 26+, so instead we reproduce the manual technique (from SpacesMenu):
    /// grab the window's title bar with a synthetic mouse-down and, while holding
    /// it, trigger the native "Move a space" shortcut — the held window rides
    /// across to the adjacent space and we follow it. Two details are essential:
    ///  • The mouse events must clear their flags — `CGEventSource(.hidSystemState)`
    ///    folds in the live hardware modifiers, and since this action is usually
    ///    triggered with a modifier held (e.g. a ⌃+corner), the grab would become
    ///    a control-click (right-click) that never picks the window up.
    ///  • The chord is read live from the user's actual "Move left/right a space"
    ///    binding (symbolic hotkey 79/81), so a remapped shortcut still works.
    /// Beeps if the window doesn't arrive.
    static func moveFocusedWindow(next: Bool) {
        guard AXIsProcessTrusted() else { NSSound.beep(); return }
        guard let (wid, element) = focusedWindowElement() else { NSSound.beep(); return }
        guard let (target, _) = adjacentSpace(of: wid, next: next) else {
            NSSound.beep()  // already at an edge, or spaces unreadable
            return
        }
        guard let grab = titleBarGrabPoint(for: element) else { NSSound.beep(); return }
        let originalFrame = axFrame(element)

        // Drive the user's real "Move left/right a space" shortcut (79/81), read
        // live. Arrow-key chords carry the fn bit, which the plist parse drops —
        // add it back. Enable the shortcut for the move if it was off, then restore.
        let hotkeyID: Int32 = next ? 81 : 79
        let bound = symbolicHotkeyBinding(id: Int(hotkeyID))
        let keyCode = bound?.keyCode ?? CGKeyCode(next ? 0x7C : 0x7B)
        let flags = (bound?.flags ?? .maskControl).union(.maskSecondaryFn)
        let modKey = representativeModifierKey(for: flags)
        let wasEnabled = symbolicHotkeyEnabled(hotkeyID)
        if wasEnabled == false { setSymbolicHotkeyEnabled(hotkeyID, true) }

        // Ask peer space managers (e.g. SpacesMenu) to stand their event tap down
        // for the move, so the native "Move a space" shortcut reaches the window
        // server and carries the grabbed window instead of being swallowed.
        postMoveCoordination(began: true)

        DispatchQueue.global(qos: .userInteractive).async {
            let src = CGEventSource(stateID: .hidSystemState)
            src?.localEventsSuppressionInterval = 0
            usleep(80_000)   // give the "move began" signal time to reach peers
            let restoreMouse = CGEvent(source: nil)?.location ?? grab
            func mouse(_ type: CGEventType, _ point: CGPoint) {
                CGWarpMouseCursorPosition(point)
                let e = CGEvent(mouseEventSource: src, mouseType: type,
                                mouseCursorPosition: point, mouseButton: .left)
                e?.flags = []   // clear live hardware modifiers (else ⌃ → control-click)
                e?.post(tap: .cgSessionEventTap)
            }
            func key(_ code: CGKeyCode, _ down: Bool, keyFlags: CGEventFlags, flagsChanged: Bool = false) {
                let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
                if flagsChanged { e?.type = .flagsChanged }
                e?.flags = keyFlags
                e?.post(tap: .cgSessionEventTap)
            }
            func waitForVisible(_ id: UInt64, tries: Int) -> Bool {
                for _ in 0..<tries {
                    if currentVisibleSpaceIDs().contains(id) { return true }
                    usleep(30_000)
                }
                return false
            }

            mouse(.mouseMoved, grab); usleep(30_000)
            mouse(.leftMouseDown, grab); usleep(110_000)                  // single clean grab
            key(modKey, true, keyFlags: flags, flagsChanged: true); usleep(40_000)   // modifiers held
            key(keyCode, true, keyFlags: flags); usleep(40_000)           // "move a space" chord
            key(keyCode, false, keyFlags: flags)
            _ = waitForVisible(target, tries: 40)                         // wait for the viewport flip
            usleep(120_000)                                               // hold the grab while it lands
            key(modKey, false, keyFlags: [], flagsChanged: true); usleep(30_000)     // modifiers up
            mouse(.leftMouseUp, grab)                                     // single drop

            var landed = false
            for _ in 0..<16 {
                if spaceIDs(for: wid).contains(target) { landed = true; break }
                usleep(50_000)
            }
            if let f = originalFrame { setAXFrame(element, f) }           // undo any drag displacement
            // Restore the cursor just OUTSIDE the corner zone that launched this,
            // so warping back doesn't immediately re-trigger the hot corner.
            CGWarpMouseCursorPosition(CornerMonitor.restorePointClearOfCornerZones(restoreMouse))
            if wasEnabled == false { setSymbolicHotkeyEnabled(hotkeyID, false) }
            postMoveCoordination(began: false)
            if !landed { DispatchQueue.main.async { NSSound.beep() } }
        }
    }

    /// Distributed-notification names a peer space manager can observe to stand
    /// its event tap down while MoreCorners performs a title-bar-drag window move.
    static let moveBeganNotification = "dev.nwf.MoreCorners.windowMoveBegan"
    static let moveEndedNotification = "dev.nwf.MoreCorners.windowMoveEnded"

    private static func postMoveCoordination(began: Bool) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(began ? moveBeganNotification : moveEndedNotification),
            object: nil, userInfo: nil, deliverImmediately: true)
    }

    // MARK: - Gesture velocity

    /// Release velocity of a natural-mode flick — the Dock finishes the slide
    /// with its own smooth animation (measured on macOS 27; see SpacesMenu).
    static let flickVelocity = 30.0

    /// Double → 16.16 fixed-point, clamped, never truncating a small non-zero to 0.
    static func toFixedPoint(_ value: Double) -> Int32 {
        let scaled = value * 65536.0
        if scaled >= Double(Int32.max) { return Int32.max }
        if scaled <= Double(Int32.min) { return Int32.min }
        let fixed = Int32(scaled)
        if fixed == 0 && value != 0 { return value > 0 ? 1 : -1 }
        return fixed
    }

    // MARK: - Window server (private CGS symbols, resolved lazily)

    private typealias MainConnFn = @convention(c) () -> Int32
    private typealias CopyDisplaySpacesFn = @convention(c) (Int32) -> CFArray?
    private typealias CopySpacesForWindowsFn = @convention(c) (Int32, UInt32, CFArray) -> CFArray?
    private typealias AXWindowIDFn = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError

    private static func sym<T>(_ name: String, _ type: T.Type) -> T? {
        dlsym(dlopen(nil, RTLD_NOW), name).map { unsafeBitCast($0, to: type) }
    }

    private static let connection: Int32 = { sym("CGSMainConnectionID", MainConnFn.self)?() ?? 0 }()

    private static func focusedWindowElement() -> (wid: UInt32, element: AXUIElement)? {
        guard let getWindow = sym("_AXUIElementGetWindow", AXWindowIDFn.self),
              let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString,
                                            &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        var wid: UInt32 = 0
        guard getWindow(element, &wid) == .success, wid != 0 else { return nil }
        return (wid, element)
    }

    /// The grab point for the title-bar drag: the center of the gap between the
    /// close (red) and minimize (yellow) traffic-light buttons — draggable window
    /// chrome on every standard window. The area right of the buttons is often a
    /// unified toolbar/tab bar (Terminal, browsers, Finder) that eats the grab.
    /// Falls back to just right of the zoom button, then the frame top-center.
    private static func titleBarGrabPoint(for element: AXUIElement) -> CGPoint? {
        if let close = buttonRect(element, kAXCloseButtonAttribute as String),
           let minimize = buttonRect(element, kAXMinimizeButtonAttribute as String) {
            return CGPoint(x: (close.midX + minimize.midX) / 2,
                           y: (close.midY + minimize.midY) / 2)
        }
        if let zoom = buttonRect(element, kAXZoomButtonAttribute as String) {
            return CGPoint(x: zoom.maxX + 5, y: zoom.midY)
        }
        if let frame = axFrame(element) {
            return CGPoint(x: frame.midX, y: frame.minY + 11)
        }
        return nil
    }

    /// The AX frame of a window's title-bar button (close / minimize / zoom).
    private static func buttonRect(_ window: AXUIElement, _ attribute: String) -> CGRect? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &ref) == .success,
              let b = ref, CFGetTypeID(b) == AXUIElementGetTypeID() else { return nil }
        return axFrame(b as! AXUIElement)
    }

    /// A representative modifier virtual-key for a flags set, for the flagsChanged
    /// frame that announces the modifiers as physically held.
    private static func representativeModifierKey(for flags: CGEventFlags) -> CGKeyCode {
        if flags.contains(.maskControl) { return 0x3B }
        if flags.contains(.maskAlternate) { return 0x3A }
        if flags.contains(.maskCommand) { return 0x37 }
        if flags.contains(.maskShift) { return 0x38 }
        return 0x3B
    }

    /// The user's live binding for a Mission Control symbolic hotkey, from
    /// `com.apple.symbolichotkeys` (what System Settings shows). nil if unset or
    /// disabled. `parameters = [asciiChar, virtualKeyCode, modifierMask]`; the
    /// mask's bit positions (shift 17, control 18, option 19, command 20) coincide
    /// with CGEventFlags.
    private static func symbolicHotkeyBinding(id: Int) -> (keyCode: CGKeyCode, flags: CGEventFlags)? {
        guard let table = UserDefaults.standard
                .persistentDomain(forName: "com.apple.symbolichotkeys")?["AppleSymbolicHotKeys"]
                as? [String: Any],
              let entry = table[String(id)] as? [String: Any],
              (entry["enabled"] as? Bool) == true,
              let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [Int], params.count >= 3 else { return nil }
        let vk = params[1]
        guard vk >= 0, vk < 0xFFFF else { return nil }   // 65535 == "no key code"
        let modMask = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)
        return (CGKeyCode(vk), CGEventFlags(rawValue: UInt64(params[2] & modMask)))
    }

    // boolean_t / _Bool differ in width across the CGS headers; take the enabled
    // flag as Int32 (0/1) so the low byte is correct either way.
    private typealias IsSHKEnabledFn = @convention(c) (Int32) -> DarwinBoolean
    private typealias SetSHKEnabledFn = @convention(c) (Int32, Int32) -> Int32

    private static func symbolicHotkeyEnabled(_ id: Int32) -> Bool? {
        sym("CGSIsSymbolicHotKeyEnabled", IsSHKEnabledFn.self).map { $0(id).boolValue }
    }
    private static func setSymbolicHotkeyEnabled(_ id: Int32, _ enabled: Bool) {
        _ = sym("CGSSetSymbolicHotKeyEnabled", SetSHKEnabledFn.self)?(id, enabled ? 1 : 0)
    }

    /// An AX element's frame in top-left-origin global points.
    private static func axFrame(_ element: AXUIElement) -> CGRect? {
        var pRef: CFTypeRef?, sRef: CFTypeRef?
        var p = CGPoint.zero, s = CGSize.zero
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sRef) == .success,
              AXValueGetValue(pRef as! AXValue, .cgPoint, &p),
              AXValueGetValue(sRef as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    private static func setAXFrame(_ element: AXUIElement, _ frame: CGRect) {
        var p = frame.origin, s = frame.size
        if let pv = AXValueCreate(.cgPoint, &p) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pv)
        }
        if let sv = AXValueCreate(.cgSize, &s) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sv)
        }
    }

    /// The managed-space id currently visible on each display, read live.
    private static func currentVisibleSpaceIDs() -> Set<UInt64> {
        guard let copyDisplays = sym("CGSCopyManagedDisplaySpaces", CopyDisplaySpacesFn.self),
              let displays = copyDisplays(connection) as? [[String: Any]] else { return [] }
        var out = Set<UInt64>()
        for display in displays {
            guard let current = display["Current Space"] as? [String: Any],
                  let id = (current["ManagedSpaceID"] as? NSNumber)?.uint64Value else { continue }
            out.insert(id)
        }
        return out
    }

    private static func spaceIDs(for wid: UInt32) -> [UInt64] {
        guard let copyForWin = sym("CGSCopySpacesForWindows", CopySpacesForWindowsFn.self)
            else { return [] }
        var w = Int64(wid)
        let arr = [CFNumberCreate(nil, .sInt64Type, &w)!] as CFArray
        return (copyForWin(connection, 0x7, arr) as? [NSNumber])?.map(\.uint64Value) ?? []
    }

    /// The managed space id adjacent to the window's current space, in the
    /// ordered space list of the display that holds it. Returns nil at an edge.
    private static func adjacentSpace(of wid: UInt32, next: Bool) -> (target: UInt64, current: UInt64)? {
        guard let copyDisplays = sym("CGSCopyManagedDisplaySpaces", CopyDisplaySpacesFn.self),
              let displays = copyDisplays(connection) as? [[String: Any]] else { return nil }
        let windowSpaces = Set(spaceIDs(for: wid))
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            let ids = spaces.compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value }
            // The window's current space is the one it belongs to on this display.
            guard let index = ids.firstIndex(where: { windowSpaces.contains($0) }) else { continue }
            let neighbor = next ? index + 1 : index - 1
            guard ids.indices.contains(neighbor) else { return nil }
            return (ids[neighbor], ids[index])
        }
        return nil
    }

    // MARK: - Undocumented CGEvent gesture fields

    static let eventTypeField = CGEventField(rawValue: 55)!
    static let gestureHIDType = CGEventField(rawValue: 110)!
    static let swipeMotion = CGEventField(rawValue: 123)!
    static let swipeProgress = CGEventField(rawValue: 124)!
    static let swipeVelocityX = CGEventField(rawValue: 129)!
    static let swipeVelocityY = CGEventField(rawValue: 130)!
    static let gesturePhase = CGEventField(rawValue: 132)!
    static let swipePositionX = CGEventField(rawValue: 125)!
    static let gesturePhase2 = CGEventField(rawValue: 134)!
    static let gestureFlavor = CGEventField(rawValue: 138)!
    static let eventTimestamp = CGEventField(rawValue: 169)!

    static let dockControl: Int64 = 30
    static let hidDockSwipe: Int64 = 23
    static let motionHorizontal: Int64 = 1
}

// MARK: - macOS 27 IOHID payload (little-endian, 16.16 fixed-point)

private struct IOHIDEventBase {
    var size: UInt32
    var type: UInt32
    var options: UInt32
    var depth: UInt8
    var reserved: (UInt8, UInt8, UInt8)
}

private struct IOHIDFluidTouchGestureData {
    var base: IOHIDEventBase
    var positionX: Int32
    var positionY: Int32
    var positionZ: Int32
    var swipeMask: UInt32
    var gestureMotion: UInt16
    var gestureFlavor: UInt16
    var swipeProgress: Int32
}

private struct IOHIDVelocityEventData {
    var base: IOHIDEventBase
    var velocityX: Int32
    var velocityY: Int32
    var velocityZ: Int32
}

private struct IOHIDSystemQueueElementHeader {
    var timestamp: UInt64
    var senderID: UInt64
    var options: UInt32
    var attributeLength: UInt32
    var eventCount: UInt32
}

/// Posts dock-swipe CGEvents, augmenting them with the IOHID payload macOS 27
/// requires (field 4205). Faithfully ported from SpacesMenu's SystemEventPoster.
struct SystemEventPoster {
    private static let kIOHIDEventTypeVelocity: UInt32 = 9
    private static let kIOHIDEventTypeFluidTouchGesture: UInt32 = 23
    private static let kIOHIDGestureFlavorDockPrimary: UInt16 = 3

    private static let requiresAugmentation: Bool = {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }()

    /// A short flick: begin at progress 0, a brief ramp, then end with release
    /// velocity — the Dock animates the rest. A pre-completed drag lands as a
    /// hard cut, so the partial-progress shape is what makes it slide.
    func postFlick(goRight: Bool, velocity: Double) {
        postDockSwipe(phase: 1, goRight: goRight, velocity: 0, progress: 0)
        for ramp in [0.05, 0.10, 0.15] {
            usleep(8_000)
            postDockSwipe(phase: 2, goRight: goRight, velocity: velocity, progress: ramp)
        }
        usleep(8_000)
        postDockSwipe(phase: 4, goRight: goRight, velocity: velocity, progress: 0.15)
    }

    func postDockSwipe(phase: Int64, goRight: Bool, velocity: Double, progress: Double = 1.0) {
        let progress = goRight ? progress : -progress
        let vel = goRight ? velocity : -velocity
        guard let event = CGEvent(source: nil) else { return }

        event.setIntegerValueField(SpaceControl.eventTypeField, value: SpaceControl.dockControl)
        event.setIntegerValueField(SpaceControl.gestureHIDType, value: SpaceControl.hidDockSwipe)
        event.setIntegerValueField(SpaceControl.gesturePhase, value: phase)
        event.setDoubleValueField(SpaceControl.swipeProgress, value: progress)
        event.setIntegerValueField(SpaceControl.swipeMotion, value: SpaceControl.motionHorizontal)
        event.setDoubleValueField(SpaceControl.swipeVelocityX, value: vel)
        event.setDoubleValueField(SpaceControl.swipeVelocityY, value: 0)

        event.setIntegerValueField(SpaceControl.gesturePhase2, value: phase)
        event.setDoubleValueField(SpaceControl.gestureFlavor, value: 3.0)
        event.setDoubleValueField(SpaceControl.eventTimestamp, value: Double(mach_absolute_time()))
        event.setDoubleValueField(SpaceControl.swipePositionX, value: 0.1)

        if Self.requiresAugmentation {
            postAugmentedEvent(event, phase: phase, velocity: vel)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func postAugmentedEvent(_ event: CGEvent, phase: Int64, velocity: Double) {
        guard let serialized = event.data else { event.post(tap: .cgSessionEventTap); return }
        let payload = buildIOHIDPayload(event: event, phase: phase, velocity: velocity)
        var bytes = Data(referencing: serialized)
        appendField4205(to: &bytes, payload: payload)
        if let augmented = CGEvent(withDataAllocator: kCFAllocatorDefault, data: bytes as CFData) {
            augmented.post(tap: .cgSessionEventTap)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func buildIOHIDPayload(event: CGEvent, phase: Int64, velocity: Double) -> Data {
        let timestamp = event.timestamp != 0 ? event.timestamp : mach_absolute_time()
        let progress = event.getDoubleValueField(SpaceControl.swipeProgress)
        let posX = event.getDoubleValueField(SpaceControl.swipePositionX)

        var data = Data()
        var header = IOHIDSystemQueueElementHeader(
            timestamp: timestamp, senderID: 0, options: 0, attributeLength: 0, eventCount: 2)
        withUnsafeBytes(of: &header) { data.append(contentsOf: $0) }

        var gesture = IOHIDFluidTouchGestureData(
            base: IOHIDEventBase(
                size: UInt32(MemoryLayout<IOHIDFluidTouchGestureData>.size),
                type: Self.kIOHIDEventTypeFluidTouchGesture,
                options: UInt32((phase & 0xFF) << 24), depth: 0, reserved: (0, 0, 0)),
            positionX: SpaceControl.toFixedPoint(posX), positionY: SpaceControl.toFixedPoint(0),
            positionZ: 0, swipeMask: 0, gestureMotion: 1,
            gestureFlavor: Self.kIOHIDGestureFlavorDockPrimary,
            swipeProgress: SpaceControl.toFixedPoint(-progress))  // IOHID sign is flipped
        withUnsafeBytes(of: &gesture) { data.append(contentsOf: $0) }

        var velocityEvent = IOHIDVelocityEventData(
            base: IOHIDEventBase(
                size: UInt32(MemoryLayout<IOHIDVelocityEventData>.size),
                type: Self.kIOHIDEventTypeVelocity, options: 0, depth: 1, reserved: (0, 0, 0)),
            velocityX: SpaceControl.toFixedPoint(-velocity), velocityY: 0, velocityZ: 0)
        withUnsafeBytes(of: &velocityEvent) { data.append(contentsOf: $0) }
        return data
    }

    /// Field 4205 = 0x106D, framed big-endian: [size_hi][size_lo][0x10][0x6D][payload].
    private func appendField4205(to bytes: inout Data, payload: Data) {
        let size = UInt16(payload.count)
        bytes.append(UInt8(size >> 8))
        bytes.append(UInt8(size & 0xFF))
        bytes.append(0x10)
        bytes.append(0x6D)
        bytes.append(payload)
    }
}
